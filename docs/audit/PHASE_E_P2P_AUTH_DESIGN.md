# FASE E — Autenticación P2P (Z-004): diseño y contrato de verificación

**Fecha:** 2026-10-23
**Estado:** diseño + contrato de verificación + orquestador de integración
(no cableado a producción).
**Integración en producción:** **NO** realizada.
**Z-004:** sigue **ABIERTO / implementación pendiente**.

---

## 1. Resumen ejecutivo

El P2P actual acepta cualquier conexión entrante y deriva una llave de sesión a
partir de una clave pública X25519 que el peer envía sin firmar. Un atacante en
la radio puede suplantar `source`, interceptar y sustituir claves (MITM), o
reproducir un handshake. Esto es **Z-004 (P0)**.

Esta fase entrega:

1. Una **auditoría del camino real** (no del diseño ideal).
2. La **especificación ejecutable** del handshake `ZONE-P2P-AKE-1`, basada en el
   diseño ya aprobado en `docs/CRYPTO_CTO_REVIEW.md` §5 (no se inventa
   criptografía).
3. Un **contrato de verificación puro** (`P2PAuthPolicy`) que decide
   aceptar/rechazar con razones tipadas, sin derivar ni guardar claves.
4. Un **orquestador de integración** (`P2PHandshakeSession`) que ejecuta el
   handshake de dos mensajes, encadena transcripts y deriva la clave con
   HKDF-SHA256. **No está cableado a `NearbyService`.**
5. **24 tests negativos/positivos** del contrato y **18 tests de integración**
   del handshake completo, con firmas Ed25519, ECDH X25519 y HKDF reales.

El contrato es la autoridad única que el cableado deberá invocar antes de
aceptar una conexión o derivar una sesión. Mientras no se integre, **la
producción sigue siendo vulnerable a Z-004**.

---

## 2. Auditoría del estado actual

### 2.1 Aceptación de conexión sin autenticación

`lib/services/nearby_service.dart`:

- `_onConnectionInitiated` (línea ~905) llama directamente a `acceptConnection(id)`
  (línea ~907). No hay challenge, firma ni verificación de identidad.
- `acceptConnection` (línea ~977) solo invoca al plugin de Nearby.

**Consecuencia:** cualquier endpoint dentro del radio puede establecer el canal
de transporte. La identidad no se prueba en ningún momento.

### 2.2 Identidad declarada, no verificada

- El emisor incluye `'source': _myZoneId` (línea ~1325) en paquetes mesh.
- El receptor confía en `packet.source` y solo comprueba que exista un perfil
  local (líneas ~1399-1404).

**Consecuencia:** el `source` es un string libre. Suplantar una zona es trivial.

### 2.3 Intercambio de claves sin firma

- `profile_exchange` envía `'publicKey': _security.publicBase64` (línea ~1099)
  dentro de un payload JSON sin firmar.
- El receptor toma `profileData['publicKey']` (líneas ~1130-1131) y, si no hay
  llave previa, llama a `_security.deriveSessionKey(remotePublicKey)` y la guarda
  (líneas ~1141-1145).

**Consecuencia:** el primer contacto es TOFU puro sobre un canal no autenticado.
Un MITM puede entregar su propia X25519 y quedarse con la sesión.

### 2.4 Derivación y cifrado actuales

`lib/services/p2p_security_service.dart`:

- `deriveSessionKey` (línea ~79) calcula el **secreto compartido X25519 crudo** y
  lo serializa en Base64 (líneas ~84-85). **No hay HKDF.**
- La llave se guarda como `sk_<zoneId>` en `FlutterSecureStorage` (líneas
  ~97-107).

`lib/services/chat_e2ee_service.dart`:

- `Chacha20.poly1305Aead()` (línea ~13).
- `encryptMessage` (línea ~60) / `decryptMessage` (línea ~86) **no pasan AAD**.
- No hay ratchet ni clave efímera por sesión.

**Consecuencia:** sin HKDF, sin binding de identidad, sin AAD y sin forward
secrecy. Esto se aborda en Fase G, no aquí.

### 2.5 Fundación de identidad ya existente (no integrada)

- `lib/identity/ed25519_identity_service.dart`: firma/verificación Ed25519.
- `lib/identity/x25519_device_service.dart`: ECDH X25519.
- `lib/identity/secure_key_store.dart`: material privado con namespace `zid1.`.
- `lib/identity/fingerprint_service.dart`: fingerprint v1 (solo Ed25519).

Estos servicios están marcados **NEW FOUNDATION — NOT YET INTEGRATED**. El P2P
legacy usa `private_key`/`public_key` en `FlutterSecureStorage`, un espacio de
nombres distinto. La convergencia es parte de Fase G.

### 2.6 Conclusión de la auditoría

| Propiedad | Estado actual |
|---|---|
| Prueba de posesión de identidad | ❌ No existe |
| Binding `endpointId` ↔ identidad | ❌ No existe |
| Firma del intercambio de claves | ❌ No existe |
| Anclaje de clave en primer contacto | ⚠️ TOFU sin verificación OOB |
| Anti-replay de handshake | ❌ No existe |
| HKDF sobre el secreto ECDH | ❌ No existe |
| AAD en AEAD | ❌ No existe |
| Forward secrecy / ratchet | ❌ No existe |
| Revocación de dispositivo en P2P | ❌ No se consulta |

---

