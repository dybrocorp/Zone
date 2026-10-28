# PHASE 2.0.1 — Decisiones Abiertas (OPEN DECISIONS)

> **Tipo:** Registro de puntos no formalmente definidos detectados en la auditoría de
> consistencia FASE 2.0.1 — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** FASE 2.0.2 — cada OPEN quedó **RESOLVED — CTO
> PROPOSED** (aprobación humana pendiente; ver `PHASE_2_DECISION_RESOLUTION.md` y la puerta
> `PHASE_2.0.2_CTO_GATE.md`). **FASE 2.0.4:** OPEN-001, OPEN-018 y la retirada M5 de
> `claim_zone_id` pasaron a **CTO APPROVED** (registro formal:
> `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`).
> **Fuente:** `PHASE_2_CONSISTENCY_MATRIX.md` (R-001…R-025). Cada OPEN remite a su R y a la
> sección del mandato 2.0.1. Mientras un OPEN no esté formalmente aprobado, su mitigación
> asociada se considera **DISEÑADA / INCOMPLETA**, nunca FIXED.

---

## Cómo se usa

1. El CTO responde cada OPEN (✔ con la opción recomendada, o una variante).
2. La respuesta se registra aquí mismo (columna "Decisión CTO").
3. Solo después, M0-M5 puede citar estos OPEN como cerrados.

---

## Estado tras FASE 2.0.2 (resoluciones PROPOSED — pendientes de firma humana)

| OPEN | Resolución propuesta | Autoridad | Estado |
|---|---|---|---|
| 001 | Recovery: Opción A (blob sin X25519 v1) | RECOVERY_POLICY | **CTO APPROVED** (2.0.4) |
| 002 | Fingerprint v1 (ACCOUNT + DEVICE, sin X25519) | FINGERPRINT_SPEC | RESOLVED — CTO PROPOSED |
| 003 | Primer enroll: pending + cancel + OOB (C) | BOOTSTRAP_POLICY | RESOLVED — CTO PROPOSED |
| 004 | Bootstrap code: 8×32 bits, rate 3/15, max 5, reissue invalida | BOOTSTRAP_POLICY | RESOLVED — CTO PROPOSED |
| 005 | QR con challenge de servidor ligado a device_2_fp (A) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 006 | Ratchet por par de devices (A/DR-2) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 007 | `users.account_id` FK débil + backfill M1 (A) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 008 | rotate_key firma `device_sk` activo (A) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 009 | Recovery single-use por código + rotación + rate-limit (A) | RECOVERY_POLICY §4 | RESOLVED — CTO PROPOSED |
| 010 | verify_zone_id sin oráculo + rate-limit (A) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 011 | Claim acotado hasta M5 + códigos en M1 (A+C) | LEGACY_ACCESS_POLICY | RESOLVED — CTO PROPOSED |
| 012 | Matriz de failure-modes de 12 escenarios (A) | MIGRATION_FAILURE_MATRIX | RESOLVED — CTO PROPOSED |
| 013 | Rotación de cuenta solo por compromiso/recovery (A) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 014 | Sin prekeys v1; handshake vivo (A) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 015 | Adoptar las 6 precisiones canónicas | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 016 | Mesh compara DEVICE_FINGERPRINT del emisor (A) | FINGERPRINT_SPEC §5 | RESOLVED — CTO PROPOSED |
| 017 | Fallback account solo legacy; secure=device-pair (A) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| 018 | Códigos en primer arranque post-M1 (A, no bloqueante) | LEGACY_ACCESS_POLICY | **CTO APPROVED** (2.0.4) |

> **Decisiones humanas aprobadas en FASE 2.0.4 — CTO APPROVED** (registro formal en
> `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`): (1) OPEN-001 — copy de pérdida del historial v1 tras
> recovery (fail-closed aprobado); (2) OPEN-018 — pantalla "guardar códigos" no bloqueante
> (RECOVERY_READY sin bloquear la creación inicial); (3) retirada de `claim_zone_id` en M5
> (LEGACY CLAIM RETIREMENT condicionado a readiness, sin fecha arbitraria).

