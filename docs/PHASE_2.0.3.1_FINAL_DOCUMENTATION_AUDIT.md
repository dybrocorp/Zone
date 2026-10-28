# FASE 2.0.3.1 — FINAL DOCUMENTATION AUDIT

> **Tipo:** correcciones documentos-only (DOC-FD-001..004) + verificación read-only final
> **Fecha:** 2026-09-24 · **Fase:** 2.0.3.1 (posterior a 2.0.3)
> **NO modifica:** arquitectura · código (`lib/`) · tests (`test/`) · Supabase (`supabase/`) ·
> migraciones · `pubspec.yaml` · decisiones ya aprobadas (18 OPEN RESOLVED — CTO PROPOSED)
> **Autoridad fingerprint:** `PHASE_2_FINGERPRINT_SPEC.md` v1 (única canónica, intacta)

---

## 1. DOC-FD-001 — RECOVERY OPTION LABELING

### Problema
La semántica de recovery "blob **sin** X25519 v1" (política segura propuesta) estaba
etiquetada de forma invertida según el documento:

- **"Opción B"** en `PHASE_2_RECOVERY_POLICY.md` §2 (título, descripción de opciones,
  DECISIÓN PROPUESTA, tabla de análisis), §7 (I-025) y §8 (estado).
- **"Opción A"** en `DECISION_RESOLUTION.md` (OPEN-001), `PHASE_2.0.2_CTO_GATE.md`,
  `PHASE_2_OPEN_DECISIONS.md`, `CRYPTO_CTO_REVIEW.md` §7.1/§7.3, `PHASE_2_CONSISTENCY_MATRIX.md`
  e `I-024`.

El contenido conceptual era idéntico en los 7 documentos; solo las etiquetas A/B estaban
invertidas.

### Archivos afectados
- `PHASE_2_RECOVERY_POLICY.md` (origen de la inversión) — corregido.
- `PHASE_2.0.3_CTO_SIGNOFF_PACK.md` (describía la inversión como BLOCKER) — actualizado a
  RESUELTO.
- Verificación: ningún otro documento de FASE 2.0/2.0.1/2.0.2 usaba etiquetas invertidas.

### Corrección aplicada
En `PHASE_2_RECOVERY_POLICY.md` se **unificó el etiquetado** (sin tocar contenido técnico ni
la decisión propuesta):

- **Opción A** = recovery blob **SIN X25519 v1** (restaura identidad Ed25519; historial v1
  ilegible) — **DECISIÓN PROPUESTA (CTO): OPCIÓN A**.
- **Opción B** = alternativa que **SÍ** restauraría la X25519 v1 (blob con
  `priv_X25519 ‖ priv_Ed25519`).
- Se intercambiaron las etiquetas de las dos descripciones (§2), se reasignaron las letras en
  la tabla de análisis A↔B conservando el texto técnico, y se alinearon I-025
  ("aceptación CTO de la **Opción A**") y §8 ("RESOLVED — CTO PROPOSED (**Opción A**)").
- No se introdujeron alternativas nuevas ni se cambió la decisión (recovery no restaura
  X25519 v1).

### Verificación
Búsqueda global de `Opción A` / `Opción B` / `OPCIÓN` (docs FASE 2.0/2.0.1/2.0.2/2.0.3/2.0.3.1):

- Todos los documentos de recovery usan **Opción A = sin X25519 v1** y **Opción B = con
  X25519 v1**: DECISION_RESOLUTION (OPEN-001), CTO_GATE, OPEN_DECISIONS, CRYPTO §7.1/§7.3,
  CONSISTENCY_MATRIX, I-024, I-025 y RECOVERY_POLICY §2/§7/§8.
- **No queda ninguna inversión residual.**
- Las restantes menciones "Opción B" en el SIGNOFF_PACK corresponden a las **decisiones
  humanas** (OPEN-001 copy de producto, OPEN-018 obligatoriedad, plazo M5), no a la semántica
  de recovery — correctas y no tocadas.

---

## 2. DOC-FD-002 — FINGERPRINT LEGACY TABLE

