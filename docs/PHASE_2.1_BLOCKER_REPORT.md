# PHASE 2.1 — Block Report (BLOCKER)

> **Tipo:** Bloqueo formal detectado durante FASE 2.1 — requiere decisión explícita del CTO.
> **Fecha:** 2026-09-25 · **Estado:** RESUELTO — ver §17/§18 y `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md`
> **Afecta:** `PHASE_2_FINGERPRINT_SPEC.md` §4 (única autoridad del fingerprint v1)
> **FASE 2.1 IMPLEMENTATION:** BLOCKED (spec corregida; implementación a la espera de revisión CTO).

---

## 1. Fuente exacta

`docs/PHASE_2_FINGERPRINT_SPEC.md` §4 "Alfabeto y encoding" (especificación canónica,
autoridad única del fingerprint v1 para FASE 2.0 y posteriores).

## 2. Contradicción exacta

El spec declara simultáneamente:

| Declaración del spec | Valor |
|---|---|
| Cardinalidad declarada del alfabeto | **32** ("Total símbolos \| 32 (5 bits/símbolo)", tabla §4) |
| Cardinalidad literal del alfabeto | **31** — los símbolos escritos en §4 son: 8 dígitos `2 3 4 5 6 7 8 9` + 23 letras `A B C D E F G H J K M N P Q R S T U V W X Y Z` |
| Anchura de encoding | **5 bits** por símbolo (tabla §4) |
| Valores válidos resultantes | **0..31** |

Conteo verificable del alfabeto literal: dígitos `2-9` = 8; letras `A-H` = 8,
`J K M N P Q R S T U V W X Y Z` = 15; total letras = 23; 8 + 23 = **31**.
El criterio textual del spec ("evita 0/O, 1/I/L") excluye 5 símbolos de 36
alfanuméricos → 36 − 5 = **31**, no 32. La afirmación "32" es, por tanto, inconsistente
con su propio alfabeto literal y con su propio criterio de exclusión.

## 3. Consecuencia matemática

Un codificador Base32 de 5 bits emite índices 0..31. El alfabeto literal actual solo
define símbolos para los índices 0..30: **no existe símbolo para el índice 31**. No hay
forma de codificar un grupo de 5 bits con valor 31 bajo el alfabeto literal.

## 4. Consecuencia de implementación

El algoritmo del fingerprint **no está completamente especificado**:
- Dado que SHA-256 produce dígitos uniformes, la prob. de que un fingerprint encuentre
  el índice 31 dentro de sus primeros 20 grupos (100 bits) es ≈ 1 − (31/32)^20 ≈ **47%**.
- Es decir, ~1 de cada 2 fingerprints no podría generarse bajo el alfabeto literal.

## 5. Consecuencia de interoperabilidad

El spec exige (principios §1.4 y §6) que **dos implementaciones independientes
produzcan exactamente los mismos bytes**. Como la tabla no especifica el símbolo del
índice 31, cada implementación podría elegir uno distinto (o fallar), y no puede
garantizarse la producción de fingerprints idénticos.

## 6. Consecuencia sobre el KAT

El **KAT del fingerprint v1** (fijado en M1, spec §6) **no puede finalizarse de forma
segura** hasta que el alfabeto quede fijado: los vectores de referencia dependen del
símbolo exacto del índice 31 (y de la cardinalidad/orden canónico del alfabeto).

## 7. Consecuencia de seguridad/identidad

Los **ACCOUNT_FINGERPRINT y DEVICE_FINGERPRINT no deben implementarse contra un
encoding subespecificado**: son el mecanismo humano out-of-band de verificación de
identidad (cuenta/device) y su corrección cross-implementación es un requisito de
confianza (I-026). Implementar ahora un alfabeto elegido unilateralmente rompería la
separación de poderes de la FASE 2.0 (los documentos aprobados son vinculantes y no se
reinterpretan).

## 8. Decisión CTO requerida

Elegir EXPLÍCITAMENTE entre:

**OPTION A** — Definir un alfabeto explícito de 32 símbolos conservando el diseño
5 bits / Base32 (20 chars, 4×5, sin padding) y su posición canónica.

**OPTION B** — Retener el alfabeto literal de 31 símbolos y **reemplazar formalmente**
el encoding 5 bits/Base32 por otro encoding distinto y precisamente especificado.

Esta fase NO recomienda ni selecciona A ni B de forma autónoma (mandato: "ask, do not
guess"; los documentos FASE 2.0 son vinculantes y toda decisión que los modifique es
potestad del CTO humano).

## 9. Actualización documental requerida después de la decisión CTO

