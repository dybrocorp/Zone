# PHASE 2.0 — Modelo de Dispositivos de ZONE

> **Tipo:** Diseño definitivo (FASE 2.0 · puerta CTO) — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** REVISIÓN PENDIENTE DE CTO · **FASE 2.0.2**: ajustes
> aplicados (device_1 `pending`, blob recovery sin X25519 v1, firmante de rotación, DR-6)
> **Depende de:** `PHASE_2_IDENTITY_ARCHITECTURE.md` (conceptos account/device/encryption identity)
> **Complementa:** `PHASE_2_CRYPTO_DECISIONS.md` (D4, D6, D7), `PHASE_2_THREAT_MODEL.md`

Este documento desarrolla el registro de dispositivos, la revocación, la rotación de
claves X25519 y el protocolo formal de challenge-response (secciones 6, 7, 8 y 11 del
mandato). **Solo diseño: ninguna migración, ningún cambio remoto, ningún cambio de código.**

---

## 1. Modelo conceptual de datos (tablas nuevas — esquema diseñado, no aplicado)

### 1.1 `account_identity`

| Columna | Tipo | Notas | Índice |
|---|---|---|---|
| `account_id` | UUID PK | Generado server-side, **inmutable** | PK |
| `zone_id` | TEXT UNIQUE NOT NULL | Se conserva de `users.zone_id` (compatibilidad) | UNIQUE |
| `identity_public_key` | TEXT NOT NULL | Ed25519 pública base64 | — |
| `identity_fingerprint` | TEXT NOT NULL | Fingerprint v1 — autoridad: `PHASE_2_FINGERPRINT_SPEC.md` (OPEN-002) | — |
| `identity_key_version` | INT DEFAULT 1 | Versionado de la clave de firma | — |
| `legacy_public_key` | TEXT | X25519 archivada de la era legacy (v0) — se conserva para descifrar historial | — |
| `mode` | TEXT DEFAULT 'legacy' | `legacy` → `transition` → `secure` (ver MIGRATION_PLAN) | — |
| `recovery_salt` | TEXT | Salt ÚNICO por cuenta para hashing de recovery codes | — |
| `recovery_hash` | TEXT[] | Argon2id/scrypt de los códigos activos (nunca en claro) | — |
| `created_at` / `updated_at` | TIMESTAMPTZ | Botones de auditoría | — |

- RLS: **sin acceso directo** (revoke ALL público; acceso solo vía RPC SECURITY DEFINER).
- **Nadie** (ni authenticated) lee `recovery_hash` ni `identity_public_key` por tabla: solo RPC selectivos (`get_identity_public_key` para verificar firmas, limitado a campos necesarios).

### 1.2 `devices`

| Columna | Tipo | Notas | Índice |
|---|---|---|---|
| `device_id` | UUID PK | Generado en el cliente (UUID v4) — decisión **DR-1** (R-012) | PK |
| `account_id` | UUID FK → account_identity | — | IDX(account_id) |
| `device_public_key` | TEXT NOT NULL | Ed25519 pública del dispositivo | — |
| `device_fingerprint` | TEXT NOT NULL | Fingerprint v1 del dispositivo | — |
| `status` | TEXT NOT NULL DEFAULT 'pending' | `pending` \| `active` \| `revoked` | IDX(account_id,status) |
| `revocation_sig` | TEXT | Firma de cuenta que revocó (nullable) | — |
| `created_at`, `last_seen`, `revoked_at` | TIMESTAMPTZ | — | IDX(last_seen) |

RLS: solo RPC; el dueño ve su propia lista de devices mediante `list_devices(account_id)`
que verifica firma/posesión. Jamás SELECT/UPDATE directo autenticado sobre la tabla.
Escalación: **no** permitir a un device revocarse con solo `status`; toda mutación vía
RPC con firma verificada.

### 1.3 `device_keys` (encryption X25519 histórica, versionada)

| Columna | Tipo | Notas | Índice |
|---|---|---|---|
| `device_id` | UUID FK → devices | — | IDX(device_id) |
| `key_version` | INT | Monótono por device | UNIQUE(device_id,key_version) |
| `encryption_public_key` | TEXT NOT NULL | X25519 pública (rotable) | — |
| `status` | TEXT | `active` \| `retired` \| `compromised` | — |
| `valid_from`, `valid_until` | TIMESTAMPTZ | Ventana de validez | — |
| `rotate_sig` | TEXT | Firma de cuenta del dispositivo al rotar | — |
| `created_at` | TIMESTAMPTZ | — | — |

### 1.4 `device_challenges` (desafíos de registro/autorización)