### Problema
`PHASE_2_IDENTITY_ARCHITECTURE.md` §7 declaraba a FINGERPRINT_SPEC como autoridad en su
header, pero su **tabla interna** (líneas 288-296) aún mostraba el formato antiguo: un solo
fingerprint con input `bytes("ZONE-FP-1\0") ‖ account_id ‖ identity_public_key ‖
device_public_key` y "único por (account, device)" — en lugar de los dos fingerprints
(ACCOUNT y DEVICE) canónicos de la spec.

### Archivo afectado
- `PHASE_2_IDENTITY_ARCHITECTURE.md` §7 — corregido.
- `PHASE_2_CONSISTENCY_MATRIX.md` §15 — la tabla activa "Fingerprint determinism" también
  mostraba el input único antiguo; sincronizada (hallazgo documental adicional coherente con
  DOC-FD-002).
- `PHASE_2.0.3_CTO_SIGNOFF_PACK.md` — descripción del hallazgo actualizada a RESUELTO.

### Corrección aplicada
La tabla de §7 se reescribió con los **dos fingerprints** de la spec:

- **ACCOUNT_FINGERPRINT**: `utf8("ZONE-FP-1\0") ‖ utf8("ACC") ‖ utf8(uuid_canonical(account_id)) ‖ base64_std_padded(identity_public_key)`
- **DEVICE_FINGERPRINT**: `utf8("ZONE-FP-1\0") ‖ utf8("DEV") ‖ utf8(uuid_canonical(account_id)) ‖ utf8(uuid_canonical(device_id)) ‖ base64_std_padded(device_public_key)`

Manteniendo: SHA-256 · Base32 sin padding (alfabeto unambiguo) · 20 chars en 4×5 · sin
X25519 en el input · estabilidad (ACC rota solo con Ed25519 de cuenta; DEV cambia con el
device) · example `FP7GK-3KQ9W-MJ2X8-PDVTC`.

`PHASE_2_CONSISTENCY_MATRIX` §15 quedó alineada con los mismos inputs y con la nota
"autoridad: FINGERPRINT_SPEC v1".

### Verificación
Búsqueda global de `7 letras` / `identity_pk ‖ x25519_pk` / inputs antiguos:

- Referencias restantes son **históricas o registro de conflicto resuelto**: CRYPTO §5.2
  marcado ⚠️ superado, DECISION_RESOLUTION OPEN-002, CONSISTENCY_MATRIX R-002/R-014,
  OPEN_DECISIONS OPEN-002, FINGERPRINT_SPEC header (deroga el formato antiguo), IDENTITY §7
  header ("NO asumir 7 letras").
- **Ningún documento usa el fingerprint antiguo como formato canónico vigente.**
- `PHASE_2_FINGERPRINT_SPEC.md` sigue siendo la **única autoridad normativa** (no se creó
  ninguna segunda especificación; no se modificó la spec).

---

## 3. DOC-FD-003 — EDITORIAL

- **Archivo:** `PHASE_2_LEGACY_ACCESS_POLICY.md` §2.27.
- **Corrección:** texto corrupto "en findistance?" → **"a distancia?"** según el contexto de
  la celda "Verificación de ownership" en M2 (¿se añade verificación por firma/fingerprint a
  distancia? → **no**, solo a nivel de cuenta; la verificación por fingerprint llega con el
  peer handshake de M3). No se modificó el significado: la respuesta sigue siendo "no — solo
  cuenta".

---

## 4. DOC-FD-004 — FILE COUNT

- **Archivo:** `PHASE_2.0.2_CTO_GATE.md` §18.4.
- **Corrección:** el conteo obsoleto de "23 untracked" se actualizó al estado verificado en
  FASE 2.0.3 = **20 archivos untracked, todos bajo `docs/`** (19 docs de diseño + el pack de
  firma 2.0.3), más este audit de FASE 2.0.3.1 (= **21** en total al cierre).
- El número no es condición arquitectónica: solo trazabilidad del commit pendiente de
  decisión humana.
- `PHASE_2.0.3_CTO_SIGNOFF_PACK.md` §12 (gate 4) y §16 actualizados al mismo estado.

---

## 5. Global consistency check

### 5.1 Recovery labels — **PASS**
Todos los documentos usan **OPTION A = SIN X25519 v1** / **OPTION B = CON X25519 v1**. Sin
inversión residual (ver §1).

