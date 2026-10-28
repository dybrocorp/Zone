# FASE G — E2EE: establecimiento autenticado de claves y ratchet

**Fecha:** 2026-10-23
**Estado:** auditoría + especificación. **NO se implementa criptografía nueva.**
**Z-004 / Z-101:** abiertos.
**Beta:** **NO-GO**.

---

## 1. Resumen ejecutivo

El E2EE actual usa el **secreto compartido X25519 crudo** como clave de
ChaCha20-Poly1305, sin HKDF, sin AAD, sin claves efímeras y sin ratchet. Cloud y
mesh cifran por caminos separados, así que el mismo mensaje viaja con dos
ciphertexts distintos. El comentario de `encryptMessage` afirma "Forward
Secrecy"; **eso es falso** con el diseño actual.

Esta fase:

1. Audita el camino real (cloud, mesh, almacenamiento, confianza en la clave).
2. Especifica un **establecimiento autenticado** que se apoya en el handshake de
   Fase E (`ZONE-P2P-AKE-1`).
3. Especifica el **key schedule HKDF** y el **ratchet** con las primitivas ya
   aprobadas (Ed25519, X25519, HKDF-SHA256, ChaCha20-Poly1305, SHA-256).
4. Define **migración por versiones** para no romper el historial v1.
5. Define los **tests de seguridad** que deben existir antes de integrar.

**No se implementa nada en esta fase.** Sustituir el protocolo E2EE es un
proyecto separado con migración y recuperación aprobadas; el gate sigue bloqueado.

---

## 2. Auditoría del estado actual

### 2.1 Derivación de clave

`lib/services/chat_e2ee_service.dart`:

- `computeSharedSecret` (líneas 39-45) llama a `X25519.sharedSecretKey`.
- El resultado se usa **directamente** como `SecretKey` de ChaCha20-Poly1305
  (`encryptMessage`, líneas 60-79; `decryptMessage`, líneas 82-114).
- No hay `Hkdf`, no hay `salt`, no hay `info`, no hay separación por dirección.
- La clave es **estática**: depende solo de las X25519 de largo plazo de ambos
  usuarios. Un compromiso futuro de cualquiera de las dos claves descifra todo
  el historial.

### 2.2 Cifrado

- `Chacha20.poly1305Aead()` (línea 13).
- `encrypt` no recibe `aad` (líneas 62-65).
- `decrypt` no recibe `aad` (líneas 99-102).

**Consecuencia:** el ciphertext no está ligado a `match_id`, `sender_id`,
`message_id` ni a la sesión. Un servidor malicioso o un atacante con acceso a la
tabla `messages` puede reordenar, borrar o reinyectar ciphertexts dentro del
mismo par sin que el AEAD lo detecte (el nonce aleatorio evita colisión, no
replay).

### 2.3 Confianza en la clave pública

`lib/screens/chat_screen.dart:194-208`:

- La clave del peer se toma de `otherProfile['public_key']` (Supabase) o del
  perfil local de Isar.
- No se verifica firma, fingerprint ni anclaje.
- `getProfileByZoneId` (`supabase_service.dart:762, 794`) devuelve `public_key`
  como un campo más.

**Consecuencia:** el servidor (o quien comprometa la DB) puede sustituir la
clave y leer el chat. Es el mismo problema que Z-004, pero en el camino cloud.

### 2.4 Dos caminos de cifrado divergentes

`lib/screens/chat_screen.dart:525-571`:

1. Cifra el texto una vez para el outbox/cloud con `_sharedSecret`.
2. Si el peer está cerca, llama a `_nearbyService.sendMeshMessage(text)` con el
   **texto claro**; `nearby_service.dart:1291-1306` lo vuelve a cifrar con la
   `sk_<zoneId>` del mesh.

**Consecuencia:** cloud y mesh tienen ciphertexts, nonces y claves distintos para
el mismo mensaje. No hay una única versión de cifrado y los bugs de una ruta no
se reproducen en la otra. `CRYPTO_CTO_REVIEW.md` §6.3 recomienda exactamente lo
contrario: un solo ciphertext y una sola versión.

### 2.5 Almacenamiento de sesión

`lib/services/p2p_security_service.dart:97-140`:

- `sk_<zoneId>` en `FlutterSecureStorage`.
- La clave es el shared secret crudo en Base64.
- No hay metadata de versión, algoritmo, transcript, contador ni estado de
  ratchet.
- `deleteAllSessionKeys` borra todas las claves; no hay rotación ni revocación
  selectiva.

### 2.6 Afirmaciones de seguridad incorrectas

- `chat_e2ee_service.dart:59`: "garantizando Forward Secrecy". **Falso**: no hay
  claves efímeras ni ratchet.
- El comentario de `decryptMessage` sugiere que un MAC inválido es "normal"
  (reinstalación); puede enmascarar un ataque. Debe distinguirse
  criptográficamente entre "clave antigua conocida" y "fallo de autenticación".

### 2.7 Fundación disponible

- Ed25519: `lib/identity/ed25519_identity_service.dart`.
- X25519: `lib/identity/x25519_device_service.dart`.
- `cryptography` 2.9.0 ya incluye `Hkdf` (HMAC-SHA256) y AAD en
  `Cipher.encrypt/decrypt`.
- No hace falta una dependencia criptográfica nueva.

### 2.8 Conclusión

| Propiedad | Actual | Objetivo |
|---|---|---|
| Autenticación del peer | ❌ | Fase E + G |
| HKDF sobre ECDH | ❌ | ✅ |
| Separación por dirección | ❌ | ✅ |
| AAD (match/sender/message) | ❌ | ✅ |
| Claves efímeras | ❌ | ✅ |
| Forward Secrecy | ❌ (comentario falso) | ✅ con ratchet |
| Post-Compromise Security | ❌ | ✅ con DH ratchet |
| Out-of-order / skipped keys | ❌ | ✅ |
| Replay de mensaje | ❌ | ✅ contador + ventana |
| Cloud/mesh mismo ciphertext | ❌ | ✅ |
| Versión de cripto explícita | ❌ | ✅ |

---

## 3. Modelo de amenazas

### 3.1 Activos

- Contenido de mensajes.
- Claves de identidad (Ed25519) y de cifrado (X25519).
- Estado de sesión/ratchet.
- Grafo de matches y metadata.

### 3.2 Atacante

- Servidor malicioso o DB comprometida.
- Observador de red (TLS roto o metadata).
- Peer malicioso en la radio.
- Dispositivo comprometido **después** de una sesión.
- No rompe Ed25519/X25519/HKDF/ChaCha20-Poly1305/SHA-256.

### 3.3 Amenazas

| # | Amenaza | Actual | Objetivo |
|---|---|---|---|
| T1 | Servidor sustituye clave pública | ❌ vulnerable | Handshake Fase E + ancla |
| T2 | Servidor lee ciphertext | ✅ protegido | Se mantiene |
| T3 | Servidor reordena/reinyecta ciphertext | ❌ vulnerable | AAD + contador + ventana |
| T4 | Compromiso futuro de clave larga | ❌ lee historial | FS con ratchet |
| T5 | Compromiso de sesión actual | ❌ lee todo el futuro | PCS con DH ratchet |
| T6 | Replay de mensaje | ❌ | Contador por sesión |
| T7 | Mensajes fuera de orden | ❌ rompe | Skipped keys acotadas |
| T8 | Downgrade a v1 | ❌ silencioso | Negociación firmada + versión mínima |
| T9 | Cruce de conversaciones | ❌ AAD ausente | AAD con match/sender/message |
| T10 | Multi-dispositivo | ❌ no existe | Sesión por device (fase posterior) |
| T11 | Metadata (quién habla con quién) | ❌ | Fuera de alcance; documentar |
| T12 | Dispositivo comprometido antes del ratchet | — | No hay defensa total; rotación/revocación |

---

## 4. Establecimiento autenticado (AKE)

Se apoya en `ZONE-P2P-AKE-1` (Fase E). El handshake aporta:

- identidad Ed25519 verificada,
- clave X25519 estática del device,
- clave efímera X25519,
- nonce, session_id, timestamp,
- transcript firmado y encadenado.

### 4.1 DH combinados

Con `A` iniciador y `B` respondedor:

```
dh1 = X25519(A.eph,  B.static)
dh2 = X25519(A.static, B.eph)
dh3 = X25519(A.eph,  B.eph)
dh4 = X25519(A.static, B.static)
```