---

## OPEN-001 — Semántica del recovery: ¿se restauran las claves X25519 v1?
- **Ref:** R-020 (C5). Mandato §7. Documentos: `CRYPTO_CTO_REVIEW.md` §7.1:317-318 / §7.3:334-337 vs `PHASE_2_IDENTITY_ARCHITECTURE.md` §5.E:226-232, `PHASE_2_CRYPTO_DECISIONS.md` D5:57 y D9:90-94.
- **Problema:** CRYPTO envuelve `priv_X25519 ‖ priv_Ed25519` en el blob y §7.3 los restaura (historial v1 descifrable tras recovery). PHASE_2 afirma "NUNCA recupera privadas viejas" (historial v1 ilegible).
- **Impacto:** decide el contenido del blob, los tests de recovery (CRYPTO §11.4), la UX ("¿recupero mis mensajes?"), y el claim de CRYPTO §7.4.
- **Opciones:** (A) Semántica PHASE_2: el blob solo envuelve la identidad Ed25519 + material de sesión nuevo; la X25519 v1 muere con el device perdido. (B) Semántica CRYPTO: el blob envuelve también la X25519 v1 → el recovery devuelve el historial (riesgo: un atacante con códigos físicos roba el historial completo si obtiene el blob).
- **Recomendación:** **A** (más alineada con D5/D9 y con "el servidor no es custodio de claves privadas"); reescribir CRYPTO §7.1/7.3.
- **Decisión CTO:** ✔ **A — CTO APPROVED (FASE 2.0.4, OPTION A = blob SIN X25519 v1).**

## OPEN-002 — Fingerprint canónico (v1)
- **Ref:** R-002 (C5)/R-014. Mandato §15. `CRYPTO_CTO_REVIEW.md` §5.1:213, §5.2:254-255, §10:388 vs `PHASE_2_IDENTITY_ARCHITECTURE.md` §7:271-286.
- **Problema:** 7 letras (hash `identity_pk‖x25519_pk`) vs 20 chars Base32 (hash `"ZONE-FP-1\0"‖account_id‖identity_pk‖device_pk`); la X25519 no debe entrar (estabilidad ante rotación).
- **Opciones:** (A) fingerprint v1 de IDENTITY §7 (recomendada); (B) mantener fingerprint del CRYPTO incluyendo X25519 (inestable).
- **Recomendación:** **A** + KAT del fingerprint como prueba M1.
- **Decisión CTO:** ⬜

## OPEN-003 — Evento anti-apropiación en el PRIMER enroll
- **Ref:** R-004 (C3). Mandato §5.L. `IDENTITY_ARCHITECTURE.md` §5.B:192-193, §5.C.2:207-209, `DEVICE_MODEL.md` §2:123, `THREAT_MODEL.md` T4:70.
- **Problema:** en el primer enroll no existe un dispositivo registrado al que notificar por push ("dispositivo original" no existe).
- **Opciones:** (A) ventana de cancelación: `pending` por N horas/días donde el titular de la sesión original (o soporte) puede cancelar; (B) canal fuera de banda (correo/OTP) exigido para **todo** primer enroll en cuentas con actividad, no solo frías; (C) combinación A+B con umbral de actividad.
- **Recomendación:** **C**: pending obligatorio + OTP/correo si la cuenta tiene actividad ambigua; frías ya son fail-closed.
- **Decisión CTO:** ⬜

## OPEN-004 — Parámetros del bootstrap code (entropía, nonce, rate-limit, interceptación, re-emisión)
- **Ref:** R-005 (C3). Mandato §5.H/§5.G/§5.J/§5.K. `IDENTITY_ARCHITECTURE.md` §5.A.
- **Problema:** 12 dígitos (~40 bits), sin rate-limit, sin nonce, sin política de interceptación/re-emisión.
- **Opciones:** (A) código alfanumérico 8-10 chars (~47-60 bits) con rate-limit ≤5 intentos, bloqueo tras N fallos, re-emisión invalidando el anterior; (B) código de 6 dígitos + rate-limit estricto (TOTP-like, pero single-use).
- **Recomendación:** **A**; nonce del código = su propio valor aleatorio (no reutilizar); re-emisión: invalidar el anterior (rotación de `used_at` por emisión).
- **Decisión CTO:** ⬜

