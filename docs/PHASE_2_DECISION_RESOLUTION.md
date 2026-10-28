# PHASE 2.0.2 — Decision Resolution (OPEN-001…OPEN-018)

> **Tipo:** Resolución formal de decisiones abiertas de FASE 2.0/2.0.1 — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** **CTO APPROVED (parcial, FASE 2.0.4)** — OPEN-001,
> OPEN-018 y la retirada M5 de `claim_zone_id` fueron aprobadas por el CTO humano;
> el resto permanece **RESOLVED — CTO PROPOSED**.
> **Blanco de la aprobación:** cada OPEN queda **RESOLVED — CTO PROPOSED**; el CTO/usuario
> los confirma (o los varía) en la puerta `PHASE_2.0.2_CTO_GATE.md`. **Nada se implementa.**
> **FASE 2.0.4:** las tres decisiones humanas pasaron a **CTO APPROVED** (registro formal:
> `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`).
> **Políticas de referencia:** `PHASE_2_RECOVERY_POLICY.md` · `PHASE_2_FINGERPRINT_SPEC.md` ·
> `PHASE_2_BOOTSTRAP_POLICY.md` · `PHASE_2_LEGACY_ACCESS_POLICY.md` ·
> `PHASE_2_MIGRATION_FAILURE_MATRIX.md`.

---

## Criterio de autoridad

Nueva jerarquía tras FASE 2.0.2 (resuelve las contradicciones C3/C4/C5 sin tocar producción):

1. **Políticas 2.0.2** (recovery, fingerprint, bootstrap, legacy access, failure matrix) —
   autoridad para los temas que cubren.
2. **FASE 2.0** (IDENTITY/DEVICE/MIGRATION/THREAT/CRYPTO_DECISIONS) — en lo no cubierto.
3. **CRYPTO_CTO_REVIEW.md** — queda **SUPERADO** en: §5.1/§5.2 (fingerprint), §7.1/§7.3
   (blob de recovery), §10 (UX fingerprint), §12 (checklist B0-B6), y la estrategia B2
   (claim endurecido) — según R-021/R-002/R-020/R-024.

---

# BLOQUEADORES C5

## OPEN-001 — Recovery: semántica del blob (R-020, C5)

- **Conflict:** `CRYPTO_CTO_REVIEW.md` §7.1:317-318 y §7.3:334-337 (blob = `priv_X25519 ‖
  priv_Ed25519`, el recovery restaura ambas ⇒ historial v1 descifrable tras recovery)
  contra `PHASE_2_IDENTITY_ARCHITECTURE.md` §5.E:226-232 y `CRYPTO_DECISIONS` D5:57/D9:90-94
  ("NUNCA recupera privadas viejas" ⇒ historial v1 ilegible).
- **Existing options:** (A) semántica PHASE_2: el blob solo envuelve la identidad Ed25519 de
  cuenta + material nuevo; X25519 v1 muere con el device. (B) semántica CRYPTO: el blob
  envuelve también X25519 v1 ⇒ el recovery devuelve el historial legacy.
- **Security impact:** (A) el robo de códigos + DB no descifra el historial v1; un atacante
  con códigos toma el control de la cuenta (corto alcance: single-use + rate-limit +
  notificación). (B) convierte los códigos en llave maestra del historial: físico roto +
  servidor comprometido = historial completo.
- **Product impact:** (A) el usuario pierde el historial v1 tras recovery — igual que **hoy**
  (no hay backup). (B) UX seductora pero con clase privilegiada: solo cuentas que crearon el
  blob con la privada v1 **antes** de perder el device se benefician.
- **Migration impact:** (A) uniforme para toda la base; implementable en M1 sin dependencias
  previas. (B) no implementable para la mayoría de legacy (no existía recovery pre-M1).
- **Related invariants:** I-004, I-012, I-016, I-024, I-025.
- **Related findings:** R-020, R-003, R-017.
- **CTO proposed decision:** **Opción A** — formalizada en `PHASE_2_RECOVERY_POLICY.md`
  (RECOVERY_POLICY_V1, §2-§4). El blob contiene `{account_sk_ed25519, identity_rotation_counter,
  created_at}`; **jamás** X25519 v1. Separación explícita de ACCOUNT / DEVICE / MESSAGE
  HISTORY / LEGACY KEY / RATCHET STATE recovery.
- **Rationale:** (a) única opción coherente para toda la población (la mayoría de legacy no
  puede crear el blob con la v1); (b) alineación con la doctrina "el servidor no es custodio";
  (c) cierra el vector de compromiso físico de códigos contra el historial; (d) no promete FS
  retroactiva ni degrada garantías (I-011, I-025).
