# PHASE 2.0.1 — Matriz de Consistencia entre Documentos FASE 2

> **Tipo:** Auditoría de consistencia (FASE 2.0.1 · puerta CTO) — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** REVISIÓN PENDIENTE DE CTO · **ACTUALIZADA EN
> FASE 2.0.2** (resoluciones PROPOSED en `PHASE_2_DECISION_RESOLUTION.md`; puerta
> `PHASE_2.0.2_CTO_GATE.md`).
> **Alcance:** comparación cruzada de los 8 documentos FASE 2.0 (7 PHASE_2 + CRYPTO_CTO_REVIEW).
> **Regla:** NO se corrigió silenciosamente ninguna contradicción en los documentos fuente;
> todas se documentan aquí con cita, impacto, resolución propuesta y clasificación C0–C5.
> **Entregables vinculados:** `PHASE_2_OPEN_DECISIONS.md`, `PHASE_2_SECURITY_INVARIANTS.md`, `PHASE_2_CTO_HANDOFF_FINAL.md`.

---

## 0. Veredicto ejecutivo

- **Decisiones núcleo D1, D2, D6, D8, D10, D11, D12, D13, D14:** consistentes entre los
  8 documentos (C0). No se encontró ninguna sección donde X25519 "firme" ni donde
  ZONE-ID se trate como prueba criptográfica de posesión.
- **25 divergencias documentadas (R-001…R-025): 6 C1, 9 C2, 5 C3, 2 C4, 2 C5, y
  R-025 clasificada doble C4/C5.** Las **C3/C4/C5 requieren revisión CTO** (mandato §17).
- **1 contradicción criptográfica crítica (R-020, C5):** el recovery **restaura o no la
  X25519 v1** según se lea `CRYPTO_CTO_REVIEW.md §7.1/7.3` o
  `PHASE_2_IDENTITY_ARCHITECTURE.md §5.E` / `PHASE_2_CRYPTO_DECISIONS.md D5/D9`.
- **1 gap de migración crítico (R-025):** la retirada de `claim_zone_id` (D11) se
  combina con el factor "sesión sobre la fila `users`" (D3) y con el modo legacy (D8),
  pero **no define el login por reinstalación de un usuario legacy sin recovery**
  → riesgo de lockout entre M1 y M5.
- **Estado del Double Ratchet:** correcto en TODOS los documentos como **DESIGNED**
  (nunca IMPLEMENTADO). Interfaces §5.1 completas salvo init/prekeys/device-binding
  (R-016).
- **Claims de seguridad (§16):** no hay exageraciones publicitarias; 2 redacciones
  fronterizas y 1 afirmación condicionada por R-020 (ver §16).

## 0.1 Actualización FASE 2.0.2 (estado de las contradicciones tras resolución)

FASE 2.0.2 resolvió (PROPOSED, no APPROVED) todas las contradicciones que requerían CTO.
Cada resolución se detalla en `PHASE_2_DECISION_RESOLUTION.md` (OPEN-001…018) y se formaliza
en las 5 políticas 2.0.2. Estado por registro (R-001…R-025):

| R | Clase | Resolución 2.0.2 | Autoridad | Estado |
|---|---|---|---|---|
| R-001 | C1 | Checklist §12 → superado; renumeración L-D1..L-D9 propuesta (limpieza) | DECISION_RESOLUTION | RESOLVED — CTO PROPOSED |
| R-002 | C5 | Fingerprint v1 canónico (ACCOUNT + DEVICE, sin X25519 en el input) | FINGERPRINT_SPEC (OPEN-002) | RESOLVED — CTO PROPOSED |
| R-003 | C2 | `recovery_wrapped` en `recovery_credentials` + `used_at` por código | RECOVERY_POLICY §4 (OPEN-009) | RESOLVED — CTO PROPOSED |
| R-004 | C3 | Primer enroll: pending + cancel + OOB frío; sin push (no hay device) | BOOTSTRAP_POLICY §2 (OPEN-003) | RESOLVED — CTO PROPOSED |
| R-005 | C3 | BOOTSTRAP_SECURITY_POLICY completa (entropía/rate/attempts/reissue) | BOOTSTRAP_POLICY §3 (OPEN-004) | RESOLVED — CTO PROPOSED |
| R-006 | C2 | QR = `{v, op, account_id, device_2_fp, challenge_id, nonce, intent, ts}` server-issued | DECISION_RESOLUTION (OPEN-005) | RESOLVED — CTO PROPOSED |
| R-007 | C2 | Ratchet por par de devices (DR-2) | DECISION_RESOLUTION (OPEN-006) | RESOLVED — CTO PROPOSED |
| R-008 | C1 | Periodicidad → DR-4 (solo por compromiso; nunca periódica) | DECISION_RESOLUTION (OPEN-013) | RESOLVED — CTO PROPOSED |
| R-009 | C2/C4 | `users.account_id` FK débil + backfill M1 | DECISION_RESOLUTION (OPEN-007) | RESOLVED — CTO PROPOSED |
| R-010 | C1 | Nomenclatura `key_version`: 0 = archivada vía `legacy_public_key` | DECISION_RESOLUTION (limpieza) | RESOLVED — CTO PROPOSED |
| R-011 | C1 | Amenazas de CRYPTO renumeradas CT-T1..T10 | DECISION_RESOLUTION (limpieza) | RESOLVED — CTO PROPOSED |
| R-012 | C1 | Erratas corregidas; entropía expresada en bits | DECISION_RESOLUTION (limpieza) | RESOLVED — CTO PROPOSED |
| R-013 | C3 | device_1 nace `pending`; máquina PENDING→ACTIVE (I-030) | BOOTSTRAP_POLICY §4 (OPEN-003) | RESOLVED — CTO PROPOSED |
| R-014 | C2 | Mesh compara DEVICE_FINGERPRINT del emisor | FINGERPRINT_SPEC §5 (OPEN-016) | RESOLVED — CTO PROPOSED |
| R-015 | C4 | Matriz de failure-modes (12 escenarios, 13 columnas) | MIGRATION_FAILURE_MATRIX (OPEN-012) | RESOLVED — CTO PROPOSED |
| R-016 | C2 | InitSession solo vía handshake vivo; sin prekeys v1 (extensión futura) | DECISION_RESOLUTION (OPEN-014) | RESOLVED — CTO PROPOSED |
| R-017 | C3 | Recovery single-use por código + rate-limit 5/15 + rotación del juego | RECOVERY_POLICY §4 (OPEN-009) | RESOLVED — CTO PROPOSED |
| R-018 | C2 | rotate_key firma `device_sk` activo + challenge | DECISION_RESOLUTION (OPEN-008) | RESOLVED — CTO PROPOSED |
| R-019 | C3 | verify_zone_id se mantiene, sin oráculo + rate-limit | DECISION_RESOLUTION (OPEN-010) | RESOLVED — CTO PROPOSED |
| R-020 | C5 | Recovery Opción A (blob sin X25519 v1; historial v1 ilegible) | RECOVERY_POLICY (OPEN-001) | RESOLVED — CTO PROPOSED |
| R-021 | C4 | M0-M5 prevalece; CRYPTO B2/§8/§10/§12 marcados superados | LEGACY_ACCESS_POLICY (OPEN-011) | RESOLVED — CTO PROPOSED |
| R-022 | C1 | DR-6 añadida (persistencia `SessionState`) — aplicado en DEVICE_MODEL §7 | DEVICE_MODEL | RESOLVED — CTO PROPOSED |
| R-023 | C2 | Solo-RPC adoptado (RLS directa de CRYPTO §7.1 superada) | SECURITY_INVARIANTS I-014 | RESOLVED — CTO PROPOSED |
| R-024 | C2 | `account_identity` como hogar de la Ed25519 (CRYPTO §4.2/§5.1 superados) | DECISION_RESOLUTION (OPEN-015) | RESOLVED — CTO PROPOSED |
| R-025 | C4/C5 | Claim acotado hasta M5 + recovery en M1; REGL-1..3; sin lockout (I-028) | LEGACY_ACCESS_POLICY (OPEN-011) | RESOLVED — CTO PROPOSED |

