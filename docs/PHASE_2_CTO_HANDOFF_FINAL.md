# PHASE 2.0.1 — CTO HANDOFF FINAL (Resultado de la Auditoría de Consistencia)

> **Tipo:** Cierre de FASE 2.0.1 (auditoría) + **FASE 2.0.2** (resoluciones PROPOSED) —
> **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** PENDIENTE DE REVISIÓN CTO · puerta 2.0.2:
> `PHASE_2.0.2_CTO_GATE.md`
> **Regla de parada:** no se abre M0 ni nada de FASE 2.0 en código hasta que este documento
> y `PHASE_2_OPEN_DECISIONS.md` estén firmados.
> **Evidencia:** `PHASE_2_CONSISTENCY_MATRIX.md` · `PHASE_2_OPEN_DECISIONS.md` ·
> `PHASE_2_SECURITY_INVARIANTS.md`.

---

## 0. Actualización FASE 2.0.2 (resoluciones PROPOSED)

- Los **18 OPEN** quedaron formalmente resueltos (PROPOSED) en
  `PHASE_2_DECISION_RESOLUTION.md`, formalizados por las **5 políticas 2.0.2**
  (`RECOVERY_POLICY`, `FINGERPRINT_SPEC`, `BOOTSTRAP_POLICY`, `LEGACY_ACCESS_POLICY`,
  `MIGRATION_FAILURE_MATRIX`).
- Bloqueadores **C5** (R-020/R-002/R-025), **C4** (R-015/R-021/R-009) y **C3**
  (R-004/R-013/R-005/R-017/R-019) tienen resolución propuesta; quedan cerrados **solo con la
  firma de la puerta `PHASE_2.0.2_CTO_GATE.md`**.
- Invariantes: I-001…I-024 revisados (**VALID**, ⚠️ PD levantados) + **I-025…I-030 nuevos**.
- Threat model: T1-T17 con estados design/planned correctos (`PHASE_2_THREAT_MODEL.md` §3.1).
- Este documento mantiene su rol de puerta de 2.0.1; la puerta de 2.0.2 es el
  **PHASE_2.0.2_CTO_GATE** y la decide el CTO sobre DECISION_RESOLUTION.

---

## 1. Resultado de la consistencia

Se compararon los 8 documentos (7 PHASE_2 + `CRYPTO_CTO_REVIEW.md`). **Veredicto:**

- ✅ **Núcleo consistente:** separación Ed25519(firma)/X25519(ECDH, jamás firma), modelo de
  4 identidades, eliminación del claim, modos legacy/transition/secure, fases M0-M5,
  Double Ratchet **solo diseñado**, sin FS retroactiva en historial v1.
- ⚠️ **22 divergencias documentadas (R-001…R-025)** — 6 C1 (terminología/editorial),
  9 C2 (diseño), 5 C3 (seguridad), 3 C4 (migración), **2 C5 (criptografía crítica)**: la
  definición de fingerprint y la semántica de recovery.
- ⚠️ **El Check (mandato §5/H, §6-QR, §7-one-time/rate-limit, §9-failure-modes) dejó 8
  preguntas sin respuesta formal** → formalizadas como OPEN-004…OPEN-012.

## 2. Contradicciones (resumen, detalle en la matriz)