## 3. Modelo de amenazas

### 3.1 Activos

- Identidad de cuenta (Ed25519) y de dispositivo (Ed25519).
- Clave de cifrado de dispositivo (X25519).
- Llaves de sesión y mensajes E2EE.
- Integridad del grafo de matches/encuentros.

### 3.2 Atacante

- Presente en la radio (BLE/Nearby), puede anunciar endpoints, conectarse,
  enviar payloads y observar tráfico.
- Puede reutilizar mensajes capturados.
- **No** compromete el SecureStorage ni el Keystore del dispositivo víctima.
- **No** rompe Ed25519/X25519/SHA-256.

### 3.3 Amenazas y tratamiento

| # | Amenaza | Vector actual | Tratamiento en el contrato | Residual |
|---|---|---|---|---|
| T1 | Suplantación de `source` | `source` string libre | El `hello` firmado liga `zone_id`, `account_id`, `device_id` y claves; `expectedZoneId` debe coincidir | Requiere integración (Fase G) |
| T2 | MITM / sustitución de X25519 | `publicKey` sin firmar | Firma Ed25519 sobre transcript + comparación con ancla (`encryptionKeySubstitution`) | Primer contacto: TOFU hasta verificación OOB |
| T3 | Sustitución de identidad | Cualquiera puede presentar otra Ed25519 | `identityKeySubstitution` contra ancla | Ídem |
| T4 | Replay de handshake | No hay nonce/ttl | TTL + `sessionId` en caché LRU con TTL | Caché es local; multi-dispositivo requiere estado compartido o aceptar ventana |
| T5 | Reutilización de sesión | No hay control | `activeSessionIds` → `sessionReuse` | El llamador debe mantener el set |
| T6 | Transcript adulterado | No hay firma | Firma sobre transcript canónico; cualquier cambio → `invalidSignature` | — |
| T7 | Dispositivo revocado/comprometido | No se consulta | `deviceStatus != active` o `revokedAt != null` → `revokedDevice` | El estado debe provenir de una fuente confiable (servidor/registro firmado) |
| T8 | Downgrade / confusión de algoritmo | Etiquetas libres | Versión fija + algoritmos esperados por propósito | — |
| T9 | Rollback/rotación silenciosa de clave | Sin versionado | `encryptionKeyVersion` contra ancla: rollback y subida no firmada se rechazan | La rotación legítima necesita registro firmado (Fase G) |
| T10 | Handshake viejo | Sin TTL | `issuedAtMs` fuera de ventana → `staleHandshake` | Depende de reloj; se tolera skew de 30 s |
| T11 | Confusión entre zonas | `source` libre | `expectedZoneId` + canonicalidad `ZONE-XXXXXXXX` | — |
| T12 | Inyección de payload incompleto | JSON libre | `incompleteNegotiation` + longitudes exactas | — |

### 3.4 Fuera de alcance del contrato

- Compromiso del dispositivo o del SecureStorage.
- Ataques de denegación de servicio por radio.
- Privacidad de metadatos (quién está cerca de quién).
- Seguridad del servidor Supabase (tratada en Z-212).
- Robo de cuenta por `claim_zone_id` (Z-001, Fase F).

---

## 4. Especificación `ZONE-P2P-AKE-1`

### 4.1 Primitivas (todas ya aprobadas)

| Uso | Primitiva | Autoridad |
|---|---|---|
| Firma de identidad | Ed25519 | `PHASE_2_CRYPTO_DECISIONS.md` D1 |
| Cifrado/ECDH | X25519 | D2 |
| Hash de transcript | SHA-256 | Estándar |
| AEAD (Fase G) | ChaCha20-Poly1305 | `cryptography` 2.9.0 |
| KDF (Fase G) | HKDF-HMAC-SHA256 | `cryptography` 2.9.0 |

No se introduce ninguna primitiva nueva. El contrato **no ejecuta ECDH ni KDF**.

### 4.2 Campos del `hello`

| Campo | Tipo | Regla |
|---|---|---|
| `version` | string | Exactamente `ZONE-P2P-AKE-1` |
| `zone_id` | string | `^ZONE-[A-Z0-9]{8}$`, ya en mayúsculas |
| `account_id` | UUID | Canónico minúsculas con guiones |
| `device_id` | UUID | Canónico minúsculas con guiones |
| `identity_key_algorithm` | string | Exactamente `Ed25519` |
| `identity_public_key` | base64 | 32 bytes raw |
| `encryption_key_algorithm` | string | Exactamente `X25519` |
| `encryption_public_key` | base64 | 32 bytes raw |
| `encryption_key_version` | int | `>= 1` |
| `ephemeral_public_key` | base64 | 32 bytes raw (una por handshake) |
| `nonce` | base64 | 32 bytes aleatorios |
| `session_id` | UUID v4 | Canónico minúsculas |
| `issued_at_ms` | int | Milisegundos UTC |
| `signature` | base64 | 64 bytes Ed25519 |
| `device_status` | enum local | Debe ser `active` |
| `revoked_at` | timestamp local | Debe ser `null` |

`device_status` y `revoked_at` **no viajan en el transcript firmado**: son
entradas de confianza locales (estado archivado). Si viajaran, un atacante
podría declararse `active`. El llamador debe obtenerlos de una fuente confiable.

### 4.3 Transcript canónico