## OPEN-005 — Payload exacto y emisor del challenge/QR (D4)
- **Ref:** R-006 (C2). Mandato §6. `DEVICE_MODEL.md` §3, `PHASE_2_CRYPTO_DECISIONS.md` D4.
- **Problema:** el QR transporta "un challenge" sin campos definidos ni emisor fijo (¿device_1 local o servidor?).
- **Opciones:** (A) `request_challenge('register_device')` server-side; QR = `{account_id, device_2_fp, challenge_id, nonce, intent, ts}`; device_2 lo firma; device_1 autoriza. (B) challenge generado por device_1 (menos control de replay).
- **Recomendación:** **A** (replay y sustitución de QR quedan cubiertos por un challenge del servidor ligado al account y al device_2 por fingerprint).
- **Decisión CTO:** ⬜

## OPEN-006 — Estado del ratchet: por par de devices (DR-2)
- **Ref:** R-007 (C2). Mandato §11. `CRYPTO_CTO_REVIEW.md` §6.3:297-299 vs `MIGRATION_PLAN.md` M4:99, §5.2:128-129.
- **Problema:** unidad de estado (`ratchet_<zoneId>` vs `ratchet_<peer_device_id>`).
- **Opciones:** (A) por par de devices (DR-2, recomendada — multi-device correcto); (B) por par de cuentas (mezcla estados en B).
- **Recomendación:** **A**; actualizar CRYPTO §6.3 y añadir KAT multi-device en M4.
- **Decisión CTO:** ⬜

## OPEN-007 — Binding `users` ↔ `account_id`
- **Ref:** R-009 (C2/C4). Mandato §4/§9. `IDENTITY_ARCHITECTURE.md` §4:144-146 vs `MIGRATION_PLAN.md` M1:47, M2:75-85.
- **Problema:** el anclaje declarado "en M2" no está en M2 y M1 no toca `users`; los RPCs M1 no pueden resolver `auth.uid() → account_id`.
- **Opciones:** (A) columna `users.account_id UUID NULL` backfilled por `zone_id` en M1; (B) tabla puente `user_account_links(uid, account_id)`; (C) resolver por `account_identity.zone_id` + sesión (sin cambiar `users`).
- **Recomendación:** **A** (FK débil + índice; `users` conserva su forma pública).
- **Decisión CTO:** ⬜

## OPEN-008 — Firmante de `rotate_key`
- **Ref:** R-018 (C2). Mandato §4. `DEVICE_MODEL.md` §4:162 / §1.3:60, `PHASE_2_CRYPTO_DECISIONS.md` D7:73.
- **Problema:** "firma de device y/o cuenta según purpose" sin regla.
- **Opciones:** (A) rotación de clave de cifrado = op de dispositivo → firma `device_sk` (device activo) + challenge; (B) firma `account_sk`; (C) ambas.
- **Recomendación:** **A** (analogía DR-5); `account_sk` solo para transfer/recover/revoke.
- **Decisión CTO:** ⬜

## OPEN-009 — Recovery: single-use por código y rate-limit
- **Ref:** R-017 (C3). Mandato §7. `CRYPTO_CTO_REVIEW.md` §7.2:324-328 / §11.4, `DEVICE_MODEL.md` §1.6, `PHASE_2_CRYPTO_DECISIONS.md` D5:56.
- **Problema:** "presentación única" ambiguo; sin `used_at` por código ni rate-limit de intentos.
- **Opciones:** (A) cada código single-use (marcar hash usado; rotación completa al usarse) + rate-limit de intentos por account (p.ej. 5/15 min, bloqueo progresivo); (B) multi-uso con límite temporal.
- **Recomendación:** **A** (un código usado para recuperar invalida los 12 → re-rotación de todo el juego).
- **Decisión CTO:** ⬜