- **Consequences:** `CRYPTO_CTO_REVIEW.md` §7.1/7.3 quedan superados; tests de recovery
  (CRYPTO §11.4) prueban: blob no contiene X25519; historial v1 ilegible tras recovery;
  re-firma de rotación con la identidad restaurada. La exposición de "pérdida de historial"
  depende de copy/producto → **HUMAN DECISION REQUIRED** (sub-item de mensajería).
- **Implementation prerequisite:** actualizar CRYPTO §7 (hecho en 2.0.2) + DEVICE_MODEL §1.6
  (blob + used_at) + OPEN_DECISIONS status.
- **Status:** **CTO APPROVED** (FASE 2.0.4 — OPTION A = SIN X25519 v1).

## CTO Approval

Decision:
CTO APPROVED

Scope:
Documentation/architecture only

Implementation:
NOT AUTHORIZED BY THIS PHASE

- **CTO approved decision:** **Opción A** — recovery restaura cuenta/device según la
  arquitectura secure, **NO restaura la X25519 v1** ni el historial legacy v1; el historial
  v1 puede quedar permanentemente ilegible (consecuencia explícitamente aceptada por CTO);
  el servidor NO se vuelve custodio de la X25519 v1 privada.
- **Rationale:** aprobada en FASE 2.0.4 (CTO humana); sin promesas de recuperación
  universal del historial.
- **Fecha/fase/autoridad:** 2026-09-24 · FASE 2.0.4 · CTO humano.

## OPEN-002 — Fingerprint canónico (R-002, C5)

- **Conflict:** `CRYPTO_CTO_REVIEW.md` §5.1:213 ("hash de la pública"), §5.2:254-255 ("7
  letras", hash de `identity_pk ‖ x25519_pk`) vs `IDENTITY_ARCHITECTURE.md` §7 (20 chars
  Base32, input sin X25519). La X25519 rota ⇒ el fingerprint de CRYPTO sería inestable y
  arrastraría la clave de cifrado a la identidad verificable.
- **Existing options:** (A) fingerprint v1 de IDENTITY §7 (+ KAT); (B) mantener el de CRYPTO
  (inestable).
- **Security impact:** el fingerprint es la verificación MITM out-of-band (M3). Dos
  definiciones ⇒ dos implementaciones incompatibles; rotación de X25519 invalidaría
  fingerprints.
- **Product impact:** UX de comparación uniforme: 20 chars en 4×5; QR; sin "7 letras".
- **Migration impact:** KAT del fingerprint entra en M1; el handshake M3 lo usa.
- **Related invariants:** I-007, I-017, I-026.
- **Related findings:** R-002, R-014.
- **CTO proposed decision:** **Opción A** canónica en `PHASE_2_FINGERPRINT_SPEC.md` v1, con
  **ACCOUNT_FINGERPRINT** y **DEVICE_FINGERPRINT** (inputs dados en la spec, sin X25519,
  Base32 sin padding 20 chars, KAT obligatorio en M1).
- **Rationale:** estabilidad ante rotación (el fingerprint representa al *poseedor* de la
  clave de firma, no a la de cifrado); determinismo entre implementaciones; separación de
  roles D1/D2 intacta.
- **Consequences:** se actualizan CRYPTO §5.1/§5.2/§10; IDENTITY §7 sigue, con la spec como
  autoridad; los flujos M3/R-014 usan DEVICE_FINGERPRINT (OPEN-016).
- **Implementation prerequisite:** KAT fingerprint v1 (2 implementaciones) en M1.
- **Status:** RESOLVED — CTO PROPOSED.

---

# BLOQUEADORES C4 / C3

## OPEN-003 — Evento anti-apropiación en el PRIMER enroll (R-004 + R-013, C3)

- **Conflict:** `IDENTITY §5.B:192-193` y `§5.C.2:207-209` notifican por push al "dispositivo
  original"; en el primer enroll **no existe** tal dispositivo. Además `DEVICE_MODEL §2:113`
  crea device_1 `active` cuando el resto exige `pending` hasta `confirm_bootstrap`.
- **Existing options:** (A) ventana de cancelación (pending N horas, cancel por titular de
  sesión/soporte); (B) canal OOB (correo/OTP) para todo primer enroll; (C) A+B con umbral de
  actividad.
- **Security impact:** sin pending, el atacante que pase el bootstrap queda **activo** de
  inmediato (T4 pierde efecto). Con la máquina PENDING, los derechos se conceden solo tras
  confirmación (código + firma). La sesión es **factor**, no prueba: ZONE-ID + sesión ≠
  ownership (regla formal).
- **Product impact:** flujo de bootstrap con pantalla de confirmación opcional (reciente) /
  bloqueo+OOB (frío); sin push en el primer enroll.