| Columna | Tipo | Notas |
|---|---|---|
| `challenge_id` | UUID PK | — |
| `account_id` | UUID FK | — |
| `challenge` | TEXT | Nonce/desafío firmable aleatorio (32 bytes b64) o encriptado |
| `purpose` | TEXT | `enroll` \| `register_device` \| `rotate_key` \| `recover` |
| `expires_at` | TIMESTAMPTZ | TTL 10 min |
| `used_at` | TIMESTAMPTZ | Single-use |

RLS: revoke ALL público; administrado por RPC SECURITY DEFINER.
Riesgo de escalación: controlar que el challenge se ligue al `account_id` solicitante y
**nunca** pueda reutilizarse (single-use + TTL).

### 1.5 `device_revocations` (auditoría de revocación)

| Columna | Tipo | Notas |
|---|---|---|
| `id` | BIGINT IDENTITY PK | — |
| `account_id` | UUID FK | — |
| `device_id` | UUID FK → devices | — |
| `revocation_sig` | TEXT | Firma de cuenta |
| `reason` | TEXT | `stolen` \| `lost` \| `user_initiated` \| `security` |
| `created_at` | TIMESTAMPTZ | — |

### 1.6 `recovery_credentials` (solo hashes, nunca secretos en claro)

| Columna | Tipo | Notas |
|---|---|---|
| `account_id` | UUID PK/FK | — |
| `recovery_hash` | TEXT[] | Ver §1.1; array de hashes activos (con `used_at` por código — OPEN-009) |
| `recovery_salt` | TEXT | Salt por cuenta |
| `recovery_wrapped` | BYTEA/TEXT | Blob E2EE (RECOVERY_POLICY_V1 — OPEN-001): identidad Ed25519 de cuenta; **sin X25519 v1** (I-025) |
| `last_recovery_at` | TIMESTAMPTZ | Auditoría |

**Regla absoluta:** ningún proveedor (Supabase, storage, logs, backups) ve jamás una
clave privada ni un recovery code en claro. Solo `argon2id(secret, salt)` y blobs
envueltos client-side.

---

## 2. Registro de **primer** dispositivo (bootstrap legacy → cuenta)

Flujo (resumen — detalle formal en fase de implementación):

```
1. App detecta: no hay account_identity en local, sí hay fila users + sesión.
2. Genera: Ed25519 account + Ed25519 device + X25519 encryption (local, SecureStorage).
3. POST rpc bootstrap_account(zone_id, device_pub_ed25519, device_fp, enc_x25519)
     ✔ si sesión = dueño de la fila users (auth.uid() = users.id)
     → crea account_identity + devices(device_1, pending)   ← BOOTSTRAP_POLICY (I-013/I-030)
     → emite one-time bootstrap code (TTL 10 min; parámetros: BOOTSTRAP_SECURITY_POLICY)
4. El dispositivo muestra el código de confirmación al usuario (opcional si
   sesión + señuelos OK; obligatorio en cuentas frías, ver A.C).
5. App confirma: rpc confirm_bootstrap(account_id, sig_device(nonce)); → active.
6. mode['legacy'] → con la cuenta creada, primera rotación firmada de X25519 (ver §4).
```

Propiedades: sin prueba de X25519 archivada (no posible), pero con controles que hoy no
existen: **código de 1 uso + TTL + rate-limit + max-attempts** (BOOTSTRAP_SECURITY_POLICY),
verificación de sesión vs fila `users`, y **`pending` sin derechos + cancelación + audit**
(en el primer enroll no existe dispositivo al que notificar por push: la defensa es la
máquina PENDING→ACTIVE — BOOTSTRAP_POLICY §2/§4, OPEN-003).

---

## 3. Registro de **nuevo dispositivo** — evaluación de 6 opciones

| Opción | Seguridad | UX | Amenazas | Offline | Mesh | Dependencia servidor | Riesgo MITM | Revocación |
|---|---|---|---|---|---|---|---|---|
| **A. QR** | Alto si el QR lleva un challenge firmable y el canal visual es real | Alta | Foto/replay del QR, shoulder-surfing | No (necesita servidor para validar) | No | Media | Bajo si se compara fingerprint en pantalla | Vía lista de devices |
| **B. Código de autorización** | Medio: código corto adivinable/robable | Alta | Finger de código, MITM del canal | No | No | Media | Medio | Vía dispositivo |
| **C. Challenge-response** | **Alto** (nonce + firma Ed25519) | Medio (requiere ambos online) | Replay si single-use falla | No | No | Media | Bajo | Vía firma |
| **D. Autorización firmada por device existente** | **Alto** (requiere firma de un device ya autorizado) | Media (requiere A autorizar a B) | Dispositivo robado que firma | No | Posible (relay de paquetes firmados entre pares) | Baja (solo valida firma y estado) | Bajo/Medio | Inmediata si A revoca |
| **E. Recovery** | Alto si los códigos son de alta entropía y hash-seguros | Alta (códigos impresos) | Robo de códigos físicos | Sí (códigos recuperables offline, uso online) | No | Media | Bajo | Rotación de recovery |
| **F. Combinación (recomendada): D + A/QR + C** | **Muy alto** | Alta con QR del device_2 mostrando su desafío | Compleja de implementar, requiere UI dedicada | Parcial (D offline si ambos pares en mesh, validado online al sincronizar) | Sí (paquetes firmados mesh) | Media-Baja | **Muy bajo** (se compara fingerprint en ambas pantallas) | Completa |