El fix del spec debe fijar, al menos:
- alfabeto literal (32 símbolos explícitos, o el encoding alternativo de OPTION B)
- cardinalidad del alfabeto
- mapeo símbolo → índice
- procedimiento de encoding
- procedimiento de decoding (si aplica)
- reglas de normalización (comparación)
- vectores KAT oficiales (M1)
- vectores de prueba de implementación (targets FASE 2.1)
- referencias cruzadas en los documentos dependientes de FASE 2.0 que citen el alfabeto
  (`PHASE_2_SECURITY_INVARIANTS.md` I-017/I-026, `PHASE_2_OPEN_DECISIONS.md` OPEN-002,
  `PHASE_2_DEVICE_MODEL.md`, `PHASE_2_IDENTITY_ARCHITECTURE.md`, `PHASE_2_THREAT_MODEL.md`
  T6/T16), más este reporte como registro del bloqueo.

## 10. Estado actual

```
FINGERPRINT SPECIFICATION: BLOCKED
PHASE 2.1 IMPLEMENTATION:   BLOCKED
PRODUCTION CODE CHANGES:    NONE
SUPABASE CHANGES:           NONE
KAT:                        NOT FINALIZED
```

### Anexo factual — estado local del repositorio en el momento del STOP

Para total transparencia (sin ocultar nada al CTO), estado verificado en
`2026-09-25` antes de redactar este reporte:

- `HEAD` intacto: `7f59b776c62cc131fd05dc999e99cbb7804385e8`.
- `git diff` y `git diff --cached` (archivos rastreados): **vacíos** — cero
  modificaciones, cero staging, cero commits.
- Archivos nuevos sin rastrear (untracked, tal como el estado esperado de la fase):
  - `docs/` — 22 documentos FASE 2.0 (preexistentes desde el inicio de FASE 2.1).
  - `lib/identity/` — esqueleto de fundación NEW FOUNDATION — **NOT YET INTEGRATED**
    (14 archivos: modelos, servicios Ed25519/X25519, almacén seguro, máquina de
    estados, persistencia Isar + `.g.dart` generado). **Ningún archivo del proyecto
    rastreado importa o referencía `lib/identity/`**; no se tocó `pubspec.yaml`, ni
    `lib/services/`, ni `lib/main.dart`, ni `lib/models/isar_models.*`, ni
    `supabase/`, ni la base de mensajes.
- El esqueleto `lib/identity/` queda **en reposo** (sin más ediciones, sin tests, sin
  integración) a la espera de la decisión CTO. Tras la decisión podrá ajustarse
  (p. ej. alfabeto del fingerprint fijado por OPTION A/B) o descartarse; su
  conservación/eliminación durante el bloqueo no modifica ningún camino de producción.

---

## 11. Resolución CTO recibida (2026-09-25) — OPTION A APPROVED

El CTO aprobó explícitamente **OPTION A**: retener el encoding de 5 bits por símbolo
y definir formalmente un alfabeto completo de 32 símbolos. Con la condición
expresa de **NO seleccionar el símbolo faltante de forma autónoma** y de verificar
primero si la arquitectura aprobada ya define el alfabeto de 32 símbolos en otro
documento.

## 12. Auditoría documental ejecutada (mandato CTO §2 / §7)

Procedimiento: búsqueda en todo `docs/` y en `lib/` de términos clave
(`alfabeto`/`alphabet`, `Base32`/`base32`, `32 símbolos`/`32 symbols`, `5 bits`,
`símbolo`/`symbol`, `KAT`, `fingerprint`, `symbol mapping`, `canonical encoding`,
`0-9`/`2-9`, `JKMN`, `WXYZ`, `charset`/`character set`) más lectura dirigida de
las secciones que citan el alfabeto.

Resultado — **NO existe ninguna definición autoritativa del 32º símbolo**:

| Fuente | Qué dice | Alfabeto literal definido |
|---|---|---|
| `PHASE_2_FINGERPRINT_SPEC.md` §4 (autoridad única) | Declara "32 (5 bits/símbolo)"; escribe 31 símbolos | **Sí (31)** — el defecto objeto de este bloqueo |
| `PHASE_2_IDENTITY_ARCHITECTURE.md` §7:294 | "Base32 sin padding, alfabeto unambiguo de 32 símbolos (evita 0/O, 1/I/L)" | No |
| `PHASE_2_CONSISTENCY_MATRIX.md` §15:336 | "Base32 RFC 4648 sin padding, 32 símbolos (sin 0/1, sin O/I/L)" | No (y el alfabeto RFC 4648 estándar incluye I/L/O — la referencia es inconsistente y nunca se literalizó) |
| `PHASE_2.0.3_CTO_SIGNOFF_PACK.md`:319 | "Base32 sin padding, alfabeto unambiguo (32 símbolos, sin 0/O/1/I/L)" | No |
| `PHASE_2_BOOTSTRAP_POLICY.md` §3:71 | "alfabeto unambiguo de BOOTSTRAP (32 símbolos)" para códigos de 8 chars | No (aplica al bootstrap code, milestone M0/M1 — fuera del scope FASE 2.1; **hallazgo adyacente** para el CTO) |
| `PHASE_2_DECISION_RESOLUTION.md` / `CRYPTO_CTO_REVIEW.md` | Referencias al fingerprint v1 | No |
| `PHASE_2.0.2_CTO_GATE.md` / `PHASE_2.0.3.1_FINAL_DOCUMENTATION_AUDIT.md` | Resumen de la spec | No |
| `lib/services/zone_id_service.dart:559` | `'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'` | Generador legacy del handle `ZONE-ID` (36 chars alfanuméricos, sin exclusión de ambiguos). **No** es ni base32 ni un alfabeto unambiguous: no constituye fuente para el fingerprint. |