```
utf8("ZONE-P2P-AKE-1\0")
‖ lp("hello")
‖ lp(version)
‖ lp(zone_id en mayúsculas)
‖ lp(account_id canónico)
‖ lp(device_id canónico)
‖ lp(identity_key_algorithm)
‖ lp(identity_public_key base64)
‖ lp(encryption_key_algorithm)
‖ lp(encryption_public_key base64)
‖ lp(encryption_key_version decimal)
‖ lp(ephemeral_public_key base64)
‖ lp(nonce base64)
‖ lp(session_id canónico)
‖ lp(issued_at_ms decimal)
[‖ lp("prior") ‖ lp(prior_transcript_hash base64)]
```

donde `lp(x) = uint32_be(len(utf8(x))) ‖ utf8(x)`.

Propiedades:

- **Sin ambigüedad de concatenación** (longitud prefijada).
- **Versionado por dominio** (el byte NUL separa dominio de contenido).
- **Encadenable**: `hello_B` puede firmar el hash de `hello_A` como `prior`,
  lo que liga ambos mensajes y evita mezclar handshakes.
- La firma **no** forma parte del transcript (es la firma de este).

### 4.4 Orden de verificación

Deliberado para que los tests distingan causas y para no tocar estado antes de
tiempo:

1. Campos obligatorios presentes.
2. Versión soportada.
3. Canonicalidad de `zone_id`, `account_id`, `device_id`, `session_id`.
4. Algoritmos por propósito (`Ed25519` firma, `X25519` cifra).
5. Longitudes exactas (32/32/32/32/64).
6. Estado del dispositivo (`active`, sin `revoked_at`).
7. Ventana temporal (TTL 2 min, skew futuro 30 s).
8. `session_id` no activo y no consumido.
9. Ancla: identidad, clave de cifrado y versión.
10. `expectedZoneId`.
11. Firma Ed25519 sobre el transcript exacto.
12. Registro en caché anti-replay **solo si se acepta**.

Un rechazo **nunca** deriva ni guarda una llave.

### 4.5 Primer contacto

Sin ancla, la decisión es `accepted=true, firstContact=true`. Eso **no** significa
"confiable": el llamador debe mostrar el `DEVICE_FINGERPRINT` (20 chars Base32,
`PHASE_2_FINGERPRINT_SPEC.md`) y exigir confirmación fuera de banda (QR, NFC o
comparación manual) antes de persistir el ancla. Hasta entonces, el canal no debe
usarse para mensajes sensibles.

### 4.6 Ancla de confianza

`P2PTrustAnchor` contiene:

- `identity_public_key` (Ed25519),
- `encryption_public_key` (X25519),
- `encryption_key_version`.

Reglas:

- Identidad distinta → `identityKeySubstitution`.
- Clave de cifrado distinta → `encryptionKeySubstitution`.
- Versión menor → `keyVersionRollback`.
- Versión mayor → `keyRotationRequired` (exige registro firmado por la identidad
  de cuenta; Fase G).

### 4.7 Caché anti-replay

`P2PSessionReplayCache`:

- TTL por defecto 10 min (cubre el TTL del handshake).
- Máximo 512 entradas (LRU por timestamp).
- `register` devuelve `false` si ya existía dentro de la ventana.
- No sustituye la deduplicación de mensajes (`MeshPolicy`): evita reutilizar un
  handshake completo, no un paquete.

---

## 5. Criterios de aceptación (ejecutables)

| ID | Criterio | Evidencia |
|---|---|---|
| AC-01 | Un `hello` firmado por la identidad anclada se acepta | `verificación positiva` |
| AC-02 | El primer contacto se marca `firstContact` y exige OOB | `verificación positiva` |
| AC-03 | `hello_B` firmado sobre el hash de `hello_A` se acepta; con otro hash no | `verificación positiva` |
| AC-04 | Identidad distinta a la anclada se rechaza | `key substitution` |
| AC-05 | X25519 distinta a la anclada se rechaza | `key substitution` |
| AC-06 | Rollback de versión se rechaza | `key substitution` |
| AC-07 | Subida de versión sin registro firmado se rechaza | `key substitution` |
| AC-08 | `zone_id` distinto del esperado se rechaza | `wrong identity` |
| AC-09 | IDs no canónicos se rechazan | `wrong identity` |
| AC-10 | Replay del mismo `session_id` se rechaza | `replay y session reuse` |
| AC-11 | `session_id` ya activo se rechaza | `replay y session reuse` |
| AC-12 | Transcript alterado se rechaza | `modified transcript` |
| AC-13 | Firma alterada byte a byte se rechaza | `modified transcript` |
| AC-14 | Dispositivo no activo o revocado se rechaza | `revoked key` |
| AC-15 | Negociación incompleta se rechaza | `incomplete negotiation` |
| AC-16 | Versión no soportada se rechaza | `incomplete negotiation` |
| AC-17 | Algoritmo intercambiado se rechaza | `incomplete negotiation` |
| AC-18 | Longitudes inválidas se rechazan | `incomplete negotiation` |
| AC-19 | Handshake viejo/futuro se rechaza | `stale handshake` |
| AC-20 | El transcript es determinista y cualquier campo lo cambia | `transcript canónico` |
| AC-21 | El caché caduca por TTL y no crece sin límite | `replay y session reuse` |

---

## 6. Matriz de tests

### 6.1 Contrato (`test/p2p_auth_negative_test.dart`) — **24/24 PASS**