- **Migration impact:** define el contrato de `bootstrap_account`/`confirm_bootstrap` en M1.
- **Related invariants:** I-013, I-027, I-030.
- **Related findings:** R-004, R-013.
- **CTO proposed decision:** **C** formalizada en `PHASE_2_BOOTSTRAP_POLICY.md` (§2 casos
  A-D y §4 máquina PENDING → CHALLENGED(AUTHORIZED) → ACTIVE / LOCKED / KILLED). device_1
  nace `pending`; `confirm_bootstrap` (código 1-uso + firma Ed25519) lo activa.
- **Rationale:** falla la defensa si no hay destinatario ⇒ el objeto protegido pasa a ser el
  *estado sin derechos* + cancelación + auditoría; única implementación determinista.
- **Consequences:** DEVICE_MODEL §2 paso 3 corregido (`pending`); T4 recibe mitigación
  formal; máquina de estados vinculante para RLS/UX (I-030).
- **Implementation prerequisite:** RPCs `bootstrap_account`/`confirm_bootstrap` con status
  machine (M1).
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-004 — Parámetros del bootstrap code (R-005, C3)

- **Conflict:** `IDENTITY §5.A` define "12 dígitos (~40 bits), TTL 10 min, 1 uso" sin
  rate-limit, nonce, interceptación ni re-emisión.
- **Existing options:** (A) código alfanumérico 8-10 chars con rate-limit ≤5 intentos,
  bloqueo, re-emisión invalidando el anterior; (B) 6 dígitos TOTP-like single-use.
- **Security impact:** riesgo real = entropy × TTL × attempts × rate limit. 8 chars × 32
  símbolos = 40 bits, ≤5 intentos, TTL 10 min ⇒ P(fuerza bruta online) ≈ 5/2^40 ≈ 5e-12 por
  ventana; el código **no** es credencial persistente.
- **Product impact:** 8 chars de alfabeto unambiguo (menos fricción que 12 dígitos con
  misma entropía); re-display dentro de TTL con contador.
- **Migration impact:** contrato de M1 para `bootstrap_account`.
- **Related invariants:** I-029.
- **Related findings:** R-005.
- **CTO proposed decision:** **A** — tabla completa en `PHASE_2_BOOTSTRAP_POLICY.md` §3
  (TTL 10 min · ONE_TIME_USE · RATE_LIMIT 3/15 por account+uid/IP · MAX_ATTEMPTS 5 →
  LOCKED 15 min · NONCE (código aleatorio + nonce de `request_challenge`) · BINDING a
  account+attempt · ISSUER servidor · REVOCATION `bootstrap_cancel` · REISSUE invalida el
  anterior · CONCURRENT_REQUESTS 1 por cuenta · AUDIT_EVENT completo).
- **Rationale:** se fijan los controles de abuso en vez de inflar bits ciegamente; el análisis
  entropy×TTL×attempts justifica 40 bits.
- **Consequences:** mandato §5 A-L quedan todos definidos (G/H/J/K ahora con respuesta).
- **Implementation prerequisite:** RPC `bootstrap_account` + `confirm_bootstrap` con los
  parámetros (M1).
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-005 — Payload del QR y emisor del challenge (D4) (R-006, C2)

- **Conflict:** el QR de la opción F transporta "un challenge" sin campos ni emisor.
- **Existing options:** (A) `request_challenge('register_device')` del servidor; QR =
  `{v:1, op:'register_device', account_id, device_2_fp, challenge_id, nonce, intent, ts}`;
  device_2 firma; device_1 autoriza (firma `authorize_device`). (B) challenge generado por
  device_1 (menos control de replay).
- **Security impact:** (A) el challenge del servidor liga el QR a `account_id` **y** al
  `device_fingerprint` de B: un QR sustituto deriva a rechazo por mismatch de fingerprint o
  challenge ya usado; cierra MITM/QR-substitution y replay (T5/T9).
- **Product impact:** flujo D4 claro para ambas pantallas (QR muestra fingerprint de B; A
  confirma).
- **Migration impact:** contrato de RPCs M1 (request_challenge/authorize_device/register_device).
- **Related invariants:** I-008, I-018, I-026.
- **Related findings:** R-006.
- **CTO proposed decision:** **A** (payload y emisor fijados arriba).
- **Rationale:** el servidor es la única fuente de desafíos single-use; el fingerprint en el
  QR es **dato de comparación/binding**, nunca credencial (I-026).
- **Consequences:** DEVICE_MODEL §3 y D4 quedan especificados sin ambigüedad.
- **Implementation prerequisite:** ninguno adicional (ya en M1).
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-006 — Unidad del estado del ratchet (R-007, C2)