**Recomendación preliminar (pendiente CTO):** **F = D (autorización firmada por un
dispositivo activo) + QR con challenge + firmware check de fingerprint.**
Razones: máxima seguridad (requiere clave de un device ya confiado), mesh-compatible,
y revocable de inmediato desde el device que autoriza. El recovery (E) queda como
red de seguridad (nunca como canal primario de alta de dispositivos).

**Reglas de autorización de un dispositivo nuevo:**
- Solo cuenta con `mode != revoked` puede autorizar (`transfer_account` no cuenta).
- Toda autorización registra `device_revocations`/auditoría y emite **una** firma con la
  **Ed25519 del device activo** (OPEN-005/DR-5): `sig = Sign(device_sk_1, register_device ‖
  new_device_id ‖ device_pub ‖ ts)` — validada por account.
- Los dispositivos revocados **no** pueden autorizar.
- El mesh transporta los paquetes firmados; el servidor solo valida firma y estado
  (sin nueva criptografía en la fase M1, solo reutilización de firmas Ed25519).

---

## 4. Rotación de la clave X25519 (dispositivo)

```
old X25519 ──(firma de cuenta)──▶ new X25519
```

Reglas de diseño (formato `PHASE_2_CRYPTO_DECISIONS.md` D7):

1. **Autorización:** solo el device **activo** propietario; la rotación de la clave de
   cifrado es una **op de dispositivo** → se firma con `device_sk` + challenge
   (OPEN-008); `account_sk` solo para ops de cuenta (transfer/recover/revoke/rotación de
   identidad).
2. **Firma:** `sig = Sign(device_sk, op ‖ device_id ‖ new_x25519_pub ‖ challenge ‖ ts)`
   — transcript canónico versionado §5.
3. **Challenge:** nonce de servidor (32 B) con TTL 10 min, single-use
   (`device_challenges`), desde RPC `request_challenge`.
4. **Protección contra replay:** nonce único + `used_at` + timestamp de firma y
   verificación de frescura (±5 min contra `expires_at`).
5. **Versionado:** `device_keys.key_version++`; la anterior pasa a `retired`
   (se conserva para descifrar historial — MIGRATION_PLAN §4).
6. **Congelación:** tras rotar, los **mensajes nuevos** al par usan la nueva clave;
   los **viejos** usan la `retired` con el mismo `peer_pub_key` leída del message.
7. **Auditoría:** `device_revocations` no aplica, pero `device_keys` guarda el
   `rotate_sig` y la fila `updated_at`.

---

## 5. Protocolo formal de challenge-response (sección 11 del mandato)

### 5.1 Estructura canónica y versionada

Se define un **formato de firma** con versión `v1`, JSON canónico (claves ordenadas
alfabéticamente, sin espacios, UTF-8 estricto, timestamps ISO-8601 UTC):

```
canonical_payload_v1 := json({
  "v": 1,
  "op": "<operation>",            // enroll | register_device | rotate_key | recover | transfer
  "account_id": "<uuid>",
  "device_id": "<uuid>",          // SUJETO (el que firma)
  "public_key": "<base64>",       // clave pública involucrada (Ed25519 o X25519 según op)
  "challenge": "<base64_nonce>",  // nonce del servidor (32 B) — single-use, TTL 10 min
  "ts": "<iso8601_utc>",          // reloj del cliente; ventana ±5 min
  "extra": {}                     // contexto op-por-op (p.ej. reason para revoke)
})
```

La firma es `sig = Ed25519.Sign(secret_key, utf8(canonical_payload_v1))`.

### 5.2 Flujo

```
CLIENT                        SERVER
  │  op = seleccionada           │
  ├──── request_challenge(op) ──▶│
  │                              │ challenge_id, nonce(32B), expires_at=now+10min
  │◀─── {challenge_id, nonce} ───┤
  │  arma canonical_payload_v1   │
  │  firma con su Ed25519        │
  ├──── verify_signed_op(payload, sig, challenge_id) ─▶│
  │                              │ 1. challenge existe, no usado, no expirado → marca used_at
  │                              │ 2. verifica firma con device_public_key o account identity
  │                              │ 3. verifica ts dentro de ±5 min
  │                              │ 4. verifica op/account/device coherentes
  │                              │ 5. ejecuta la operación (con su propia lógica)
  │◀─── {ok | error} ────────────┤
```