Archivo: `test/p2p_auth_negative_test.dart` — **24/24 PASS**.

| Grupo | Tests | Cubre |
|---|---|---|
| transcript canónico | 2 | determinismo, sensibilidad a campos y `prior` |
| verificación positiva | 3 | ancla, primer contacto, encadenado A→B |
| key substitution | 4 | identidad, X25519, rollback, rotación |
| wrong identity | 3 | `expectedZoneId`, zona no canónica, IDs no canónicos |
| replay y session reuse | 3 | replay, sesión activa, TTL/LRU |
| modified transcript | 2 | campos alterados, firma alterada |
| revoked key | 2 | estados no activos, `revoked_at` |
| incomplete negotiation | 4 | campos ausentes, versión, algoritmo, longitudes |
| stale handshake | 1 | antiguo y futuro |

Los tests usan firmas Ed25519 reales y claves X25519 reales derivadas de seeds
deterministas. No hay mocks de criptografía.

**Comando:**

```powershell
C:\flutter\bin\flutter.bat test --no-pub test/p2p_auth_negative_test.dart
```

**Resultado:** `00:01 +24: All tests passed!` (`TEST_EXIT=0`).

### 6.2 Integración (`test/p2p_handshake_integration_test.dart`) — **18/18 PASS**

| Grupo | Tests | Cubre |
|---|---|---|
| handshake completo | 5 | misma clave en ambos lados, transcript, no-es-secreto-crudo, efímeros frescos, roles |
| sustitución de identidad y MITM | 3 | X25519 alterada, re-firma con identidad ajena, `prior` distinto |
| replay, TTL y estado | 3 | replay del hello, TTL, dispositivo revocado |
| negociación incompleta / fail-closed | 7 | `complete()` sin peer, tras rechazo, `prior` obligatorio, firma vacía, versión, endpoint, `destroy()` |

**Comando:**

```powershell
C:\flutter\bin\flutter.bat test --no-pub test/p2p_handshake_integration_test.dart
```

**Resultado:** `00:01 +18: All tests passed!` (`TEST_EXIT=0`).

Los 24 tests negativos originales **no se han modificado ni eliminado**.

---

## 7. Diseño de integración (implementado como capa pura, NO cableado)

### 7.1 Qué se implementó en esta fase

| Artefacto | Estado | Qué hace |
|---|---|---|
| `lib/services/p2p_auth_policy.dart` | Ya existente (Fase E) | Contrato de verificación puro, 24 tests negativos |
| `lib/services/p2p_handshake_session.dart` | **Nuevo** | Orquesta `hello_A`/`hello_B`, valida, encadena transcripts y deriva la clave de sesión |
| `test/p2p_handshake_integration_test.dart` | **Nuevo** | 18 tests de integración con Ed25519/X25519/HKDF reales |
| `NearbyService` | **Sin cambios** | Sigue aceptando conexiones sin handshake |

El orquestador **no** se instancia desde producción. No hay feature flag activo
ni camino alternativo: mientras no se cablee, el comportamiento sigue siendo el
actual (vulnerable a Z-004).

### 7.2 Secuencia del handshake

```text
A (iniciador)                         B (responder)
  createHello() ──── hello_A ────────▶ acceptPeerHello(hello_A)
                                      createHello(prior = H(hello_A))
  acceptPeerHello(hello_B,            ◀──── hello_B ────
                  prior = H(hello_A))
  complete()                          complete()
```

Reglas de la orquestación:

- `hello_A` **no** lleva `prior`; `hello_B` **sí** lleva `prior = SHA-256(hello_A)`.
- El iniciador rechaza un `hello_B` sin `prior` (`transcriptBindingRequired`).
- El responder rechaza un `hello_A` con `prior` (`unexpectedPriorTranscript`).
- `complete()` exige: `hello` local, `hello` remoto, decisión aceptada, `prior`
  correcto y `endpointId` ligado.
- Un rechazo del contrato **no** deriva clave; `complete()` lanza
  `remoteHelloRejected`.
- `destroy()` libera la referencia al efímero; Dart no garantiza zeroización.

### 7.3 Key schedule exacto

```text
dh1 = X25519(eph_I, static_R)
dh2 = X25519(static_I, eph_R)
dh3 = X25519(eph_I, eph_R)
dh4 = X25519(static_I, static_R)

salt    = identity_pk_I ‖ identity_pk_R          (32 + 32 bytes)
master  = HKDF-SHA256(dh1‖dh2‖dh3‖dh4, salt, info="zone-xtdhs-v1")
info    = "zone-session" ‖ 0x00 ‖ SHA-256(hello_B con prior)
session = HKDF-SHA256(master, salt=0^32, info=info)   → 32 bytes
```

- **Por qué el hash final en `info`:** sin él, la clave no queda ligada a los
  nonces/efímeros del handshake. La autoridad (`CRYPTO_CTO_REVIEW.md` §5.2) ya
  exige `info` jerárquico; el separador `0x00` evita colisiones de prefijo.
- **Por qué `salt=0^32` en el segundo HKDF:** RFC 5869 define salt ausente como
  `HashLen` ceros. Se pasa explícito para no depender de la implementación.
- **Por qué no se usa el secreto crudo:** es exactamente el bug actual
  (`p2p_security_service.dart:79-85`). El test de regresión comprueba que
  `session != dh4`.

### 7.4 Asociación handshake ↔ transporte