### 5.2 Fingerprint — **PASS**
`FINGERPRINT_SPEC.md` es la única autoridad normativa. IDENTITY §7 y CONSISTENCY_MATRIX §15
coinciden con ella. Sin fingerprint legacy contradictorio vigente (ver §2).

### 5.3 Security invariants — **PASS (30/30 VALID)**
I-001…I-030 verificados nuevamente; **numeración intacta**. Resultado: 30/30 VALID. Las notas
de etiquetado (I-024/I-025 → DOC-FD-001) y de tabla stale (I-017 → DOC-FD-002) están
resueltas; ninguna corrección documental reveló una contradicción real en los invariantes.

### 5.4 Threat model — **INTACTO**
No se modificó ningún estado de T1-T17. Se mantienen los estados DISEÑADO / PLANNED /
IMPLEMENTED / VERIFIED según la especificación; **ninguna T marcada FIXED** (T17 = PLANNED M4).

### 5.5 Human decisions — **INTACTAS (3 pendientes)**
- OPEN-001 (copy de producto sobre historial legacy) — sigue pendiente.
- OPEN-018 (obligatoriedad de recovery codes) — sigue pendiente.
- Plazo de retirada de `claim_zone_id` / M5 (30 vs 90 días) — sigue pendiente.

Ninguna fue marcada como aprobada ni modificada por esta fase.

### 5.6 CTO gate — **SIN CAMBIOS DE ESTADO**
Se mantienen, sin marcar casillas del approval checklist:

```
CTO SIGN-OFF STATUS: PENDING HUMAN APPROVAL
IMPLEMENTATION STATUS: BLOCKED
```

La puerta `PHASE_2.0.2_CTO_GATE.md` §18 sigue sin ninguna condición PASS: las 7 exigen
decisión humana (las condiciones de documentación que dependían de DOC-FD-001/DOC-FD-002
quedaron liberadas por esta fase, pero ninguna se convierte en PASS automático).

---

## 6. Scope validation

### 6.1 Comandos ejecutados (read-only)
```
git diff --stat                  → vacío
git diff --cached --stat         → vacío
git status --short               → solo archivos bajo docs/
```

### 6.2 Resultado
- Archivos untracked al cierre de FASE 2.0.3.1: **21**, **todos bajo `docs/`** (20 de 2.0.3 +
  este audit). Ninguno en `lib/`, `test/`, `supabase/`.
- `pubspec.yaml` y configs Flutter/Supabase: sin modificaciones.
- `git diff` / `git diff --cached`: vacíos ⇒ ningún archivo versionado modificado.
- HEAD intacto (`7f59b77`); sin cambios staged; **sin commits**.
- Cambios remotos: **ninguno**.

---

## 7. Final status

| Dominio | Estado |
|---|---|
| DOC-FD-001 (etiquetas recovery) | ✅ RESUELTO (2.0.3.1) |
| DOC-FD-002 (tabla fingerprint stale) | ✅ RESUELTO (2.0.3.1) |
| DOC-FD-003 (texto corrupto §2.27) | ✅ RESUELTO (2.0.3.1) |
| DOC-FD-004 (conteo untracked) | ✅ RESUELTO (2.0.3.1) |
| Recovery labels | Homogéneo: OPTION A = sin X25519 v1 |
| Fingerprint | Única autoridad: FINGERPRINT_SPEC v1 |
| Invariantes | 30/30 VALID (numeración intacta) |
| Threat model | Estados intactos (ninguna FIXED) |
| Decisiones humanas | 3 pendientes (OPEN-001, OPEN-018, plazo M5) |
| Firma CTO | PENDIENTE |
| Implementación | BLOQUEADA |

```
FILES MODIFIED OUTSIDE DOCS: NONE
SUPABASE CHANGES: NONE
REMOTE CHANGES: NONE
COMMITS: NONE
IMPLEMENTATION: NONE
```

---

DOCUMENTATION AUDIT STATUS: PASS

CTO SIGN-OFF STATUS: PENDING HUMAN APPROVAL

IMPLEMENTATION STATUS: BLOCKED

STOP.