**Veredicto:** no existe definición autoritativa del alfabeto de 32 símbolos ni del
símbolo faltante en ningún documento aprobado.

## 13. Declaración formal (mandato CTO §3)

> **OPTION A approved by CTO, but the exact 32-symbol alphabet remains
> underspecified because the approved architecture does not define the missing
> symbol.**

## 14. Alfabeto actual exacto (31 símbolos) y restricciones para cualquier solución de 32

### Alfabeto literal actual (spec §4, líneas 69-70) — 31 símbolos

```
2 3 4 5 6 7 8 9 A B C D E F G H J K M N P Q R S T U V W X Y Z
```

- dígitos: `2 3 4 5 6 7 8 9` (8)
- letras: `A B C D E F G H J K M N P Q R S T U V W X Y Z` (23; excluye `I`, `L`, `O`)
- total: **31**

### Restricciones que toda solución de 32 símbolos debe satisfacer

Derivadas exclusivamente del texto aprobado (sin invención):

1. **Cardinalidad:** exactamente 32 símbolos distintos.
2. **Anchura/valores:** 5 bits por símbolo; valores 0..31; **cada índice tiene
   exactamente un símbolo**; ningún índice sin símbolo; ningún símbolo duplicado;
   ningún símbolo mapea a dos índices.
3. **Mapeo:** el spec implica mapeo posicional (índice k → k-ésimo símbolo en orden
   literal); la corrección debe declarar explícitamente `índice → símbolo` y
   `símbolo → índice` (sin ordenamiento implícito).
4. **Legibilidad humana (intención del spec "evita 0/O, 1/I/L"):** prohibir pares
   confundibles coexistiendo (0↔O y 1↔I/L). El conjunto literal ya excluye
   `{0, 1, I, L, O}`; alcanzar 32 exige **re-incluir exactamente uno de esos cinco**
   (o adoptar otro conjunto explícitamente aprobado) sin reabrir la ambigüedad.
5. **Invariantes de encoding que NO cambian:** SHA-256 sobre el input canónico ACC/DEV
   (§3); Base32 sin padding sobre el digest completo; **primeros 20 caracteres**
   (100 bits); grupos 4×5 con `-`; MAYÚSCULAS visual; normalización a MAYÚSCULAS para
   comparar; sin checksum.
6. **No alterar el input criptográfico:** canonicalización (UUID lowercase con guiones;
   clave Ed25519 32 bytes raw → Standard Base64 con padding); prefijo de versión
   `"ZONE-FP-1\0"` y kind `"ACC"`/`"DEV"`; truncación; longitud; separación de dominio.
   Esto es una **reparación de especificación**, no un rediseño criptográfico.
7. **Versionado:** preservar el fingerprint v1 (`"ZONE-FP-1"`). La corrección se
   documenta como **SPECIFICATION CORRECTION BEFORE IMPLEMENTATION** (la implementación
   FASE 2.1 no existe aún: no hay formato publicado, no hay fingerprints almacenados,
   no hay KAT publicado) — **sin** crear una versión de fingerprint nueva.
8. **Determinismo cross-implementación (spec §1.4/§6):** una vez fijados alfabeto y
   mapeo, dos implementaciones independientes deben producir bytes idénticos.

### Hallazgo adyacente (fuera del scope de FASE 2.1, informativo)

`PHASE_2_BOOTSTRAP_POLICY.md` usa el mismo concepto "alfabeto unambiguo de 32
símbolos" para el bootstrap code (8 chars, 40 bits) sin definir el alfabeto literal
en ningún documento. Si el CTO fija el alfabeto de 32 símbolos, se recomienda
declarar explícitamente en el milestone de bootstrap (M0/M1) si comparte alfabeto y
mapeo con el fingerprint o es un conjunto propio. **No se actúa sobre ello aquí.**