- **Conflict:** `CRYPTO §6.3:297-299` (`ratchet_<zoneId>`, par de zonas) vs `MIGRATION M4:99`
  y §5.2:128-129 (`ratchet_<peer_device_id>`, par de devices).
- **Existing options:** (A) por par de devices (DR-2); (B) por par de cuentas.
- **Security impact:** (B) mezcla estados de A1 y A2 en B (contadores, cadenas DH): vectores
  de confusión y replay inducidos por el diseño.
- **Product impact:** multi-device correcto; un mensaje de A se descifra con el ratchet del
  par de devices emisor.
- **Migration impact:** M4 persiste `ratchet_<peer_device_id>`.
- **Related invariants:** I-023.
- **Related findings:** R-007, R-016.
- **CTO proposed decision:** **A** (DR-2) — estado por par de devices; CRYPTO §6.3 superado
  en la unidad de estado.
- **Rationale:** multi-device sin re-handshake (requisito §6.1) y contadores por dirección sin
  colisión.
- **Consequences:** KAT multi-device en M4; OPEN-014 asume esta unidad.
- **Implementation prerequisite:** M4.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-007 — Binding `users` ↔ `account_id` (R-009, C2/C4)

- **Conflict:** `IDENTITY §4:144-146` ancla "users → account_id (fase M2)" pero `MIGRATION
  M1:47`/M2:75-85 no tocan `users`; los RPCs M1 no resolverían `auth.uid() → account_id`.
- **Existing options:** (A) columna `users.account_id UUID NULL` (FK débil + índice),
  backfill por `zone_id` en M1; (B) tabla puente; (C) resolución por `account_identity.zone_id`
  + sesión.
- **Security impact:** sin binding, RLS/validación M1 no puede mapear la sesión anónima a la
  cuenta → validaciones incorrectas o ausentes.
- **Product impact:** ninguno (interno).
- **Migration impact:** DDL M1 + backfill; `users` conserva su forma pública.
- **Related invariants:** I-015.
- **Related findings:** R-009.
- **CTO proposed decision:** **A** (columna en `users`, FK débil, backfill en M1).
- **Rationale:** mínimo cambio de esquema, actualiza el pendiente de MIGRATION_PLAN sin
  re-diseñar `users`.
- **Consequences:** MIGRATION_PLAN M1 actualizado; `decode_auth.uid() → account_id` claro.
- **Implementation prerequisite:** M1.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-008 — Firmante de `rotate_key` (R-018, C2)

- **Conflict:** `DEVICE_MODEL §4:162` ("device y/o de la cuenta según purpose") y §1.3:60
  ("firma de cuenta del dispositivo al rotar") sin regla única.
- **Existing options:** (A) firma `device_sk` del device activo + challenge; (B) firma
  `account_sk`; (C) ambas.
- **Security impact:** la rotación de la clave de cifrado es una op de dispositivo (analogía
  DR-5); firmarla con la cuenta amplía superficie de la identidad de cuenta sin necesidad.
- **Product impact:** ninguno perceptible.
- **Migration impact:** validación server-side de `rotate_key` con clave del device.
- **Related invariants:** I-003.
- **Related findings:** R-018.
- **CTO proposed decision:** **A** — la X25519 se rota firmando con `device_sk` (device
  ACTIVE) + challenge; `account_sk` solo para ops de cuenta (transfer/recover/revoke/rotación
  de identidad). Se corrige DEVICE_MODEL §1.3/§4 y D7.
- **Rationale:** separación de roles; la clave de cifrado pertenece al device.
- **Consequences:** `device_keys.rotate_sig` verificado contra `devices.device_public_key`.
- **Implementation prerequisite:** M1.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-009 — Recovery: single-use por código + rate-limit (R-017, C3)

- **Conflict:** "presentación única" ambiguo (¿UI o criptográfico?) sin `used_at` por código
  ni rate-limit de intentos.
- **Existing options:** (A) cada código single-use; uso de cualquiera rota el juego completo;
  rate-limit de intentos por account (5/15 min, bloqueo progresivo); (B) multi-uso temporal.
- **Security impact:** robo de código + DB robada: sin single-use el atacante entra; con
  rate-limit fuerte se frena la fuerza bruta sobre los 12 códigos.
- **Product impact:** guardar códigos correctamente (pantalla única); nueva emisión tras
  pérdida = rotación.
- **Migration impact:** blob re-envuelto con la clave derivada del nuevo juego (RECOVERY_POLICY §4).
- **Related invariants:** I-016.
- **Related findings:** R-017, R-003.
- **CTO proposed decision:** **A** + columna `used_at` por hash (o fila por código) en
  `recovery_credentials` + campo `recovery_wrapped` (OPEN-001). Parámetros en
  `PHASE_2_RECOVERY_POLICY.md` §4/§5.