> **Ninguna resolución es APPROVED:** la firma humana queda registrada en la puerta
> `PHASE_2.0.2_CTO_GATE.md`. Sin esa firma, las C3/C4/C5 siguen bloqueando la implementación.

---

## 1. Matriz de consistencia D1–D14 (mandato §2)

| Decisión | FUENTE 1 | FUENTE 2 | FUENTE 3 | CONSISTENTE | CONTRADICCIÓN | IMPACTO | RESOLUCIÓN |
|---|---|---|---|---|---|---|---|
| **D1** Account identity (Ed25519) | CRYPTO_CTO_REVIEW §4.1 (línea 167) | IDENTITY_ARCHITECTURE §3 (90,96) | CRYPTO_DECISIONS D1 (11-13) | ✅ Sí (firma; no cifra; privada en SecureStorage) | Ubicación de almacenamiento: `users` (CRYPTO §5.1:211) vs `account_identity` (DEVICE_MODEL §1.1:22) → R-024 (C2) | Cómo migrar columna / dónde lee RLS | Adoptar `account_identity`; actualizar CRYPTO §5.1 |
| **D2** Device encryption identity (X25519) | CRYPTO_CTO_REVIEW §4.1 (169-170), §0 (49-51) | IDENTITY_ARCHITECTURE §2-3 (76,98-99) | CRYPTO_DECISIONS D2 (18-25) | ✅ Sí (ECDH; jamás firma; regla reforzada) | — | Ninguno | — |
| **D3** First device bootstrap | IDENTITY_ARCHITECTURE §5.A-C (157-214) | DEVICE_MODEL §2 (104-123) | CRYPTO_DECISIONS D3 (27-36) | ⚠️ Parcial | Status inicial de device_1: `active` (DEVICE_MODEL §2 paso 3, línea 113) vs `pending` hasta confirmación (IDENTITY §5.C.3, THREAT T4) → R-013 (C3). Detalle del código A-L incompleto → R-005 (C3) | La defensa anti-apropiación depende del `pending`; si device_1 nace `active`, T4 pierde efecto | device_1 nace `pending`; `active` solo tras `confirm_bootstrap` (R-013) |
| **D4** Second device enrollment | DEVICE_MODEL §3 opción F (129-151) | IDENTITY_ARCHITECTURE §5.G (248-253) | CRYPTO_DECISIONS D4 (38-47) | ⚠️ Parcial | Opción F consistente (D+A/QR+C). Falta definir payload exacto del QR y quién genera el challenge → R-006 (C2) | Implementación ambigua; replay/QR-substitution no 100% cerrados | Especificar QR = `{account_id, device_2_fp, challenge_id, nonce, intent}` firmado/ligado (R-006) |
| **D5** Account recovery | CRYPTO_CTO_REVIEW §7.1-7.4 (311-343) | CRYPTO_DECISIONS D5 (49-59) | DEVICE_MODEL §1.6 (89-100) | ❌ **NO** | **R-020 (C5):** CRYPTO §7.1/7.3 restaura `priv_X25519 ‖ priv_Ed25519` (blob) → historial v1 descifrable tras recovery; IDENTITY §5.E y D5/D9 dicen que las privadas viejas **nunca** se recuperan → historial v1 ilegible. Además blob sin columna (R-003, C2) y one-time/rate-limit sin fijar (R-017, C3) | Producto y seguridad: ¿el recovery devuelve el historial v1 o no? | Adoptar semántica PHASE_2 (recupera identidad Ed25519; X25519 v1 NO se restaura); reescribir CRYPTO §7.1/7.3. **DECISIÓN CTO** |
| **D6** Device revocation | DEVICE_MODEL §6 (239-264) | CRYPTO_DECISIONS D6 (61-68) | THREAT_MODEL T11/T14 (122-152) | ✅ Sí | — | Ninguno | — |
| **D7** X25519 rotation | DEVICE_MODEL §4 (154-175) | CRYPTO_DECISIONS D7 (70-78) | MIGRATION_PLAN M2/M5 (75-108) | ⚠️ Parcial | Firmante de `rotate_key` ambiguo: "device y/o de la cuenta según purpose" (DEVICE_MODEL §4:162) + "firma Ed25519 de device/account" (D7:73) → R-018 (C2) | ¿Device_sk o account_sk? Define la cadena de validación server-side | Rotación X25519 = op de **dispositivo** → firma con `device_sk` del device activo + challenge; cuenta solo para ops de cuenta (R-018) |
| **D8** Legacy users | MIGRATION_PLAN §2-3 (30-50) | CRYPTO_DECISIONS D8 (80-86) | HANDOFF §10 (79-84) | ✅ Sí | Retirada de claim + reinstalación legacy sin recovery → **R-025 (C4/C5)** | Lockout de usuarios legacy que reinstalan entre M1 y M5 | Definir vía de reintroducción para `mode=legacy` sin devices (R-025) |
| **D9** Lost original device | IDENTITY_ARCHITECTURE §5.E (222-232) | CRYPTO_DECISIONS D9 (88-95) | THREAT_MODEL T14 (146-152) | ⚠️ Parcial | Depende de R-020: "pdf no recupera privadas viejas" (D9:94) contradice CRYPTO §7.3 | Ver R-020 | Ver R-020 |
| **D10** Lost recovery | CRYPTO_DECISIONS D10 (97-102) | CRYPTO_CTO_REVIEW §7.4 (339-343) | DEVICE_MODEL §1.6 (98-100) | ✅ Sí (fail-closed, sin puerta trasera) | — | Ninguno | — |
| **D11** ZONE-ID semantics | IDENTITY_ARCHITECTURE §6 (257-267) | CRYPTO_DECISIONS D11 (104-112) | THREAT_MODEL T1-T3 (42-64) | ⚠️ Parcial | CRYPTO_CTO_REVIEW §5.1:214, §10:390, §12-D5 siguen describiendo `claim_zone_id` endurecido como primera fase → R-021 (C4). Destino de `verify_zone_id` sin definir → R-019 (C3) | Referencias cruzadas apuntan a caminos distintos (claim endurecido vs claim eliminado) | PHASE_2 prevalece (claim eliminado); marcar secciones B2/§10/§12 de CRYPTO como superadas; decidir `verify_zone_id` (R-019/R-021) |
| **D12** Mesh authentication | MIGRATION_PLAN M3 (87-93) | CRYPTO_DECISIONS D12 (114-119) | THREAT_MODEL T6/T16 (82-88,162-168) | ⚠️ Parcial | Fingerprint del handshake: CRYPTO §5.2 (7 letras, incluye x25519) vs IDENTITY §7 (20 chars, sin x25519) → R-002 (C5) + R-014 (C2) | El fingerprint es la verificación MITM out-of-band; no puede haber dos definiciones | Canonizar fingerprint v1 de IDENTITY §7; actualizar CRYPTO §5.2 (R-002) |
| **D13** Double Ratchet prep | MIGRATION_PLAN §5 (112-152) | CRYPTO_DECISIONS D13 (121-130) | CRYPTO_CTO_REVIEW §6 (264-305) | ⚠️ Parcial | Unidad del estado del ratchet: por par de **zonas** `ratchet_<zoneId>` (CRYPTO §6.3:297-299) vs por par de **devices** `ratchet_<peer_device_id>` (MIGRATION §5.2:128-129, M4:99) → R-007 (C2). Faltan init/prekeys/binding → R-016 (C2) | Multi-device con estados ambiguos; no se puede implementar M4 | Adoptar DR-2 (por par de devices); actualizar CRYPTO §6.3 (R-007) |
| **D14** Migration | MIGRATION_PLAN §1-4 (14-108) | CRYPTO_DECISIONS D14 (132-140) | HANDOFF §11 (86-91) | ⚠️ Parcial | Sin idempotencia/failure-modes (R-015, C4); `users.ancla a account_id` sin fase asignada (R-009, C2/C4); orden "B2 primero" de CRYPTO §12 vs M1 primero (R-021, C4) | Ejecución insegura si falla la red/DB a mitad | Añadir precondiciones/rollback/estados por cabecera (R-015), asignar binding users↔account_id en M1 (R-009) |

