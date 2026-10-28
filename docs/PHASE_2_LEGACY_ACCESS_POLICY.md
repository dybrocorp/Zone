# PHASE 2.0.2 — Legacy Access Policy v1 (LEGACY_ACCESS_POLICY)

> **Tipo:** Política de acceso y migración de usuarios legacy — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** **CTO APPROVED** (FASE 2.0.4 — `claim_zone_id` =
> mecanismo legacy de compatibilidad; retirada definitiva solo en M5 condicionada a
> readiness; registro: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`)
> **Resuelve:** R-025 (C4/C5) · OPEN-011 · OPEN-018 · R-021 (parcial: prevalencia de M0-M5)
> **Afecta:** `PHASE_2_CRYPTO_DECISIONS.md` D3/D8/D11 · `PHASE_2_MIGRATION_PLAN.md` M1/M5 ·
> `PHASE_2_IDENTITY_ARCHITECTURE.md` §5.A/F
> **Invariantes:** I-021 (revisado) · I-028 (nuevo)

---

## 1. Problema que resuelve (R-025)

M1 elimina/restringe `claim_zone_id`; un usuario legacy sin Ed25519/devices que **reinstala**
no puede: (a) probar sesión (`auth.uid()` nuevo), (b) recovery (no emitió códigos en v1).
Resultado posible: **LOCKOUT permanente** entre M1 y M5.

**Decisión estructural: NO se elimina el claim en M1.** El claim se retira **solo en M5**
y solo cuando se cumplen las condiciones de §5. El claim legacy queda **acotado**:
exclusivo para cuentas `mode=legacy` **sin devices activos**.

## 2. Matriz de acceso por fase (intervalo M0 → M5)

| Recurso | M0 (hoy) | M1 | M2 | M3 | M4 | M5 |
|---|---|---|---|---|---|---|
| Login legacy (reinstall sin devices) | `claim_zone_id` (5/15 min) | **claim acotado** (modo legacy sin devices) | idem | idem | idem | **retirado** (solo recovery/device) |
| Verificación de ownership | ZONE-ID por conocimiento (rate-limit) | añade señuelos + pending + cancel | añade firma/fingerprint a distancia? (no — solo cuenta) | peer handshake | — | solo device/recovery |
| Creación de Ed25519 identity | — | bootstrap (session + OTP + firma) | — | — | — | — |
| Creación del primer device X25519 | — | bootstrap (device_keys v1) | rotación firmada | — | — | — |
| E2EE | v1 estático | v1 (sin cambio M1) | v3 (HKDF+AAD) | v4 (handshake) | v5 (ratchet) | v5 |
| Devices activos | no existen | sí | sí | sí | sí | sí |
| Recovery codes | no existen | **emitidos en el primer arranque post-M1** (OPEN-018) | idem | idem | idem | obligatorio |
| Mensajes v1 | legibles con clave archivada | legibles | legibles (retired key) | legibles | legibles (retired) | solo lectura (retired) |

## 3. Credencial legacy vigente y su ciclo

| Pregunta | Respuesta |
|---|---|
| ¿Puede un usuario legacy reinstalar durante M1? | **Sí**: claim acotado (modo legacy, sin devices) — sin cambio de UX pre-M5 |
| ¿Cómo demuestra ownership? | ZONE-ID + rate-limit (como HOY, auditado). No se regala: el claim **no crea devices** ni identity |
| ¿Qué credencial legacy sigue siendo válida? | `zone_id` como secreto de re-claim **solo** para `mode=legacy` sin devices |
| ¿Cuándo deja de ser válida? | En el momento en que la cuenta tiene **un device activo o recovery** (transición a `transition`/`secure`); y globalmente en M5 bajo las condiciones de §5 |
| ¿Cómo se crea la nueva Ed25519 identity? | Client-side en el primer arranque post-M1: bootstrap (BOOTSTRAP_POLICY) |
| ¿Cómo se crea el primer device X25519? | En el mismo bootstrap: `device_keys.key_version=1`; la clave archivada v0 queda en `users.public_key` + `account_identity.legacy_public_key` |
| ¿Qué ocurre si el usuario perdió todos sus dispositivos? | Reinstall → claim acotado → bootstrap (si la cuenta pasó a tener recovery, recovery; si sigue legacy, claim+bootstrap con señuelos) |
| ¿Qué ocurre si nunca migró? | Permanece `mode=legacy` soportado (D8) hasta M5; en M5 se le exige upgrade con vía documentada (recovery emitida o claim final + OOB) |
| ¿Qué ocurre durante rollback? | Feature flags por fase: si M1/M5 revierten, el claim vuelve a su estado anterior (audit) |
| ¿Qué ocurre si M1 se ejecutó pero M2 no? | Acceso intacto: los upgraded tienen devices/identity; los no-upgraded siguen legacy; mensajes v1 legibles (M1 no toca cifrado) |

## 4. Propiedad across la migración (regla anti-lockout)

> **REGL-1:** En ningún punto del intervalo M0..M5 un usuario `mode=legacy` sin devices queda
> sin una ruta documentada para restaurar el acceso tras reinstalación: **claim acotado**
> (hasta M5) **o** recovery (emitida en el primer arranque post-M1, OPEN-018).
> **REGL-2:** Un usuario con dispositivo activo **no** puede usar el claim (siempre device o
> recovery) — el claim no es puerta trasera para cuentas seguras (residual T1 cerrado).
> **REGL-3:** La retirada del claim en M5 exige: (a) 100% de cuentas con `mode != legacy`, o
> (b) ventana de gracia + soporte para las restantes. (I-028)

## 5. Condiciones de retirada del claim (M5)

1. Auditoría previa: cuenta activa sin `legacy` (todas transition/secure) o con recovery.
2. Feature flag `claim_legacy_disabled` con rollback documentado (re-enable + audit).
3. Los RPC `claim_zone_id` quedan desactivados para `mode != legacy` **antes** de M5
   (en M1), y totalmente en M5.
4. Mensaje de producto: "cuenta requires upgrade" ante intento de claim legacy en M5.
5. **CTO APPROVED (FASE 2.0.4):** el `claim_zone_id` es **mecanismo legacy de
   compatibilidad**, NO prueba de ownership en la arquitectura secure; sigue acotado
   (`mode=legacy` sin devices) durante la transición.
6. **CTO APPROVED (FASE 2.0.4):** la retirada definitiva ocurre **solo en M5** bajo los
   **preconditions de readiness** de `PHASE_2_MIGRATION_PLAN.md` M5 (enrollment seguro,
   identidad Ed25519, dispositivo seguro, recovery, reinstalación, migración legacy,
   rollback, compatibilidad mínima, ausencia de lockout conocido, validaciones y
   auditabilidad) — **sin fecha arbitraria** y **sin ventana de lockout**.

## 6. Detección y auditoría

| Evento | Fase | Finalidad |
|---|---|---|
| `legacy_claim_accepted` (mode legacy, sin devices) | M1-M4 | Traza de uso del claim acotado |
| `legacy_claim_denied_secure` (cuenta con devices) | M1+ | Evidencia anti-puerta-trasera |
| `upgrade_bootstrap_completed` | M1 | Cuenta abandona legacy |
| `recovery_codes_issued` | M1 (primer arranque) | Backup mitigador (OPEN-018) |
| `claim_disabled_migrated` | M5 | Confirmación de retirada |

## 7. Invariantes

- **I-021** (la retirada del claim no deja usuarios legacy sin vía): **VALID** — ahora la
  política §3-§5 es autoridad; se refuerza con REGL-1.
- **I-028 (NUEVO):** *Ninguna cuenta `mode=legacy` sin devices queda sin una ruta
  documentada de reinstalación entre M0 y M5; el claim acotado y la emisión de recovery
  (primer arranque post-M1) son las vías; la retirada del claim se condiciona a las reglas
  §5 (I-021/LEGACY_ACCESS_POLICY).*

## 8. Estado

> **CTO APPROVED** (FASE 2.0.4 — claim legacy como mecanismo de compatibilidad acotado;
> retirada definitiva solo en M5 condicionada a readiness; sin fecha arbitraria ni ventana
> de lockout). Aprobada por el CTO humano el 2026-09-24; registro formal:
> `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`. Requiere actualización de
> `PHASE_2_CRYPTO_DECISIONS.md` D11 (nota de fases) y `PHASE_2_MIGRATION_PLAN.md` M1/M5.