- **Rationale:** mitiga el peor vector (código robado) con estado por código y autorregulación
  del uso.
- **Consequences:** rotación re-envuelve y revoca el juego anterior (ya en CRYPTO §7.2).
- **Implementation prerequisite:** M1 (schema `recovery_credentials` + RPC `recover_account`).
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-010 — Destino de `verify_zone_id` (R-019, C3)

- **Conflict:** si sobrevive → oráculo de existencia; si se retira → se pierde el pre-check
  de formato/estado para recovery.
- **Existing options:** (A) mantener con rate-limit y respuesta no distinguible; (B) retirar.
- **Security impact:** (A) con respuesta canónica indiferenciable (`ok`/`expired` genéricos,
  sin boolean de existencia, rate-limit por uid/IP) no permite enumerar; refuerza Z-103.
- **Product impact:** pre-check amable en recovery ("revisa tu zona") sin fuga.
- **Migration impact:** RPC existente se conserva o re-especifica en M1.
- **Related invariants:** I-022.
- **Related findings:** R-019, R-021.
- **CTO proposed decision:** **A** — `verify_zone_id` se mantiene, sin oráculo de existencia,
  con rate-limit; documentado en D11/M1.
- **Rationale:** utilidad de UX + cero superficie nueva de enumeración.
- **Consequences:** T3 cierra su rama de oráculo.
- **Implementation prerequisite:** M1.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-011 — Retirada del claim vs reinstalación legacy (R-025, C4/C5)

- **Conflict:** eliminar `claim_zone_id` (D11) + factor sesión (D3) + legacy sin recovery
  (D8) ⇒ usuario legacy reinstalado sin devices ni códigos no puede volver a entrar
  (lockout entre M1 y M5).
- **Existing options:** (A) claim legacy acotado (solo `mode=legacy` sin devices) con
  rate-limit + aviso de upgrade; (B) verificación OOB para toda la base antes de retirar;
  (C) forzar upgrade + emisión de recovery codes en el primer arranque post-M1.
- **Security impact:** el claim acotado cierra la puerta trasera para cuentas `secure`
  (REGL-2 de LEGACY_ACCESS_POLICY) y conserva una vía estrecha para legacy; el lockout se
  elimina por diseño.
- **Product impact:** usuarios legacy no pierden acceso durante M1..M5; aviso de upgrade en
  vez de bloqueo.
- **Migration impact:** claim retirado solo en M5 bajo condiciones (§5 de la política);
  rolback por feature flag.
- **Related invariants:** I-021, I-028.
- **Related findings:** R-025, R-021.
- **CTO proposed decision:** **A + C** — formalizado en `PHASE_2_LEGACY_ACCESS_POLICY.md`
  (REG-1..3, matriz por fase M0-M5, condiciones de retirada). M1 emite recovery codes en el
  primer arranque (OPEN-018).
- **Rationale:** única solución sin ventana de lockout no documentada (mandato §8/§9) y
  compatible con M0-M5 en ambos sentidos.
- **Consequences:** actualizar D11 (faseo del claim), MIGRATION_PLAN M1/M5.
- **Implementation prerequisite:** M1 (claim acotado + emisión de códigos) y M5 (retirada).
- **Status:** **CTO APPROVED** (FASE 2.0.4 — componente de retirada M5 / decisión de
  producto sobre `claim_zone_id`).

## CTO Approval

Decision:
CTO APPROVED

Scope:
Documentation/architecture only

Implementation:
NOT AUTHORIZED BY THIS PHASE

- **CTO approved decision:** `claim_zone_id` NO es prueba de ownership en la arquitectura
  secure; existe únicamente como mecanismo legacy controlado durante la transición; la
  retirada definitiva ocurre **solo en M5**, condicionada a enrollment seguro, identidad
  Ed25519, dispositivo seguro, recovery, reinstalación, migración legacy, rollback,
  compatibilidad mínima, ausencia de lockout conocido y validaciones de seguridad —
  **sin fecha arbitraria** (la propuesta de "90 días" queda superada como fecha; M5 exige
  readiness documentado).
- **Rationale:** M5 no depende de una fecha de corte sino de los preconditions de
  `PHASE_2_MIGRATION_PLAN.md` M5; el sign-off aprueba la política arquitectónica, no la
  ejecución.
- **Fecha/fase/autoridad:** 2026-09-24 · FASE 2.0.4 · CTO humano.

## OPEN-012 — Seguridad de migración / failure-modes (R-015, C4)