- `endpointId` se fija en el constructor de la sesión y **nunca** se reasocia.
- `assertEndpoint(incomingEndpointId)` se ejecuta antes de procesar cualquier
  payload de aplicación; un endpoint distinto lanza `endpointMismatch`.
- El `endpointId` **no** se convierte en Zone ID ni en identidad (ya lo exige
  `discovery_policy.dart`).
- Al desconectar, la sesión se destruye y el ancla verificada se conserva solo
  si el usuario confirmó el fingerprint OOB.

### 7.5 Validación, errores y rechazo de negociación incompleta

| Condición | Resultado |
|---|---|
| Campo ausente / firma vacía | `incompleteNegotiation` |
| Versión distinta de `ZONE-P2P-AKE-1` | `unsupportedVersion` |
| Algoritmo intercambiado | `keyPurposeMismatch` |
| Longitud de clave/nonce/firma incorrecta | rechazo tipado |
| `hello_B` sin `prior` | `P2PHandshakeFailure.transcriptBindingRequired` |
| `hello_A` con `prior` | `P2PHandshakeFailure.unexpectedPriorTranscript` |
| `complete()` sin `hello` local/remoto | `localHelloMissing` / `remoteHelloMissing` |
| `complete()` tras rechazo | `remoteHelloRejected` |
| `complete()` dos veces | `alreadyCompleted` |
| Endpoint distinto | `endpointMismatch` |

Ningún error incluye material secreto; `P2PSessionKeyMaterial.toString()` está
redactado.

### 7.6 Rotación y revocación

- **Revocación:** `P2PAuthPolicy` rechaza `deviceStatus != active` o
  `revokedAt != null`. El estado lo aporta el llamador desde el registro local;
  **no** se acepta del cable.
- **Rotación:** un cambio de `identity_public_key` o `encryption_public_key`
  contra el ancla se rechaza (`identityKeySubstitution` /
  `encryptionKeySubstitution`). Una versión mayor exige
  `keyRotationRequired`, es decir, un registro firmado por la identidad de
  cuenta que **todavía no existe**.
- **Consecuencia:** hoy la rotación legítima solo es posible re-anclando por
  OOB. No hay rotación silenciosa ni automática.

### 7.7 Compatibilidad y prevención de downgrade

- La versión es fija: no hay negociación ni fallback. Cualquier otro valor se
  rechaza antes de derivar.
- Las sesiones legacy `sk_<zoneId>` (X25519 crudo) **no** se tocan; siguen
  descifrando historial antiguo. Las sesiones nuevas usan el camino autenticado.
- La migración de derivation v1→v2 se tratará en Fase G con una tabla de
  versiones; no se reescribe el historial.
- Un cliente viejo que no hable `ZONE-P2P-AKE-1` no puede degradar al camino
  sin firma: el receptor debe rechazar y cerrar, no aceptar `profile_exchange`
  como fallback.

### 7.8 Secuencia de cableado en `NearbyService` (pendiente)

1. `_onConnectionInitiated` deja de llamar `acceptConnection` directamente:
   crea una `P2PHandshakeSession` con rol responder y `endpointId`.
2. Envía `hello_A`/recibe `hello_B` por el canal de control (nuevo tipo de
   paquete, no `profile_exchange`).
3. Verifica con `acceptPeerHello`; si falla, cierra la conexión y registra el
   motivo (sin datos sensibles).
4. Solo tras `complete()` acepta `acceptConnection` y deriva la sesión.
5. `profile_exchange.publicKey` deja de ser la fuente de la clave; el `source`
   se toma del `hello` verificado, no del JSON libre.
6. Persiste el `P2PTrustAnchor` solo tras confirmación OOB del fingerprint.
7. Feature flag fail-closed: si el handshake nuevo falla, **no** se vuelve al
   camino inseguro.

#### 7.8.1 Diseño de integración completo (2026-10-27)

Verificación previa contra el código real de esta fecha: `NearbyService` **no
importa** `p2p_handshake_session.dart` ni `p2p_auth_policy.dart`
(`nearby_service.dart`, bloque de imports 1–22), `_onConnectionInitiated`
(línea 905) sigue llamando `acceptConnection` directamente, y
`profile_exchange` sigue aceptando `publicKey` sin firma (líneas 1044-1145).
El orquestador existe y está probado, pero **ninguna parte del contrato está
implementada en producción**. El diseño siguiente es una especificación de
trabajo, no un registro de implementación:

**a) Nodo de integración único.** Todo el cableado se concentra en dos puntos
de `NearbyService`: `_onConnectionInitiated` (instancia la sesión responder con
el `endpointId` recibido; el `ConnectionInfo` **no** se filtra a la
app hasta `complete()`), y el despachador de payloads (línea 1044: nuevo tipo
de paquete de control `p2p_ake_hello` que llega al orquestador **antes** de
cualquier `profile_exchange`/mensaje mesh). El flujo iniciador se cuelga del
`requestConnection`/`connect` existente: al pedir conexión, la sesión
iniciadora **envía** `hello_A` antes de declarar "conectado".