| ID | Clase | Síntesis | Decisión requerida |
|---|---|---|---|
| **R-020** | C5 | Recovery: ¿restaura la X25519 v1 (CRYPTO §7.1/7.3) o no (IDENTITY §5.E/D9)? | OPEN-001 |
| **R-002/R-014** | C5 | Fingerprint: 7 letras+hash de `identity‖x25519` (CRYPTO §5.2) vs 20 chars canónico (IDENTITY §7); arrastra X25519 → inestable ante rotación | OPEN-002/OPEN-016 |
| **R-004** | C3 | Evento anti-apropiación sin destinatario en el **1er** enroll (no hay device que notificar) | OPEN-003 |
| **R-005** | C3 | Bootstrap code: 40 bits, sin rate-limit, sin nonce, sin política de interceptación/re-emisión | OPEN-004 |
| **R-013** | C3 | `device_1` nace `active` (DEVICE_MODEL §2:113) vs `pending` hasta confirmación (el resto) | OPEN-003 |
| **R-017** | C3 | Recovery code: one-time use y rate-limit sin fijar | OPEN-009 |
| **R-019** | C3 | `verify_zone_id`: oráculo de enumeración sin destino definido | OPEN-010 |
| **R-025** | C4/C5 | Claim retirado en M1 + factor sesión + legacy sin recovery ⇒ **lockout de legacy reinstalado** | OPEN-011 |
| **R-015** | C4 | Migración sin idempotencia ni failure-modes (mandato §9 incompleto) | OPEN-012 |
| **R-021** | C4 | CRYPTO §12-D5 propone "B2 (claim endurecido) primero", PHASE_2 lo elimina en M1 | parte de OPEN-011 (prevalece M0-M5) |
| **R-006/R-007/R-009/R-016/R-018** | C2 | QR payload, unidad de ratchet, binding users↔account_id, interfaces DR incompletas, firmante de rotate | OPEN-005…OPEN-008, OPEN-013…OPEN-017 |
| **R-001/R-008/R-010/R-011/R-012/R-022/R-023/R-024** | C1/C2 | Doble numeración D/T, DR-6 ausente del registro, typos, RLS directa vs solo-RPC, ubicación de claves | Editorial + OPEN-015 |

## 3. Decisiones pendientes (18 — listadas en `PHASE_2_OPEN_DECISIONS.md`)

Bloqueantes antes de M1: **OPEN-001 (C5), OPEN-002 (C5), OPEN-003 (C3), OPEN-011 (C4/C5)**.
Bloqueantes antes de M0: OPEN-012 (C4). Resto: OPEN-004…OPEN-010, OPEN-013…OPEN-018 (M1-M5).

## 4. Invariantes (24 — `PHASE_2_SECURITY_INVARIANTS.md`)

I-001…I-012 del mandato + I-013…I-024 derivadas de la auditoría (primer enroll pending,
solo-RPC, account_id inmutable, single-use recovery, fingerprint KAT, canonical v1, migración
idempotente, fuente única de claves, retirada de claim condicionada, verify_zone_id sin
oráculo, ratchet local, no-degradación del historial). ⚠️ I-004/I-013/I-014/I-016/I-017/
I-021/I-022/I-024 quedan PD hasta las decisiones CTO correspondientes.

## 5. Riesgos (actualizados tras la auditoría)

1. **R20 — Historial v1 tras recovery (C5):** según la decisión, el recovery devuelve (blob
   con X25519) o no (placeholder 🔒) el historial. Riesgo de producto + claim técnico.
2. **R25 — Lockout de legacy reinstalado (C4/C5):** retirar `claim_zone_id` en M1 sin un
   camino para `mode=legacy` sin devices expulsa usuarios reales (los 2 actuales + futuros).
3. **R04 — Apropiación en cuentas legacy activas:** el evento anti-apropiación no notifica a
   nadie en el primer enroll; la defensa real depende de `pending` + canal de confirmación.
4. **R05 — Fuerza bruta del bootstrap code:** 40 bits + sin rate-limit = adivinable en la
   ventana de TTL.
5. Historial v1 sin FS retroactiva (aceptado — CTO_REVIEW_REQUIRED §3.1) y compromiso total
   del servidor (T12, mitigado en M3) — sin cambios respecto a FASE 2.0.

## 6. Orden recomendado de implementación (tras firma CTO)

```
0) Firma de PHASE_2_CTO_REVIEW_REQUIRED.md + OPEN_DECISIONS + este handoff (puerta).
1) M0 (preparatoria sin crypto)      → 1 sprint   [requiere OPEN-012]
2) M1 (Ed25519 + devices + RPCs)     → 2-3 sprints [requiere OPEN-001..011, 013, 015, 018]
3) M2 (HKDF + AAD)                   → 1 sprint
4) M3 (handshake v4 + fingerprint)   → 1 sprint   [requiere OPEN-002, 016]
5) M4 (Double Ratchet)               → 2 sprints  [requiere OPEN-006, 014]
6) M5 (retiro legacy)                → 1 sprint, 90 días tras M4 [requiere OPEN-011, 17]
```
Cada fase: análisis 0 + criterio de salida por invariantes (sección "Verificación por fase").

## 7. Pruebas necesarias (añadidas a las ya exigidas por CTO_REVIEW_REQUIRED §4)

- **KAT fingerprint v1** (M1): dos implementaciones independientes → mismo fingerprint
  (OPEN-002/OPEN-015; invariante I-017).
