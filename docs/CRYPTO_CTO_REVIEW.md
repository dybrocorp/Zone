# CRYPTO_CTO_REVIEW — Protocolo Criptográfico de ZONE

> **Tipo de documento:** Especificación técnica + revisión CTO (PUERTA de decisión).
> **Fecha:** 2026-09-23 (actualizado 2026-09-24 con FASE 2.0) · **Estado:** REVISIÓN PENDIENTE DE CTO — **NO IMPLEMENTAR**
> **Regla:** Nada de este documento se implementa sin aprobación explícita. Pausa de
> implementación vigente: no modificar código, no crear migraciones, no modificar
> Supabase, no cambiar protocolos.
>
> **FASE 2.0 (2026-09-24):** este documento madre se complementa con el conjunto de
> diseño de identidad/dispositivos/migración:
> `PHASE_2_IDENTITY_ARCHITECTURE.md`, `PHASE_2_DEVICE_MODEL.md`,
> `PHASE_2_MIGRATION_PLAN.md`, `PHASE_2_THREAT_MODEL.md`, `PHASE_2_CRYPTO_DECISIONS.md`,
> `PHASE_2_CTO_REVIEW_REQUIRED.md`, `PHASE_2_CTO_HANDOFF.md`. Las decisiones D1–D14 de
> FASE 2.0 refinan y sustituyen las decisiones preliminares B0–B6 de la sección 8 de
> este documento; el checklist de aprobación vive ahora en `PHASE_2_CTO_REVIEW_REQUIRED.md`.
>
> **FASE 2.0.2 (2026-09-24):** quedan **SUPERADAS o precisadas** por las políticas 2.0.2:
> §4.2/§5.1/§5.2/§10 (fingerprint → `PHASE_2_FINGERPRINT_SPEC.md`, OPEN-002/016),
> §7.1/§7.3 (blob de recovery → `PHASE_2_RECOVERY_POLICY.md`, OPEN-001), la estrategia
> **B2** de §8 y la RLS directa de §7.1 (→ `PHASE_2_LEGACY_ACCESS_POLICY.md` y solo-RPC,
> OPEN-011/I-014), y el checklist §12 (→ puerta `PHASE_2.0.2_CTO_GATE.md`).

---

## 0. Resumen ejecutivo

ZONE cifra los mensajes con **X25519 (ECDH estático) + ChaCha20-Poly1305 (AEAD)** y
nunca transporta texto en claro de mensajes por la malla (fail-closed, Z-003/Z-005).
Eso es real y se verifica en el código.

Pero hay garantías que **el código NO demuestra** y que hoy se asumen por costumbre:

- **No existe Forward Secrecy.** El secreto compartido es el resultado de ECDH entre
  dos claves X25519 **estáticas de largo plazo**; es el mismo para toda la conversación.
  El comentario `chat_e2ee_service.dart:59` *"garantizando Forward Secrecy"* es **incorrecto**.
- **No existe autenticación criptográfica del peer** (sin firmas, sin fingerprints,
  sin comparación out-of-band): hay **MITM posible** en el primer contacto mesh (perfiles en
  claro por radio) y en el primer contacto cloud (la public_key la sirve el servidor sin
  anclaje firmado).
