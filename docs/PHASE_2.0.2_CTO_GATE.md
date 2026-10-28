# PHASE 2.0.2 — CTO GATE (Decision Resolution & Architecture Freeze)

> **Tipo:** Puerta de aprobación de FASE 2.0.2 — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** **APROBADA (FASE 2.0.4)** — CTO SIGN-OFF STATUS:
> **APPROVED** · IMPLEMENTATION STATUS: **PHASE 2.1 AUTHORIZATION PENDING**
> **Regla:** esta puerta cierra FASE 2.0.2 (solo documentación). No se abre FASE 2.1 ni se
> toca `lib/`, `supabase/`, `pubspec.yaml` ni el estado remoto hasta la firma.

---

## 1. Decisions resolved

Los **18 OPEN (OPEN-001…018)** quedan **RESOLVED — CTO PROPOSED** (ver
`PHASE_2_DECISION_RESOLUTION.md`) y las **5 políticas 2.0.2** los formalizan:
`RECOVERY_POLICY`, `FINGERPRINT_SPEC`, `BOOTSTRAP_POLICY`, `LEGACY_ACCESS_POLICY`,
`MIGRATION_FAILURE_MATRIX`.

## 2. Decisions requiring human choice

1. **OPEN-001:** copy/producto de la pérdida del historial v1 tras recovery (aceptar
   fail-closed como experiencia oficial) — **decisión humana. → CTO APPROVED (FASE 2.0.4).**
2. **OPEN-018:** pantalla "guardar códigos" no bloqueante (recomendada) vs bloqueante.
   **→ CTO APPROVED (FASE 2.0.4: no bloqueante; RECOVERY_READY sin bloquear creación).**
3. **M5:** plazo de retirada del claim legacy (90 días propuesto — decisión de producto).
   **→ CTO APPROVED (FASE 2.0.4: retirada en M5 condicionada a readiness, sin fecha
   arbitraria; la propuesta de "90 días" queda superada como plazo fijo).**
4. Firma de estas resoluciones como PROPOSED→APPROVED (usuario/CTO).
   **→ Firme: CTO SIGN-OFF STATUS: APPROVED (FASE 2.0.4).**