`dh4` liga las identidades de largo plazo; `dh1`-`dh3` aportan material efímero.
Los cuatro son necesarios para replicar la propiedad de X3DH sin inventar un
protocolo nuevo.

### 4.2 Salt y transcript

```
salt = SHA-256(
  "ZONE-AKE-SALT-1\0"
  ‖ identity_pk_A
  ‖ identity_pk_B
)
```

Orden canónico: por `account_id` (menor primero) para que ambos lados calculen
el mismo salt. Esto refina `CRYPTO_CTO_REVIEW.md` §5.2 (que usa la concatenación
directa) para obtener longitud fija y separación de dominio. **Requiere revisión
del CTO antes de implementar.**

`transcript_hash` es el SHA-256 del transcript de Fase E (incluye `hello_A`,
`hello_B` y el encadenado `prior`).

### 4.3 Key schedule

```
master = HKDF-SHA256(
  ikm  = dh1 ‖ dh2 ‖ dh3 ‖ dh4,
  salt = salt,
  info = "ZONE-AKE-1 master" ‖ transcript_hash
)

root_key        = HKDF(master, info = "ZONE-AKE-1 root")
chain_A2B       = HKDF(master, info = "ZONE-AKE-1 chain A2B")
chain_B2A       = HKDF(master, info = "ZONE-AKE-1 chain B2A")
header_key      = HKDF(master, info = "ZONE-AKE-1 header")
```

Reglas:

- `info` incluye el transcript hash: dos handshakes distintos **nunca** producen
  las mismas claves (unknown key share).
- Direcciones separadas: `A2B` y `B2A` no son intercambiables.
- Ninguna clave derivada se usa para dos propósitos.
- `HKDF` se usa con `Hmac.sha256()` y `outputLength = 32`.

### 4.4 Verificación antes de derivar

No se deriva ninguna clave hasta que `P2PAuthPolicy.verifyHello` acepte ambos
`hello` y el ancla/TOFU esté resuelto. Un rechazo no produce claves ni sesión.

### 4.5 Primer contacto

Sin ancla, el handshake es `firstContact=true`. El fingerprint OOB (Fase E) debe
confirmarse **antes** de usar la sesión para mensajes sensibles. Mientras no se
confirme, la UI debe mostrarlo como "canal no verificado".

---

## 5. Ratchet

### 5.1 Estructura

Doble ratchet (Signal) con las primitivas aprobadas:

- **DH ratchet**: al cambiar de dirección, se genera un nuevo par X25519 y se
  mezcla con la clave pública de ratchet del peer.
- **Symmetric ratchet**: cadena de claves por dirección; cada mensaje consume
  una message key y avanza la cadena.

```
root_key, chain_send, chain_recv, dh_send, dh_recv,
msg_n_send, msg_n_recv, prev_n_send, skipped_keys
```

### 5.2 Message key

```
message_key = HKDF(chain_key, info = "ZONE-MSG-1" ‖ counter)
next_chain  = HKDF(chain_key, info = "ZONE-CHAIN-1")
```

La message key se borra después de usarse. El contador es monótono por
dirección.

### 5.3 Cabecera y AAD

```
header = {
  version: "ZONE-E2EE-3",
  session_id,
  dh_public,
  counter,        // n
  previous_chain_length // pn
}
```

`AAD = canonical(header) ‖ match_id ‖ sender_id ‖ message_id`.

El AEAD debe recibir `aad` en `encrypt` y `decrypt`. Un AAD distinto ⇒
`SecretBoxAuthenticationError` ⇒ rechazo, no "mensaje antiguo".

### 5.4 Fuera de orden y skipped keys

- Ventana máxima configurable (p. ej. 2000 claves).
- TTL de skipped keys (p. ej. 7 días).
- Nunca se reutiliza una message key.
- Un contador ya consumido ⇒ replay, se rechaza.
- Un salto mayor que la ventana ⇒ rechazo (no crecer sin límite).

### 5.5 Persistencia

- Estado por par `(mi device, device del peer)` en SecureStorage.
- Nunca en Isar plano, logs ni Supabase.
- Al desinstalar/recovery, el estado se pierde y la sesión se re-negocia; los
  mensajes anteriores del device perdido no se recuperan
  (`PHASE_2_RECOVERY_POLICY.md`).