**b) Autenticación de claves e identidad.** El `hello` firma el transcript
canónico con Ed25519 del dispositivo (contrato paso 11); `expectedZoneId` se
extrae de los datos de descubrimiento (endpoint info) y se cruza; `deviceId`
y `account_id` son declarativos en v1 — por eso el ancla nunca se persiste sin
`firstContact` + fingerprint OOB confirmado, y la sustitución contra ancla se
rechaza (pasados 9-11 del contrato). Hueco declarado y sindicado: falta el
`device_certificate` v2 firmado por la cuenta para cerrar la reclamación de
cuenta ajena en el primer contacto (ver 7.9).

**c) Transcript binding.** `hello_B` firma `prior = H(hello_A)` (verificado en
`complete()`); el iniciador rechaza `hello_B` sin `prior`. Cualquier
modificación de cualquier campo del canal impide reconstruir el mismo
transcript y rompe la firma o el binding: no hay forma de continuar con la
clave esperada. El AAD por mensaje se añade en Fase G, no en este cableado.

**d) Nonces y anti-replay.** Cada `hello` lleva nonce de 32 bytes aleatorios
e `issued_at_ms` acotado (TTL 2 min, skew 30 s); `session_id` v4 y la caché
LRU con TTL 10 min impide reusar handshakes. Especificación del cableado:
una `P2PHandshakeSession` por conexión activa, destruida al desconectar; los
mensajes post-handshake se deduplican con la idempotencia/ack de
`MeshPolicy` ya existente (no se duplica estado).

**e) Asociación handshake ↔ transporte.** `endpointId` se fija con el
constructor y nunca se reasocia (`assertEndpoint` antes de cada payload de
aplicación; un paquete que llegue por otro endpoint invalida la sesión).
`discoverEndpoint/ConnectionInfo` nunca aporta identidad: solo el `hello`
firmado. Binding fuerte: `endpointId` + `session_id` + transcript hash.

**f) Validación, errores y rechazo de negociación incompleta.** Toda decisión
del contrato lleva razón tipada (`incompleteNegotiation`, `unsupportedVersion`,
`keyPurposeMismatch`, longitudes exactas, etc.); el orquestador añade
`transcriptBindingRequired`, `unexpectedPriorTranscript`, `endpointMismatch`,
`localHelloMissing`, `remoteHelloRejected`. Reglas de integración: (1) un
rechazo **nunca** deriva clave ni guarda ancla; (2) el motivo se registra
sin material secreto y con detalle saneado; (3) un error de protocolo
**cierra** la conexión — ningún reintento automático sobre el canal inseguro:
cada reconexión re-negocia con efímeros frescos.

**g) Rotación y revocación.** `deviceStatus`/`revokedAt` provienen solo del
registro local de confianza (fase actual: la foundation local en Isar
`zone_identity`; tras la Decisión F, la tabla `device_revocations`
server-side). Rotación: una versión mayor de `encryption_key_version`
conduce a `keyRotationRequired`, que exige un registro firmado por la
identidad de cuenta que **aún no existe**. Resultado operativo actual:
no hay downgrade silencioso, y la rotación legítima no puede ocurrir
sin el registro firmado (aceptable para una beta con un dispositivo activo
por cuenta).

**h) Compatibilidad y prevención de downgrade.** Versión fija
`ZONE-P2P-AKE-1` — no hay negociación ni fallback, y el receptor sin ancla no
recae al path TOFU actual: si no hay ancla y no hay handshake, **no hay
conexión**. Un cliente legado que solo hable `profile_exchange` sin firma
quedará sin servicio en el feature activado (criterio de versión mínima de
app, igual que Z-212). Las sesiones legacy `sk_<zoneId>` se conservan para
seguir descifrando el historial antiguo (Fase G); los contactos **nuevos**
solo por el camino autenticado.

**i) Pruebas de integración del cableado (contrato, no ejecutadas aún; se
agregarán sobre los 18 actuales sin sustituirlos):**

| ID | Escenario | Resultado esperado |
|---|---|---|
| WI-1 | Conexión con `hello` firmado + ancla | sesión válida; la clave coincide en ambos lados |
| WI-2 | `profile_exchange` recibido antes del handshake | descartado + conexión cerrada (no alimenta la derivación) |
| WI-3 | Handshake fallido → `acceptConnection` nunca invocado | sin sesión, sin clave, estado limpio |
| WI-4 | Payload por endpoint distinto del ligado | `endpointMismatch`, sesión invalidada |
| WI-5 | Cliente viejo sin `ZONE-P2P-AKE-1` | rechazo tipado; **no** cae a TOFU |
| WI-6 | Rechazos repetidos del mismo par | rate-limit local (protección de radio, no criptográfica) |
| WI-7 | Peer con ancla y versión rollback | `keyVersionRollback`, sin sesión |

**j) Criterio de cierre de Z-004** (no cambia respecto a 7.9; se concreta el
método de demostración): cerrarlo requiere que, con la integración activa en
un dispositivo con ancla confirmada por OOB, se demuestre en dos dispositivos
físicos que un atacante en la radio no puede: (1) presentarse como otro
`zone_id` (WI-5/AC-08); (2) sustituir la clave de identidad o de cifrado
respecto al ancla (AC-04/AC-05); ni (3) obtener una sesión sin la clave
privada Ed25519 del dispositivo anclado (todo rechazo deriva 0 bytes). Esa
demostración física es la evidencia que falta; los tests locales solo cubren
la parte determinista.

#### 7.8.2 Matriz de trazabilidad WI-1…WI-7 → código y pruebas (2026-10-27, gate CTO)

