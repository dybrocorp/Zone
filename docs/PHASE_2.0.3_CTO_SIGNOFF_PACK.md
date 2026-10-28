# PHASE 2.0.3 — CTO SIGN-OFF PACK (Revisión Previa a Firma)

> **Tipo:** Pack de firma CTO de FASE 2.0.2 — **NO IMPLEMENTAR · SOLO REVISIÓN**
> **Fecha:** 2026-09-24 · **Estado:** **CTO SIGN-OFF STATUS: APPROVED** (FASE 2.0.4;
> registro formal: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`)
> **Puerta revisada:** `PHASE_2.0.2_CTO_GATE.md` (fase cerrada en
> `IMPLEMENTATION STATUS: BLOCKED — CTO REVIEW REQUIRED`; tras FASE 2.0.4:
> `IMPLEMENTATION STATUS: PHASE 2.1 AUTHORIZATION PENDING`)
> **Alcance:** revisión read-only de los 17 documentos FASE 2.0/2.0.2 + verificación de los
> 12 objetivos de FASE 2.0.3. **No se modificó ningún documento fuente** (ni `lib/`,
> `supabase/`, `pubspec.yaml`); este pack es el único archivo nuevo.
> **Regla de parada:** mientras este pack no se firme, M0-M5 no se abren y FASE 2.1 no existe.

---

## 1. Executive summary

- La FASE 2.0.2 terminó formalmente en **`IMPLEMENTATION STATUS: BLOCKED — CTO REVIEW
  REQUIRED`** (verificado: única ocurrencia de `IMPLEMENTATION STATUS` en `PHASE_2.0.2_CTO_GATE.md`).
- Los **18 OPEN (OPEN-001…018)** están **RESOLVED — CTO PROPOSED** en
  `PHASE_2_DECISION_RESOLUTION.md` y formalizados por las **5 políticas 2.0.2**
  (RECOVERY · FINGERPRINT · BOOTSTRAP · LEGACY_ACCESS · MIGRATION_FAILURE_MATRIX).
- Las **3 decisiones humanas** (OPEN-001 copy, OPEN-018 obligatoriedad de guardar
  códigos, plazo M5) se presentan en §3 con el plantel completo exigido — **las tres fueron
  CTO APPROVED en FASE 2.0.4** (`PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`).
- La arquitectura documental es **suficiente para iniciar implementación controlada solo
  después de la firma CTO + 2 correcciones documentales** (etiquetas A/B y tabla stale de
  IDENTITY §7) — ver §13/§14.
- **No hay contradicción semántica de recovery, fingerprint, bootstrap, device state ni
  legacy** con efectos sobre el diseño; los bloques restantes son documentales/decisión humana.
- Validación read-only: **sin cambios fuera de `docs/`, sin Supabase, sin remoto, sin commits**
  (§16).

---

## 2. Architecture status

| Bloque | Estado en documentos | Veredicto 2.0.3 |
|---|---|---|
| Identidad: Ed25519 cuenta / X25519 device-encryption / X25519 jamás firma | D1/D2 + I-002 + THREAT | **Consistente** (0 ocurrencias de firma X25519) |
| Recovery (5 conceptos separados) | RECOVERY_POLICY §1 | **Consistente** (ver §4; DOC-FD-001 etiquetas — RESUELTO en FASE 2.0.3.1) |
| Fingerprint canónico | FINGERPRINT_SPEC v1 | **Consistente** (ver §5; DOC-FD-002 tabla IDENTITY §7 — RESUELTO en FASE 2.0.3.1) |
| Bootstrap security | BOOTSTRAP_POLICY §2-§4 | **Completa** (13 parámetros + 4 casos + máquina) |
| Machine de estados device | BOOTSTRAP_POLICY §4 + DEVICE_MODEL §2 | **Consistente** (device_1 = pending) |
| Legacy M0-M5 | LEGACY_ACCESS_POLICY + MIGRATION_PLAN §8 | **Sin ventana de lockout** (REGL-1..3, I-028) |
| Failure matrix | MIGRATION_FAILURE_MATRIX (12 escenarios) | **Completa** (cada escenario con 7 respuestas) |
| Threat model | THREAT_MODEL §3.1 (T1-T17) | **Estados correctos** (DISEÑADO/PLANEADO; sin FIXED) |
| Invariantes | SECURITY_INVARIANTS I-001…I-030 | **30 invariantes, todos VALID** (notas de etiquetas resueltas en 2.0.3.1) |
| Double Ratchet / Mesh | DISEÑADO (M4/M3) | **Boundaries preservados** (sin implementación) |
| Supabase | Sin modificar | **NO MODIFICADO** (requisitos futuros solo documentados) |

---

## 3. Human decisions

Decisión humana #1 de 3:

### DECISIÓN — OPEN-001: copy/producto de la pérdida del historial v1 tras recovery

### Pregunta exacta que debe responder CTO
¿Aceptamos **fail-closed como experiencia oficial**: el recovery restaura la cuenta pero el
historial v1 queda ilegible (placeholder 🔒) y la app lo comunica así — o exigimos una
promesa de producto distinta (p.ej. backup cifrado de historial como extensión)?

### Contexto
OPEN-001 (decidido en FASE 2.0.2 como **"blob sin X25519 v1"**) define qué recupera el
blob. La decisión técnica ya está cerrada (PROPOSED) en `PHASE_2_RECOVERY_POLICY.md` §2-§4:
el blob contiene solo `{account_sk_ed25519, rotation_counter, created_at}`; **jamás** la
X25519 v1. Lo que queda es **decisión de producto/mensajería**: el copy y la UX que
comunican "tu historial anterior no se descifra". I-025 y CRYPTO §7.3 ya lo fijan
técnicamente; este punto decide cómo se presenta al usuario.

### Opción A — Fail-closed como experiencia oficial (recomendada por arquitectura)
Comunicar sin rodeos que el recovery no es un backup de chats: historial v1 ilegible
(placeholder 🔒), mensajes v3+ dirigidos al device perdido también.

Consecuencias:
- **security:** coherente con I-012/I-025; el robo de códigos + DB no descifra historial v1.
- **privacy:** cero exposición adicional; el ciphertext permanece ilegible.
- **recovery:** la cuenta se recupera plenamente; el contenido no — sin promesas rotas.
- **migration:** uniforme para toda la base (la mayoría de legacy no puede crear blob con v1);
  implementable en M1 sin clase privilegiada.
- **UX:** requiere copy honesto y visible ("historial anterior no se descifra"); placeholder
  **ya existe** (`chat_e2ee_service.dart:105-109`).
- **legacy:** sin cambio respecto a hoy (hoy ya no hay backup).
- **data loss:** pérdida permanente del historial v1 aceptada y documentada (coste real de la
  decisión, mitigable solo con la extensión futura de §6).

### Opción B — Recuperar también el historial v1
Blob con `priv_X25519 ‖ priv_Ed25519` (semántica CRYPTO original): el recovery devuelve el
historial legacy.

Consecuencias:
- **security:** los códigos de recovery se convierten en "llave maestra del historial":
  físico robado + servidor comprometido = historial completo (vector cerrado por I-025).
- **privacy:** el historial legacy queda ligado a los códigos (superficie mayor).
- **recovery:** recupera cuenta **y** mensajes antiguos (UX seductora).
- **migration:** **inimplementable para la mayoría**: los legacy no tienen recovery pre-M1 y
  el blob con v1 solo puede crearse en el device que aún posee la privada ⇒ clase
  privilegiada incoherente (OPEN-001 rationale).
- **UX:** mejora solo para la minoría con blob pre-creado, a costa de seguridad.
- **legacy:** rompe la doctrina "servidor no custodio" en su versión estricta (blob contiene
  clave capaz de abrir historial).
- **data loss:** evita la pérdida solo para cuentas con blob pre-existente.

### Si existen más opciones
- **Opción C (extensión futura, OUT-OF-SCOPE):** "backup de historial cifrado" — export del
  historial cifrado bajo clave derivada del `recovery_key` (RECOVERY_POLICY §6). Permite
  MESSAGE HISTORY RECOVERY v3+ **sin** exponer claves al servidor. Requiere mini-spec aparte
  y decisión de producto; **no bloquea** FASE 2.0.

### Decisión actualmente propuesta por arquitectura
**Opción A** (fail-closed como experiencia oficial): la documentación propone aceptar la
pérdida del historial v1 como comportamiento oficial y comunicarlo con copy honesto.

### Qué documentos cambiarían después de la decisión
`PHASE_2_RECOVERY_POLICY.md` §6 (confirmar extensión futura o eliminarla) · copy/UX de M1 ·
`PHASE_2_CTO_HANDOFF_FINAL.md` (riesgo R20 resuelto). Nada de código.

### Qué invariantes serían afectados
Ninguno por la decisión A (I-011, I-012, I-025 ya lo fijan). La Opción B **contradeciría**
I-025 ⇒ sería un cambio de invariante bloqueante (no recomendado).

### Qué fases dependen de esta decisión
M1 (copy del recovery, tests de recovery §11.4) y M5 (mensajería de retiro cuando aplique).

**CTO APPROVED — FASE 2.0.4:** Opción A (fail-closed) aprobada. Account recovery ≠ legacy
key recovery; historial v1 puede quedar permanentemente ilegible (consecuencia aceptada por
CTO); el servidor NO custodia X25519 v1. Registro: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`.

---

Decisión humana #2 de 3:

### DECISIÓN — OPEN-018: obligatoriedad de guardar los códigos de recovery

### Pregunta exacta que debe responder CTO
En el **primer arranque post-M1**, la pantalla "guarda tus códigos" ¿es **no bloqueante**
(recomendada) o **bloqueante** (no se continúa sin guardar)?

### Contexto
M1 emite recovery codes a toda cuenta que abra la app (OPEN-018, PROPOSED). Sin ellos, un
usuario legacy sin devices que reinstale dependería solo del claim acotado (hasta M5). La
pregunta es de UX/enforcement, no técnica: RECOVERY_POLICY §4-§5 ya define single-use +
rotación + rate-limit; LEGACY_ACCESS_POLICY REGL-1 garantiza que nadie quede sin vía.

### Opción A — No bloqueante (recomendada por arquitectura)
Mostrar "guarda tus códigos" con posibilidad de cerrar; el claim acotado sigue como red de
seguridad hasta M5.

Consecuencias:
- **security:** los códigos no guardados = menor exposición física; el claim acotado es la
  red (rate-limit 5/15 + audit).
- **privacy:** sin captura forzada de nada.
- **recovery:** usuarios que no guardan dependen del claim hasta M5; en M5 recuperan por
  claim final + OOB o recovery ya emitida.
- **migration:** M5 condicionada a métricas de adopción (LEGACY_ACCESS_POLICY §5.1): si la
  adopción es baja, M5 espera (REGL-3).
- **UX:** sin fricción; adopción medida con métricas.
- **legacy:** nadie queda sin ruta (REGL-1 + I-028).
- **data loss:** posible pérdida de acceso si no guarda códigos **y** pierde device **y**
  M5 ya retiró el claim (mitigado por REGL-3/§5).

### Opción B — Bloqueante
No se continúa con la cuenta hasta guardar los códigos.

Consecuencias:
- **security:** mayor garantía de recovery operativo (los códigos existen de verdad).
- **privacy:** idle; la app retiene la sesión hasta completar el paso.
- **recovery:** cobertura máxima de la base (menos "huérfanos" sin códigos).
- **migration:** M5 puede cumplir el requisito §5.1 más rápido (100% con recovery emitida),
  pero **arriesga abandono de usuarios legacy que no quieren el paso** (los 2 reales + futuros).
- **UX:** fricción real en el primer arranque post-M1.
- **legacy:** refuerza REGL-1 pero puede empujar a usuarios a no migrar nunca.
- **data loss:** minimiza pérdida de acceso (más códigos guardados); aumenta riesgo de
  abandono de cuenta.

### Si existen más opciones
Híbrido: no bloqueante **con recordatorio diferido** (n-recordatorios hasta M5) — variante de
producto que podría evaluarse en M1 (no documentada como propuesta formal).

### Decisión actualmente propuesta por arquitectura
**Opción A** (no bloqueante): `PHASE_2_DECISION_RESOLUTION.md` OPEN-018 (A, no bloqueante) y
`LEGACY_ACCESS_POLICY` (emisión en primer arranque, sin forzar la pantalla).

### Qué documentos cambiarían después de la decisión
`LEGACY_ACCESS_POLICY` (si se eligiera bloqueante, ajustar §3/§5 y métricas) · notas de UX M1 ·
`PHASE_2_DECISION_RESOLUTION` OPEN-018 (registro de la elección del CTO).

### Qué invariantes serían afectados
Ninguno bloqueante: I-016, I-021, I-028 se cumplen en ambas opciones (la emisión ocurre en
ambas; solo cambia el enforcement de la pantalla).

### Qué fases dependen de esta decisión
M1 (emisión + pantalla guardar códigos) y M5 (condiciones de retiro, §5.1).

**CTO APPROVED — FASE 2.0.4:** Opción A (no bloqueante) aprobada. Recovery permite alcanzar
`RECOVERY_READY` sin bloquear la creación inicial de cuenta; mientras `RECOVERY_UNCONFIGURED`
aplican restricciones para operaciones de alto riesgo; servidor sin códigos en plaintext.
Registro: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`.

---

Decisión humana #3 de 3:

### DECISIÓN — Plazo de retirada del claim legacy (M5)

### Pregunta exacta que debe responder CTO
¿Qué plazo/condición fija el retiro total de `claim_zone_id` en M5? (Propuesta documental:
**90 días tras M4**, condicionado a REGL-3.)

### Contexto
OPEN-011 (PROPOSED) define el claim **acotado** (solo `mode=legacy` sin devices) hasta M5 y
su retiro **solo bajo condiciones** (§5 de LEGACY_ACCESS_POLICY): (a) 100% de cuentas con
`mode != legacy`, o (b) ventana de gracia + soporte para las restantes. La fecha "90 días"
aparece en MIGRATION_PLAN §7/M5 y HANDOFF §6 como propuesta de producto, no como decisión.

### Opción A — 90 días tras M4 + condiciones §5 (recomendada por arquitectura)
Fijar corte a 90 días tras M4, con la condición REGL-3 (100% migradas o ventana) verificada.

Consecuencias:
- **security:** ventana acotada y explícita; el claim deja de existir al corte (si se cumplen
  las condiciones).
- **privacy:** sin cambios (el claim nunca expone contenido).
- **recovery:** M1 ya emitió códigos a todos los que abrieron la app; el corte solo afecta a
  cuentas nunca migradas (resueltas por §5 o soporte).
- **migration:** calendario predecible; M5 ejecutable en un sprint tras M4.
- **UX:** mensaje "cuenta requires upgrade" claro ante intento de claim en M5 (§5.4).
- **legacy:** retirada con red (REGL-3): si quedan legacy sin devices, el claim **no** se
  apaga (rollback por flag `claim_legacy_disabled`, §5.2).
- **data loss:** ninguno (no afecta contenido).

### Opción B — Plazo distinto (30/60/180 días) o condición por métricas puras
Mantener el claim hasta que las métricas digan 100% migrado, sin fecha.

Consecuencias:
- **security:** el claim (único vector de apropiación residual) permanece más tiempo; acotado
  a legacy sin devices (riesgo bajo pero no cero).
- **privacy:** idem A.
- **recovery:** sin cambio (recovery ya emitida en M1).
- **migration:** M5 sin plazo firme ⇒ planificación menos predecible; exige dashboard de
  adopción.
- **UX:** menos presión de upgrade; el mensaje de §5.4 suavizado.
- **legacy:** máxima conservación de acceso (el claim sigue como red indefinidamente).
- **data loss:** ninguno.

### Si existen más opciones
Corte por **doble condición**: 90 días **y** (a) o (b) de §5 — variante que refuerza REGL-3
sin depender solo del calendario.

### Decisión actualmente propuesta por arquitectura
**90 días tras M4, sujeto a las condiciones REGL-3/§5** — es la formulación textual de
`MIGRATION_PLAN.md` M5 y `PHASE_2_CTO_HANDOFF_FINAL.md` §6 (plazo de producto, no fijo).

### Qué documentos cambiarían después de la decisión
`MIGRATION_PLAN.md` M5 (fecha de corte determinada) · `LEGACY_ACCESS_POLICY.md` §5 (si el CTO
elige una variante) · `PHASE_2.0.2_CTO_GATE` §2·`PHASE_2_DECISION_RESOLUTION` (registro).

### Qué invariantes serían afectados
I-021 e I-028 (retirada condicionada) **no cambian**: el corte nunca deja a un legacy sin vía
(documentado en §4: "REGL-1…3").

### Qué fases dependen de esta decisión
M5 (retiro de claim) — y M1 solo indirectamente (métricas de adopción que se miden desde M1).

**CTO APPROVED — FASE 2.0.4:** M5 = **LEGACY CLAIM RETIREMENT** condicionado a los
preconditions de readiness de `PHASE_2_MIGRATION_PLAN.md` M5 (enrollment, identidad,
dispositivo, recovery, reinstalación, migración legacy, rollback, compatibilidad, sin
lockout conocido, validaciones y auditabilidad). **Sin fecha arbitraria** (la propuesta de
"90 días" queda superada como plazo fijo); sin ventana de lockout; `claim_zone_id` no se
elimina en esta fase ni se modifican RPC/RLS. Registro: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`.

---

## 4. Recovery decision

Veredicto Objetivo 2 — **sin ambigüedad entre los 5 conceptos; no se tratan como equivalentes**:

| Concepto | DOC | Definido |
|---|---|---|
| ACCOUNT RECOVERY | RECOVERY_POLICY §1/§3.1 | Restaura identidad Ed25519 vía blob ✓ |
| DEVICE RECOVERY | RECOVERY_POLICY §1/§5 | Device nuevo con la identidad restaurada ✓ |
| MESSAGE HISTORY RECOVERY | RECOVERY_POLICY §1/§3.2 | ❌ v1 (placeholder 🔒); v3+ según device activo ✓ |
| LEGACY KEY RECOVERY | RECOVERY_POLICY §1/§3.3 | ❌ **JAMÁS** X25519 v1 (I-025) ✓ |
| RATCHET STATE RECOVERY | RECOVERY_POLICY §1/§3.4 + MIGRATION §5.2 | ❌ secreto local; re-sync, no restauración ✓ |

Confirmaciones específicas:
- **Recovery no recupera X25519 v1** ✓ (RECOVERY_POLICY §2 "Opción A", I-025, CRYPTO
  §7.1/7.3 — etiquetas unificadas en FASE 2.0.3.1, DOC-FD-001 RESUELTO).
- **Historial v1 puede quedar ilegible** ✓ (placeholder 🔒 existente es el diseño oficial).
- **Servidor no custodia private keys en plaintext** ✓ (I-012; solo hash argon2id + blob
  envuelto + salt; DEVICE_MODEL §1.6).
- **Secure identity/device recovery separado de history recovery** ✓ (RECOVERY_POLICY §1).
- **Double Ratchet state no se confunde con identity recovery** ✓ (SessionState local,
  I-023; §5.2 re-sync — MIGRATION_PLAN).
- **Ratchet state nunca sube al servidor** ✓ (I-023; solo parámetros públicos por device_keys).

**Hallazgo DOC-FD-001 (documentación, no semántica) — RESUELTO en FASE 2.0.3.1:** la
semántica "blob **sin** X25519 v1" se etiquetaba **"Opción A"** en
DECISION_RESOLUTION/GATE/CONSISTENCY_MATRIX/OPEN_DECISIONS/I-024/CRYPTO §7.1, pero **"Opción
B"** en RECOVERY_POLICY §2/§8 e I-025. El contenido era idéntico en los 7 documentos. Se marcó
como **BLOCKER DOCUMENTAL** (armonizar etiquetas con edit de texto antes de firmar; sin cambio
de decisión). **Corrección aplicada (2.0.3.1):** unificada a "Opción A = sin X25519 v1"
(mayoría + documento maestro) en RECOVERY_POLICY §2/§7/§8 e I-025; verificado sin inversión
residual en los 7 documentos.

---

## 5. Fingerprint decision

Veredicto Objetivo 3 — **solo existe una especificación canónica**: `FINGERPRINT_SPEC.md` v1.

| Atributo | Valor canónico (SPEC) |
|---|---|
| Fingerprints | **2**: ACCOUNT_FINGERPRINT y DEVICE_FINGERPRINT (inputs distintos) |
| ACCOUNT input | `"ZONE-FP-1\0" ‖ "ACC" ‖ account_id ‖ identity_public_key` |
| DEVICE input | `"ZONE-FP-1\0" ‖ "DEV" ‖ account_id ‖ device_id ‖ device_public_key` |
| Hash | SHA-256 (RFC 6234) |
| Encoding | Base32 sin padding, alfabeto unambiguo (32 símbolos, sin 0/O/1/I/L) |
| Longitud | 20 chars → 100 bits, agrupado `XXXXX-XXXXX-XXXXX-XXXXX` |
| Canonicalización | UUID lowercase con guiones; base64 estándar con padding (44 chars) |
| Estabilidad | Cambia solo con rotación Ed25519 (cuenta) / cambio de device (device); **NO cambia** con rotación X25519 |
| Rotación | Ligada a OPEN-013 (cuenta) y a reinstall/device nuevo |
| Finalidad | Verificación humana out-of-band MITM (M3) y binding en D4/QR |
| Display | 4 grupos de 5, MAYÚSCULAS; normalización case-insensitive a MAYÚSCULAS |
| Autenticación vs verificación | **Nunca** entrada de auth/RPC/recovery (I-026); la auth la hacen firmas Ed25519 |

Referencias al fingerprint antiguo "7 letras": **todas son históricas o de derivación**
(CRYPTO §5.2:265 marcado como ⚠️ superado; DECISION_RESOLUTION OPEN-002; CONSISTENCY_MATRIX
R-002/R-014 como registro del conflicto; FINGERPRINT_SPEC §7 deroga; IDENTITY §7 header
"NO asumir 7 letras"). **Ningún documento lo utiliza como formato canónico vigente.**

**Hallazgo DOC-FD-002 (documentación) — RESUELTO en FASE 2.0.3.1:** en
`PHASE_2_IDENTITY_ARCHITECTURE.md` §7, el header declaraba a FINGERPRINT_SPEC como autoridad,
pero la **tabla interna** (líneas 288-296) aún mostraba el input del fingerprint único antiguo
(`bytes("ZONE-FP-1\0") ‖ account_id ‖ identity_public_key ‖ device_public_key` y "único por
(account, device)") en lugar de los dos inputs ACC/DEV de la spec. La spec §7 ya decía "gana
esta spec como autoridad", por lo que la resolución está declarada; pero la tabla stale era una
**referencia incompatible residual** ⇒ se marcó **BLOCKER DOCUMENTAL**. **Corrección aplicada
(2.0.3.1):** la tabla de §7 quedó sincronizada con los inputs ACC/DEV de la spec (dos
fingerprints). Sin cambio de diseño.

---

## 6. Bootstrap decision

Veredicto Objetivo 4 — política completa (BOOTSTRAP_POLICY §2-§4; parámetros §3):

| Control | Valor | Verificado |
|---|---|---|
| TTL | 10 min | ✓ |
| Entropy | 8 chars × 32 símbolos = **40 bits** (justificado por entropy×TTL×attempts ≈ 5e-12/ventana) | ✓ |
| Nonce | Código aleatorio + nonce de `request_challenge` (32 B single-use) | ✓ |
| One-time use | Consumido en `confirm_bootstrap` | ✓ |
| Rate limit | 3 emisiones/15 min por account+uid/IP | ✓ |
| Max attempts | 5 confirmaciones fallidas → código invalidado + LOCKED 15 min | ✓ |
| Lockout | Cool-down 15 min + audit | ✓ |
| Binding | Código ligado a account_id + bootstrap_attempt + device; confirm exige sesión + firma | ✓ |
| Issuance | Servidor (`bootstrap_account`, SECURITY DEFINER) | ✓ |
| Revocation | `bootstrap_cancel` → KILLED + audit | ✓ |
| Reissue | Nueva solicitud **invalida** la anterior (rotación) | ✓ |
| Concurrency | 1 intento activo por cuenta (segundo → 409 + audit) | ✓ |
| Audit events | 8 eventos (issued/confirm_success/confirm_fail/expired/revoked/cancelled/concurrent_denied/cold_blocked) | ✓ |

**ZONE-ID + sesión básica ≠ ownership:** ✓ regla formal (§5.1, I-013): ningún estado con
derechos sin `confirm_bootstrap` (código + firma).

Rutas de first-device enrollment — **las 4 tienen autorización inequívoca**:

| Ruta | Autorización (documentada) | BLOCKER |
|---|---|---|
| 1. Cuenta fría (sin actividad > 30 días) | Fail-closed: OOB (correo verificado) o soporte; sin puerta abierta (`bootstrap_cold_blocked`) | No |
| 2. Legacy activa sin devices | Sesión (factor 1) + one-time code (factor 2) + confirmación firmada Ed25519 | No |
| 3. Cuenta con device activo | Bootstrap **denegado**; vía D4 (firma del device activo) o recovery | No |
| 4. Enrollment concurrente | 1 intento activo; segundo rechazado (409) | No |

---

## 7. Device lifecycle

Veredicto Objetivo 5 — máquina de estados formal (BOOTSTRAP_POLICY §4, DEVICE_MODEL §1.2, I-030):

```
(ninguno) ──bootstrap_account──▶ PENDING ──confirm_bootstrap (code+firma)──▶ ACTIVE
                                     │── timeout TTL ─▶ artefactos GC (legacy intacta)
                                     │── MAX_ATTEMPTS ─▶ LOCKED (cool-down 15 min)
                                     └── bootstrap_cancel/cold_block ─▶ KILLED
  ACTIVE ──revoke_device──▶ REVOKED · ACTIVE ──detección compromiso──▶ COMPROMISED
```

- **device_1 nace `pending`** ✓ — `DEVICE_MODEL §2` paso 3 y `D3` (OPEN-003/I-013); la única
  aparición de "device_1 · active" (`IDENTITY §5.D:225`) es lenguaje de resultado (tras
  confirm), no estado inicial — C1 editorial menor.
- **PENDING → CHALLENGED/AUTHORIZED → ACTIVE:** la política formaliza la transición como
  `confirm_bootstrap` (código + firma) — los estados CHALLENGED/AUTHORIZED no se persisten
  como status propios; la transición es atómica por RPC. Consistente entre
  DECISION_RESOLUTION (OPEN-003) y BOOTSTRAP_POLICY §4.
- Operaciones por estado:
  | Estado | Puede | NO puede |
  |---|---|---|
  | PENDING | Mostrar estado, firmar su confirmación, ser cancelado | Autorizar devices · leer/sync mensajes · recibir secretos · enviar · listarse activo |
  | ACTIVE | Mensajes, D4, rotación device_keys | Actuar por otro device |
  | LOCKED/KILLED/REVOKED/COMPROMISED | Nada (denegado en RPC por `devices.status`) | Re-entrar por sí mismo |
- **Ningún documento asume `device_1 = active` como inicial** ⇒ no hay BLOCKER.

---

## 8. Legacy migration

Veredicto Objetivo 6 — tabla READ-ONLY (fuentes: LEGACY_ACCESS_POLICY §2-§5, MIGRATION_PLAN §8):

| Migration | Legacy reinstall | Secure enrollment | claim_zone_id | Recovery | Rollback | Lockout |
|---|---|---|---|---|---|---|
| **M0 (hoy)** | Claim full (5/15 min) | No existe | Pleno (rate-limit) | No existe | N/A | ✓ sin riesgo (estado HOY) |
| **M1** | Claim **acotado** (mode=legacy sin devices) | Bootstrap PENDING→ACTIVE (sesión+código+firma) + D4 | Acotado; denegado para cuentas con devices (`legacy_claim_denied_secure`) | **Emitida en el primer arranque post-M1** | Flag de fase; tablas inertes; claim vuelve a pleno | **Sin ventana** (REGL-1/I-028) |
| **M2/M3/M4** | Idem M1 | Idem + v3/v4 | Idem acotado | Idem | Idem | **Sin ventana** |
| **M5** | **Retirado** (solo recovery/device) | Solo recovery/device | Desactivado para `mode != legacy` (desde M1) y **totalmente en M5** (§5.2-5.3) | Obligatorio (recovery emitida) | Flag `claim_legacy_disabled` re-enable + audit | **Condicional**: nunca si quedan legacy sin devices ni recovery (REGL-3 / §5) |

**Conclusión:** la política documentada **no crea ventana de lockout** en ningún punto
M0→M5: toda cuenta legacy sin devices tiene claim acotado **o** recovery (I-028), y la
retirada de M5 está condicionada (§5.1: (a) 100% migradas o (b) ventana+soporte).

---

## 9. Failure matrix status

Veredicto Objetivo 7 — **los 12 escenarios** de `PHASE_2_MIGRATION_FAILURE_MATRIX.md`:

Cada escenario tiene respuesta para las 7 columnas exigidas:
**DETECTION · RECOVERY · ROLLBACK · DATA LOSS · LOCKOUT RISK · SECURITY IMPACT · AUDIT EVENT**.

| Escenario | Detección | Recuperación | Rollback | Data loss | Seguridad | Audit |
|---|---|---|---|---|---|---|
| 1 Cierre a mitad | audit issued sin confirm | nuevo código | cancel | ninguna | PENDING sin derechos | ✓ |
| 2 Pérdida de red | error+retry | retry/downgrade v1 | re-empaqueta | ninguna (outbox) | v3→v1 seguro | ✓ |
| 3 Supabase no disponible | 5xx+backoff | reintento idempotente | flag M1 off | ninguna | nada expuesto pre-RLS | ✓ |
| 4 Ejecución duplicada | checksum flag | verificar checksum | N/A | ninguna | ninguna | ✓ |
| 5 Dos devices simultáneos | UNIQUE/challenge used | reintento nuevo challenge | cancel perdedor | ninguna | single-use | ✓ |
| 6 App eliminada a mitad | TTL expiry | reinstall → retomar | cancel | ninguna | PENDING | ✓ |
| 7 Reinstalación durante migración | audit claim | claim acotado+bootstrap | N/A | ninguna | claim acotado auditado | ✓ |
| 8 Rollback parcial | flag vs tablas | re-aplicar M1/inertes | flag off | ninguna | solo-RPC ya aplicada | ✓ |
| 9 Marker incorrecto | compat test / ilegible | marker_error + doble derivación | N/A | un mensaje (acotado) | footer autenticado en M4 | ✓ |
| 10 Cliente antiguo vs servidor nuevo | min_version/denied | upgrade app | flag claim on | ninguna | claim acotado | ✓ |
| 11 Cliente nuevo vs servidor sin M1 | 404/423 | retry tras deploy | flag capability | ninguna | fail-closed | ✓ |
| 12 Bootstrap sin confirm | audit timeout | nuevo código/cancel | ninguna | ninguna | PENDING (I-013) | ✓ |

**Ningún escenario carece de respuesta** ⇒ sin BLOCKER en Objetivo 7.

---

## 10. Threat model status

Veredicto Objetivo 8 — **ninguna T marcada FIXED por existir documentación** (THREAT_MODEL §3.1):

| T | Estado 2.0.3 | Nota |
|---|---|---|
| T1-T3 | DISEÑADO (residual documentado) | claim acotado/recovery; verify_zone_id sin oráculo |
| T4 | DISEÑADO | máquina PENDING→ACTIVE, sin push en 1er enroll |
| T5-T11 | DISEÑADO | challenge single-use, firmas, device status |
| T12 | DISEÑADO (residual inherente) | MITM de entrega no eliminable; fingerprints off-band |
| T13 | DISEÑADO (residual: historial v1) | FS no retroactiva (I-011) — no se afirma |
| T14-T16 | DISEÑADO (residual documentado) | revocación+recovery; handshake v4+fingerprint |
| T17 | **PLANEADO M4** ✓ | msg_n/prev_n + nonce (ratchet) |

Estados usados con rigor: DISEÑADO = especificado sin código · PLANEADO = fase futura
programada (M4) · IMPLEMENTADO = en producción · VERIFICADO = demostrado tras implementar.
**Ningún threat se considera cerrado por diseño** (§3.1 footer). T17 permanece PLANEADO M4,
tal como define la documentación ⇒ sin BLOCKER.

---

## 11. Security invariant status

Veredicto Objetivo 9 — INVARIANT STATUS TABLE (I-001…I-030):

| Inv | Clasificación | Nota |
|---|---|---|
| I-001 Conocer ZONE-ID ≠ posesión | **VALID** | T1/T3 |
| I-002 X25519 jamás firma | **VALID** | git grep a partir de M1 |
| I-003 Autorización criptográfica por op | **VALID** | D3-D7, DEVICE_MODEL §5 |
| I-004 Privadas solo en device (salvo recovery) | **VALID** | acotado por I-025 |
| I-005 Sin plaintext por mesh | **VALID** | MeshPolicy |
| I-006 Nonces únicos | **VALID** | v1 aleatorio→contador v3+ |
| I-007 Peer no autenticado ≠ confianza | **VALID** | M3 + DEVICE_FINGERPRINT |
| I-008 Sin replay de challenges | **VALID** | used_at+TTL |
| I-009 Sin downgrade silencioso | **VALID** | MIGRATION M3/M5 |
| I-010 Migración no destructiva sin rollback | **VALID** | failure matrix (12) |
| I-011 Sin FS retroactiva afirmada | **VALID** | T13 |
| I-012 Servidor no custodio de privadas | **VALID** | D5/D1/T12/T13 |
| I-013 Primer enroll no activa sin confirm | **VALID** | BOOTSTRAP §4, I-030 |
| I-014 Sin acceso directo a tablas identidad | **VALID** | solo-RPC (R-023) |
| I-015 account_id inmutable | **VALID** | DEVICE_MODEL §1.1 |
| I-016 Recovery single-use + rate-limit | **VALID** | RECOVERY_POLICY §4 |
| I-017 Fingerprint determinista canónico | **VALID** | FINGERPRINT_SPEC (2 fingerprints) |
| I-018 Serialización canónica única | **VALID** | DEVICE_MODEL §5.1 |
| I-019 Migraciones idempotentes reversibles | **VALID** | failure matrix |
| I-020 Fuente única de keypair | **VALID** | M0 |
| I-021 Retirada claim sin dejar legacy sin vía | **VALID** | REGL-1..3 |
| I-022 verify_zone_id sin oráculo | **VALID** | Z-103 |
| I-023 Ratchet state secreto local | **VALID** | MIGRATION §5.2 |
| I-024 Recovery no degrada garantía del historial | **VALID** | nota: DOC-FD-001 RESUELTO (2.0.3.1) |
| I-025 Recovery jamás restaura X25519 v1 | **VALID** | nota: DOC-FD-001 RESUELTO (2.0.3.1) |
| I-026 Fingerprint nunca secreto/credencial | **VALID** | SPEC §1/§5 |
| I-027 Única secuencia bootstrap en curso | **VALID** | BOOTSTRAP §2-D/§3 |
| I-028 Ninguna legacy sin devices sin vía M0-M5 | **VALID** | LEGACY §3-§5 |
| I-029 Bootstrap code cumple policy | **VALID** | BOOTSTRAP §3 |
| I-030 Máquina de estados de device | **VALID** | BOOTSTRAP §4 |

Suma: **30 invariantes — 30 VALID**. Los únicos matices eran de **etiquetado** (I-024 "Opción
A" vs I-025 "Opción B" para la misma semántica → DOC-FD-001) y la **tabla stale** de IDENTITY
§7 (asociada a I-017 → DOC-FD-002) — **ambos resueltos en FASE 2.0.3.1**. No se renumeró
ninguno; no se detectó contradictorio.

---

## 12. Seven CTO gate requirements

Veredicto Objetivo 10 — condiciones exactas de `PHASE_2.0.2_CTO_GATE.md` §18:

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| 1 | Firma humana/CTO de la puerta (PROPOSED→APPROVED) y de los 3 puntos de §2 | Puerta §2 + este pack §3 (3 decisiones) | ✅ **CUMPLIDO en FASE 2.0.4** — CTO SIGN-OFF: APPROVED (`PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`) |
| 2 | Aceptar las 5 policies 2.0.2 como autoridad (sin cambios de decisiones) | DECISION_RESOLUTION criterio de autoridad; 5 policies | **BLOCKED BY HUMAN DECISION** (DOC-FD-001 etiquetas RESUELTO en 2.0.3.1) |
| 3 | Aprobar la limpieza editorial C1 (R-001, R-008, R-010, R-011, R-012, R-022) y el marcado de CRYPTO como superado | CONSISTENCY_MATRIX §0.1; CRYPTO header 2.0.2 | **BLOCKED BY HUMAN DECISION** (requiere aprobación; los edits ya están aplicados en los docs) |
| 4 | Decidir el commit de los docs untracked | Git: 20 archivos untracked bajo `docs/` al cierre de 2.0.3 (la puerta citó 23 — desactualizado; corregido en 2.0.3.1 a 20 y +1 audit = 21) | **BLOCKED BY HUMAN DECISION** |
| 5 | Reconfirmar `external_anonymous_users_enabled=true` (offline-first; no revertir) | HANDOFF §9.8 · GATE §18.5 | **BLOCKED BY HUMAN DECISION** |
| 6 | Reabrir FASE 1.8 (Security Advisor) en lote separado | HANDOFF §6/§8 · decisión pactada | **BLOCKED BY HUMAN DECISION** |
| 7 | Solo después: M0 (requiere OPEN-012) → M1 (requiere OPEN-001/002/003/011 + resto) | MIGRATION_PLAN §7-§8 · GATE §18.7 | **BLOCKED BY HUMAN DECISION** (depende de 2-6) |

Gate 1 (firma CTO + 3 decisiones humanas) **PASS en FASE 2.0.4**. Los gates 2-7 siguen
**BLOCKED BY HUMAN DECISION**: aprobación de la limpieza C1, decisión de commit, y
reasignación de FASE 1.8 — fuera del alcance de FASE 2.0.4. Estado global: **CTO SIGN-OFF
APPROVED — IMPLEMENTATION STATUS: PHASE 2.1 AUTHORIZATION PENDING**.

---

## 13. Remaining blockers

| ID | Tipo | Descripción | Resolución propuesta (docs-only) | Impacto |
|---|---|---|---|---|
| ~~**DOC-FD-001**~~ | ~~Documentación (C1)~~ | ~~Etiquetas invertidas de semántica OPEN-001 entre RECOVERY_POLICY ("Opción B") y el resto ("Opción A")~~ | ✅ **RESUELTO en 2.0.3.1** — unificado a "Opción A = sin X25519 v1" en RECOVERY_POLICY §2/§8 e I-025 | Sin efecto sobre el diseño |
| ~~**DOC-FD-002**~~ | ~~Documentación (C1)~~ | ~~Tabla de `IDENTITY_ARCHITECTURE §7` aún muestra el fingerprint único antiguo, no los dos ACC/DEV~~ | ✅ **RESUELTO en 2.0.3.1** — tabla sincronizada con FINGERPRINT_SPEC §2 (ACC/DEV) | Sin efecto sobre la spec (ya es autoridad) |
| ~~**DOC-FD-003**~~ | ~~Editorial (C1)~~ | ~~`LEGACY_ACCESS_POLICY` §2.27 texto corrupto: "en findistance?"~~ | ✅ **RESUELTO en 2.0.3.1** — redacción corregida ("a distancia?") | Legibilidad de la política |
| ~~**DOC-FD-004**~~ | ~~Editorial (C1)~~ | ~~GATE §18.4 cita "23 untracked"; real = 19 (20 con este pack)~~ | ✅ **RESUELTO en 2.0.3.1** — cifra actualizada a 20 (+1 audit = 21) | Trazabilidad del commit |
| **HD-1…HD-3** | Decisión humana | OPEN-001 copy · OPEN-018 obligatoriedad · plazo M5 | ✅ **RESUELTO en FASE 2.0.4** — las 3 decisiones **CTO APPROVED** (`PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`) | M5 sin fecha arbitraria; recovery no bloqueante |
| **C1 pendientes** | Decisión humana | Limpieza editorial R-001/R-008/R-010/R-011/R-012/R-022 (ya aplicadas como edits; falta aprobar) | Aprobación CTO (puerta §18.3) | — |

Nota: **C5/C4/C3 no quedan bloqueando** una vez firmadas las resoluciones (puerta §3-§5) —
los obstáculos restantes son humanos (C1 + commit + FASE 1.8). Las 3 decisiones humanas
HD-1..3 fueron **CTO APPROVED en FASE 2.0.4**.

---

## 14. Implementation readiness

Veredicto Objetivo 11 (la pregunta es: ¿la arquitectura documental está suficientemente
definida para iniciar implementación controlada **una vez que el CTO firme**?):

**TRANSICIÓN EN FASE 2.0.4:**
1. ✅ El CTO firmó la puerta 2.0.2 y respondió las **3 decisiones humanas** (§3) — ver
   `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md` (CTO SIGN-OFF: APPROVED; OPEN-001/018/M5).
2. ⏳ Pendiente de decisión humana: commit de los docs (gate §18.4) y reapertura de FASE 1.8
   (gate §18.6).
3. ⏳ Pendiente de decisión humana: aprobación de la limpieza editorial C1 (gate §18.3).

Los bloqueadores documentales **DOC-FD-001..004 ya fueron corregidos en FASE 2.0.3.1**
(ediciones de texto; no cambian decisiones).

Tras esos puntos, la arquitectura documental (18 OPEN resueltos, 5 policies, 30 invariantes,
T1-T17 con estados, M0-M5 reconstruidos, failure matrix de 12 escenarios como contrato) está
**definida con el detalle suficiente** para M0 y M1. No se evalúa aquí la "seguridad"
absoluta del producto ni se hace ninguna afirmación de captura ("military-grade",
"impenetrable", etc.) — solo madurez de especificación.

---

## 15. Exact CTO approval checklist

> Casillas marcadas **solo** cuando representan exactamente decisiones aprobadas en
> **FASE 2.0.4** (OPEN-001, OPEN-018, retirada M5 de `claim_zone_id`). NINGUNA casilla
> implica implementación realizada: el sign-off aprueba arquitectura/documentación.

- [x] CTO approves recovery policy
- [x] CTO approves legacy history behavior
- [ ] CTO approves bootstrap policy
- [ ] CTO approves fingerprint specification
- [ ] CTO approves device lifecycle
- [x] CTO approves legacy migration policy
- [ ] CTO approves M0–M5 migration contract
- [ ] CTO approves failure matrix
- [x] CTO acknowledges residual risks
- [ ] CTO authorizes transition to implementation

---

## 16. Validación final (solo lectura)

Comandos ejecutados: `git diff --stat` (vacío) · `git diff --cached --stat` (vacío) ·
`git status --short`.

Resultado (al cierre de FASE 2.0.3):
- 20 archivos untracked, **todos bajo `docs/`** (ninguno en `lib/`, `test/`, `supabase/`);
  este pack fue el 20º archivo nuevo de la fase 2.0.3.
- Tras FASE 2.0.3.1: +1 archivo (`PHASE_2.0.3.1_FINAL_DOCUMENTATION_AUDIT.md`) = **21**.
- `git diff --stat` **vacío** ⇒ ningún archivo versionado modificado.
- HEAD intacto (`7f59b77`); sin cambios staged; sin commits.

---

**FILES MODIFIED OUTSIDE DOCS: NONE**

**SUPABASE CHANGES: NONE**

**REMOTE CHANGES: NONE**

**COMMITS: NONE**

**IMPLEMENTATION: NONE**

---

CTO SIGN-OFF STATUS: APPROVED

IMPLEMENTATION STATUS: PHASE 2.1 AUTHORIZATION PENDING