- Rotación/revocación de device elimina su estado.

### 5.6 Cloud y mesh: un solo ciphertext

El cifrado debe ocurrir **una vez** en la capa de chat. El mismo `SecretBox`
(ciphertext, nonce, mac, header) se persiste en outbox, se envía a Supabase y se
transporta por mesh. El mesh no vuelve a cifrar.

Esto elimina la divergencia actual y permite que el receptor descifre con el
mismo estado de ratchet, venga el mensaje por donde venga.

### 5.7 Multi-dispositivo

- Cada device tiene su propia X25519 y su propio estado de ratchet.
- Un mensaje saliente se cifra por separado para cada device activo del peer
  (fan-out), o se usa una sesión de grupo (fase posterior).
- El dispositivo perdido se revoca; los demás conservan sus sesiones.
- No se implementa en esta fase; se documenta para no bloquear el diseño.

---

## 6. Versionado y migración

### 6.1 Versiones

| Versión | Clave | AAD | Handshake | Ratchet | Estado |
|---|---|---|---|---|---|
| v1 (actual) | X25519 crudo | ❌ | ❌ | ❌ | Producción |
| v2 | HKDF | ✅ | ❌ | ❌ | Intermedio opcional |
| v3 | HKDF + transcript | ✅ | ✅ Fase E | ❌ | Objetivo mínimo |
| v4 | HKDF + transcript | ✅ | ✅ | ✅ | Objetivo completo |

No se debe saltar de v1 a v4 sin v3: v3 permite validar HKDF/AAD/handshake con
un cambio acotado antes de introducir el ratchet.

### 6.2 Compatibilidad con historial v1

- Los mensajes v1 se descifran con la clave estática archivada.
- La X25519 v1 **no** se restaura tras recovery (I-025).
- La clave v1 se conserva localmente mientras exista historial v1 que mostrar;
  no se sube al servidor.
- Los mensajes nuevos usan la versión más alta soportada por ambos devices.

### 6.3 Negociación y downgrade

- Cada mensaje lleva `version` en la cabecera (AAD).
- La versión se negocia en el handshake y se firma en el transcript.
- Un peer que solo soporta v1 se marca explícitamente; la UI advierte.
- **No hay downgrade silencioso.** Si la versión firmada es v3+, un mensaje v1
  inyectado se rechaza.

### 6.4 Esquema

Añadir a `messages` (migración no destructiva, nullable para filas v1):

- `crypto_version smallint`,
- `session_id uuid`,
- `header jsonb` (o `text` canónico).

No se modifican las filas existentes. RLS no cambia. La migración debe ser
revisada y aplicada solo con autorización (igual que Z-212).

### 6.5 Rollback

- Feature flag por versión.
- Si v3 falla, se puede volver a v1 **solo** con decisión explícita y aviso; el
  rollback no debe ser automático ni silencioso.
- El estado de ratchet v4 no se puede "bajar" a v3 sin re-negociar.

### 6.6 Orden de implementación

1. Corregir el comentario falso de Forward Secrecy y la clasificación de errores
   de descifrado (sin cambio de comportamiento).
2. v2: HKDF + AAD + versión, manteniendo claves estáticas. Tests KAT y de AAD.
3. v3: integrar Fase E (handshake) y derivar del transcript. Tests de
   sustitución/replay/identidad.
4. v4: ratchet. Tests de FS/PCS/out-of-order/replay.
5. Cloud/mesh unificado.
6. Multi-dispositivo.

Cada paso es un proyecto con su propia revisión; no se implementa en Fase G.

---

## 7. Tests de seguridad requeridos

### 7.1 KAT (known-answer tests)

- HKDF-SHA256 con vectores RFC 5869.
- ChaCha20-Poly1305 con vectores RFC 8439.
- Ed25519 con vectores RFC 8032.
- X25519 con vectores RFC 7748.

No se aceptan implementaciones sin KAT.

### 7.2 Key schedule

- Determinismo: mismos DH + salt + transcript ⇒ mismas claves.
- Distinto transcript ⇒ claves distintas (unknown key share).
- `A2B` ≠ `B2A`.
- `root` ≠ `chain` ≠ `header`.
- Cambiar `dh1..dh4` cambia el resultado.