---

## 2. Registro de contradicciones (R-001…R-022)

Clasificación (mandato §17): **C0** sin contradicción · **C1** terminología · **C2** diseño ·
**C3** seguridad · **C4** migración · **C5** criptografía crítica.

| ID | Clase | Documentos en conflicto (cita) | Contradicción | Impacto | Resolución propuesta | CTO |
|---|---|---|---|---|---|---|
| R-001 | C1 | `CRYPTO_CTO_REVIEW.md` §12:417-430 (D1-D9 legacy) vs `PHASE_2_CRYPTO_DECISIONS.md` D1-D14 | Doble numeración D1-D9 con significados distintos (p.ej. CRYPTO D3=ratchet, PHASE_2 D3=primer device; CRYPTO D5="B2 primera fase", PHASE_2 D5=recovery). La nota header del CRYPTO (líneas 9-15) ya declara que D1-D14 de FASE 2.0 sustituyen B0-B6, pero §12 sigue en vigor | Citas ambiguas: "D5 decide" no dice qué decide; trazabilidad rota | Marcar §12 del CRYPTO como SUPERADO/renumerar a `L-D1..L-D9`; el checklist vive en `PHASE_2_CTO_REVIEW_REQUIRED.md` | ✅ |
| R-002 | **C5** | `CRYPTO_CTO_REVIEW.md` §5.2:254-255 ("7 letras", hash de `identity_pk ‖ x25519_pk`) y §5.1:213 contra `PHASE_2_IDENTITY_ARCHITECTURE.md` §7:271-286 (20 chars Base32, input `"ZONE-FP-1\0" ‖ account_id ‖ identity_public_key ‖ device_public_key`) | Definición de fingerprint: representación (7 letras vs 20 chars), input (incluye x25519 vs no), y por tanto **estabilidad** (cambia con rotación X25519 vs nunca cambia) | El fingerprint es la prueba MITM out-of-band (M3). Dos implementaciones producirían fingerprints distintos; rotación X25519 invalidaría fingerprints según CRYPTO | Canonizar fingerprint v1 = IDENTITY §7; actualizar CRYPTO §5.1/§5.2/§10:388 e injertar en M3 | ✅ (crítico) |
| R-003 | C2 | `CRYPTO_CTO_REVIEW.md` §7.1:317-319 (`recovery_wrapped` blob) y `PHASE_2_CRYPTO_DECISIONS.md` D5:53-54 (`recovery_blob`) contra `PHASE_2_DEVICE_MODEL.md` §1.6:89-100 (+§1.1) | El blob envuelto es referenciado en decisiones pero **no tiene columna/tabla** en el schema diseñado (`recovery_credentials` solo tiene hashes+salt) | No se puede crear la migración M1 (no hay dónde persistir el blob) | Añadir `recovery_wrapped BYTEA/TEXT` a `recovery_credentials` (o tabla `recovery_blob`) en DEVICE_MODEL §1.6 | ✅ |
| R-004 | C3 | `PHASE_2_IDENTITY_ARCHITECTURE.md` §5.B:192-193 ("push al dispositivo original") y §5.C.2:207-209 (notificación al "dispositivo registrado") contra `DEVICE_MODEL.md` §2:104-123 y THREAT_MODEL T4:70 | En el **primer** enroll no existe ningún dispositivo registrado: no hay a quién notificar por push. El evento anti-apropiación solo es efectivo si ya hay un device (es decir, sirve para el 2º enroll, no para el 1º) | Un atacante con ZONE-ID de cuenta legacy **activa** podría bootstrapear y confirmar con SU Ed25519 (device_1 active) sin que el dueño reciba aviso (no hay push destino) | Definir canal de confirmación para el primer enroll: ventana de cancelación por el titular de la sesión original, o canal fuera de banda (correo) para todo primer enroll, no solo frío | ✅ (crítico) |
| R-005 | C3 | Mandato §5 A-L sobre `IDENTITY_ARCHITECTURE §5.A` y `DEVICE_MODEL §2` | Del código bootstrap solo están definidos: emisor (servidor), receptor (dispositivo solicitante), TTL (10 min), 1 uso. **No definidos:** nonce del código, rate-limit de intentos, entropía mínima (12 dígitos ≈ 40 bits), qué pasa si se intercepta, qué pasa si se solicita otro código | Código de 40 bits + sin límite de intentos = adivinable por fuerza bruta online en la ventana de 10 min; flujo de re-emisión arbitrario | Especificar: código ≥ 8-10 chars alfanuméricos (≈ 50-60 bits), rate-limit (≤3-5 intentos por código), bloqueo + re-emisión con invalidación del anterior (tabla §5 del matrix) | ✅ |
| R-006 | C2 | Mandato §6 (D4) contra `DEVICE_MODEL §3` (opción F), `CRYPTO_DECISIONS D4` | El QR transporta un "challenge" pero **no está especificado** su payload exacto ni quién lo genera (¿device_1 local o `request_challenge` de servidor?) ni qué liga el challenge al device_2 | No se puede cerrar MITM/QR-substitution sin conocer los campos autenticados del QR | QR = `{account_id, device_2_fp, challenge_id, nonce, intent:'register_device', ts}`; challenge single-use de servidor vía `request_challenge(register_device)` (ver §6 matrix) | ✅ |
| R-007 | C2 | `CRYPTO_CTO_REVIEW.md` §6.3:297-299 (`ratchet_<zoneId>`, par de zonas) contra `MIGRATION_PLAN.md` M4:99 y §5.2:128-129 (`ratchet_<peer_device_id>`, par de devices) y `CRYPTO_DECISIONS D13:128` | Unidad del estado del ratchet distinta (par de zonas vs par de devices) | Multi-device: B recibiendo de A1 y A2 con un único `ratchet_<zoneId>` mezclaría estados; almacenamiento contradictorio | Adoptar DR-2 (par de devices) — confirmado en CTO_REVIEW_REQUIRED; actualizar CRYPTO §6.3 | ✅ |
| R-008 | C1 | `CRYPTO_CTO_REVIEW.md` §12-D7/D8 vs `PHASE_2_DEVICE_MODEL` §7 DR-4 | Periodicidad de rotación formulada dos veces sin unificar (CRYPTO D8 "decidir periodicidad" vs DR-4 "no periódica inicial, por compromiso") | Menor; ambigüedad de referencia | Adoptar DR-4; retirar CRYPTO D8 | ⬜ |
| R-009 | C2/C4 | `IDENTITY_ARCHITECTURE.md` §4:144-146 ("users se ancla a account_id — ver MIGRATION_PLAN (fase M2)") contra `MIGRATION_PLAN.md` M1:47 ("users se mantiene; tablas NUEVAS adjuntas") y M2:75-85 (HKDF+AAD, sin tocar `users`) | El anclaje users↔account_id se declara en M2 pero M2 no lo contiene, y M1 excluye tocar `users`. No existe FK `users → account_identity` ni hook auth.uid()→account_id en el esquema | Sin binding, los RPCs M1 no pueden resolver `auth.uid()` → `account_id` para RLS/validación | Asignar explícitamente en M1: columna `users.account_id UUID NULL` (backfill por `zone_id`) o tabla puente; actualizar MIGRATION_PLAN | ✅ |
| R-010 | C1 | `CRYPTO_CTO_REVIEW.md` §9:370-372 ("doble clave: public_key vieja + active_public_key") contra `DEVICE_MODEL §1.1/§1.3` (legacy_public_key + device_keys versionado) | Mecanismos compatibles con nomenclatura distinta; `device_keys` no modela key_version=0 (la archivada) | Trazabilidad de implementación | Unificar: `key_version=0` = clave v1 archivada, referenciada desde `account_identity.legacy_public_key` | ⬜ |
| R-011 | C1 | `CRYPTO_CTO_REVIEW.md` §2 (T1-T10 con significados distintos) vs `PHASE_2_THREAT_MODEL.md` (T1-T17) | Dos tablas "T<num>" con mapeos distintos (CRYPTO T4=dispositivo comprometido; PHASE_2 T4=registro Ed25519 maliciosa; CRYPTO no tiene T11-T17) | `CRYPTO_DECISIONS D11:112` cita "THREAT_MODEL T1-T4" y `CRYPTO §12-D5` cita "T3/T8" del propio CRYPTO → referencias ambiguas | Renumerar las amenazas del CRYPTO como `CT-T1..CT-T10` y remitir al THREAT_MODEL FASE 2.0 | ⬜ |
| R-012 | C1 | `THREAT_MODEL.md` T15:159 ("underscore de mensajes ilegibles"), T12:134 ("Drama de trust"); `CRYPTO_DECISIONS.md` D8:85 ("El cultivate de la base"); `DEVICE_MODEL.md` §1.2:38 ("decisión DR-3" por DR-1); `CRYPTO_DECISIONS D5:52` (16 chars alfanuméricos ≈ 95 bits, escrito "(120 bits)") | Erratas y una referencia cruzada errónea (DR-3→DR-1). Entropía del recovery code mal calculada si se expresa en chars | Menor (C1) pero con fricción si se cita el DP | Corregir redacción; expresar entropía en bits (objetivo ≥120 bits ⇒ 20+ chars o injustificar con base62) | ⬜ |
| R-013 | C3 | `DEVICE_MODEL.md` §2 paso 3:113 ("devices(device_1, active)") contra §1.2:42 (default `pending`) y paso 5:117 (confirm → active), `IDENTITY §5.C.3:210` y `THREAT T4:70` | Estado inicial del primer device: `active` al crear vs `pending` hasta `confirm_bootstrap` | Si nace `active`, el atacante que pase el bootstrap queda activo de inmediato y la ventana de reversibilidad (la defensa real de T4) desaparece | device_1 se crea `pending`; solo `confirm_bootstrap` (firma Ed25519 + código 1-uso) lo pasa a `active` | ✅ |
| R-014 | C2 | `MIGRATION_PLAN.md` M3:89-90 (cita CRYPTO §5 + IDENTITY §7 a la vez) | M3 afirma dos definiciones de fingerprint simultáneamente (cuenta + dispositivo v1, y la antigua de 7 letras del CRYPTO) sin elegir cuál se compara | Handshake M3 sin fingerprint canónico | Reutilizar R-002: fingerprint v1 (cuenta y device) de IDENTITY §7; eliminar la referencia de 7 letras | ✅ |
| R-015 | C4 | Mandato §9 contra `MIGRATION_PLAN.md` §4 (todo el detalle M0-M5) | No se definen: idempotencia de migraciones (doble ejecución), precondiciones atómicas, rollback, failure-modes (app cerrada a mitad, red, Supabase down, reinicio, versión muy antigua, dos dispositivos migrando a la vez) | Ejecución de producción insegura; reversibilidad declarada pero no operacionalizada | Añadir sección "Seguridad de migración" con: DDL idempotente (IF NOT EXISTS), footer de versión como source of truth por fila, transacciones por fase, estado `migrating` por cuenta, verificación previa de versión de app, tabla de failure-modes (tabla §9 del matrix) | ✅ |
| R-016 | C2 | Mandato §11 (interfaces) contra `MIGRATION_PLAN §5.1` | Las 7 interfaces están definidas; faltan: inicialización sesión (handshake→SessionState), **prekeys** (CRYPTO §6.3 menciona X3DH pero no define interfaces de prekey en M4), binding identidad de dispositivo→ratchet, y serialización/persistencia del SessionState | Multi-device asíncrono y restauración tras reinicio sin contrato | Añadir a §5.1: `InitSession`, `PreKey(s)` (o justificación de su ausencia por handshake §5), `SessionSerialization`, binding `device_public_key → ratchet_id` | ✅ |
| R-017 | C3 | Mandato §7 (recovery) contra `CRYPTO §7.2/§11.4`, `DEVICE_MODEL §1.6`, `CRYPTO_DECISIONS D5` | "Presentación única" ambiguo: ¿solo UI o single-use criptográfico del código? Sin rate-limit de intentos de entrada ni `used_at` por código (`last_recovery_at` no basta) | Robo de un recovery code + blob (DB robada) = acceso si no hay single-use/rate-limit | Cada código single-use (`recovery_credentials.used_at` por hash); rate-limit de intentos por account; rotación revoca (ya definido) | ✅ |
| R-018 | C2 | `DEVICE_MODEL §4:162` ("device y/o de la cuenta según purpose") y §1.3:60 ("Firma de cuenta del dispositivo al rotar") contra `CRYPTO_DECISIONS D7:73` | Quién firma `rotate_key`: `device_sk`, `account_sk`, o ambos — sin regla | Validación server-side con claves distintas; cadena de confianza indefinida | Rotación de clave de cifrado = op de **dispositivo**: firma `device_sk` (device activo) + challenge single-use; `account_sk` solo en ops de cuenta (transfer/recover/revoke) (ver DR-5 analogía) | ✅ |
| R-019 | C3 | `THREAT_MODEL T3:62-63` ("verify_zone_id complementa y NO expone") contra `CRYPTO_DECISIONS D11:104-112` (no lo menciona) | Destino de `verify_zone_id` (mantener con rate-limit como oráculo de existencia) no definido tras eliminar el claim | Oráculo de enumeración si sobrevive sin límite | Decidir: mantener con rate-limit y respuesta no distinguible, o retirar; formalizar en D11/M1 | ✅ |
| R-020 | **C5** | `CRYPTO_CTO_REVIEW.md` §7.1:317-318 y §7.3:334-337 (restaura `priv_X25519`) contra `IDENTITY_ARCHITECTURE.md` §5.E:226-232 y `CRYPTO_DECISIONS.md` D5:57, D9:90-94 ("NUNCA recupera privadas viejas") | El recovery **sí** restaura la X25519 v1 (CRYPTO: el blob la envuelve; §7.3 la restaura y luego rota) vs **no** la restaura (PHASE_2: el historial v1 queda ilegible tras recovery) | Decisión de producto/seguridad opuesta: ¿recuperar la cuenta devuelve el historial v1 o no? Afecta blob, tests, UX y claims (CRYPTO §7.4 "no abre el blob sin recovery" depende de esto) | Adoptar semántica PHASE_2 (recupera identidad Ed25519 + clave de sesión nueva; X25519 v1 **no** se restaura; historial v1 ilegible). Reescribir CRYPTO §7.1/7.3. **DECISIÓN CTO** | ✅ (crítico) |
| R-021 | C4 | `CRYPTO_CTO_REVIEW.md` §5.1:214, §10:390, §12-D5 (B2 = claim endurecido como PRIMERA fase) contra `PHASE_2_CRYPTO_DECISIONS D11` y `MIGRATION_PLAN §7` (M1 primero, claim eliminado) | Estrategia y orden distintos: endurecer `claim_zone_id` con firma primero vs eliminar el claim en M1 | Dos hojas de ruta divergentes; la nota header (CRYPTO:9-15) dice que PHASE_2 sustituye B0-B6 pero las secciones del cuerpo no se actualizaron | M0-M5 de MIGRATION_PLAN prevalece; marcar §5.1/§8-B2/§10/§12 del CRYPTO como superados por D11 | ✅ |
| R-022 | C1 | `DEVICE_MODEL.md` §7:268-278 lista DR-1..DR-5 y `MIGRATION_PLAN §5.1:118` cita "decisión DR-6" (persistencia SessionState) | DR-6 existe en `CTO_REVIEW_REQUIRED.md:37` y en HANDOFF:121 pero NO en el registro de DEVICE_MODEL §7 | Registro de decisiones incompleto en un documento | Añadir DR-6 al registro de DEVICE_MODEL §7 | ⬜ |
| R-023 | C2 | `CRYPTO_CTO_REVIEW.md` §7.1:321-322 (RLS `USING (id = auth.uid())` en consulta directa) contra `DEVICE_MODEL §1.1:31` y `§1.6` y `HANDOFF §8:68` (solo RPC, "jamás SELECT público") | Modelo de acceso a identidad/recovery: consulta directa con RLS scoped vs acceso exclusivo vía RPC SECURITY DEFINER | Consulta directa sobre `recovery_hash`/blob (aunque scoped) amplía superficie y oráculos | Adoptar solo-RPC (PHASE_2); actualizar CRYPTO §7.1 | ✅ |
| R-024 | C2 | `CRYPTO_CTO_REVIEW.md` §4.2:198 y §5.1:211 ("clave de firma archivada en `users`") contra `DEVICE_MODEL §1.1:22` y `IDENTITY §3:89` (`account_identity.identity_public_key`) | Almacenamiento de la Ed25519 pública: en `users` vs en `account_identity` | Esquema y RLS divergentes | `account_identity` (tabla nueva) es el hogar; `users` no cambia de forma (M1) | ✅ |
| R-025 | **C4/C5** | `CRYPTO_DECISIONS D11` (eliminar claim) + `D3` (factor sesión sobre la fila users) + `D8` (legacy retenido) contra `IDENTITY §5.A` y mandato §9 | Tras eliminar el claim, un usuario **legacy que reinstala** (sin devices, sin recovery — no emitió códigos en v1) no puede: (a) probar sesión (`auth.uid()` nuevo), (b) recovery (no existe). El bootstrap exige sesión del dueño → lockout | Lockout de acceso para legacy reinstalado entre M1 y M5; fricción de producto | Mantener un camino legado acotado y distinguible (`mode=legacy` sin devices) con rate-limit + ventana de activación, emitido SOLO hasta que el usuario haga upgrade, o exigir upgrade con verificación fuera de banda antes de retirar el claim | ✅ (crítico) |