## OPEN-010 — Destino de `verify_zone_id`
- **Ref:** R-019 (C3). Mandato §3. `THREAT_MODEL.md` T3:62-63, `PHASE_2_CRYPTO_DECISIONS.md` D11.
- **Problema:** si sobrevive, es oráculo de existencia de zona; si se retira, se pierde verificación de formato/estado para recovery.
- **Opciones:** (A) mantener con rate-limit y respuesta no distinguible (sin boolean de existencia); (B) retirar del cliente; el recovery valida por hash del code, no por zona.
- **Recomendación:** **A** con respuesta canónica "ok/expired" indiferenciable (Z-103 ya parcial — `secure_claim_zone_id.sql:129-144`).
- **Decisión CTO:** ⬜

## OPEN-011 — Retirada del claim vs reinstalación legacy (lockout)
- **Ref:** R-025 (C4/C5). Mandato §8/§9. `PHASE_2_CRYPTO_DECISIONS.md` D3/D8/D11, `IDENTITY_ARCHITECTURE.md` §5.A.
- **Problema:** usuario legacy que reinstala (sin devices ni recovery) no puede ni bootstrapear (exige sesión) ni recuperar (no hay códigos) tras eliminar el claim.
- **Opciones:** (A) mantener un claim legacy acotado (solo `mode=legacy` sin devices), rate-limit fuerte + ventana de activación + aviso de upgrade; (B) exigir verificación fuera de banda en el upgrade para toda la base antes de retirar el claim; (C) forzar upgrade con emisión de recovery codes en la primera sesión tras M1.
- **Recomendación:** **A + C** (el claim legacy se retira en M5, no en M1; M1 emite recovery codes a todo usuario que abra la app).
- **Decisión CTO:** ✔ **A + C — CTO APPROVED (FASE 2.0.4: retirada definitiva de `claim_zone_id` en M5, condicionada a readiness; sin fecha arbitraria).**

## OPEN-012 — Seguridad de migración (idempotencia y failure-modes)
- **Ref:** R-015 (C4). Mandato §9. `MIGRATION_PLAN.md` §4.
- **Problema:** sin precondiciones/rollback/idempotencia/estado por fila; los "qué pasa si…" del mandato no tienen respuesta.
- **Opciones:** (A) añadir sección "Seguridad de migración" con: DDL idempotente, footer de versión como source of truth, transacciones por fase, verificación de versión mínima de app, tabla de failure-modes (la del matrix §9); (B) dejar la responsabilidad a implementación (no recomendado).
- **Recomendación:** **A** — el MIGRATION_PLAN se actualiza (solo doc).
- **Decisión CTO:** ⬜

## OPEN-013 — Rotación de identidad Ed25519 (account)
- **Ref:** Mandato §4/§7; `DEVICE_MODEL.md` §1.1 `identity_key_version`; no hay decisión D formal.
- **Problema:** la tabla versiona `identity_key_version` pero ninguna decisión define cuándo/cómo se rota la Ed25519 de cuenta (¿por compromiso? ¿recovery?).
- **Opciones:** (A) rotación solo tras recovery de cuenta o compromiso, con firma de la clave anterior + ventana de gracia; (B) rotación periódica con la X25519.
- **Recomendación:** **A** (una rotación de identidad de cuenta es de alto impacto; no periódica).
- **Decisión CTO:** ⬜

## OPEN-014 — Prekeys y arranque multi-device del ratchet (M4)
- **Ref:** R-016 (C2). Mandato §11.
- **Problema:** el handshake §5 reemplaza a X3DH (CRYPTO §6.3:289), pero: ¿prekeys? ¿cómo inicia B un ratchet con A1 si A1 está offline? ¿cómo se liga `device_public_key` al ratchet?
- **Opciones:** (A) ratchet solo se inicia en contacto real (handshake §5) — sin prekeys en v1 (simple, BLE-compatible); (B) prekeys one-time por device para async.
- **Recomendación:** **A** para M4 inicial; documentar prekeys como extensión (no bloquea mesajería mesh que es online).
- **Decisión CTO:** ⬜