- **Conflict:** `MIGRATION_PLAN §4` sin idempotencia, precondiciones atómicas, rollback ni
  failure-modes; los "qué pasa si…" del mandato §9 sin respuesta.
- **Existing options:** (A) sección "Seguridad de migración" (DDL idempotente, footer de
  versión como source of truth, transacciones por fase, verificación de versión mínima,
  matriz de failure-modes); (B) dejarlo a implementación.
- **Security impact:** sin la matriz, una migración interrumpida puede dejar estado
  inconsistente (versiones cruzadas, blobs sin RLS aplicada, reintentos duplicados).
- **Product impact:** ningún cambio observable.
- **Migration impact:** contrato de todas las fases (M0-M5).
- **Related invariants:** I-010, I-019, I-028.
- **Related findings:** R-015.
- **CTO proposed decision:** **A** — `PHASE_2_MIGRATION_FAILURE_MATRIX.md` (12 escenarios,
  13 columnas: precondición, estado, operación, fallo, detección, recuperación, rollback,
  pérdida, lockout, seguridad, audit) + principios §1; MIGRATION_PLAN absorbe la sección como
  contrato (solo doc).
- **Rationale:** operacionaliza reversibilidad; regla de oro: **sin lockout no documentado**.
- **Consequences:** T1-T17 y M0-M5 verificables contra la matriz.
- **Implementation prerequisite:** M0 (plan).
- **Status:** RESOLVED — CTO PROPOSED.

---

# OPEN-013…OPEN-018 (C2 / diseño)

## OPEN-013 — Rotación de identidad Ed25519 de cuenta

- **Conflict:** `device_keys.identity_key_version` versiona, pero ninguna decisión define
  cuándo/cómo se rota la Ed25519 de cuenta.
- **Existing options:** (A) rotación solo tras recovery de cuenta o compromiso, con firma de
  la clave anterior + ventana de gracia; (B) periódica junto a X25519.
- **Security impact:** rotar la identidad de cuenta es de alto impacto (invalida el anclaje
  de todos los devices y fingerprints); no debe ser periódica.
- **Product impact:** cambiar de "identidad de cuenta" tras pérdida/robo sin romper servicios.
- **Migration impact:** mecanismo acotado (nunca automático) — evolución de
  `identity_key_version`.
- **Related invariants:** I-015, I-026.
- **Related findings:** DEVICE_MODEL §1.1; mandato §4/§7.
- **CTO proposed decision:** **A** — rotación solo por compromiso o recovery de cuenta;
  firma de la clave anterior + ventana de gracia; nunca periódica. El fingerprint de cuenta
  cambia con ella (FINGERPRINT_SPEC §2) y se re-verifica fuera de banda.
- **Rationale:** la identidad de cuenta es el ancla; mutarla es excepcional.
- **Consequences:** alto coste de rotación, documentado; KAT de fingerprints por versión.
- **Implementation prerequisite:** M1/M5 (opcional, solo si ocurre).
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-014 — Prekeys y arranque multi-device del ratchet (R-016, C2)

- **Conflict:** handshake §5 reemplaza a X3DH; no se definen prekeys ni el caso "B inicia
  ratchet con A1 offline".
- **Existing options:** (A) ratchet solo iniciado en contacto real (handshake §5), sin
  prekeys v1; (B) prekeys one-time por device para async.
- **Security impact:** (A) reduce superficie y complejidad (BLE online); sin prekeys no hay
  envío asíncrono a device offline en M4 inicial — trade-off documentado.
- **Product impact:** mesajería mesh es online ⇒ (A) no degrada la UX.
- **Migration impact:** M4 con interfaces mínimas (InitSession vía handshake, sin
  PreKey/v1).
- **Related invariants:** I-023.
- **Related findings:** R-016.
- **CTO proposed decision:** **A** para M4 inicial; prekeys one-time quedan como extensión
  (fuera de alcance, se documenta en MIGRATION §5.1).
- **Rationale:** mesh online-first; las prekeys añaden estado asíncrono sin necesidad.
- **Consequences:** `session_establishment` siempre requiere handshake vivo.
- **Implementation prerequisite:** M4.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-015 — Especificación canónica formal (refinamientos §14)

- **Conflict:** 6 precisiones sin fijar (extra obligatorio, base64 padding, UUID case,
  ts .SSS, transcript como formato propio, challenge obligatorio salvo ancestro).
- **Existing options:** adoptar las 6 (recomendado) o dejar ambigüedad.
- **Security impact:** canonicalización fija = firmas deterministas = sin ambigüedad de
  re-serialización server-side (I-018).