---

## 3. Identity consistency (mandato §3)

Verificación del triplete terminológico en los 8 documentos: **Ed25519 = Account Identity ✅** ·
**X25519 = Device Encryption Identity ✅** · Session Identity = par (mi device ↔ peer) ✅.

- **X25519 como firma:** 0 ocurrencias. Todos los documentos aplican la regla
  (CRYPTO §0:49-51, §4.1:170; IDENTITY §2:76-81; CRYPTO_DECISIONS D2:24; DEVICE_MODEL §4).
- **ZONE-ID como prueba de posesión:** 0 ocurrencias como afirmación positiva; se afirma lo
  contrario en IDENTITY §6:266-267, D11, T1/T3.
- Único matiz: el *fingerprint* del CRYPTO §5.2 combina `identity_pk ‖ x25519_pk` en el
  hash — no es una firma, pero **arrastra la X25519 a la identidad verificable** → R-002/R-014.

## 4. Device model consistency (mandato §4)

| Objeto | Quién crea | Quién firma | Quién verifica | Dónde se almacena | Quién puede revocar | Cómo se propaga | Consistencia |
|---|---|---|---|---|---|---|---|
| `account_identity` | Servidor (RPC `create_account`/`bootstrap_account`, SECURITY DEFINER) | — (el device firma al enlazarse) | Solo RPC | `account_identity` | `delete_own_account` / soporte | N/A (fila) | ✅ (R-024: ubicación vs `users`) |
| `device_id` | Cliente UUIDv4 (DR-1) | — | Servidor en RPC (unicidad) | `devices` | `revoke_device` (firma de cuenta) | list_devices del dueño | ✅ (R-006: etiqueta DR-3→DR-1) |
| `identity_public_key` | Cliente (Ed25519), subida en enroll | Device (confirm_bootstrap) | Servidor (firma) + peers (handshake M3) | `account_identity` | — (rotación de identidad futura) | `get_identity_public_key` (RPC limitado) | ✅ (R-024) |
| `device_public_key` | Cliente (Ed25519) | Device al firmar ops | Servidor (`devices.status=active`) + peers (fingerprint) | `devices` | Device activo auto? `revoke_device` | mesh vía `revocation_notice` | ✅ |
| `device_keys` (X25519) | Cliente (de cada device) | Device activo (R-018: `device_sk`) | Servidor (`key_version` monótono, `rotate_sig`) | `device_keys` | Rotación a `retired/compromised` | mensajes con `key_version` | ⚠️ R-010/R-018 |
| `fingerprint` | Cliente (hash canónico §7) | — | Ambos extremos (comparación off-band) | `account_identity.identity_fingerprint` + `devices.device_fingerprint` | N/A | M3/profile_exchange v2 | ⚠️ R-002, R-014 |
| Desafío (challenge) | Servidor (`request_challenge`) | Cliente (canonical_payload_v1) | Servidor (single-use + TTL 10 min + ts ±5 min) | `device_challenges` | N/A | N/A | ✅ (R-005 aplica al bootstrap code) |
| Autorización device_2 | device_1 firma `authorize_device`; device_2 firma `register_device` | Ambos (Ed25519) | Servidor (firmas + estado + challenge) | `device_revocations`/auditoría + `devices` | Device activo que autorizó | mesh (paquetes firmados) | ✅ |

