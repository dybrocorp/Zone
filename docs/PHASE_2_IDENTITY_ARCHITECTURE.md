# PHASE 2.0 — Arquitectura de Identidad de ZONE

> **Tipo:** Diseño definitivo (FASE 2.0 · puerta CTO) — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** REVISIÓN PENDIENTE DE CTO · **FASE 2.0.2**: anclajes a
> BOOTSTRAP_POLICY / RECOVERY_POLICY / FINGERPRINT_SPEC (OPEN-001/002/003/016)
> **Referencias:** `CRYPTO_CTO_REVIEW.md`, `PHASE_2_DEVICE_MODEL.md`, `PHASE_2_THREAT_MODEL.md`,
> `PHASE_2_MIGRATION_PLAN.md`, `PHASE_2_CRYPTO_DECISIONS.md`, `PHASE_2_CTO_HANDOFF.md`

Este documento responde a las secciones 2–5, 9 y 12 del mandato FASE 2.0: separar
**cuenta** de **dispositivo**, mapear la arquitectura actual con evidencia, definir el
modelo de identidad objetivo y cerrar el **problema crítico de los usuarios existentes**.

---

## 1. Mapa de la arquitectura actual (con evidencia real)

```
CUENTA  →  Supabase Auth (anónimo, auth.uid() por sesión)
             └─ users.id  UUID  (REFERENCES auth.users)   — supabase_schema.sql:14
AUTH    →  signInAnonymously() en cada registro / login / ensureAuth
             └─ zone_id_service.dart:187, 248, 131
ZONE-ID →  'ZONE-' + 8×[A-Z0-9]  (~41 bits de entropía)  — zone_id_service.dart:558-565
             └─ UNIQUE en users.zone_id                    — supabase_schema.sql:15
             └─ credencial de LOGIN por conocimiento (sin prueba de posesión)
IDENTIDAD →  users.public_key = X25519 pública base64 (estática, larga vida)
             └─ supabase_schema.sql:17
             └─ SIEMPRE se preserva en DB (Z-001 A): checkAndFixRegistration → 357-369
DISPOSITIVO →  keypair X25519 local en FlutterSecureStorage
             └─ keys 'private_key' / 'public_key'           — zone_id_service.dart:25-26
             └─ P2PSecurityService.initialize() en arranque — initial_loading_screen.dart:57-60
             └─ ⚠️ un segundo keypair se crea en _registerInSupabase (197)
X25519   →  ECDH estático → shared secret CRUDO (sin KDF)   — p2p_security_service.dart:52-64
             └─ session keys sk_<zoneId> en SecureStorage   — p2p_security_service.dart:70-94
CHAT     →  ChaCha20-Poly1305 AEAD sin AAD                  — chat_e2ee_service.dart:60-79
             └─ outbox: ciphertext+nonce+mac en Isar        — chat_screen.dart:536-544
MESH     →  profile_exchange en claro (incluye public_key)  — nearby_service.dart:885-907
             └─ derivación de session key al recibirlo       — nearby_service.dart:918-928
             └─ auto-aceptación de conexiones (sin auth)     — nearby_service.dart:772-775
```

### Lectura del mapa actual (lo que el código demuestra)

| Eje | Realidad verificada |
|---|---|
| Cuenta | Es **solo** una fila `users` anclada a un `auth.uid()` efímero. El uid anónimo puede **cambiar** en cada restauración (`ensureAuth` re-crea sesión anónima si no hay sesión — `zone_id_service.dart:246-252`). |
| ZONE-ID | Es la **única credencial estable** que sobrevive reinstalaciones. Es un **secreto por conocimiento** de ~41 bits: quien lo conoce puede `claim_zone_id` y *adueñarse* del uid (`supabase_schema.sql:673` `UPDATE public.users u SET id = v_uid`). |
| Identidad | `public_key` (X25519) es identidad E2EE **por cuenta**, pero el dispositivo local puede tener otra clave distinta (ver inconsistencia abajo). |
| Dispositivo | No hay concepto de dispositivo: el keypair local es la "identidad" y al reinstalar se genera uno nuevo sin relación. |
| Bindings | **Ninguno** entre `zone_id`, `public_key` y la clave privada: la DB no puede verificar que quien reclama un ZONE-ID posee la privada correspondiente. |

### Inconsistencias vigentes que el nuevo diseño debe resolver

1. **Doble keypair en primer arranque:** `P2PSecurityService.initialize()` genera un
   par (arranque), y `_registerInSupabase` genera **otro** (registro) y lo escribe en el
   mismo storage. `_publicBase64` interno de `P2PSecurityService` no se refresca →
   el mesh puede anunciar una clave distinta de la archivada.
   Evidencia: `p2p_security_service.dart:27-49` + `zone_id_service.dart:197-203`.