## OPEN-015 — Especificación canónica formal (refinamientos §14 del mandato)
- **Ref:** Mandato §14; `DEVICE_MODEL.md` §5.1/§5.3.
- **Problema:** 6 precisiones pendientes (extra obligatorio, base64 padding, UUID case, ts .SSS, transcript handshake como Encoding propio, challenge obligatorio salvo ancestro).
- **Recomendación:** adoptar las 6 como especificación formal v1 en DEVICE_MODEL §5 (edición de doc).
- **Decisión CTO:** ⬜

## OPEN-016 — Fingerprint del handshake M3 vs fingerprint de cuenta/dispositivo
- **Ref:** R-014 (C2). Mandato §12/§15.
- **Problema:** ¿qué fingerprint se compara fuera de banda en el primer contacto: el de cuenta, el de device, o un binding de ambos?
- **Opciones:** (A) comparar **device fingerprint del emisor** (+account en primer contacto cuando haya transferencia de confianza); (B) comparar ambos.
- **Recomendación:** **A** para mesh (identity por device); el fingerprint de cuenta se compara en alta de devices/recovery.
- **Decisión CTO:** ⬜

## OPEN-017 — Mercado del "modo secure" y cuentas elevadas (DR-2 fallback)
- **Ref:** Mandato §8; `DEVICE_MODEL.md` §6.1; `PHASE_2_CRYPTO_DECISIONS.md` D2/D9.
- **Problema:** resolución de la tabla matriz de decisión `devices` para cuentas con varios devices: ¿sesión E2EE por par de devices siempre, o fallback por account en legacy? No se fija si el fallback es una opción de privacidad o una degradación temporal.
- **Opciones:** (A) fallback por account SOLO mientras `mode=legacy`; en `secure` siempre por device-pair (recomendada); (B) fallback configurable por el usuario.
- **Recomendación:** **A**.
- **Decisión CTO:** ⬜

## OPEN-018 — Backfill de recovery codes para la base legacy
- **Ref:** Mandato §8/§7; OPEN-011 C.
- **Problema:** los usuarios legacy no tienen códigos; si M1 retira claim (aunque sea en M5), el recovery debe existir antes. ¿Cuándo se emiten?
- **Opciones:** (A) emisión en el primer arranque post-M1 (upgrade obligatorio suave); (B) solo al activar recovery manualmente.
- **Recomendación:** **A** con pantalla "guardar códigos" no bloqueante en M1 (mitiga OPEN-011).
- **Decisión CTO:** ✔ **A — CTO APPROVED (FASE 2.0.4: RECOVERY_READY alcanzable sin bloquear creación inicial de cuenta).**

---

## Resumen para el CTO

| Prioridad | OPEN | Clase | Decide antes de |
|---|---|---|---|
| 🔴 Crítica | OPEN-001 (recovery X25519) | C5 | M1 (blob/tests/UX) |
| 🔴 Crítica | OPEN-002 (fingerprint) | C5 | M1/M3 (KAT) |
| 🔴 Crítica | OPEN-003 (evento 1º enroll) | C3 | M1 (bootstrap) |
| 🔴 Crítica | OPEN-011 (claim vs reinstalación legacy) | C4/C5 | M1-D11 |
| 🟠 Alta | OPEN-004, OPEN-005, OPEN-006, OPEN-007, OPEN-008, OPEN-009, OPEN-010 | C2/C3 | M1 (RPCs) |
| 🟠 Alta | OPEN-012 | C4 | M0 (plan) |
| 🟡 Media | OPEN-013, OPEN-014, OPEN-015, OPEN-016, OPEN-017, OPEN-018 | C2 | M2-M5 |

> ⚠️ Ninguna respuesta de este documento se implementa. Solo define el diseño.