- **No existe ratchet**, ni claves efímeras, ni KDF sobre el shared secret (la "session
  key" es el shared secret X25519 crudo en base64, sin HKDF), ni AAD ligando el
  ciphertext al match/remitente/mensaje.
- **Login sin prueba de posesión de clave:** la credencial es `ZONE-XXXXXXXX` (~41 bits)
  por conocimiento; `claim_zone_id` mueve la fila `users` a cualquier uid autenticado que
  conozca el código, sin desafío firmado con la clave privada.
- **Cambio de dispositivo rompe el E2EE cloud** y no se puede reparar: la clave privada
  nunca sale del dispositivo, la public_key archivada en Supabase jamás se rota → el MAC
  falla para siempre contra el historial y los contactos.

Este documento establece, para aprobación, el **protocolo objetivo**: identidad de cuenta
**Ed25519** (firma, recovery codes, login con prueba de posesión) **separada** del
**X25519** (cifrado), más **KDF + AAD** primero, y **Double Ratchet** como base evaluada
para lograr forward secrecy y post-compromise security.

**Regla de hierro del objetivo:** `X25519` se usa **exclusivamente** para ECDH/cifrado.
**NO se firmará con X25519** ni se inventarán firmas sobre él. Las firmas las aporta la
identidad **Ed25519**.

---

## 1. Arquitectura actual (estado verificado, 2026-09-23)

### A. Identidad

| Elemento | Qué es | Evidencia |
|---|---|---|
| `zone_id` | IDENTIFICADOR DE CUENTA público, formato `ZONE-` + 8 chars `[A-Z0-9]` (~41 bits). **Es la única credencial de login (secreto por conocimiento)** | Generación `zone_id_service.dart:558-565`; validación cliente `:553-556`, servidor `supabase_schema.sql:656,723` |
| `users.id` | UUID de Supabase Auth **anónimo** (`signInAnonymously()`), no es identidad estable | `zone_id_service.dart:187-193`; `supabase_schema.sql:14` |
| `users.public_key` | Clave pública **X25519** base64, estática de largo plazo, subida en registro y preservada (nunca rotada) | `supabase_schema.sql:17`; `zone_id_service.dart:209-214`; preservación `:357-369,408-421` |
| Claves privadas | X25519 privada en FlutterSecureStorage (`encryptedSharedPreferences`) keys `private_key`/`public_key` | `p2p_security_service.dart:12-16,20-49` |
| Session keys | Shared secret X25519 **crudo** (sin KDF), por `remoteZoneId`, key `sk_<zoneId>` en SecureStorage | `p2p_security_service.dart:52-64,70-74` |
| **Ed25519** | **NO EXISTE** en producción (solo comentarios de "Fase B") | `zone_id_service.dart:360`; `supabase_migrations/secure_claim_zone_id.sql:14-15` |
| **Recovery codes** | **NO EXISTEN** | — |
| **auth_public_key / firma de identidad** | **NO EXISTEN** | — |

**Inconsistencia conocida:** `P2PSecurityService.initialize()` corre en el arranque
(`initial_loading_screen.dart:57-60`) ANTES del registro; al registrarse
`_registerInSupabase` genera un **segundo** keypair y sobrescribe el storage sin refrescar
`_publicBase64` (`p2p_security_service.dart:47`). Durante el primer arranque, el mesh
anunciaría una public key obsoleta en `profile_exchange` (`nearby_service.dart:900-901`).

### B. Chat E2EE (cloud + mesh)

| Etapa | Implementación actual | Evidencia |
|---|---|---|
| Generación de claves | X25519 nuevo keypair | `chat_e2ee_service.dart:21-24` |
| Almacenamiento | SecureStorage cifrado (Android keystore / iOS keychain) | `p2p_security_service.dart:12-16` |
| Intercambio (cloud) | Se LEEN `public_key` del otro vía `v_profile`/queries. **El servidor entrega la clave del peer sin anclaje firmado** | `chat_screen.dart:194-197`; `supabase_schema.sql:243` |
| Intercambio (mesh) | `profile_exchange` en claro por radio con `publicKey`/`public_key` | `nearby_service.dart:889-906,918-924` |
| Derivación de sesión | ECDH estático X25519 → shared secret **crudo** base64, sin HKDF, sin info o salt | `chat_e2ee_service.dart:39-45`; `p2p_security_service.dart:52-64` |
| Cifrado | ChaCha20-Poly1305 AEAD, nonce aleatorio por mensaje, **sin AAD** | `chat_e2ee_service.dart:60-79` |
| Autenticación AEAD | MAC (Poly1305) sobre ciphertext+nonce; al fallar → placeholder `🔒 Mensaje cifrado con llaves anteriores` | `chat_e2ee_service.dart:93-109` |
| Descifrado | Reconstruye SecretBox y descifra; `SecretBoxAuthenticationError` → placeholder | `chat_e2ee_service.dart:82-114` |
| Persistencia | Outbox en Isar guarda **solo ciphertext+nonce+mac**; histórico igual | `chat_screen.dart:536-544`; `isar_service.dart` (sin cifrado de la DB local) |
| Eliminación | `deleteSessionKey/deleteAllSessionKeys`; borrado de cuenta borra bucket + row + local | `p2p_security_service.dart:96-115`; `zone_id_service.dart:571-615` |
| Backup/restore | **NO EXISTE** | — |

### C. Mesh / Nearby

| Etapa | Implementación actual | Evidencia |
|---|---|---|
| `profile_exchange` | P2P en claro con datos de perfil + `public_key`; el receptor deriva y guarda session key | `nearby_service.dart:885-962` |
| Descubrimiento | BLE con token efímero (UUID v4 TTL 10 min) o pseudónimo offline `OFFLINE:`; el nombre BLE es el token, no el zone_id | `nearby_service.dart:446-465`; `ble_proximity_service.dart:30-37` |
| Resolución token→perfil | RPC `resolve_bt_token` (authenticated; **cualquier autenticado resuelve cualquier token activo**; el token NUNCA se marca `used`) | `supabase_schema.sql:409-410,753-789,61` |
| Autenticación del peer | **NO criptográfica**: todas las conexiones entrantes se auto-aceptan | `nearby_service.dart:772-775` |
| Derivación sessionKey | Igual que chat: ECDH estático crudo, guardada `sk_<zoneId>` **sin expiración** | `p2p_security_service.dart:52-94` |
| Relay | Paquetes `profile_exchange`/`routing_table` en claro; `mesh_msg` cifrado AEAD fail-closed; flood o ruta; hops máx 5 | `nearby_service.dart:868-1077,1115-1173` |
| Deduplicación | `MeshDedup` LRU+TTL 15 min, `msgId` UUID v4; cubre duplicados de red, no replay criptográfico | `mesh_policy.dart:64-123,146-163` |
| Expiración de sesiones | Session keys **no expiran**; rutas caducan 30 min | `isar_service.dart:134-142`; `nearby_service.dart:138-140` |
| Transporte | `nearby_connections 4.3.0` **sin cifrado de capa de enlace** en el API usado → `profile_exchange`/`routing_table` viajan en claro por radio | pub-cache `nearby.dart:165-274` |

### D. Lifecycle

| Momento | Qué ocurre criptográficamente | Evidencia |
|---|---|---|
| Instalación | Se crea keypair X25519 (SecureStorage). El ZONE-ID se genera al pulsar "Comenzar" | `initial_loading_screen.dart:57-60`; `zone_id_service.dart:69-107` |
| Registro | `signInAnonymously()` + `users.upsert({id, zone_id, public_key})`; guarda claves locales | `zone_id_service.dart:184-236` |
| Login explícito | `signInAnonymously()` → `claim_zone_id(p_zone_id)` (mueve la fila al nuevo uid; **no exige desafío firmado**); luego `ensureAuth` restaura o (si falta) genera KNUEVA clave local sin rotar la archivada | `zone_id_service.dart:111-178`; `secure_claim_zone_id.sql` |
| Logout real | `clearAuth` borra zone_id, claves, session keys, signOut | `zone_id_service.dart:618-634` |
| Cierre por lifecycle | `endRuntimeSession` SOLO signOut + borra uid; **conserva claves y session keys** | `zone_id_service.dart:537-545` |
| Cambio de dispositivo | Se pierde el material local; se recupera perfil vía zone_id; la privada es irrecuperable; la public archivada no se rota → **MAC falla vs contactos** | `zone_id_service.dart:357-369`; `chat_e2ee_service.dart:105-109` |
| Reinstalación | Keypair nuevo local + public archive vieja → estado **inconsistente cloud vs mesh** | `zone_id_service.dart:268-299`; `nearby_service.dart:934` |
| Eliminación de cuenta | Borra bucket, `delete_own_account` (cascada users+auth), Isar, prefs, claves | `zone_id_service.dart:571-615` |

---

## 2. Modelo de amenazas

| # | Amenaza | Qué puede hacer hoy | Protección actual | Protección faltante | Impacto |
|---|---|---|---|---|---|
| T1 | Atacante de red (WiFi/móvil, sniffing) | Lee `profile_exchange`, `routing_table`, tokens BT en claro; captura nonce+ciphertext+MAC de `mesh_msg` y de tráfico HTTPS (no si TLS OK) | Cifrado AEAD del contenido de `mesh_msg`; TLS en cloud | Cifrado/perfeccional del transporte mesh; firma del perfil | Medio: fuga de metadatos y perfiles; contenido ilegible sin claves |
| T2 | Peer malicioso en proximidad | Envía `profile_exchange` falso/robado; se auto-accepta la conexión; puede volverse next-hop del mesh | Fail-closed en contenido; dedup | **Autenticación del peer** (sin ella puede activamente MITM/forwardear basura) | **Alto**: identidad falsa; MITM del canal mesh |
| T3 | Usuario que conoce un ZONE-ID | `signInAnonymously` + `claim_zone_id` y adueñarse del perfil/mensajes (sin prueba de clave) | Rate-limit por zone_id (5/15 min); formato estricto | **Prueba de posesión de clave privada** (challenge firmado) | **Crítico**: apropiación total de cuenta |
| T4 | Dispositivo comprometido (malware con acceso a SecureStorage) | Accede a clave privada X25519 + todas las session keys → descifra TODO | SecureStorage cifrado con keystore | FS (compromiso no debe descifrar historial); detección/revocación | **Crítico** |
| T5 | Servidor Supabase comprometido (DB + auth) | Expone claves públicas, ciphertext, metadatos; **no posee privadas** pero puede manipular quién ve qué | Secreto privado nunca en servidor; RLS | FS (historial no descifrable con claves de sesión pasadas); integridad de la clave pública servida | Medio: sin FS el historial se descifra si se compromete una clave estática |
| T6 | Base de datos comprometida | Lee ciphertext+nonce+mac (asintomático sin claves); puede reinsertar mensajes en matches | AEAD detecta alteración | Contexto vinculante (AAD) y autenticidad de origen | Bajo con AEAD; orden de bloques no protegidos |
| T7 | Replay de mensajes | Reinsertar un mensaje cifrado viejo con otro nonce/id; dedup solo temporal | `msgId` UUID + dedup LRU/TTL mesh; idempotencia outbox | **nonce/timestamp autenticado + caducidad de mensajes**; sequence numbers | Medio |
| T8 | Impersonación de peer | En mesh: envía `profile_exchange` con public_key ajena (la DB la entrega sin firma en cloud también) | Ninguna criptográfica | Clave pública **firmada Ed25519** + anclaje verificado en registro | **Crítico** |
| T9 | Pérdida/robo del dispositivo | Se pierde la clave privada (ya no se descifra historial) y el acceso por zona_id queda expuesto si el código se conoce | SecureStorage cifrado | Recovery codes + borrado remoto/bloqueo | Alto (disponibilidad) |
| T10 | Reinstalación | Estado inconsistente cloud vs mesh; MAC falla vs contactos; sin vía de reparación | `profile_exchange` regenera mesh entre pares cercanos | Device binding + upgrade/re-issue de clave autenticado (firma Ed25519) | Alto |

---

## 3. Garantías reales (sin asumir)

| Propiedad | Estado | Nota / evidencia |
|---|---|---|
| Confidencialidad del contenido en tránsito/alojado | ✅ **IMPLEMENTADO** | AEAD ChaCha20-Poly1305 sobre contenido; outbox persistido solo como ciphertext (`chat_e2ee_service.dart:60-79`; `chat_screen.dart:536-544`) |
| Integridad / autenticación AEAD del contenido | ✅ **IMPLEMENTADO** (intra-mensaje) | MAC Poly1305; fallo → placeholder (`chat_e2ee_service.dart:93-109`) |
| Fail-closed del malla (sin texto en claro de mensajes) | ✅ **IMPLEMENTADO** | `MeshPolicy` (`mesh_policy.dart:125-163`); `sendMeshMessage` (`nearby_service.dart:1025-1053`) |
| Deduplicación/replay de red | ✅ **PARCIAL** (red) | LRU/TTL + UUID (Z-005). **No** cubre replay por re-insert del actor autorizado |
| **Forward Secrecy** | ❌ **NO IMPLEMENTADO** | ECDH estático; mismo secreto toda la conversación; el airtight comentario en `chat_e2ee_service.dart:59` es falso |
| **Post-Compromise Security** | ❌ **NO IMPLEMENTADO** | — |
| KDF sobre shared secret | ❌ **NO IMPLEMENTADO** | Session key = shared secret crudo (`p2p_security_service.dart:57-59`) |
| AAD / contexto ligado al mensaje | ❌ **NO IMPLEMENTADO** | `encrypt` sin AAD (`chat_e2ee_service.dart:62-65`) |
| Autenticación del peer / protección MITM | ❌ **NO IMPLEMENTADO** | Sin firmas; `_onConnectionInitiated` auto-acepta (`nearby_service.dart:772-775`); `resolve_bt_token` abierto a cualquier authenticated |
| Key rotation / versionado de claves | ❌ **NO IMPLEMENTADO** | `public_key` jamás se rota; sin `update_public_key` SQL |
| Multi-dispositivo | ❌ **NO IMPLEMENTADO** | Un solo keypair por instalación; reclamar destruye el estado del otro |
| Replay criptográfico | ❌ **NO IMPLEMENTADO** | Dedup es de red, no criptográfica; sin sequence binding |
| Device binding del login | ❌ **NO IMPLEMENTADO** | `claim_zone_id` sin prueba de posesión |
| Recuperación (recovery codes / backup) | ❌ **NO IMPLEMENTADO** | — |
| Confidencialidad del historial tras compromiso | ❌ **NO VERIFICABLE** | Depende de claves estáticas |
| Cifrado de la DB local (Isar) | ⚠️ **PARCIAL** | Mensajes guardados como ciphertext; perfiles/rutas/outbox en claro; Isar sin `encryptionKey` |
| Anclaje de la clave pública al servidor | ❌ **NO VERIFICABLE / NO IMPLEMENTADO** | La public_key viaja por API sin firma ni certificado de clave |

---

## 4. Arquitectura objetivo

### 4.1 Principios

1. **Separación de identidades**: 
   - **Identidad de CUENTA = Ed25519** (firma): demuestra posesión y autoriza operaciones
     de identidad (login, claim, rotación de X25519, recovery). **Jamás cifra.**
   - **Identidad de SESIÓN/CIFRADO = X25519** (ECDH): establece secretos compartidos.
     **Jamás firma.** (Regla explícita: X25519 NO se usa para firmar).
2. **Todo intercambio de mensajes pasa por un KDF (HKDF-SHA256)** con dominio de separación
   (contexto: `peer`, `match_id`, `view`, `epoch`) y **AAD** (AEAD con `match_id|sender|msg_id`).
3. **Forward Secrecy** vía claves efímeras + ratchet (ver §6).
4. **Posesión demostrable** en login y en rotación de claves (challenge-response firmado).
5. **Recuperación sin exponer claves privadas** (wrap E2EE del material privado con el
   recovery secret; el servidor solo guarda hashes + blob cifrado, §7).
6. No romper el historial existente durante la migración (sección §11/§12).

```
IDENTIDAD DE CUENTA (Ed25519)
        │  firma (login/claim, recovery, rotación de X25519, prekeys)
        ▼
IDENTIDAD DE CIFRADO (X25519 estática + efímeras)
        │  ECDH → HKDF(shared, context) → session keys (ratchet)
        ▼
AEAD ChaCha20-Poly1305 (o AES-256-GCM) con AAD = match|sender|msgId
```

### 4.2 Tabla de decisiones

| Decisión | Opciones | Recomendación inicial (a validar por CTO) |
|---|---|---|
| Firma | Ed25519 (RFC 8032) vía `cryptography` pkg | Ed25519 — el paquete ya está en `pubspec` |
| ECDH | X25519 (sin cambios) | X25519 (mantener) |
| AEAD | ChaCha20-Poly1305 (actual) o AES-GCM | Mantener ChaCha20-Poly1305 (ya auditado en runtime) + **AAD obligatorio** |
| KDF | HKDF-SHA256 (RFC 5869) | HKDF-SHA256 con `info` jerárquico y `salt` = public_keys concatenadas |
| Ratchet | Double Ratchet (Signal) vs ratchet propio | **Double Ratchet** (ver §6 comparación) |
| Anclaje PK | Embedded/archivada + firma Ed25519 en el primer uso | ⚠️ **Superado (FASE 2.0.2):** la Ed25519 vive en `account_identity` (R-024); fingerprint v1 en FINGERPRINT_SPEC; verificado en registro y cada `profile_exchange` |
| Recovery | Códigos + blob wrap vs backup puro | Códigos de recuperación (hash servidor) + wrapped private key (client-side) |

---

## 5. Z-004 — Handshake de autenticación (diseño, NO implementar)

> Objetivo: autenticar al peer con **prueba de posesión** antes de derivar sesión y, en
> el primer contacto, **anclar la clave pública real** para matar al MITM.

### 5.1 Precondiciones (anclaje de identidad)

1. Al registrar/crear cuenta, el cliente genera **Ed25519 identity keypair** además de la
   X25519. Sube a `users`:
   - `identity_public_key` (Ed25519 pública, base64)
   - `identity_fingerprint` = **fingerprint v1** de `PHASE_2_FINGERPRINT_SPEC.md`
     (SHA-256 + Base32 20 chars, ACCOUNT/DEVICE — sin X25519; ⚠️ §5.1/§5.2 quedan superados
     aquí y su anclaje real vive en `account_identity`, R-024/OPEN-002).
2. `claim_zone_id` / login: el RPC **NO** mueve la fila sin exigir firma (ver §5.3).
   ⚠️ **FASE 2.0.2:** el claim pasa a **acotado** (`mode=legacy` sin devices) hasta M5 —
   `PHASE_2_LEGACY_ACCESS_POLICY.md` (OPEN-011).
3. La clave pública X25519 del otro SE OBTIENE del server, pero su **integridad** se
   valida con la **firma del dueño** (poseedor de la Ed25519) cuando sea posible, o con
   el fingerprint por un canal segregado (QR / NFC / comparación manual de letras).

### 5.2 Protocolo (bidireccional, transcripto)

```
A → B:  hello_A = { A.identity_pk, A.x25519_pk, A.eph_pk,
                    sigA = Sign(A.sk, transcript[:hello_A]),
                    nonceA, tsA, intent }
B → A:  hello_B = { B.identity_pk, B.x25519_pk, B.eph_pk,
                    sigB = Sign(B.sk, transcript[:hello_B]),
                    nonceB, tsB, intentB }
A → B:  ack_A = { sigA2 = Sign(A.sk, transcript[:ack_A]) }   (opcional, confirmación)
```

Campos:
- `identity_pk` — Ed25519 pública (la del anclaje archivado).
- `x25519_pk` — clave de cifrado de largo plazo (estática).
- `eph_pk` — clave efímera X25519 (una por handshake) → aporta FS en la sesión.
- `sig*` — firma Ed25519 sobre el **transcript acumulado** (todos los bytes previos del
  handshake, incluidos nonces, timestamps, keys e intents). Transcript binding total.
- `nonceA/nonceB` — aleatorios de 32B; evitan replay.
- `tsA/tsB` — TTL del handshake (p.ej. 60 s registrados en el transcript).

Derivación (tras ambos hola):
```
dh1 = X25519(A.eph, B.x25519)   dh2 = X25519(A.static, B.eph)
dh3 = X25519(A.eph, B.eph)      dh4 = X25519(A.static, B.static)   // enlaza identidades
salt = A.identity_pk ‖ B.identity_pk
master = HKDF(secret = dh1‖dh2‖dh3‖dh4, salt, info="zone-xtdhs-v1")
session key = HKDF(master, info="zone-session")
```

Verificación por el receptor:
1. Comprobar `ts` dentro de TTL y `nonce` no repetido (cache).
2. **Verificar `sig`** con la `identity_pk` del peer **contra el transcript exacto**.
3. Si el peer fue visto antes, comparar `identity_pk` con la anclada en Isar/match; si
   difiere → **abortar** (posible MITM o reinstall; exigir verificación out-of-band).
4. Si es primer contacto, mostrar el **DEVICE_FINGERPRINT** del emisor (20 chars Base32
   en 4×5, `PHASE_2_FINGERPRINT_SPEC.md` — ⚠️ el "número de 7 letras" de `identity_pk ‖
   x25519_pk` queda **superado**: el input jamás incluye X25519, OPEN-002/016) y pedir
   confirmación, o usar canal telefónico/QR.
5. Tras el `ack_A`, marcar el par `(identity_pk, x25519_pk)` como confiado.

Prevenciones integradas: replay (nonce+ts), MITM (firma+transcript), impersonación
(identidad archivada), asociación por canal fuera de banda, expiración del handshake
(TTL), forward secrecy inicial (las claves efímeras contribuyen a dh1–dh3).

---

## 6. Z-101 — Estrategia de ratchet (comparada, NO implementar)

### 6.1 Requisitos técnicos (lista de aceptación)
- Forward Secrecy: compromiso de una clave de sesión no descifra mensajes anteriores.
- Post-Compromise Security: tras una revelación, una nueva interacción sanea el canal.
- Key rotation automática (por mensaje o por contador).
- Manejo de mensajes **fuera de orden** y **perdidos** (delivery precedente).
- **Skipped message keys** (recibir en orden 2,4,3,5 sin romper el canal).
- Replay protection (nunca redecifrar el mismo `n` dos veces).
- Multi-dispositivo viable sin re-handshake por dispositivo (o handshake por par de
  dispositivos).

### 6.2 Comparación conceptual

| Criterio | **Double Ratchet (Signal)** | Ratchet propio simple (hash chain por turno) | Ephemeral-per-message naïve |
|---|---|---|---|
| Forward Secrecy | ✅ completo (cadenas DH+HKDF) | ✅ una dirección (no reversible) | ✅ por mensaje (nuevo ECDH por msg) |
| Post-Compromise Security | ✅ se auto-repara (DH público periódico) | ❌ no (ambos lados siguen en la misma cadena) | ⚠️ depende de ECDH nuevo |
| Out-of-order / lost / skipped | ✅ skipped-keys + cabecera de contador | ❌ rompe el orden | ✅ (nonce por clave nueva) |
| Multi-dispositivo | ✅ (X3DH + ratchets por dispositivo) | ⚠️ complejo | ⚠️ funcional pero costoso |
| Coste cómputo / radio | Bajo (1 DH por turno + hash) | Bajo | **Alto** (1 DH por mensaje; caro en BT) |
| Madurez / bibliografía | Alta (Signal Protocol, auditable) | Ninguna; invitación a errores | Muy alto coste, sin ventaja |
| Complejidad de integración en Flutter | Media (implementación o rewrite) | Baja | Baja |

### 6.3 Recomendación basada en requisitos
**Double Ratchet** (con X3DH como handshake inicial o nuestro handshake §5 como reemplazo
del primer contacto). Razón técnica (no preferencia): es el único que satisface **todos**
los criterios de la lista de aceptación — FS, PCS, out-of-order + skipped keys y
multi-dispositivo — con cómputo apto para BLE.

Refinamientos para ZONE:
- Inicialización: sustituir el **X3DH** por el handshake de §5 (ya tenemos public keys
  ancladas vía server) → transcript con `identity_pk` + dependencia de 4 DH.
- Ratchet state por **par (mi zona ↔ zona del peer)** almacenado en SecureStorage
  (`ratchet_<zoneId>`), con campos: `root_key`, `chain_key_send`, `chain_key_recv`,
  `dh_send`, `dh_send_pk`, `dh_recv` (o sus derivados), `msg_n_*`, `skipped`.
- Cabecera de mensaje: `{ dh_pk (nuevo si rotó), msg_n, prev_n }` + AEAD nonce.
- Marcar mensajes cloud con el mismo `header` → cloud y mesh comparten el mismo
  ciphertext y versión (evita la actual divergencia cloud/mesh).
- TTL de skipped keys p.ej. 2000 entradas; persistencia en SecureStorage/Isar-cifrado.
- El mensaje mesh reutiliza el paquete AEAD del mismo estado → no hay doble asignación de
  claves ni caminos divergentes.

---

## 7. Recovery (diseño, NO implementar)

### 7.1 Creación
- Al crear la cuenta (post instalación), el cliente genera **12 recovery codes**
  aleatorios alfanuméricos de 16 chars (120 bits), o **1 recovery key de 32 chars**
  (p.ej. 4 grupos de 8). El servidor **solo** recibe:
  - `recovery_hash` = `scrypt(prefix, code, salt)` (con salt aleatorio por usuario) o
    `argon2`-plegado; **nunca el código en claro**.
  - `recovery_wrapped` = blob **E2EE con clave derivada `master = HKDF(recovery_key)`**:
    `wrap(account_sk_ed25519 ‖ rotation_counter ‖ created_at)` cifrado con AES-256-GCM
    (clave derivada del recovery key, AAD = `account_id`). ⚠️ **Superado (FASE 2.0.2,
    OPEN-001, Opción A):** el blob **no** incluye la X25519 v1; el historial v1 queda
    ilegible tras recovery — `PHASE_2_RECOVERY_POLICY.md`.
- Todo esto se sube con **service_role / sin retorno**, y las columnas **no se exponen** en
  `v_profile` ni en queries del cliente. ⚠️ **FASE 2.0.2:** se adopta **solo-RPC** — sin RLS
  directa (REVOKE ALL); acceso exclusivo vía RPC SECURITY DEFINER (I-014, R-023).

### 7.2 Presentación única y rotación
- Los códigos se muestran **una sola vez** en pantalla con aviso (pantalla de
  confirmación de "Guardados en un lugar seguro").
- Rotación: al generar nuevos códigos, se **re-envuelve** el blob con la nueva clave
  derivada y se sobrescribe el hash; se revoca los viejos (marcados `revoked_at`).

### 7.3 Recuperación de cuenta / cambio de dispositivo
1. Usuario escoge "Recuperar cuenta con códigos".
2. Ingresa `zone_id` + un código de recuperación.
3. Servidor valida `scrypt(código)` contra el hash; si OK devuelve el **blob envuelto**
   (que ni el servidor ni el transporte ven en claro).
4. El cliente descifra el blob localmente → restaura la **identidad Ed25519 de cuenta**
   (⚠️ **nunca** la X25519 v1 — `PHASE_2_RECOVERY_POLICY.md`, OPEN-001: el historial v1
   queda ilegible tras recovery).
5. El dispositivo genera claves **nuevas** (device Ed25519 + X25519) firmadas con la
   identidad recuperada y registra su `device_keys` vía RPC con challenge firmado.

### 7.4 Seguridad
- El servidor jamás ve la clave privada ni el recovery key (solo hash del código + blob).
- Un atacante que robe la DB no puede abrir el blob sin el recovery.
- Pérdida de códigos + dispositivo = pérdida de acceso (sin puerta trasera).
- Opcional de producto: `delete_own_account` permablorrea sin recovery (menú).

---

## 8. Migración (fases, NO implementar)

| Fase | Alcance | Impacto |
|---|---|---|
| **B0 (compat, sin crypto nueva)** | Documentar + tests; arreglar el «alias stale `publicBase64`» y decidir si `P2PSecurityService.initialize` es la única fuente | Ninguno criptográfico |
| **B1: identidad Ed25519 (opcional-in)** | Nueva columna `identity_public_key`/`fingerprint`/`recovery_*`; cuentas NUEVAS generan Ed25519; las viejas pueden seguir | Baja (opcional) |
| **B2: login con prueba de posesión** | `claim_zone_id` exige `challenge signed` (firma Ed25519); cuentas viejas sin clave de firma reciben upgrade forzado/rotación | Media (requiere UI de upgrade) |
| **B3: KDF + AAD en el E2EE existente** | Al cifrar, pasar de shared secret crudo a `HKDF(shared, salt|info)` y añadir AAD; los mensajes nuevos se firman· derivación v1 vs v2 | Media: los nuevos deben poder descifrar los viejos (tabla de versiones de derivación) |
| **B4: handshake de §5 obligatorio** | Todo peer nuevo debe validarse contra identidad anclada; fingerprint UI | Media |
| **B5: Double Ratchet** | Sesiones nuevas usan ratchet; estado por par; cloud+mesh mismo ciphertext | Alta |
| **B6: recovery** | Codes + wrapped key para cuentas nuevas; upgrade opcional para viejas | Media |

Cada fase se integra con **flag de feature** y es **no destructiva** (no tocar
filas/mensajes existentes; solo agregar columnas y modos).

---

## 9. Compatibilidad con usuarios existentes

- **Historial cloud**: los mensajes viejos están cifrados con el **shared secret X25519
  estático** entre los pares originales. Para que sigan descifrándose, la X25519 estática
  del usuario MANTIENE su rol de "clave de archivado" durante B3-B5; los mensajes nuevos
  usan derivaciones v2 (con el mismo `public_key` o con rotación firmada).
- **`public_key` en `v_profile`**: no se puede reemplazar en caliente sin romper a los
  contactos; la rotación debe ir acompañada de `rekey` firmado que todos acepten, o doble
  clave (`public_key` vieja para histórico + `active_public_key` nueva firmada).
- **Mesh**: `profile_exchange` incluye transporte de la clave nueva; con el handshake §5 y
  fingerprint, el cambio se hace seguro y visible.
- **Multi-dispositivo**: un segundo dispositivo podrá reclamar con recovery firmada y
  registrar sus **propias** claves, sin tumbar al primero (diseño nuevo; hoy el claim
  "mueve" la fila y rompe el anterior).

---

## 10. Riesgos de la migración

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Romper el descifrado del historial | Media | Alto | Fases no destructivas; "clave de archivado" para v1; tests de compat |
| Romper el match/mesh en producción | Media | Alto | Feature flags; rollout progresivo por versión de app |
| Claves efímeras coste BLE | Media | Medio | Ratchet solo rota por turno; estado persistido |
| UX del fingerprint complicada | Media | Bajo | QR / NFC / comparación 4×5 del fingerprint v1 (FINGERPRINT_SPEC) |
| Recovery mal gestionado (usuario pierde códigos) | Media | Medio | Campaña in-app; backup del blob en otro canal (no requerido v1) |
| Vector: `claim_zone_id` durante B2 | Alta (hoy) | **Crítico** | B2 desprioriza el flujo de apropiación; desafío firmado ANTES de mover la fila |
| Consistencia enabled/disabled de session state | Alta (tests) | Medio | Test vectors + determinismo del ratchet |

---

## 11. Pruebas criptográficas necesarias (a escribir cuando se implemente)

1. **KAT / determinismo**: vectores fijos para X25519 (RFC 7748), ChaCha20-Poly1305
   (RFC 8439), Ed25519 (RFC 8032), HKDF (RFC 5869).
2. **Handshake §5**: simular MITM (peer sin firma o firma inválida), replay (nonce
   repetido), expiración (ts fuera de ventana), transcript tampering — todos deben abortar.
3. **Ratchet**: secuencia 1..N; entregas out-of-order (ej: 1,3,2,5,4); paquetes perdidos;
   `skipped keys` > límite; rotación DH; **FS** (revelación de un estado no devela
   anteriores); **PCS** (revelación + re-interacción sanea).
4. **Recovery**: hash no invertible; blob solo abre con el código correcto; rotación
   revoca; presentación única (segundo intento con mismo código falla o se limita).
5. **Compat v1→v2**: mensajes v1 descifrados tras upgrade (clave de archivado);
   mensajes v2 para el mismo par.
6. **Property-based** (fuzz con `dart` / `package:test`): claves corruptas, nonces
   repetidos, largos de texto límite.
7. **Rendimiento BLE**: latencia de derivación/ratchet con 4 DH + HKDF en dispositivo
   medio (p.ej. < 50 ms; no decodificar en el mismo hilo de UI).

---

## 12. Decisiones que requieren CTO (CHECKLIST de aprobación)

> ⚠️ **FASE 2.0.2:** este checklist y la estrategia **B2** quedan **superados** por las
> decisiones D1-D14 de FASE 2.0 y las políticas 2.0.2 (R-001/R-021: el claim acotado
> reemplaza al "login con desafío firmado" como mitigación de T3/T8). La puerta de
> aprobación vigente es `PHASE_2_CTO_REVIEW_REQUIRED.md` + `PHASE_2.0.2_CTO_GATE.md`.

- [ ] D1: Aprobar el **objetivo de protocolo** (Ed25519 identidad + X25519 cifrado con
      **KDF + AAD** obligatorios) — este documento pasa a ser el spec de partida.
- [ ] D2: Confirmar que **X25519 jamás firma** y que las firmas son solo Ed25519.
- [ ] D3: Elegir **Double Ratchet** como base del ratchet (vs. propio / naïve) para FS+PCS.
- [ ] D4: Aprobar el **handshake Z-004** (5 campos, transcript binding, fingerprint).
- [ ] D5: Aprobar **B2** (login con desafío firmado) como primera fase de la migración —
      cierra el vector crítico T3/T8 sin mover aún el E2EE.
- [ ] D6: Aprobar el esquema de **recovery** (códigos + wrapped key client-side; nunca
      clave privada en claro en el servidor).
- [ ] D7: Decidir alcance temporal: ¿B0–B2 en un solo lote o una fase por sprint? (Recom.
      B0 + B2 primero.)
- [ ] D8: Periodicidad de la rotación de tokens/prekeys y TTL de skipped keys.
- [ ] D9: Trazabilidad: registrar las decisiones en `CTO_REVIEW_REQUIRED.md` y aquí mismo
      (esta sección), antes de tocar código.

**Tras aprobar, se actualiza este documento a `ESTADO: APROBADO` y solo entonces se abre
el lote de implementación (nunca antes).**

---

*Fin del documento. No implementar nada hasta la decisión CTO.*