## 5. First device bootstrap — respuestas A–L (mandato §5)

| # | Pregunta | Respuesta en los documentos | Estado |
|---|---|---|---|
| A | ¿Quién genera el código? | Servidor (`bootstrap_account`, emite one-time code) — IDENTITY §5.A, DEVICE_MODEL §2 | ✅ Definido |
| B | ¿Quién recibe el código? | El dispositivo que llama a `bootstrap_account` (único poseedor de la sesión + fila) | ✅ Definido |
| C | ¿Qué demuestra? | Que el solicitante conserva la sesión anónima cuya fila `users` es esa cuenta. **NO demuestra** posesión de la X25519 (explícito: IDENTITY §5.B "no se exige… no hay ancestro") | ✅ Definido |
| D | ¿Cómo se vincula al account_id? | El código se emite dentro del mismo RPC que crea `account_identity`/device, ligado a ese account_id y a `expires_at` | ✅ Definido |
| E | ¿Puede un atacante con el ZONE-ID usarlo? | No sin la sesión del dueño; mitigado con señuelos + `pending` + fail-closed (frío). **Gap:** para cuenta activa sin devices, nadie recibe el evento (R-004); la fuerza del control es la sesión + pending | ⚠️ Parcial (R-004/R-005) |
| F | ¿Tiene expiración? | Sí, TTL 10 min (IDENTITY §5.A, DEVICE_MODEL §2, D3) | ✅ Definido |
| G | ¿Tiene nonce? | No se define nonce del código (solo el propio código es el secreto; los challenges sí tienen nonce) | ❌ Baste → R-005 |
| H | ¿Tiene rate limit? | No (solo el legado `claim_zone_id` tiene 5/15 min; el código bootstrap no) | ❌ Baste → R-005 |
| I | ¿Es reutilizable? | No, 1 uso (IDENTITY §5.A:163; DEVICE_MODEL §2:114) | ✅ Definido |
| J | ¿Qué pasa si se intercepta? | No definido (¿revocación? ¿re-emisión?) | ❌ Baste → R-005 |
| K | ¿Qué pasa si se solicita otro? | No definido (¿invalida el anterior?) | ❌ Baste → R-005 |
| L | ¿Cuenta fría? | Fail-closed: canal fuera de banda o bloqueo (IDENTITY §5.C.1:201-206; D3:34-35) | ✅ Definido |