2. **Clave local ≠ clave archivada tras reinstalación:** `ensureAuth` genera una clave
   privada nueva si no hay local (líneas 268-299), pero `checkAndFixRegistration`
   **preserva** la `public_key` de la DB (357-369). Resultado: el dispositivo no puede
   descifrar mensajes cloud cifrados con la clave archivada (MAC falla) y el mesh
   ofrece una clave que no coincide → **estado dual insostenible**.
3. **`claim_zone_id` sin posesión:** el claim solo exige conocer `ZONE-XXXXXXXX`
   (rate-limit 5/15 min). No hay desafío firmado. `secure_claim_zone_id.sql:44-90`.
4. **`public_key` jamás se rota** y no hay SQL de `update_public_key` (Z-001 Fase B
   pendiente — `secure_claim_zone_id.sql:14-15`).
5. **Session keys mesh sin expiración:** `sk_<zoneId>` se guardan sin TTL y solo se
   borran con `clearAuth`/`deleteAllSessionKeys`. `p2p_security_service.dart:70-115`.

---

## 2. Regla fundamental de separación

```
CUENTA   → Ed25519 → identidad criptográfica de la cuenta (firma, autorización,
                     fingerprint, recovery futuro)
DISPOSITIVO → X25519 → identidad propia del dispositivo (sesiones E2EE, ratchet futuro)
```

**No asumir:** ZONE-ID = identidad criptográfica ·
**No asumir:** X25519 = firma ·
**No asumir:** conocer el ZONE-ID demuestra posesión.

---

## 3. Modelo de identidad objetivo (4 niveles)

| Nivel | Entidad | Clave | Familia | Rol | Persistencia |
|---|---|---|---|---|---|
| **Account Identity** | La cuenta ZONE | `account_id` (UUID) + `identity_public_key` (Ed25519) | Firma | Prueba posesión de la cuenta, autoriza operaciones (claim/transfer/recovery/rotación/alta-dispositivo) | Supabase (server-side) + local (privada) |
| **Device Identity** | El dispositivo | `device_id` (UUID) + `device_public_key` (Ed25519) | Firma | Identifica un dispositivo concreto, firma operaciones del dispositivo, se vincula a la cuenta vía autorización | Supabase (`devices`) + local |
| **Encryption Identity** | El dispositivo para E2EE | `encryption_public_key` (X25519) | ECDH | Deriva claves de sesión con peers | Supabase (`device_keys`, rotable) + local (privada) |
| **Session Identity** | El par (mi dispositivo ↔ peer) | Ratchet state | Symmetric | Cifrado/descifrado de mensajes | Local (SecureStorage/Isar cifrado), opcional escaneable |

### Decisiones de fondo (respuestas preliminares a D1/D2)

- **Ed25519 = Account Identity. ✔ Sí.** Es la identidad que **firma**; puede emitir
  recovery, transferir, rotar claves, y anclar trust.
- **X25519 = Device Encryption Identity. ✔ Sí.** Es la identidad que **cifra**. Regla
  cerrada: **X25519 jamás firma** (`CRYPTO_CTO_REVIEW.md` §4.1).

### Campos canónicos del modelo (diseño; no se crean columnas todavía)

```
account_identity (conceptual):
  account_id            UUID PK
  identity_public_key   TEXT   -- Ed25519 pública base64
  identity_fingerprint  TEXT   -- hash estable (ver §5 de este doc)
  recovery_salt         TEXT   -- para hash de recovery (argon2/scrypt)
  recovery_hash         TEXT[] -- hashes de códigos de recuperación
  created_at, updated_at

devices (conceptual):
  device_id            UUID PK
  account_id           UUID FK → account_identity
  device_public_key    TEXT   -- Ed25519 del dispositivo
  device_fingerprint   TEXT
  device_status        TEXT   -- 'active' | 'revoked' | 'pending'
  created_at, last_seen, revoked_at

device_keys (conceptual):
  device_id            UUID FK → devices
  encryption_public_key TEXT  -- X25519 (rotable)
  key_version          INT
  valid_from, valid_until
  revoked_by_sig       TEXT
```

---

## 4. Registro inicial de una cuenta nueva (objetivo)