- **KAT canonical_payload_v1** (M1): re-serialización server-side byte a byte (I-018; T7).
- **Recovery semantics** (M1): blob solo abre con el code correcto; single-use; rotación
  revoca; rate-limit (I-016; OPEN-009; CRYPTO §11.4).
- **Bootstrap** (M1): TTL, single-use, rate-limit, re-emisión invalida anterior (OPEN-004).
- **Lockout legacy** (M1/M5): reinstalación de cuenta legacy sin devices (OPEN-011) —
  test de regresión de UX.
- Las ya definidas: prueba por fase CTO_REVIEW_REQUIRED §4; plus v1↔v3, FS/PCS, out-of-order.

## 8. Cambios remotos necesarios (Solo tras aprobación; listados para planificación)

| Ítem | Fase | Nota |
|---|---|---|
| Nueva tabla `account_identity` (+ FK binding users `account_id`) | M1 | DDL idempotente (OPEN-007/012) |
| Tablas `devices`, `device_keys`, `device_challenges`, `device_revocations`, `recovery_credentials` (incl. columna del blob — según OPEN-001) | M1 | DEVICE_MODEL §1 · R-003 |
| Revoke ALL anon/authenticated sobre las 6 tablas + RPCs SECURITY DEFINER | M1 | INVARIANTE I-014 |
| RPCs: `bootstrap_account`, `confirm_bootstrap`, `request_challenge`, `verify_signed_op`, `register_device`, `authorize_device`, `revoke_device`, `rotate_key`, `list_devices`, `recover_account`, `transfer_account` | M1 | + destino de `verify_zone_id` (OPEN-010) |
| Eliminación/desactivación de `claim_zone_id` (acotada a modo legacy — OPEN-011) | M1→M5 | Retirada completa en M5 |
| Footer de versión en `encrypted_content` (sin cambio de columnas) | M2 | MIGRATION §4-M2 |
| `profile_exchange` v2 (firma + fingerprint) | M3 | MIGRATION §4-M3 |
| (Opción de política) `password_min_length` y REVOKE sobre `storage.objects` — **FASE 1.8, sigue pausada** | 1.8 | Fuera de FASE 2.0.1 |
| Rotación de sesión/ratchet público en `device_keys` | M4 | Solo parámetros públicos |

## 9. Puntos que requieren aprobación CTO (puerta de firma)

1. **R-020 → OPEN-001:** contenido del blob de recovery (recomendación: sin X25519 v1).
2. **R-002/R-014 → OPEN-002/016:** fingerprint canónico v1 con KAT (recomendación: IDENTITY §7).
3. **R-004/R-013 → OPEN-003:** canal de confirmación del primer enroll y estado `pending`.
4. **R-025 → OPEN-011:** vía de acceso para legacy reinstalado antes de retirar el claim.
5. **R-005 → OPEN-004** y **R-017 → OPEN-009:** parámetros de bootstrap code y recovery
   (entropía/rate-limit/single-use).
6. **R-015 → OPEN-012:** sección "Seguridad de migración" en MIGRATION_PLAN.
7. Resto de OPEN (005-008, 010, 013-018) y la lista C1 editorial (R-001/R-008/R-010/R-011/
   R-012/R-022) — aprobación de limpieza documental (sin cambios de decisiones).
8. **Declaración explícita:** FASE 2.0 mantiene `external_anonymous_users_enabled=true`
   (requisito offline-first de FASE 1.x) — confirmar que no se revierte.

---

## Plan de acción siguiente (esperando CTO)

1. **CTO** revisa: `PHASE_2_CONSISTENCY_MATRIX.md` (evidencia) → `PHASE_2_OPEN_DECISIONS.md`
   (resoluciones) → `PHASE_2_SECURITY_INVARIANTS.md` (reglas) → este handoff (puerta).
2. Responde los 18 OPEN (✔/✘/variante) y firma `PHASE_2_CTO_REVIEW_REQUIRED.md`.
3. Autoriza (o no) el commit de los 8 documentos FASE 2.0 + los 4 entregables 2.0.1.
4. Desbloquea FASE 1.8 (Security Advisor) y M0+ en lotes separados, como ya se pactó.

**DETENERSE. Sin firma CTO no se toca `lib/`, `supabase/`, `pubspec.yaml`, ni se crean
migraciones.**