- **Product impact:** ninguno.
- **Migration impact:** base para M1 KAT canonical_payload_v1.
- **Related invariants:** I-018, I-026.
- **Related findings:** mandato §14; DEVICE_MODEL §5.1/§5.3.
- **CTO proposed decision:** **Adoptar las 6** en DEVICE_MODEL §5 (edición de doc) +
  FINGERPRINT_SPEC §3 (canonicalización base64/UUID).
- **Rationale:** cumplen determinismo entre implementaciones.
- **Consequences:** KAT de canonical v1 en M1.
- **Implementation prerequisite:** M1.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-016 — Fingerprint del handshake M3 vs cuenta/dispositivo (R-014, C2)

- **Conflict:** no se define qué fingerprint se compara en el primer contacto mesh.
- **Existing options:** (A) DEVICE_FINGERPRINT del emisor (account en transferencia de
  confianza); (B) ambos.
- **Security impact:** identidad mesh por device; comparar el device del peer detecta
  reinstall/MITM sin contaminar la clave de cuenta.
- **Product impact:** una sola comparación por pantalla (menos fricción).
- **Migration impact:** M3 usa DEVICE_FINGERPRINT en `profile_exchange` v2.
- **Related invariants:** I-007, I-026.
- **Related findings:** R-014, R-002.
- **CTO proposed decision:** **A** — mesh compara el DEVICE_FINGERPRINT del emisor; el
  ACCOUNT_FINGERPRINT se usa en alta de devices/recovery/transfer.
- **Rationale:** la entidad que se autentica en el handshake es el dispositivo (DR-2/OPEN-006).
- **Consequences:** FINGERPRINT_SPEC §5 reglas de uso.
- **Implementation prerequisite:** M3.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-017 — Sesión E2EE por device-pair vs fallback por cuenta

- **Conflict:** la tabla `devices` (DR-2) no fija si el fallback por account en legacy es
  opción de privacidad o degradación temporal.
- **Existing options:** (A) fallback por account SOLO mientras `mode=legacy`; en `secure`
  siempre device-pair; (B) configurable por el usuario.
- **Security impact:** en `secure` el device-pair evita que B mezcle estados (OPEN-006); un
  fallback configurable abriría caminos legacy persistentes no deseados.
- **Product impact:** sin opción en UI (degrado automático solo legacy).
- **Migration impact:** M3/M4 con la regla.
- **Related invariants:** I-009, I-023.
- **Related findings:** mandato §8; DEVICE_MODEL §6.1; D2/D9.
- **CTO proposed decision:** **A** — fallback solo `mode=legacy`; en `secure` siempre
  device-pair.
- **Rationale:** no introducir una ruta legacy perpetua (mandato mesh: sin plaintext); la
  degradación es temporal y explícita.
- **Consequences:** DR-2 con regla de modo; sin configuración de usuario.
- **Implementation prerequisite:** M3/M4.
- **Status:** RESOLVED — CTO PROPOSED.

## OPEN-018 — Backfill de recovery codes para la base legacy

- **Conflict:** los legacy no tienen códigos; si el claim se retira (M5), el recovery debe
  existir antes.
- **Existing options:** (A) emisión en el primer arranque post-M1 (no bloqueante); (B) solo
  activación manual.
- **Security impact:** (A) reduce la ventana de derecho sin vía (si M5 llega sin que todos
  abrieran la app, REGL-1 de LEGACY_ACCESS_POLICY). (B) deja cuentas sin recovery hasta que
  el usuario actúe.
- **Product impact:** pantalla "guardar códigos" no bloqueante en M1; mensajería de producto
  → **HUMAN DECISION REQUIRED** (¿obligatoria o suave?).
- **Migration impact:** M1 emite códigos + blob en el primer arranque; el claim acotado sigue
  para quienes nunca abren la app.
- **Related invariants:** I-016, I-021, I-028.
- **Related findings:** OPEN-011 C; D5.
- **CTO proposed decision:** **A** (no bloqueante) — emisión en primer arranque post-M1;
  claim acotado permanece como red para account legacy nunca abierta.
- **Rationale:** prudencia de producto manteniendo la malla de seguridad de OPEN-011.
- **Consequences:** métricas de adopción de recovery; la retirada de claim en M5 se condiciona
  a estas cifras (LEGACY_ACCESS_POLICY §5).
- **Implementation prerequisite:** M1 (RPC de emisión + UX guardar códigos).
- **Status:** **CTO APPROVED** (FASE 2.0.4 — opción A, no bloqueante).

## CTO Approval

Decision:
CTO APPROVED

Scope:
Documentation/architecture only

Implementation:
NOT AUTHORIZED BY THIS PHASE