## 6. Second device (mandato §6)

Flujo obligatorio verificado: **DEVICE A → authorization → challenge/QR → DEVICE B → proof → SERVER → B ACTIVE** ✅

| Pregunta | Respuesta | Definido |
|---|---|---|
| ¿Qué firma A? | `authorize_device` con `sig_account(op='register_device' ‖ new_device_id ‖ device_pub ‖ ts)` (DEVICE_MODEL §3:146-147) | ✅ |
| ¿Qué firma B? | `register_device(op, device_2)` con su Ed25519 + el challenge firmado (D4:43-44; DEVICE_MODEL §5.2) | ✅ |
| ¿Qué clave conoce cada uno? | A: device_1_sk (+account_sk). B: su propia device_sk. B conoce claves públicas de A vía QR/fingerprint | ✅ |
| ¿Qué valida el servidor? | Firmas (A y B), challenge single-use/TTL, `devices.status='active'`, `op/account/device` coherentes (DEVICE_MODEL §5.2 pasos 1-5) | ✅ |
| ¿Qué valida A? | Fingerprint de B en pantalla (comparación off-band) | ✅ |
| ¿Qué valida B? | Fingerprint de A y la firma del `authorize_device` | ✅ |
| ¿Qué evita MITM? | Fingerprints en ambas pantallas + firma Ed25519 sobre payload canónico (M3) | ✅ |
| ¿Qué evita replay? | Challenge single-use (`used_at`) + TTL 10 min + ventana ts ±5 min + idempotencia por challenge_id (T5/T9) | ✅ |
| ¿Qué evita QR substitution? | **No cerrado:** payload del QR sin especificar (R-006); si el QR no liga `challenge_id`↔device_2, un QR sustituto deriva a un challenge del atacante | ❌ Baste → R-006 |
| ¿Qué ocurre si A está offline? | Opción F: parcial en mesh (paquetes firmados entre pares; servidor valida al sincronizar) (DEVICE_MODEL §3:136) | ✅ |
| ¿Qué ocurre si A está comprometido? | T10: alta de devices sospechosos → flag + notificación + revocación por el dueño; no hay prevención absoluta | ✅ (documentado) / ⚠️ depende de R-004 (a quién notifica) |

## 7. Recovery (mandato §7)

| Tipo | Definición en los documentos | Estado |
|---|---|---|
| **ACCOUNT RECOVERY** | Restaura el control de la cuenta (identidad Ed25519 vía blob) y permite registrar device nuevo (CRYPTO §7.3:330-337; D5) | ✅ / ⚠️ R-020 |
| **DEVICE RECOVERY** | Registrar un device nuevo tras recovery usando la identidad restaurada | ✅ |
| **KEY RECOVERY** | La X25519 v1 **no se recupera** en PHASE_2 (D5/D9) pero **sí** en CRYPTO §7.1/7.3 → **R-020 (C5)** | ❌ CONTRADICCIÓN |
| **MESSAGE HISTORY RECOVERY** | Sin recovery de historial v1 (placeholder 🔒); "recuperar la cuenta" ≠ "recuperar mensajes" | ✅ (PHASE_2) / ⚠️ R-020 |

Respuestas por ítem (mandato §7): qué contiene el blob → `priv_X25519 ‖ priv_Ed25519 ‖ clave_rng` (CRYPTO §7.1:318) — **depende de R-020**; qué clave lo cifra → `master=HKDF(recovery_key)`, AES-256-GCM, AAD=`user_id` (CRYPTO §7.1:317-319) ✅; de dónde sale → recovery codes del usuario (12×16 chars o 1×32 chars ≈ 120 bits declarados — ver R-012) ✅; qué secreto tiene el usuario → los codes ✅; qué guarda el servidor → hash + salt + blob (R-003: blob sin columna) ⚠️; DB robada → no abre blob sin el code ✅ (condicionado a R-020 para el claim de "historial"); code robado → acceso si no hay single-use/rate-limit (**R-017**) ⚠️; revocación → rotación re-envuelve y revoca ✅; one-time use → ambiguo (R-017) ❌; rate limit → no definido (R-017) ❌.

## 8. Legacy users (mandato §8)

| Estado | Identidad | Login | E2EE | Mensajes | Mesh | Device registration | Recovery | FS | Ops permitidas |
|---|---|---|---|---|---|---|---|---|---|
| **LEGACY** | `users.public_key` X25519 estática; sin Ed25519 | ZONE-ID por conocimiento (claim vigente HOY; en el objetivo solo sesión restaurada — ver R-025) | v1 (X25519 estático, sin KDF/AAD) | Historial v1 con clave estática | profile_exchange v1 en claro + auto-acepta | No existe | No existe | **NO** | Uso de la app sin upgrade |
| **TRANSITION** | Ed25519 añadida (upgrade opcional) | sesión/auth.uid + device activo + upgrade bootstrap (D3) | v3 (HKDF+AAD) si ambos lados; v1 si alguno legacy | v1 + v3 coexisten por footer de versión | profile_exchange v2 con fingerprint + firma; downgrade explícito con warning | Registro con autorización firmada | Disponible tras upgrade | Parcial (mensajes nuevos) | Upgrade + uso normal |
| **SECURE** | Ed25519 (cuenta) + Ed25519 (device) + X25519 rotable (device_keys) | verificación de device activo; sin ZONE-ID como credencial | v4/v5 (handshake + ratchet) | v1 retirado para pares upgraded | mesh v2 autenticado; `revocation_notice` | devices + revocación | Recovery codes + blob | **SÍ** (mensajes nuevos, M4) | Todo |
| **RETIREMENT (M5)** | Solo cuentas upgraded | requiere upgrade anunciado | v5 | v1 solo lectura con claves retiradas | v2 obligatorio entre upgraded | Igual | Igual | Igual | Lectura histórica v1 acotada |

**Verificación especial:**
- ✅ **Ningún** documento afirma que migrar a Ed25519 otorga FS a usuarios legacy.
  `PHASE_2_CTO_REVIEW_REQUIRED.md` §3.1 y THREAT T13:142-144 lo niegan explícitamente.
- ✅ **Ningún** documento afirma FS retroactiva sobre mensajes antiguos.
- ⚠️ **R-025 detectado** en la combinación D8 + D11 + D3 (reinstalación legacy).

## 9. Migration safety (mandato §9)

| Escenario | Estado en los documentos | Necesario (propuesta) |
|---|---|---|
| App se cierra a mitad de fase | No definido | Footer de versión por fila como source of truth; retomar desde la última versión confirmada; transacciones por fase |
| Red se pierde | No definido | RPCs idempotentes; reintentos; estado parcial marcado y reanudable |
| Supabase falla | No definido | M1 crea tablas en 1 transacción; fallo ⇒ no cambia nada (DDL atómica) |
| Dispositivo se reinicia | Parcial (MIGRATION §5.2 "snapshots para restauración tras reinicio") | Ratchet: snapshot del SessionState; identidad: op local re-ejecutable |
| Usuario actualiza desde versión muy antigua | No definido | Verificación de `users`/footer; upgrade escalonado (legacy→v3→v4→v5) sin salto destructivo |
| Migración se ejecuta dos veces | No definido | DDL `IF NOT EXISTS` + `migrations` guard de fase por versión de app |
| Dos dispositivos migran simultáneamente | No definido | `account_identity` UNIQUE(zone_id); device registrado con challenge single-use; rotación con `key_version` atómico (MAX+1 en transacción) |

→ **R-015 (C4):** todos los "qué pasa si…" del mandato carecen de respuesta formal. Se
recomienda añadir al MIGRATION_PLAN una sección "Seguridad de migración" con la tabla
anterior como contrato (DISEÑO, no implementación).