### 7.3 AEAD y AAD

- AAD correcto ⇒ descifra.
- `match_id`, `sender_id`, `message_id`, `session_id`, `counter` o `version`
  alterados ⇒ fallo de autenticación.
- Nonce reutilizado ⇒ rechazo (no solo confiar en el AEAD).

### 7.4 Ratchet

- FS: un estado actual comprometido no descifra mensajes anteriores.
- PCS: tras un DH ratchet, un estado viejo no descifra mensajes nuevos.
- Out-of-order: 2,4,3,5 se descifran.
- Pérdida dentro de la ventana: se descifra.
- Salto fuera de la ventana: se rechaza.
- Replay de contador: se rechaza.
- Skipped key usada dos veces: se rechaza.
- Persistencia: reinicio conserva el estado y no reutiliza claves.

### 7.5 Migración

- Mensaje v1 sigue descifrando tras introducir v2/v3.
- Mensaje v3 no se puede degradar a v1.
- Mezcla de versiones en el mismo hilo no rompe el orden.
- Recovery no restaura v1 ni el ratchet.

### 7.6 Integración

- Cloud y mesh entregan el mismo ciphertext y el receptor lo descifra igual.
- Un peer que no soporta v3 se marca; no hay downgrade silencioso.
- Un device revocado no recibe nuevas claves.

---

## 8. No objetivos

- No se implementa HKDF, AAD ni ratchet en esta fase.
- No se cambia `chat_e2ee_service.dart`, `nearby_service.dart` ni el esquema.
- No se añade una dependencia criptográfica.
- No se promete FS/PCS en la UI hasta que exista y esté probado.
- No se resuelve multi-dispositivo ni recovery (Fases F/G posteriores).
- No se toca staging/producción.

---

## 9. Riesgos y decisiones pendientes

| Riesgo / decisión | Estado |
|---|---|
| Salt con SHA-256 vs concatenación de §5.2 | **Requiere aprobación CTO** |
| Implementar Double Ratchet desde cero vs librería revisada | **Requiere decisión CTO** — comparación investigada con evidencia en `docs/audit/E2EE_RATCHET_ALTERNATIVES.md` (2026-10-27): no existe paquete Dart mantenido + licencia compatible + modelo de identidad adecuado; recomendación: módulo propio según specs publicadas, obligado a KATs + matriz §7 + revisión externa |
| Ventana/TTL de skipped keys | Propuesta justificada: 2000 / 7 días / 10 min de handshake pendiente — argumentos de seguridad/offline en `E2EE_RATCHET_ALTERNATIVES.md` §4; exige firma CTO |
| ¿Permitir v1 para peers antiguos? | **Decisión de producto/seguridad**; hoy sería un downgrade |
| Fan-out multi-device vs sesión de grupo | Fase posterior |
| Migración de esquema `messages` | Requiere autorización (como Z-212) |
| Historial v1 tras recovery | Ya decidido: no se recupera (I-025) |

---

## 10. Impacto en el gate

- **Z-004:** sigue abierto (Fase E solo define verificación).
- **Z-101:** sigue abierto (ratchet no implementado).
- **Beta:** **NO-GO** hasta v3 como mínimo y validación en dos dispositivos.
- Sin cambios remotos, sin commits, HEAD
  `7f59b776c62cc131fd05dc999e99cbb7804385e8`.

---

## 11. Referencias

- `docs/CRYPTO_CTO_REVIEW.md` §5 (handshake) y §6 (ratchet).
- `docs/PHASE_2_CRYPTO_DECISIONS.md` D1/D2.
- `docs/PHASE_2_RECOVERY_POLICY.md` I-025.
- `lib/services/chat_e2ee_service.dart`.
- `lib/services/p2p_security_service.dart`.
- `lib/services/nearby_service.dart:1291-1306, 1444-1471`.
- `lib/screens/chat_screen.dart:194-208, 525-571`.
- `lib/services/p2p_auth_policy.dart` (Fase E).
- RFC 5869 (HKDF), RFC 8439 (ChaCha20-Poly1305), RFC 8032 (Ed25519),
  RFC 7748 (X25519).