- **CTO approved decision:** **Opción A (no bloqueante)** — recovery permite alcanzar
  `RECOVERY_READY` sin bloquear la creación inicial de la cuenta; estados mínimos
  `RECOVERY_UNCONFIGURED → RECOVERY_READY`; mientras una cuenta esté `RECOVERY_UNCONFIGURED`
  aplican restricciones para operaciones de alto riesgo que requieran recovery; el servidor
  no almacena códigos en plaintext (hash/derivación, client-side wrapping, no custodia).
- **Rationale:** el recovery NO debe bloquear inmediatamente la creación inicial; la máquina
  de estados documentada es la aprobada.
- **Fecha/fase/autoridad:** 2026-09-24 · FASE 2.0.4 · CTO humano.

---

## Resumen de estado

| OPEN | R-IDs | Clase | Decisión CTO PROPUESTA | Documento de autoridad |
|---|---|---|---|---|
| 001 | R-020, R-003, R-017 | C5+C3 | Opción A (blob sin X25519 v1) — **CTO APPROVED 2.0.4** | RECOVERY_POLICY |
| 002 | R-002, R-014 | C5 | Fingerprint v1 (ACC+DEV, sin X25519) | FINGERPRINT_SPEC |
| 003 | R-004, R-013 | C3 | Pending + cancel + OOB; máquina PENDING→ACTIVE | BOOTSTRAP_POLICY |
| 004 | R-005 | C3 | Código 8×32 bits, rate 3/15, max 5, reissue invalida | BOOTSTRAP_POLICY |
| 005 | R-006 | C2 | QR server-challenge ligado a device_2_fp | DECISION_RESOLUTION |
| 006 | R-007 | C2 | Ratchet por par de devices (DR-2) | CRYPTO §6.3 (superado) |
| 007 | R-009 | C2/C4 | `users.account_id` FK débil + backfill M1 | MIGRATION_PLAN M1 |
| 008 | R-018 | C2 | rotate_key firma `device_sk` activo | DEVICE_MODEL §4 |
| 009 | R-017 | C3 | Single-use por código + rotación del juego + rate-limit | RECOVERY_POLICY §4 |
| 010 | R-019 | C3 | verify_zone_id sin oráculo + rate-limit | DECISION_RESOLUTION |
| 011 | R-025, R-021 | C4/C5 | Claim acotado hasta M5 + códigos en M1 (A+C) — **retirada M5 CTO APPROVED 2.0.4** | LEGACY_ACCESS_POLICY |
| 012 | R-015 | C4 | Matriz de failure-modes (12 escenarios) | MIGRATION_FAILURE_MATRIX |
| 013 | — | C2 | Rotación de cuenta solo por compromiso/recovery | DECISION_RESOLUTION |
| 014 | R-016 | C2 | Sin prekeys v1; handshake vivo (extensión futura) | DECISION_RESOLUTION |
| 015 | §14 | C2 | Adoptar las 6 precisiones canónicas | DEVICE_MODEL §5, FINGERPRINT_SPEC §3 |
| 016 | R-014 | C2 | Mesh compara DEVICE_FINGERPRINT del emisor | FINGERPRINT_SPEC §5 |
| 017 | — | C2 | Fallback account solo legacy; secure=device-pair | DECISION_RESOLUTION |
| 018 | — | C2 | Códigos en primer arranque post-M1 (no bloqueante) — **CTO APPROVED 2.0.4** | LEGACY_ACCESS_POLICY |

**HUMAN DECISION REQUIRED (no resuelto técnicamente) — LAS TRES APROBADAS EN FASE 2.0.4:**
1. OPEN-001 — copy de producto sobre pérdida del historial v1 tras recovery (aceptar la
   protección fail-closed como experiencia oficial). **→ CTO APPROVED (2.0.4, Opción A).**
2. OPEN-018 — obligatoriedad de la pantalla "guardar códigos" (no bloqueante suave vs
   bloqueante) — recomendado no bloqueante. **→ CTO APPROVED (2.0.4, no bloqueante).**
3. Plazo de retirada del claim en M5 (90 días propuestos; decisión de producto).
   **→ CTO APPROVED (2.0.4): retirada en M5 condicionada a readiness documentado, sin
   fecha arbitraria.** La propuesta de "90 días" queda **superada como plazo fijo**.

Registro formal de la aprobación humana: **FASE 2.0.4 · CTO humano · 2026-09-24** —
`PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`. El apartado "CTO Approval" de OPEN-001/OPEN-011/OPEN-018
arriba conserva decisión propuesta + decisión aprobada + consecuencias.

**Regla de parada:** las tres decisiones abiertas ya no son bloqueadores humanos; el resto
de OPEN permanece **RESOLVED — CTO PROPOSED** hasta la firma completa de la puerta
`PHASE_2.0.2_CTO_GATE.md`. **Nada de esto se implementa.**