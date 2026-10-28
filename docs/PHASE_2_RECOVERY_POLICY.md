# PHASE 2.0.2 — Recovery Policy v1 (RECOVERY_POLICY_V1)

> **Tipo:** Política formal de recuperación — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** **CTO APPROVED** (FASE 2.0.4 — OPTION A = SIN X25519 v1;
> registro: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`)
> **Resuelve:** R-020 (C5) · OPEN-001 · OPEN-009 · OPEN-013 (parcial)
> **Afecta:** `CRYPTO_CTO_REVIEW.md` §7.1/§7.3 (queda superado por esta política) ·
> `PHASE_2_IDENTITY_ARCHITECTURE.md` §5.E · `PHASE_2_CRYPTO_DECISIONS.md` D5/D9 ·
> `PHASE_2_DEVICE_MODEL.md` §1.6 · `PHASE_2_MIGRATION_PLAN.md` (M1-M5)
> **Invariantes:** I-004, I-016, I-024 (revisados) · I-025 (nuevo)

---

## 1. Las cinco recuperaciones son cosas distintas

| Tipo | Qué significa | RECOVERY_POLICY_V1 |
|---|---|---|
| **ACCOUNT RECOVERY** | Restaurar la identidad de cuenta (Ed25519) y el control de la cuenta tras pérdida del dispositivo | ✅ **SÍ se recupera** (identidad de cuenta vía blob envuelto) |
| **DEVICE RECOVERY** | Registrar un dispositivo nuevo usable para la cuenta | ✅ **SÍ** (flujo de recovery = account recovery + alta de device nuevo; los demás devices activos se conservan) |
| **MESSAGE HISTORY RECOVERY** | Volver a leer mensajes ya intercambiados (v1 y v3+) | ❌ **NO para v1** / v3+ depende del device activo (los mensajes de un device perdido no se re-descifran) |
| **LEGACY KEY RECOVERY** | Restaurar la privada X25519 v1 (estática, era legacy) | ❌ **JAMÁS** — el blob **no** la contiene |
| **RATCHET STATE RECOVERY** | Restaurar el estado de sesión del ratchet (futuro M4) | ❌ **NO** — el `SessionState` es secreto local; tras recovery se re-sincroniza (MIGRATION_PLAN §5.2) |

## 2. Decisión (R-020): opción A — la X25519 v1 no se restaura

Entre las opciones existentes en los documentos:

- **Opción A** (`PHASE_2_IDENTITY_ARCHITECTURE.md` §5.E:226-232, `PHASE_2_CRYPTO_DECISIONS.md`
  D5:57, D9:90-94): el recovery restaura la **identidad de cuenta** (Ed25519) y **nunca**
  la X25519 v1; el historial v1 queda ilegible (placeholder 🔒).
- **Opción B** (`CRYPTO_CTO_REVIEW.md` §7.1:317-318 y §7.3:334-337): el blob contiene
  `priv_X25519 ‖ priv_Ed25519`; el recovery restaura ambas y el historial v1 vuelve a
  descifrarse.

**DECISIÓN PROPUESTA (CTO): OPCIÓN A**, por los siguientes análisis:

| Eje | Análisis |
|---|---|
| Confidencialidad histórica | A conserva el principio fail-closed: ni el robo de códigos físicos ni el de la DB + códigos permite leer mensajes v1. B convierte los códigos en una "llave maestra del historial". |
| Recuperación de cuenta | A recupera plenamente la cuenta (identidad Ed25519 + devices + claves nuevas). La cuenta no queda bloqueada. |
| Pérdida de dispositivo | El historial v1 se pierde **en ambos** escenarios (hoy ya se pierde: no hay backup). B solo lo evitaría para cuentas que crearon el blob con la privada v1 **antes** de perder el device. |
| Reinstalación | A: reinstall recupera la cuenta, no el contenido. Coherente con IDENTITY §5.F/G. |
| Compromiso del mecanismo de recovery | En B, un atacante con códigos + blob descifra TODO el historial legacy. En A, el peor caso del atacante es tomar el control de la cuenta (grave pero acotado, y mitigado por single-use + rate-limit + notificación + revocación, I-016). |
| Custodia de claves | A es la doctrina más limpia del "servidor nunca custodio": el servidor aún conserva hashes + blob, pero el blob ya no contiene la clave capaz de abrir el historial. |
| Amenaza de servidor comprometido (T12/T13) | Con A, un compromiso total (servidor + códigos) no descifra el historial v1. Con B, sí. |
| Compatibilidad con M0-M5 | B es **inimplementable para la base actual**: los usuarios legacy no tienen recovery hasta M1, y el blob con la privada v1 solo puede crearse en el dispositivo que aún la posee ⇒ la mayoría de usuarios legacy no podría beneficiarse ⇒ B crea una "clase privilegiada" incoherente. A es uniforme para toda la población. |
| Transición legacy → secure | A no interfiere: el historial v1 se declara no-recobrable desde el inicio; los mensajes v3+ ya usan device_keys (claves por device, no globales). |
| Forward Secrecy | Ni A ni B otorgan FS retroactiva a v1 (prohibido afirmarla — I-011). A no lo promete; B tampoco podría. |
| Post-compromise recovery | A + ratchet M4: tras recovery se re-establecen sesiones nuevas (PCS vía M4). B restaura claves estáticas viejas = peor postura. |
| UX de recuperación | A exige comunicar "tu historial anterior no se descifra" (placeholder 🔒 ya existe). B mejora la UX solo para cuentas con blob pre-creado (minoría) a costa de seguridad. |
| Responsabilidad del usuario | A: el usuario debe saber que el recovery NO es un backup de chats. Requiere copy de producto (decisión humana, abajo). |
| Pérdida permanente del historial | Coste real y aceptado (ya es la realidad HOY). Mitigación futura opcional: "envío de historial cifrado" (extensión OUT-OF-SCOPE, ver §6). |

## 3. Elementos de la política

### 3.1 Qué se recupera
1. **Identidad de cuenta**: la privada Ed25519 de cuenta, **solo si** fue envuelta en el blob
   durante configuración en un dispositivo vivo (alta de cuenta o upgrade). Con ella, el nuevo
   device firma la alta de sus propias claves.
2. **Registro de devices activos** (metadatos públicos del servidor): el nuevo device entra
   como device adicional; la revocación del perdido es acción del usuario.
3. **Claves de cifrado nuevas**: el device recuperado genera su propia X25519
   (device_keys nueva, key_version propio).

### 3.2 Qué NO se recupera
- X25519 v1 (LEGACY KEY RECOVERY = NO).
- Mensajes v1 (MESSAGE HISTORY RECOVERY v1 = NO; placeholder 🔒).
- Mensajes v3+ dirigidos a la clave de un device perdido.
- Estado de ratchet (futuro; local-only, re-sync).

### 3.3 Material criptográfico que PUEDE existir en el recovery (blob envuelto)
| Elemento | Permitido | Nota |
|---|---|---|
| privada Ed25519 de cuenta | ✅ | Es el objeto de ACCOUNT RECOVERY |
| contador de rotación de identidad | ✅ | Auditoría |
| salt/versión del blob | ✅ | `blob_version=1` |
| claves X25519 (v1 o devices) | ❌ | **Prohibido por política** (I-025) |
| claves de ratchet / session keys | ❌ | Secretos locales (I-023) |
| recovery codes en claro | ❌ | Solamente hash en servidor (I-016) |

### 3.4 Material que JAMÁS existe en el servidor
- Claves privadas en claro (ninguna).
- Recovery code en claro (solo `argon2id(code, salt)` o equivalente aprobado).
- Session keys de la era v1 derivadas.
- Material de ratchet.

### 3.5 Mensajes
- **Legacy (v1):** tras recovery, ilegibles (placeholder 🔒 actual, `chat_e2ee_service.dart:105-109`).
- **Secure (v3+):** los nuevos mensajes del par se dirigen a la clave activa del device
  recuperado (device_keys); los anteriores a la clave del device perdido no se re-descifran.
- **Mesh:** el fingerprint del device recuperado es nuevo ⇒ el par debe re-verificar
  out-of-band (M3).

### 3.6 Nueva instalación
1. `recover_account(zone_id, code)` → valida single-use + rate-limit → devuelve blob.
2. Cliente descifra blob localmente → restaura identidad Ed25519 de cuenta.
3. Cliente genera device nuevo (Ed25519 + X25519) y lo registra con la identidad restaurada.
4. Las claves v1 no existen ⇒ historial v1 ilegible; los mensajes nuevos usan la clave nueva.

## 4. Blob de recovery (especificación de diseño)

```
blob_v1 = AES-256-GCM(
    key   = HKDF-SHA256(ikm = recovery_key, salt = recovery_salt, info = "zone-recovery-v1"),
    aad   = account_id (UUID lowercase),
    plain = JSON canónico { v:1, account_sk_ed25519 (b64), identity_rotation_counter (int),
                            created_at (ISO-8601 UTC) },
    nonce = CSPRNG 12B
)
```
- `recovery_key`: derivado del código (o recovery key de 32 chars) por el cliente.
- El servidor almacena: `recovery_hash[]` (argon2id por código, salt por cuenta) +
  `recovery_salt` + `recovery_wrapped` (el blob) — ver actualización de
  `DEVICE_MODEL §1.6` (R-003). **Nunca** en claro.
- Presentación única (UI) **y** single-use criptográfico (I-016): un código usado → rota el
  juego completo (los 12 se re-emiten, los hash viejos se revocan, el blob se re-envuelve
  con la clave derivada del nuevo juego).
- Rate-limit de intentos por account: 5/15 min, escalada progresiva (OPEN-009).

## 5. Secuencia de recuperación (flujo formal)

```
CLIENT                              SERVER
  │ verify_zone_id(zone) (no oráculo) │
  ├── request_recovery_challenge ────▶│ challenge single-use + TTL 10 min
  │◀── challenge                      │
  │ (deriva recovery_key del code)    │
  ├── recover_account(code_hash_proof? NO — el server valida hash; payload firmado con
  │       la identidad restaurada? NO — aún no existe) ─▶
  │
  ► Etapa 1 (possession): cliente envía code → servidor valida argon2id(code) single-use →
  │   devuelve blob envuelto.
  ► Etapa 2 (restauración local): cliente descifra blob → restaura account_sk_ed25519.
  ► Etapa 3 (device nuevo): cliente genera device (Ed25519+X25519) → register_device
  │   firmado con la identidad de cuenta recuperada + challenge.
  │◀── device ACTIVE
  ► Etapa 4 (notificación): evento audit a los demás devices activos ("device añadido tras
  │   recovery") — aviso de posible apropiación si no fue el dueño.
  │◀── ok
```

- La presentación del código NO requiere firma previa (no existe identidad aún); el
  rate-limit + single-use + TTL + auditoría cubren el abuso (T5/T9 análogos).
- La etapa 3 sí exige firma Ed25519 de cuenta (replicable por cualquier poseedor del blob).

## 6. No-objetivos y extensiones futuras

- **Sin FS/PCS retroactivo** para v1 (I-011). FS deriva de M4 y solo para mensajes nuevos.
- **Extensión futura (OUT-OF-SCOPE, requiere decisión humana):** "backup de historial
  cifrado" — export del historial cifrado bajo una clave derivada del recovery_key, que
  permitiría MESSAGE HISTORY RECOVERY v3+ sin exponer claves al servidor. No se diseña en
  FASE 2.0; si el producto lo quiere, se abre mini-spec aparte.
- **Copy de producto** sobre pérdida de historial: decisión humana (ver OPEN-001).

## 7. Invariantes

- **I-004** (privadas solo en dispositivo, salvo recovery aprobado): **VALID** — el recovery
  aprobado es exclusivamente el blob de §4; nada más sale del dispositivo.
- **I-016** (single-use + rate-limit): **VALID** con parámetros de OPEN-009.
- **I-024** (recovery no degrada garantías del historial): **VALID** — ahora con política
  formal; ver nuevo **I-025**.
- **I-025 (NUEVO):** *El recovery no restaura la X25519 v1 ni el historial v1: la
  recuperación de cuenta, de dispositivo y de claves de cifrado nuevas son independientes de
  la clave de cifrado legacy; "recuperar la cuenta" ≠ "recuperar mensajes".*
  (**CTO APPROVED** — FASE 2.0.4, Opción A.)

## 8. Estado

> **CTO APPROVED** (FASE 2.0.4 — OPTION A = SIN X25519 v1). Aprobada por el CTO humano el
> 2026-09-24; registro formal: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`.
> Requiere actualización de: `CRYPTO_CTO_REVIEW.md` §7 (superado), `PHASE_2_CRYPTO_DECISIONS.md`
> D5/D9 (nota), `PHASE_2_DEVICE_MODEL.md` §1.6 (blob + single-use).

---

## CTO Approved Policy

Recovery restores account/device authorization according to the secure architecture but
does not restore X25519 v1 historical private key material.

Historical v1 message recovery is therefore not guaranteed.

No private historical X25519 key may be introduced into server custody merely to provide
legacy history recovery.

**STATUS: CTO APPROVED** — FASE 2.0.4 · CTO humano · registro:
`PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`. Documentación/arquitectura únicamente (no implementa).