Auditoría de trazabilidad pedida por el gate. Sin cambios de código. Estados:
**PROBADO** = demostrado por prueba ejecutada en la línea base local (289/289,
2026-10-27); **SIN CABLEAR** = existe en el orquestador/capa pura, pero
`NearbyService` no lo invoca; **NO IMPLEMENTADO** = no hay código ni prueba.
Ninguna fila declara Z-004 cerrado (§7.9 sigue íntegro).

| WI | Componente responsable | Estado real en el código | Prueba que lo demuestra hoy | Ataques/fallos aún no cubiertos | Cambio mínimo necesario |
|---|---|---|---|---|---|
| WI-1 | `_onConnectionInitiated` (`nearby_service.dart:905`) + iniciador en `requestConnection` + `P2PHandshakeSession.complete()` | Sesión **PROBADO**; integración **SIN CABLEAR** (0 referencias a `p2p_handshake_session.dart` en `nearby_service.dart`) | `p2p_handshake_integration_test.dart`: "handshake completo" — misma clave y transcript en ambos lados, separación de roles, efímeros frescos | MITM físico en la radio y fuga de `ConnectionInfo` real antes de `complete()` — demo en dos dispositivos (PHASE_H, 0/15) | Cableado (a) de §7.8.1: sesión por conexión; no exponer canal hasta `complete()` |
| WI-2 | Despachador de payloads (`nearby_service.dart:1044`) | **NO IMPLEMENTADO en producción**: `profile_exchange` entra sin firma hoy | Session-level: "un hello sin firma se rechaza como negociación incompleta" (integración) | Downgrade a intercambio plano (TOFU) si el gate se salta al cablear parcialmente | Tipo de control `p2p_ake_hello` interceptado **antes** de `profile_exchange`; descartar + cerrar |
| WI-3 | `_onConnectionInitiated` (`nearby_service.dart:907` hoy llama `acceptConnection` directo) | **NO IMPLEMENTADO** en producción; a nivel sesión **PROBADO** | "complete() sin hello remoto no deriva clave", "complete() tras un rechazo no deriva clave", "destroy() impide completar" | Reintentos automáticos sobre canal inseguro; escrituras de estado parcial en cliente | `acceptConnection` solo tras sesión confirmada; regla (f)(3) §7.8.1 |
| WI-4 | `P2PHandshakeSession.assertEndpoint` (`:326`) + binding endpoint↔sesión en el despachador | Sesión **PROBADO**; binding del despachador **SIN CABLEAR** | "un endpoint distinto invalida la sesión" (`endpointMismatch`) | Alias de endpoint tras reconexión (mitigado: cada reconexión re-negocia con efímeros frescos) | `assertEndpoint` en cada payload entrante |
| WI-5 | Despachador + versión fija del orquestador | Versión **PROBADA** a nivel sesión; en producción se caería al path TOFU actual | "una versión no soportada se rechaza (sin downgrade)" | Flota legada sin servicio al activar (mínimo de app, como Z-212) | Gate del despachador + versión mínima de app documentada |
| WI-6 | Rate-limit local (nuevo; no criptográfico) | **NO IMPLEMENTADO** | — | Spam/DoS de radio (también en producción actual) | Contador LRU con TTL por peer (patrón `MeshDedup`) + test WI-6 |
| WI-7 | `P2PAuthPolicy` (ancla) | **PROBADO** | `p2p_auth_negative_test.dart`: `keyVersionRollback`, `keyRotationRequired`; integración: re-firma del atacante no supera el ancla | Rotación legítima imposible: no existe registro firmado (`device_certificate` v2, §7.9) | Rechazo: nada que cambiar; rotación: registro firmado por cuenta (Fases F/G) |

**Chequeo horizontal (7 aspectos exigidos por el gate):** autenticación mutua
**PROBADA** (hello_A firmado; hello_B firma `prior = H(hello_A)`); binding de
claves a identidad **PROBADO contra ancla** / **SIN CABLEAR sin ancla** (v1 con
`account_id` declarativo — hueco §7.9); replay **PROBADO** (nonce 32 B, TTL 2
min + skew, `session_id` v4, caché LRU 10 min); negociación **PROBADA** sin
downgrade; cancelación/expiración **PROBADA** (`destroy()`, rechazo por TTL,
expiración de caché anti-replay) y **SIN CABLEAR** a nivel transporte; errores
**PROBADOS** con razones tipadas (reglas de integración §7.8.1(f)); registro
seguro **PARCIAL**: regla §7.8.1(f)(2) sin material secreto — la suite de
identidad demuestra errores tipados sin secreto; el handshake demuestra
rechazos tipados sin aserción explícita de no-filtración de detalle saneado.

**`device_certificate` v2 y dependencia con el login existente.** El `hello` v1
no lleva certificado de dispositivo firmado por la cuenta y `account_id` es
declarativo. Emitir el certificado exige: (1) fundación de identidad
server-side (Decisión F §10.3 — A2 objetivo o shim A1), (2) `register_device`
firmado por la Ed25519 de cuenta, y (3) tabla de revocación (ambigüedad #5 de
PHASE_F §3.2.5, resolución propuesta en §10.4 — **no aprobada**). Orden de
dependencia: **P0-3 (decisión de login) precede al cierre de P0-2**. El
cableado de P0-2 puede implementarse antes con ancla OOB local, pero el cierre
de la reclamación de cuenta ajena en primer contacto (Z-004) no puede
declararse sin (1)-(3) y la demostración física (j) §7.8.1.