```
1. El dispositivo genera: account identity (Ed25519) + device identity (Ed25519)
   + encryption key (X25519). Privadas: NUNCA salen del dispositivo (SecureStorage).
2. signInAnonymously() → auth.uid() efímero.
3. El servidor CREA la cuenta: account_id (servidor, UUID v4) + sube
   identity_public_key + fingerprints, con el primer device y su device_public_key,
   vía RPC SECURITY DEFINER `create_account(...)` (sin aceptar claves en claro del
   payload de forma no firmada; la creación inicial es el único caso sin ancestro).
4. El ZONE-ID se conserva como handle público (no cambia) pero deja de ser
   credencial: se convierte en identificador enrutable + entrada para recovery.
```

Nota clave: hoy `claim_zone_id` hace que `users.id` sea mutable (mueve la fila).
En el modelo objetivo, `account_id` es **inmutable** y la tabla `users` se ancla a
`account_id`, no a un uid efímero − ver `PHASE_2_MIGRATION_PLAN.md` (fase M2).

---

## 5. Problema crítico: usuarios existentes (preguntas A–G)

Caso: usuario con `ZONE-XXXXXXXX` + X25519 archivada + historial E2EE existente +
**sin Ed25519**.

### A. ¿Cómo se registra inicialmente su Ed25519?

**Diseño:** mediar por **código de autorización único** generado server-side, ligado
al `account_id` (uid actual) y presentado **con frase de confirmación de riesgo**:

1. `create_account_bootstrap(zone_id, device_pub_ed25519, encryption_pub_x25519)` se
   invoca desde el dispositivo que tiene **session activa y fila `users`** → el
   servidor crea `account_identity` + primer device (status **`pending`** — I-013/I-030),
   emite `one-time bootstrap code` (8 chars Base32 ≈ 40 bits, TTL 10 min, 1 uso —
   parámetros completos en `PHASE_2_BOOTSTRAP_POLICY.md`) y devuelve el par de
   fingerprints.
2. El dispositivo **muestra/firma** el enroll con su Ed25519 local (recién generada).
3. Si el código no se presenta en TTL → la cuenta queda en modo `legacy` y **no**
   pierde nada (ver B).

**NO se acepta** "generar Ed25519 al iniciar sesión" como respuesta sin autenticar la
propiedad. La propiedad aquí la acredita la **fila `users` existente + sesión anónima
activa del mismo usuario** + código de 1 uso con TTL emitido por el servidor.

### B. ¿Cómo demostramos que el dispositivo actual controla esa cuenta?

Hoy: solo conoce el ZONE-ID + formato + rate-limit. Insuficiente (T3/T8).

**Diseño (dos factores de conocimiento):**
1. **Factor 1 — sesión activa:** el dispositivo tiene un `auth.uid()` cuya fila
   `users` es la de esa cuenta (mismo `zone_id`). Ese vínculo ya existe en la DB.
2. **Factor 2 — posesión de clave X25519:** challenge-response **diseñado sobre la
   clave X25519 archivada** en la FASE TRANSITORIA (Ed25519 aún no existe): el
   servidor envía un nonce, el cliente devuelve un **HMAC del nonce** derivado del
   **shared secret** que produce haciendo ECDH(privada_local, public_key_archivada)
   … **imposible** porque la privada NO es la misma que generó la archivada tras
   reinstalación. ⇒ **La posesión real de la X25519 archivada solo es demostrable por
   el dispositivo que conserva esa privada.** Por eso la estrategia es:

> **Fase transitoria (M1):** el primer dispositivo con **sesión activa** hace
> bootstrap del account. **NO se exige prueba de posesión de la X25519 archivada**
> para el *primer* enroll (razón: no hay ancestro de confianza — la DB es la fuente).
> Se **síntoma-verifica** con datos auxiliares que ya existen (último `updated_at`,
> tokens BT activos, encuentros recientes) como señuelo anti-apropiación y el enroll
> queda **`pending` sin derechos + cancelación + audit** (en el primer enroll no hay
> dispositivo que notificar por push — máquina PENDING→ACTIVE en
> `PHASE_2_BOOTSTRAP_POLICY.md`, OPEN-003). En **M2+** (ya con Ed25519 anclada) todo
> claim/alta exige firma.

### C. ¿Cómo evitamos que alguien que solo conoce el ZONE-ID registre primero una Ed25519 maliciosa?

**Premisa:** no se puede evitar al 100 % solo con lo que existe hoy porque la
DB no distingue al dueño real. Mitigaciones **por capas** (objetivo):

1. **Ventana de apropiación** (anti-scoop): el bootstrap con código de 1 uso se abre
   SOLO cuando la cuenta está en `mode=legacy` y la fila tiene **actividad reciente
   verificable** (tokens BT no expirados / `updated_at` < 30 días). Para cuentas
   "frías" (sin actividad > 30 días) se **exige un canal fuera de banda**: el código
   se envía al correo/verificación que el usuario registre (análisis de producto) o se
   bloquea el enroll hasta contacto con soporte (fail-closed).