## 15. Estado tras la auditoría (mandato CTO §12 — CRITICAL STOP CONDITION)

```
FINGERPRINT SPECIFICATION: CTO OPTION A APPROVED
EXACT ALPHABET:            BLOCKED
PHASE 2.1:                 BLOCKED
PRODUCTION CODE:           UNCHANGED
KAT:                       NOT FINALIZED
```

Se aplica la **CRITICAL STOP CONDITION**: el repositorio no contiene una definición
autoritativa del símbolo faltante ⇒ **no se elige ningún símbolo**, **no se corrige el
spec**, **no se crea `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md`** (esa ruta solo aplica
si existe una definición autoritativa — §4/§11 del CTO), **no se continúa la
implementación**. Nada en `lib/`, `test/`, `supabase/`, `pubspec.yaml` ni en la
documentación canónica ha sido modificado tras la decisión CTO; el esqueleto
`lib/identity/` sigue intacto y no integrado.

## 16. Siguiente acción (requiere CTO)

El CTO debe **elegir explícitamente el símbolo** que completa el alfabeto a 32
(respetando las restricciones §14) o **aprobar un conjunto de 32 símbolos** con su
mapeo; tras ello, se actualizará `PHASE_2_FINGERPRINT_SPEC.md` §4 (normativo completo:
alfabeto literal, cardinalidad, mapeo, encoding, padding, case, normalización,
símbolos inválidos, representación canónica), se documentará la corrección como
**SPECIFICATION CORRECTION BEFORE IMPLEMENTATION**, y se calcularán los vectores KAT
independientes siguiendo los pasos CTO §6.**

---

## 17. Resolución aplicada (2026-09-25) — decisión formal CTO

El CTO emitió la **CTO FORMAL DECISION — FINGERPRINT v1 ALPHABET**, que resuelve el
bloqueo con **OPTION A** y selecciona explícitamente el 32º símbolo (decisión humana,
no inferida):

- **Alfabeto final (32):** `23456789ABCDEFGHJKMNPQRSTUVWXYZ-`
- **Símbolo adicional:** `-` (ASCII **U+002D**), índice 31 — símbolo literal del
  alfabeto, no separador/operador.
- **Mapeo 0..31:** el aprobado íntegramente por el CTO (reproducido en
  `PHASE_2_FINGERPRINT_SPEC_RESOLUTION.md` §5 y en el spec §4.3).
- **5 bits por símbolo**, sin padding, 20 chars (100 bits), 4×5 display.

Acciones ejecutadas en esta ronda (solo documentación):

1. `PHASE_2_FINGERPRINT_SPEC.md` §4 → normativo completo (§4.1–§4.10: nombre/versión,
   alfabeto literal, cardinalidad, mapeo, encoding, truncamiento, longitud,
   normalización, case, padding, símbolos inválidos, representación canónica, `-`).
2. `PHASE_2_FINGERPRINT_SPEC.md` §6 → estado KAT (NOT FINALIZED; vectores preparados).
3. `PHASE_2_FINGERPRINT_SPEC.md` §8 → nota de corrección SPECIFICATION CORRECTION
   BEFORE IMPLEMENTATION.
4. `PHASE_2_CONSISTENCY_MATRIX.md` §15:336 → célula Codificación sincronizada.
5. `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md` → creado (reporte completo de 15 puntos).
6. Validaciones matemáticas §6 del CTO + vectores KAT esperados (implementación
   independiente Python) → documentados en el reporte de resolución §14/§13.
7. Auditoría de compatibilidad §9 del CTO → sin fingerprints persistidos/publicados/
   usados por código activo (ver resolución §9).

El esqueleto `lib/identity/` **no** se ha modificado: su constante de alfabeto
(`base32_unambiguous.dart:20`, 31 símbolos sin `-`) sigue pendiente de corrección en
la futura implementación autorizada — fuera del scope documental de esta ronda.

## 18. Estado final tras la corrección documental (mandato CTO §12)

```
FINGERPRINT SPECIFICATION: CORRECTED / BLOCKED
ALPHABET: 32 SYMBOLS / BLOCKED
KAT: NOT FINALIZED
PRODUCTION CODE: UNCHANGED
SUPABASE CHANGES: NONE
PHASE 2.1 IMPLEMENTATION: BLOCKED
CTO REVIEW: REQUIRED
```

**STOP.** Se detiene aquí la FASE 2.1 a la espera de una nueva revisión CTO que
autorice la implementación del fingerprint y de la fundación de identidad. No se
inicia FASE 2.2. No se modifica código de producción, Supabase, RLS/RPC, migraciones
ni el flujo legacy de chat.