## 10. Threat model consistency (mandato §10)

Cada T (PHASE_2_THREAT_MODEL T1-T17) mapeado a protección/propiedad, fase y prueba:

| T | Amenaza | Protección actual (HOY) | Protección objetivo | Fase | Pruebas (CTO_REVIEW_REQUIRED §4) | Decisión documentada |
|---|---|---|---|---|---|---|
| T1 | Conoce ZONE-ID | Rate-limit claim (5/15) | claim eliminado; bootstrap/recover con firma | M1 | T1-T4 | D11 ✅ |
| T2 | Crea anonymous auth | RLS self-scoped | RPCs con challenge firmado; rate-limit | M1 | T1-T4 | D3/D11 ✅ |
| T3 | Intenta claim / oráculo | claim vigente post-rate-limit; Z-103 parcial | claim eliminado; `verify_zone_id` sin oráculo | M1 | T1-T4 | D11 + **R-019** ⚠️ |
| T4 | Registra Ed25519 de la víctima | NO APLICA (no existe bootstrap) | pending + señuelos + fail-closed frío | M1 | T1-T4 | D3 + **R-004/R-013** ⚠️ |
| T5 | Repite challenge | NO APLICA | single-use + TTL + ventana | M1 | T5 (M4 aplica a ratchet) | DEVICE_MODEL §5 ✅ |
| T6 | Modifica transcript | NO APLICA | firma sobre transcript canónico → abort | M3 | T6, T16 | D12 + R-002 ⚠️ |
| T7 | Cambia device_id | NO APLICA | device_id dentro del payload firmado | M1 | T7-T11 | DEVICE_MODEL §5.3 ✅ |
| T8 | Reemplaza public key | Preservación en DB (parcial) | rotate_key con cadena de firma + fingerprint | M1+M3 | T7-T11 | D7 + R-018 ⚠️ |
| T9 | Replay de operación | NO APLICA | used_at + idempotencia | M1 | T9 | DEVICE_MODEL §5 ✅ |
| T10 | Registra 2º device | NO APLICA (claim destruye) | firma device activo + flag + revocación | M1 | T7-T11 | D4 + R-006 ⚠️ |
| T11 | Device revocado opera | NO APLICA | status='active' en RPC; mesh descarta | M1 | T7-T11 | D6 ✅ |
| T12 | Servidor comprometido | Sin privadas server-side | Igual + fingerprints off-band | M3 | T6, T12, T16 | Riesgo aceptado (CTO §3.2) ✅ |
| T13 | DB comprometida | Ciphertext AEAD | FS en M4; sin recovery claro | M2/M4 | T5, T9, T17 | Riesgo aceptado (CTO §3.1) ✅ |
| T14 | Pérdida de dispositivo | keystore + nada más | revocación + recovery | M1/M5 | T14-T15 | D6/D9 ✅ |
| T15 | Reinstalación | claim vulnerable | devices/recovery; X25519 v1 irrecuperable | M1/M5 | T14-T15 | D9 + **R-020/R-025** ⚠️ |
| T16 | MITM mesh | 🚨 auto-acepta | handshake v4 + fingerprint | M3 | T6, T16 | D12 ✅ |
| T17 | Replay mesh | dedup LRU/TTL 15 min | msg_n/prev_n + nonce | M4 | T5, T9, T17 | D13 ✅ |

- **Estado etiquetado correctamente:** ninguna amenaza T1-T17 se declara FIXED estando solo
  diseñada; THREAT_MODEL §1 usa IMPLEMENTADO (v1)/DISEÑADO/NO IMPLEMENTADO/NO VERIFICABLE y
  §3:185-188 declara las 2 excepciones (T12/T13) como mitigadas-no-eliminadas. ✅
- ⚠️ R-004, R-006, R-018, R-019, R-020, R-025 son mitigaciones "diseñadas" incompletas que
  NO deben considerarse cerradas (ver OPEN_DECISIONS).

## 11. Double Ratchet boundary (mandato §11)

- ✅ **Estado correcto en los 8 documentos: DESIGNED.** 0 ocurrencias de "Double Ratchet
  implementado". MIGRATION M4 lo programa como fase futura; CRYPTO §6 es evaluación.
- ✅ Interfaces definidas (MIGRATION §5.1): `SessionState`, `RootKey`, `ChainKey`,
  `MessageKey`, `RatchetPublicKey`, `SkippedMessageKeys`, `MessageCounter`.
- ❌ **Faltan** (R-016): init de sesión (handshake→SessionState), prekeys, binding
  `device_public_key`→ratchet, serialización/persistencia del estado, política de
  restauración multi-device (solo "re-sync" — MIGRATION §5.2:132-134).

## 12. Mesh consistency (mandato §12)

La cadena objetivo se mantiene en todos los documentos:

```
ACCOUNT IDENTITY (Ed25519) → DEVICE IDENTITY (Ed25519, devices) → AUTHENTICATED PEER (handshake M3 + fingerprint)
→ X25519 (device_keys) → SESSION (ratchet por par de devices) → RATCHET → MESSAGE
```

- ✅ ZONE-ID nunca se propone como identidad criptográfica (D11, T1-T3, IDENTITY §6).
- ✅ `public_key` sin autenticación nunca se considera identidad suficiente: se identifica
  como la vulnerabilidad actual (CRYPTO §1.B:82-83, THREAT T16) y se cierra en M3.
- ⚠️ El único desvío textual es el fingerprint del CRYPTO §5.2 que arrastra la X25519
  (R-002/R-014).

## 13. Supabase consistency (mandato §13)

| Tabla | Ownership | RLS | Insert | Select | Update | Delete | SECURITY DEFINER | auth.uid() | Escalación | Replay | Race conditions |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `account_identity` | Cuenta (inmutable) | Sin acceso directo (R-023) | RPC `create_account`/`bootstrap_account` | RPC `get_identity_public_key` (limitado) | RPC rotate/recover | `delete_own_account` (cascada) | Sí (todos los RPC) | Mapeo uid→users→account (**R-009** gap) | Media: controlar RPC | challenges single-use | Dos bootstraps mismo zone_id → UNIQUE(zone_id) ✅ |
| `devices` | Device + cuenta | Solo RPC (list/authorize/revoke) | RPC register_device | list_devices (dueño) | status via RPC | nunca directo | Sí | Verificar firma + estado | **Alta**: no auto-revocar por status | challenge single-use | Dos register simultáneos → challenge single-use serializa ✅ |
| `device_keys` | Device | Solo RPC | rotate_key (firma) | por device | status→retired/compromised | nunca directo | Sí | — | controlar rotación firmada | nonce + key_version | **key_version atómico** (MAX+1 transacción) — a definir → R-015 |
| `device_challenges` | — | Sin acceso directo | RPC request_challenge | — | used_at | GC | Sí | Ligar challenge al account solicitante (DEVICE_MODEL §1.4:75) | control single-use/TTL 10 min | used_at + idempotencia | OK ✅ |
| `device_revocations` | Auditoría | "Solo lectura owner" (HANDOFF §8:67) vs regla global "sin acceso directo" (DEVICE_MODEL §1.1:31) → **R-023** ⚠️ | RPC revoke_device | owner | — | — | Sí | — | baja | firma revoke + audit | OK ✅ |
| `recovery_credentials` | Cuenta | Solo RPC (R-023; CRYPTO §7.1:321-322 discrepante) | RPC recover/rotate | — | used_at/rotación | delete cuenta | Sí | — | **alta** — jamás SELECT público | single-use + rate-limit (R-017) | rotación concurrente → transacción por account |

→ R-003 (blob sin columna), R-009 (binding auth.uid↔account_id), R-015 (atomics), R-017,
R-023. **No se crean tablas ni migraciones en esta fase.**

## 14. Canonical transcript (mandato §14)