2. **Detección:** si la cuenta ya tuvo un enroll previo y aparece uno nuevo con
   **otra** Ed25519 → evento de *possible account takeover* + notificación push al
   dispositivo registrado (evidencia de apropiación). En el **primer** enroll no hay
   destinatario push: la defensa es `pending` + cancelación + audit (BOOTSTRAP_POLICY
   §2, OPEN-003).
3. **Reversibilidad:** todo enroll inicial queda en `status=pending` hasta que el
   dispositivo **firme una confirmación** con su Ed25519 y el servidor vea la fila
   `users` intacta; mientras tanto, la X25519 archivada NO se toca.
4. **Jamás** se permite el enroll de una Ed25519 que "pruebe" ser dueña solo por
   presentar `claim_zone_id`; el claim pierde su poder de apropiación (ver §7).

### D. ¿Qué ocurre si el usuario tiene sesión activa en su dispositivo original?

- Es el caso ideal (B, factor 1=OK): bootstrap inmediato con código de 1 uso, sin
  fricción. El dispositivo original queda `device_1 · active`. Nada se rompe: la
  X25519 archivada se mantiene como `encryption key v0` hasta la primera rotación.

### E. ¿Qué ocurrió si perdió el dispositivo original?

- Sin recovery ni claves locales → **pérdida garantizada del historial E2EE** (hoy
  ya es así: no hay backup). FASE 2.0 NO promete recuperar claves privadas perdidas.
- El nuevo dispositivo podrá **reclamar la cuenta** (ZONE-ID + recovery codes **o**
  proceso de soporte), pero **no** obtiene las claves privadas viejas → el historial
  sigue cifrado e ilegible (correcto: el servidor no es custodio de claves privadas).
- Diseño: el claim vía recovery **reemplaza** el estado de device_keys con claves
  nuevas **firmadas por la cuenta recién recuperada**, y los mensajes nuevos usan la
  nueva clave; los viejos quedan como "historial no descifrable" (placeholder
  actual `🔒` ya existe — `chat_e2ee_service.dart:105-109`). **Política formal:**
  `PHASE_2_RECOVERY_POLICY.md` (OPEN-001) — el blob jamás contiene la X25519 v1; el
  historial v1 queda ilegible tras recovery (I-025).

### F. ¿Qué ocurre si instaló ZONE nuevamente (reinstalación)?

- Hoy: keypair nuevo local + `public_key` archivada preservada → **inconsistencia
  dual** (evidencia §1.2-3). Con el modelo objetivo:
  - La reinstalación **no toca** `account_identity` ni `devices`.
  - El nuevo install genera **nuevo device** → entra como `device_2 · pending` y se
    autoriza desde `device_1` (flujo A/B en `PHASE_2_DEVICE_MODEL.md` §3) **o** por
    recovery.
  - El nuevo device genera su **propia** encryption key X25519 rotada y registrada con
    firma de cuenta → adiós al estado dual: cada dispositivo tiene SU clave.
  - Los mensajes cloud dirigidos al par usan la clave **del dispositivo/PK del par**
    (diseño multi-device: se elige por `device_keys` activa y session por par de
    devices o por cuenta — decisión D13/DR-2).

### G. ¿Qué ocurre si quiere registrar un segundo dispositivo?

- Flujo completo con las 6 opciones evaluadas → `PHASE_2_DEVICE_MODEL.md` §3
  (QR / código / challenge-response / autorización firmada / recovery / combinación).
  Resultado preliminar: **autorización firmada por un dispositivo activo + QR que
  despliega un challenge** (elección combinada, recomendación en CTO_REVIEW).

---

## 6. `claim_zone_id`: qué debería ser (análisis de transformación)

| Función actual | Problema | Transformación objetivo |
|---|---|---|
| `claim` (adueñarse del uid) | Mueve `users.id` a un uid anónimo nuevo sin prueba (`supabase_schema.sql:673`) | **Eliminar** la semántica de apropiación. El `uid` deja de ser la identidad de cuenta (pasa a ser "sesión"). `account_id` inmutable. |
| `transfer` (cambio de titular) | No existe | Nuevo RPC `transfer_account` con **firma Ed25519 de la cuenta** + verificación, para cesión legítima y voluntaria. |
| `device registration` | No existe | Nuevo RPC `register_device` con firma de cuenta + challenge (ver DEVICE_MODEL). |
| `account recovery` | No existe | Nuevo RPC `recover_account` con **recovery code** + firma del código (hash server-side) — ver `PHASE_2_CRYPTO_DECISIONS.md` D5. |