> Registro formal de las aprobaciones: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md` (FASE 2.0.4 ·
> CTO humano · 2026-09-24). La firma aprueba arquitectura/documentación, no implementación.

## 3. C5 blockers status

| R | Estado tras 2.0.2 | Autoridad |
|---|---|---|
| **R-020** (recovery X25519 v1) | **RESUELTO (propuesto):** Opción A — el recovery NO restaura la X25519 v1; historial v1 ilegible; blob sin X25519 | RECOVERY_POLICY (OPEN-001) |
| **R-002** (fingerprint) | **RESUELTO (propuesto):** fingerprint v1 canónico (ACCOUNT + DEVICE), sin X25519 en el input | FINGERPRINT_SPEC (OPEN-002) |
| **R-025** (lockout legacy) | **RESUELTO (propuesto):** claim acotado hasta M5 + recovery emitida en M1 + reglas REGL-1..3 | LEGACY_ACCESS_POLICY (OPEN-011) |

## 4. C4 blockers status

| R | Estado tras 2.0.2 | Autoridad |
|---|---|---|
| **R-015** (migración) | **RESUELTO (propuesto):** matriz de failure-modes de 12 escenarios, 13 columnas | MIGRATION_FAILURE_MATRIX (OPEN-012) |
| **R-021** (orden B2 vs M1) | **RESUELTO (propuesto):** M0-M5 prevalece; CRYPTO §5.1/§8-B2/§10/§12 marcados superados | DECISION_RESOLUTION (OPEN-011) |
| **R-009** (binding users↔account_id) | **RESUELTO (propuesto):** `users.account_id` FK débil + backfill M1 | DECISION_RESOLUTION (OPEN-007) |

## 5. C3 blockers status

| R | Estado tras 2.0.2 | Autoridad |
|---|---|---|
| **R-004** (evento 1er enroll) | **RESUELTO (propuesto):** máquina PENDING; sin push; cancel + OOB frío | BOOTSTRAP_POLICY (OPEN-003) |
| **R-013** (device_1 active vs pending) | **RESUELTO (propuesto):** device_1 nace `pending`; `confirm_bootstrap` → `active` | BOOTSTRAP_POLICY (OPEN-003) |
| **R-005** (bootstrap code) | **RESUELTO (propuesto):** BOOTSTRAP_SECURITY_POLICY completa | BOOTSTRAP_POLICY (OPEN-004) |
| **R-017** (recovery one-time/rate-limit) | **RESUELTO (propuesto):** single-use por código + rotación + rate-limit 5/15 | RECOVERY_POLICY §4 (OPEN-009) |
| **R-019** (verify_zone_id oráculo) | **RESUELTO (propuesto):** se mantiene sin oráculo + rate-limit | DECISION_RESOLUTION (OPEN-010) |

## 6. Security invariants status

- I-001…I-024 revisados: **VALID** (se levantan los ⚠️ PD de I-004, I-010, I-013, I-014,
  I-016, I-017, I-018, I-019, I-021, I-022, I-024 contra las policies 2.0.2).
- **Nuevos: I-025…I-030** (recovery sin X25519 v1 · fingerprint no-credencial · único
  bootstrap en curso · sin lockout legacy M0-M5 · parámetros bootstrap · máquina de estados
  de device) → total 30 en `PHASE_2_SECURITY_INVARIANTS.md`.
- Ninguno renumerado.

## 7. Threat model status

T1-T17 revisados con los estados correctos (**DISEÑADO / PLANEADO / IMPLEMENTADO /
VERIFICADO**; ver `PHASE_2_THREAT_MODEL.md` §3.1):
T1-T3, T4, T5-T12, T14, T15, T16 → **DISEÑADO (residual documentado)** · T17 → **PLANEADO
(M4)** · T12/T13 → residual inherente aceptado (no se declaran "mitigated" por diseño).
Ninguna amenaza se declara FIXED tras diseño.

## 8. Migration status

M0-M5 reconstruidos conceptualmente en `PHASE_2_MIGRATION_PLAN.md` §8 (objetivo,
precondición, permitido/prohibido, compatibilidad, rollback, recovery, legacy/secure,
server/client state, verificación). Sin ventana de lockout no documentada (I-028).
Claim legacy acotado (OPEN-011) y retirado solo en M5 bajo condiciones.

## 9. Recovery status

RECOVERY_POLICY_V1 (Opción A): se recupera la cuenta (Ed25519), se registran devices
nuevos, se generan claves nuevas; **no** se recupera X25519 v1, historial v1, ni ratchet.
Blob ≈ `{account_sk_ed25519, rotation_counter, created_at}`, AES-256-GCM, AAD=account_id.
Single-use + rate-limit + rotación del juego. Sin FS retroactiva (I-011/I-025).

## 10. Fingerprint status

FINGERPRINT_SPEC_V1: ACCOUNT_FINGERPRINT y DEVICE_FINGERPRINT (20 chars Base32 sin
padding, alfabeto unambiguo, SHA-256, input sin X25519, canon. base64/UUID, KAT en M1).
Nunca credencial (I-026). CRYPTO §5.1/§5.2/§10 superados.

## 11. Bootstrap status

BOOTSTRAP_SECURITY_POLICY: casos A-D (frío/legacy/activo/concurrente), máquina
PENDING→ACTIVE/LOCKED/KILLED, código 8×32 bits (40 bits) TTL 10 min, single-use,
rate 3/15, max 5 intentos, reissue-invalida, audit completo. ZONE-ID + sesión ≠ ownership.

## 12. Legacy access status

LEGACY_ACCESS_POLICY: claim acotado (solo `mode=legacy` sin devices) hasta M5; recovery
emitida en el primer arranque post-M1; REGL-1..3; matriz de acceso por fase M0-M5; sin
lockout entre M1 y M5.

## 13. Double Ratchet boundary

**NO IMPLEMENTADO — SOLO DISEÑO (M4).** Límites preservados: IDENTITY (Ed25519) ≠ DEVICE
AUTH ≠ SESSION ESTABLISHMENT (handshake §5) ≠ RATCHET ≠ MESSAGE. Estado por **par de
devices** (OPEN-006); sin prekeys v1 (OPEN-014); SessionState secreto local (I-023);
backup de historial v3+ = extensión futura (fuera de alcance).

## 14. Mesh boundary

**NO IMPLEMENTADO.** Verificado compatible: autenticación por DEVICE_FINGERPRINT (OPEN-016),
X25519 solo ECDH, handshake autenticado (M3), anti-replay (T17 → M4), fail-closed (I-005),
sin ruta legacy que permita plaintext (OPEN-017).

## 15. Supabase boundary

**NO MODIFICADO.** Requisitos futuros documentados (sin SQL de implementación): tablas
`account_identity`(+`users.account_id`), `devices`(status machine), `device_keys`
(key_version atómico), `device_challenges`(single-use), `recovery_credentials`
(+`recovery_wrapped`, `used_at` por código), RPCs SECURITY DEFINER, I-014 (REVOKE ALL
público), audit events de bootstrap/recovery/legacy claim.

## 16. Remaining contradictions

- **Ninguna C5 activa:** R-020/R-002/R-025 resueltas (propuesto).
- **C1 editoriales pendientes de aceptación CTO** (no bloquean): R-001 (numeración §12
  CRYPTO → L-D1..D9), R-008 (periodicidad rotación → DR-4), R-010 (unificar nomenclatura
  key_version=0), R-011 (renumerar CT-T1..T10), R-012 (erratas/entropía), R-022 (añadir
  DR-6 al registro — aplicado en DEVICE_MODEL §7).
- **C2 residuales:** R-003 (blob columna — dado por OPEN-001/009), R-023 (solo-RPC adopta —
  pendiente de la mecánica M1), R-024 (`account_identity` como hogar; CRYPTO §4.2/§5.1
  marcado superado).

## 17. Remaining unknowns

- Precisión del KAT del fingerprint (vectores oficiales a fijar al inicio de M1).
- Encriptación de la DB local (Isar) — fuera de alcance FASE 2.0 (no prometido).
- Prekeys one-time (extensión futura, no bloquea).
- Backup cifrado de historial v3+ (extensión futura, requiere decisión de producto).
- Rendimiento BLE de M4 (< 50 ms) — medible solo tras implementación.

## 18. Exact prerequisites for FASE 2.1

1. Firma humana/CTO de esta puerta (PROPOSED → APPROVED) y de los 3 puntos de §2.
   **→ CUMPLIDO en FASE 2.0.4** (`PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`; CTO SIGN-OFF:
   APPROVED). Las paradas 2.0.3 pendientes (OPEN-001/018/plazo M5) quedan resueltas.
2. Aceptar las 5 policies 2.0.2 como autoridad (sin cambios de decisiones).
3. Aprobar la limpieza editorial C1 (R-001, R-008, R-010, R-011, R-012, R-022) y el
   marcado de CRYPTO §5.1/§5.2/§7/§10/§12 como superados.
4. Decidir el commit de los 20 archivos untracked verificados en FASE 2.0.3 (19 docs de
   diseño + el pack de firma 2.0.3, todos bajo `docs/`), más este audit de FASE 2.0.3.1
   (21 en total). El conteo anterior de "23 untracked" quedó desactualizado (FASE 2.0.3.1).
5. Reconfirmar `external_anonymous_users_enabled=true` (offline-first; no revertir).
6. Reabrir FASE 1.8 (Security Advisor) en lote separado, como ya se pactó.
7. Solo después: M0 (requiere OPEN-012) → M1 (requiere OPEN-001/002/003/011 + resto).

---

CTO SIGN-OFF STATUS: APPROVED

IMPLEMENTATION STATUS: PHASE 2.1 AUTHORIZATION PENDING

> Fuente de la transición: **FASE 2.0.4** (`PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`).
> Esto NO autoriza FASE 2.1: requiere su propio prompt, alcance, pruebas y CTO gate.