### 5.3 Definiciones exactas

| Campo | Valor |
|---|---|
| `canonical serialization` | JSON canónico sin espacios, claves ordenadas, UTF-8, `\u` escapes para no-ASCII; `extra` anidado igual de canónico |
| `nonce` | 32 bytes CSPRNG (`Random.secure`), base64, single-use (`used_at`), TTL 10 min |
| `expiry` | `expires_at = now()+10min`; verificación `|server_now - ts| <= 5min` |
| `audience/context` | `op` + `account_id` + `device_id` (no hay audience tipo "app"; el contexto es la operación) |
| `public key` | La que corresponde a la op (`device_public_key` para device ops; `identity_public_key` para account ops: transfer/recover/rotación de identidad) |
| `replay protection` | nonce single-use + expiración + ventana temporaria + idempotencia de `verify_signed_op` por `challenge_id` |
| `auditoría` | fila en `device_revocations`/tuplas log + `used_at` del challenge (traza) |

**Regla contra firmas ambiguas:** nunca se firman datos JSON arbitrarios del cliente;
siempre se firma el `canonical_payload_v1` producido por la librería de firma, y el
servidor **re-serializa** el payload recibido a su forma canónica antes de verificar
(no confía en el JSON del cliente para la verificación byte a byte).

---

## 6. Revocación de dispositivos (sección 7 del mandato)

### 6.1 Quién puede revocar

- **El usuario** desde cualquier device activo (`list_devices` + `revoke_device` con
  firma de cuenta, `sig(op='revoke_device', device_id, reason)`).
- **Auto-revocación** por «eliminar cuenta» (`delete_own_account` actual ya borra todo:
  `zone_id_service.dart:571-615`; en el nuevo modelo borra `account_identity`,
  `devices`, `device_keys`, `recovery` además de `users`).

### 6.2 Qué ocurre con

| Recurso | Comportamiento en revocación |
|---|---|
| Sesiones E2EE del device revocado | **Dejan de sincronizarse**: el servidor filtra nuevas entregas de mensajes a ese device (device en `revoked` no recibe enfila de sync); las sesiones ya reveladas no se pueden "des-revelar" retroactivamente — documentar en threat model (T11/T14) |
| Claves X25519 del device | `device_keys.status → retired|compromised` según `reason`; si `compromised` se prohíbe su uso para mensajes nuevos inmediatamente |
| Mensajes pendientes (outbox) | Si estaban cifrados con clave del device revocado y no entregados, se marcan `FAILED`/`PENDING→retry con device activo`; si ya entregados, nada que hacer (cifrado apunta al receptor, no al emisor) |
| Offline | La revocación se **propaga** al sincronizar; en mesh, un `revoke_notice` firmado (paquete mesh) se propaga entre peers para que no reenvíen a un device revocado (diseño de paquete mesh v2 — sin implementar) |
| Validación server-side | RPC `revoke_device` verifica firma de cuenta + estado del device + auditoría en `device_revocations` |

### 6.3 Propagación mesh de revocación

- Paquete: `{ type:'revocation_notice', payload: canonical_sig(account, op, device_id, ts), peer_fp }`.
- Los pares lo reenvían (TTL por hop similar a routing table); los clientes que lo
  reciben marcan el `device_id` como revocado en sus tablas locales y detienen
  enrutado hacia él. **Fail-closed:** ante duda de validez de firma, se descarta.

---

## 7. Matriz de decisiones pendientes (referenciadas desde CTO_REVIEW)

| Ref | Decisión | Opciones | Recomendación preliminar |
|---|---|---|---|
| DR-1 | ¿Dónde se genera `device_id`? | Cliente (UUIDv4) / servidor | Cliente con validación de unicidad |
| DR-2 | ¿Sesión E2EE por par de devices o por cuenta? | Por device_pair / por account | Por **par de devices** si multi-device activo; fallback account en legacy |
| DR-3 | ¿TTL de challenges? | 5/10/15 min | 10 min |
| DR-4 | ¿Periodicidad de rotación X25519? | No periódica / 90 días / 180 días | No periódica inicial; rotación por compromiso (DR en MIGRATION_PLAN) |
| DR-5 | ¿Quién firma el alta de device_2? | Solo account / device activo / ambos | **Device activo**, validado por account |
| DR-6 | ¿Dónde se persiste el `SessionState` del ratchet? | SecureStorage / Isar cifrado | SecureStorage con snapshot (R-022 — faltaba en los registros previos) |

Documento vinculado: `PHASE_2_CTO_REVIEW_REQUIRED.md` (decisión final de DR-1..DR-5 y D4-D14).