**Principio rector:** `CONOCER ZONE-ID ≠ POSEER CUENTA`. La nueva arquitectura **no**
permite que `signInAnonymously + conocer ZONE-ID = apropiarse`.

---

## 7. Fingerprint (sección 12 del mandato — NO asumir "7 letras")

> **Autoridad (FASE 2.0.2):** `PHASE_2_FINGERPRINT_SPEC.md` v1 — **dos** fingerprints
> (ACCOUNT_FINGERPRINT y DEVICE_FINGERPRINT) con input **sin X25519** (OPEN-002/016).
> Esta sección recoge el diseño FASE 2.0 original y queda alineada con la spec: 20 chars
> Base32 en 4×5, KAT obligatorio en M1 (I-017).

`CRYPTO_CTO_REVIEW.md` §5.2 proponía "número de 7 letras". Análisis formal:

| Decisión | Propuesta de diseño | Justificación |
|---|---|---|
| Fingerprints | **Dos** (autoridad: `FINGERPRINT_SPEC` §2): **ACCOUNT_FINGERPRINT** y **DEVICE_FINGERPRINT**, con inputs distintos | Verificación humana out-of-band de cuenta (alta de device/recovery/transfer) y de dispositivo (mesh M3, alta de device QR) |
| Input canónico — ACC | `utf8("ZONE-FP-1\0") ‖ utf8("ACC") ‖ utf8(uuid_canonical(account_id)) ‖ base64_std_padded(identity_public_key)` | Fija el orden para evitar ambigüedad; **sin X25519** (canonicalización de `FINGERPRINT_SPEC` §3, OPEN-015) |
| Input canónico — DEV | `utf8("ZONE-FP-1\0") ‖ utf8("DEV") ‖ utf8(uuid_canonical(account_id)) ‖ utf8(uuid_canonical(device_id)) ‖ base64_std_padded(device_public_key)` | Idem; incluye `device_id` para distinguir devices del mismo account |
| Hash | SHA-256 (RFC 6234) sobre el input canónico | Estándar, disponible en `cryptography` |
| Codificación | Base32 sin padding, alfabeto **unambiguo** de 32 símbolos (evita 0/O, 1/I/L) | Adecuado para comparación humana y QR |
| Longitud | **20 caracteres** agrupados `XXXXX-XXXXX-XXXXX-XXXXX` (100 bits del digest) | Equilibrio seguridad/UX; ~1/2^100 de colisión intencional |
| Representación humana | 4 grupos de 5 (MAYÚSCULAS; la comparación normaliza a MAYÚSCULAS) | El "7 letras" original era débil para comparación manual de dispositivos |
| Comparación QR | El payload escaneado es el fingerprint + `account_id`; el teléfono lo re-hash y compara | Sin exposición de claves |
| Estabilidad | ACCOUNT cambia solo si rota la Ed25519 de cuenta (OPEN-013); DEVICE cambia si cambia el device (incl. reinstalación); **ninguno** cambia con rotación de X25519 | El fingerprint identifica al *poseedor*, no a la clave de cifrado |

Ejemplo visual de comparación segura (fuera de banda): mostrar
`FP7GK-3KQ9W-MJ2X8-PDVTC` en ambas pantallas y pedir confirmación de coincidencia.

---

## 8. Resumen de decisiones tomadas en este documento

| # | Pregunta | Respuesta | Estado |
|---|---|---|---|
| D1 | ¿Ed25519 = identidad de cuenta? | **Sí** (firma; no cifra) | PROPUESTA |
| D2 | ¿X25519 = identidad de cifrado de dispositivo? | **Sí** (cifra; no firma) | PROPUESTA |
| D3 | ¿Cómo se registra el primer dispositivo? | Bootstrap con código de 1 uso + sesión activa + señuelos | PROPUESTA |
| D4 | ¿Cómo se registra un segundo dispositivo? | Autorización firmada + QR/challenge (ver DEVICE_MODEL) | PROPUESTA |
| D5 | ¿Cómo se recupera una cuenta? | Recovery codes (hash server-side) + nuevo account; claves viejas NO son recuperables | PROPUESTA |
| D12 | ¿Cómo se autentica el primer contacto mesh? | Fingerprint + firma Ed25519 en `profile_exchange` v2 (handshake CRYPTO_CTO_REVIEW §5) | DISEÑADO |
| — | ¿`claim_zone_id`? | Se **elimina la semántica de claim**; se sustituye por `transfer`/`register_device`/`recover_account` | PROPUESTA |

Todo queda sujeto a `PHASE_2_CTO_REVIEW_REQUIRED.md`.