Definición actual (DEVICE_MODEL §5.1:187-199, §5.3:224-235): JSON canónico v1, claves
ordenadas, sin espacios, UTF-8 estricto con `\u` escapes, ISO-8601 UTC, `extra` canónico,
firma Ed25519 sobre `utf8(canonical_payload_v1)`, re-serialización server-side. **Base sólida.**

Refinamientos propuestos para una especificación formal (sin ambigüedades):

1. `extra` siempre presente: si no hay contexto, serializar como `{}` **obligatorio**
   (nunca omitir el campo) → elimina ambigüedad ausente-vs-vacío.
2. `base64`: fijar **Standard Base64 con padding** para todas las claves/nonces (o sin
   padding en todo el sistema; una sola convención documentada).
3. `account_id`/`device_id`: **UUID canónico lowercase con guiones**.
4. `ts`: ISO-8601 UTC con **3 dígitos fraccionarios fijos** (`.SSS`) y `Z` (o sin
   fracción); el servidor normaliza antes de verificar.
5. La serialización canónica del **handshake transcript** (CRYPTO §5.2) es un formato
   propio distinto de `canonical_payload_v1`: requiere su propia especificación de
   concatenación de bytes (orden, tipos, longitudes) — hoy solo se describe
   conceptualmente ("todos los bytes previos").
6. `challenge` obligatorio en todas las ops salvo los casos sin ancestro
   (`create_account`/`bootstrap_account` inicial), que se validan por sesión+señuelos.

No hay JSON ambiguo, orden variable, encoding ambiguo ni concatenaciones inseguras en el
diseño documentado; faltan las 6 precisiones. **REQUIERE CTO** para adoptarlas como
especificación formal (las añadimos a OPEN_DECISIONS como OPEN-015).

## 15. Fingerprint determinism (mandato §15)

Definición FASE 2.0.2 (**autoridad: FINGERPRINT_SPEC v1** — dos fingerprints, inputs ACC/DEV):

| Atributo | Valor | Determinismo |
|---|---|---|
| Fingerprints | **2**: ACCOUNT_FINGERPRINT y DEVICE_FINGERPRINT (inputs distintos) | ✅ fijado en SPEC §2 (OPEN-002/016) |
| Input ACC | `utf8("ZONE-FP-1\0") ‖ utf8("ACC") ‖ utf8(uuid_canonical(account_id)) ‖ base64_std_padded(identity_public_key)` | ✅ orden fijo + prefijo versión |
| Input DEV | `utf8("ZONE-FP-1\0") ‖ utf8("DEV") ‖ utf8(uuid_canonical(account_id)) ‖ utf8(uuid_canonical(device_id)) ‖ base64_std_padded(device_public_key)` | ✅ orden fijo + `device_id` |
| Hash | SHA-256 | ✅ RFC 6234 |
| Codificación | Bit-packing RFC 4648 (5 bits/símbolo, MSB-first) **sin padding**, alfabeto unambiguo de **32 símbolos**: `23456789ABCDEFGHJKMNPQRSTUVWXYZ-` (sin 0/O/1/I/L; índice 31 = `-` U+002D) | ✅ fijado en SPEC §4 (corrección CTO 2026-09-25) |
| Canonicalización requerida | UUID lowercase con guiones; base64 de claves con padding fijo (ver §14) | ⚠️ pendiente de §14.2/14.3 |
| Case | Mayúsculas (visual); comparación normaliza a MAYÚSCULAS | ✅ documentado en SPEC §4 |
| Checksum | **NO** (justificado: 100 bits ≈ 1/2^100 colisión; opcional 1 char de checksum si hay tipeo manual) | ✅ decisión documentada |
| QR | payload = fingerprint + `account_id` (SPEC §5) | ✅ |
| Humana | 4 grupos de 5: `FP7GK-3KQ9W-MJ2X8-PDVTC` | ✅ |

**Regla de dos implementaciones independientes:** el fingerprint solo es idéntico entre
implementaciones si se fijan la canonicalización del §14 (base64 padding y UUID case) y el
subconjunto Base32 exacto. Se exige **test vector KAT del fingerprint v1 en M1** como
criterio de salida (añadir a CTO_REVIEW_REQUIRED §4 M1). ⚠️ Choca con el fingerprint del
CRYPTO §5.2 (7 letras + x25519) → R-002/R-014 (resuelto: la spec es la autoridad).

## 16. Security claims (mandato §16)

Barrido de términos (`garantiza`, `imposible`, `militar`, `impenetrable`, `100%`, `seguro`,
`protegido`, `perfectamente`) en los 8 documentos + resto de `docs/`:

| Claim | Cita | Veredicto |
|---|---|---|
| "garantizando Forward Secrecy" (comentario de código) es **incorrecto** | CRYPTO:29 | ✅ Correcto (lo desmiente) |
| "no se puede evitar al 100 %" | IDENTITY §5.C:198 | ✅ Honesto (niega garantía) |
| "Pérdida garantizada del historial v1" | D5:57 / IDENTITY §5.E:224 | ✅ Preciso (server no es custodio) |
| "es el único que satisface todos los criterios" (Double Ratchet) | CRYPTO §6.3:290 | ⚠️ Fronterizo: afirmación comparativa razonada con tabla; proponer "es la opción que satisface la lista de aceptación en la evaluación comparada" |
| "Compatibilidad garantizada (lo que NO puede romperse)" | MIGRATION §3:41 | ⚠️ Fronterizo: es una lista de requisitos con mecanismo; proponer "Compatibilidad requerida (no romper)" — y cumplir R-015 para poder garantizarlo |
| "Un atacante que robe la DB no puede abrir el blob sin el recovery" | CRYPTO §7.4:341 | ⚠️ **Condicionado a R-020**: si el blob envuelve la X25519 v1 y el recovery la restaura, la afirmación técnicamente se mantiene (no abre sin el code), pero pierde la garantía de historial ilegible que defiende FASE 2.0 — revisar tras R-020 |
| "ningún proveedor ve jamás una clave privada ni un recovery code en claro" | DEVICE_MODEL §1.6:98 | ✅ Regla de diseño verificable |
| "Los uids anónimos no otorgan derechos sobre ninguna cuenta" | THREAT T2:54 | ✅ Cierto en el objetivo (RPC con firma); hoy un uid anónimo sí crea su fila — el propio T2 lo aclara |
| "**NO** se firmará con X25519" regla de hierro | CRYPTO §0:49-51 | ✅ |

**Conclusión:** no hay claims publicitarios; 2 redacciones fronterizas (recomendadas a
sustituir) y 1 afirmación que depende de la decisión CTO R-020. No se editaron los
documentos fuente (regla de no-corregir-silenciosamente).

---

## 17. Resumen de clasificación C0–C5

| Clase | R-IDs | Total | Requiere CTO |
|---|---|---|---|
| C0 (sin contradicción) | D1 núcleo, D2, D6, D8(v1), D10, D12(núcleo), D13(diseño), D14(fases), T-numeración PHASE_2 interna, estado DR | — | No |
| C1 (terminología) | R-001, R-008, R-010, R-011, R-012, R-022 | 6 | No (limpieza editorial) |
| C2 (diseño) | R-003, R-006, R-007, R-009, R-014, R-016, R-018, R-023, R-024 | 9 | Sí |
| C3 (seguridad) | R-004, R-005, R-013, R-017, R-019 | 5 | Sí |
| C4 (migración) | R-015, R-021 (+ R-025 C4 parte) | 2-3 | Sí |
| C5 (criptografía crítica) | **R-002**, **R-020** (+ R-025 C5 parte) | 2-3 | **Sí — prioridad** |

> 📌 **Los entregables operativos son `PHASE_2_OPEN_DECISIONS.md` (resoluciones),
> `PHASE_2_SECURITY_INVARIANTS.md` (reglas no-rompibles) y
> `PHASE_2_CTO_HANDOFF_FINAL.md` (plan de firma).** Este documento es la evidencia.