### 7.9 Huecos que impiden cerrar Z-004

| Hueco | Por qué importa | Estado |
|---|---|---|
| El `hello` v1 no lleva certificado de dispositivo firmado por la cuenta | `account_id` es declarativo; un atacante puede declarar cualquier cuenta con su propia device key | **Abierto** — requiere `device_certificate` v2 o registro firmado |
| Primer contacto TOFU | Sin OOB, la sustitución de identidad en el primer contacto no es detectable | **Abierto** — requiere UI de fingerprint |
| Fuente de revocación | El estado `deviceStatus` es una entrada local; no hay lista firmada ni consulta server-side | **Abierto** — Fase F/G |
| Sin cableado | `NearbyService` sigue aceptando sin handshake | **Abierto** — este diseño no cambia producción |
| Rotación legítima | No hay registro firmado de rotación | **Abierto** — Fase F/G |

**Por tanto Z-004 sigue ABIERTO.** Los 18 tests demuestran que la sustitución
se detecta **cuando ya existe un ancla**; no demuestran que el primer contacto
sea seguro.

### 7.10 Evidencia

```text
flutter analyze --no-pub lib/services/p2p_handshake_session.dart \
  lib/services/p2p_auth_policy.dart test/p2p_handshake_integration_test.dart
→ No issues found!

flutter test --no-pub test/p2p_handshake_integration_test.dart
→ 00:01 +18: All tests passed!

flutter test --no-pub test/p2p_auth_negative_test.dart
→ 00:01 +24: All tests passed!
```

Los 24 tests negativos originales siguen intactos; los 18 nuevos se añaden sin
sustituirlos.

---

## 8. No objetivos

Este trabajo **no**:

- Cablea el handshake en `NearbyService`.
- Persiste, rota ni revoca llaves de sesión en producción.
- Sustituye `profile_exchange` en el camino real.
- Añade AAD ni ratchet (Fase G).
- Implementa el certificado de dispositivo firmado por la cuenta.
- Implementa la UI de fingerprint OOB.
- Resuelve Z-001 (`claim_zone_id`) ni la recuperación de cuenta (Fase F).
- Cambia el esquema de Supabase.
- Habilita ningún claim de seguridad en la UI.

Sí implementa, como capa pura y testeable, la derivación HKDF del key schedule
para que el cableado no improvise criptografía. No se ejecuta desde producción.

Por tanto, **Z-004 permanece abierto** y el gate de beta sigue **NO-GO**.

---

## 9. Evidencia

```text
flutter analyze --no-pub lib/services/p2p_auth_policy.dart \
  lib/services/p2p_handshake_session.dart \
  test/p2p_auth_negative_test.dart test/p2p_handshake_integration_test.dart
→ No issues found!

flutter test --no-pub test/p2p_auth_negative_test.dart
→ 00:01 +24: All tests passed!  (TEST_EXIT=0)

flutter test --no-pub test/p2p_handshake_integration_test.dart
→ 00:01 +18: All tests passed!  (TEST_EXIT=0)
```

- `lib/services/p2p_auth_policy.dart` — contrato puro, sin ECDH/KDF.
- `lib/services/p2p_handshake_session.dart` — orquestador + key schedule HKDF,
  no cableado.
- `test/p2p_auth_negative_test.dart` — 24 tests del contrato.
- `test/p2p_handshake_integration_test.dart` — 18 tests de integración.
- `docs/CRYPTO_CTO_REVIEW.md` §5/§6 — diseño autoritativo.
- `docs/PHASE_2_CRYPTO_DECISIONS.md` — D1/D2.
- `docs/PHASE_2_FINGERPRINT_SPEC.md` — fingerprint OOB.

---

## 10. Riesgos residuales

| Riesgo | Estado | Mitigación |
|---|---|---|
| Producción sigue sin handshake | **Abierto** | Cablear §7.8 |
| Primer contacto TOFU sin UI OOB | **Abierto** | Fase G + UI |
| `account_id` declarativo (sin certificado de device) | **Abierto** | `device_certificate` v2 firmado por cuenta |
| `info` del HKDF incluye el hash final | **Pendiente de revisión CTO** | Documentado en §7.3; no cambia el wire format |
| Sin AAD/ratchet | **Abierto** | Fase G |
| Estado de revocación no consultado en P2P | **Abierto** | Fase F/G (registro firmado/servidor) |
| Caché anti-replay local por dispositivo | Aceptado | TTL corto; multi-dispositivo en Fase G |
| Rotación legítima de clave no implementada | **Abierto** | Registro firmado (Fase F/G) |
| Reloj del dispositivo manipulado | Aceptado | TTL + skew; el servidor puede acotar en Fase G |
| Zeroización del efímero en Dart | Aceptado | `destroy()` libera la referencia; no garantiza borrado de memoria |

---

## 11. Decisión de gate

- **Z-004:** diseño completado, contrato + orquestador probados, **sin cablear**.
  No se cierra: falta el certificado de device, la UI OOB, la fuente de
  revocación y la prueba física de dos dispositivos.
- **Beta:** **NO-GO** hasta cablear §7.8 y validar en dos dispositivos.
- No se ha tocado staging/producción, no se ha hecho commit y HEAD sigue en
  `7f59b776c62cc131fd05dc999e99cbb7804385e8`.
