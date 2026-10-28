# PHASE 2.1 — Fingerprint Specification Resolution (RESOLUTION)

> **Tipo:** Reporte de resolución del bloqueo del alfabeto del fingerprint v1
> (decisión CTO **OPTION A**).
> **Fecha:** 2026-09-25 · **Estado:** CORRECCIÓN DE SPEC APLICADA — IMPLEMENTACIÓN BLOQUEADA
> **Documentos relacionados:** `PHASE_2_FINGERPRINT_SPEC.md` (autoridad, §4 corregido) ·
> `PHASE_2.1_BLOCKER_REPORT.md` (registro histórico del bloqueo)

---

## 1. Bloqueo original

`PHASE_2_FINGERPRINT_SPEC.md` §4 declaraba un alfabeto de **32** símbolos (5 bits/
símbolo, valores 0..31) pero escribía literalmente **31** (`2 3 4 5 6 7 8 9` +
`A B C D E F G H J K M N P Q R S T U V W X Y Z`). El índice **31 no tenía símbolo**:
un codificador de 5 bits no podía representarlo, ~1 de cada 2 fingerprints no era
generable (1 − (31/32)^20 ≈ 47%), el KAT de M1 no era finalizable y dos
implementaciones independientes no podían garantizar bytes idénticos (spec §1.4/§6).
Registro completo: `PHASE_2.1_BLOCKER_REPORT.md` §1–§10.

## 2. Decisión CTO: OPTION A

El CTO aprobó formalmente:

- **OPTION A** — retener el encoding de **5 bits por símbolo** y definir un alfabeto
  **completo de 32 símbolos**.
- Símbolo adicional seleccionado **explícitamente** por el CTO (decisión humana, no
  inferida por el agente): **`-`** (ASCII U+002D), índice **31**, tratado como
  **símbolo literal** del alfabeto (no separador, no operador, no opcional).
- Mapeo inicial 0..31 aprobado sin modificaciones.

## 3. Fuente autoritativa del alfabeto final

**La CTO FORMAL DECISION — FINGERPRINT v1 ALPHABET (2026-09-25) es la fuente
autoritativa** del alfabeto y del mapeo.

Auditoría previa (blocker report §12): **ningún** documento aprobado de la
arquitectura FASE 2.0 definía el 32º símbolo ni un alfabeto literal alternativo
(`IDENTITY_ARCHITECTURE` §7, `CONSISTENCY_MATRIX` §15, `SIGNOFF_PACK`, `BOOTSTRAP_POLICY`
y gates se limitaban a declarar "32 símbolos" sin literalizarlos; el único literal en
código legacy — `zone_id_service.dart:559` — es el generador del handle ZONE-ID de 36
caracteres alfanuméricos, sin relación con el fingerprint). Por tanto el alfabeto final
no deriva de una definición preexistente, sino de la **decisión humana explícita del
CTO**.

## 4. Alfabeto final (32 símbolos)

```
23456789ABCDEFGHJKMNPQRSTUVWXYZ-
```

- dígitos `2..9` (8) — excluye `0`, `1`
- letras `A B C D E F G H J K M N P Q R S T U V W X Y Z` (23) — excluye `I`, `L`, `O`
- `-` U+002D (1)
- **Total = 32.** Legibilidad original conservada: 0/O y 1/I/L nunca coexisten.

## 5. Mapeo completo índice → símbolo (0..31)

| índice | símbolo | índice | símbolo | índice | símbolo | índice | símbolo |
|---|---|---|---|---|---|---|---|
| 0 | `2` | 8 | `A` | 16 | `J` | 24 | `T` |
| 1 | `3` | 9 | `B` | 17 | `K` | 25 | `U` |
| 2 | `4` | 10 | `C` | 18 | `M` | 26 | `V` |
| 3 | `5` | 11 | `D` | 19 | `N` | 27 | `W` |
| 4 | `6` | 12 | `E` | 20 | `P` | 28 | `X` |
| 5 | `7` | 13 | `F` | 21 | `Q` | 29 | `Y` |
| 6 | `8` | 14 | `G` | 22 | `R` | 30 | `Z` |
| 7 | `9` | 15 | `H` | 23 | `S` | 31 | `-` |

Inverso (símbolo → índice): posición k-ésima del símbolo en la secuencia literal.
Sin ordenamiento implícito, sin alias.

## 6. Reglas documentadas (spec §4, ahora normativo)

Todas quedan definidas explícitamente en `PHASE_2_FINGERPRINT_SPEC.md` §4:

| Regla | Dónde |
|---|---|
| Nombre del formato | §4.1 (`ZONE Fingerprint v1`) |
| Versión del fingerprint | §4.1 (`v1`, sin versión nueva) |
| Alfabeto completo (literal) | §4.2 |
| Cardinalidad exacta | §4.2 (32) |
| Mapeo índices 0..31 | §4.3 (y §5 de este reporte) |
| Encoding 5 bits/símbolo | §4.4 (MSB-first, bit-packing RFC 4648 con alfabeto propio) |
| Conversión bits → símbolos | §4.4 (bit-stream → bloques de 5) |
| Reglas de truncamiento | §4.5 (primeros 20 símbolos; 100 bits; sin cortar bloc residual) |
| Longitud final | §4.5 (20 caracteres) |
| Reglas de normalización | §4.8 (upper; desagrupado posicional; validación; comparación) |
| Regla de mayúsculas/minúsculas | §4.8/§4.10 (MAYÚSCULAS canónico; ingesta case-insensitive) |
| Padding | §4.4/§4.10 (**NO** — prohibido) |
| Símbolos inválidos | §4.9 (fuera de alfabeto ⇒ rechazo) |
| Representación canónica | §4.6 (20 chars MAYÚSCULAS sin separadores) |
| Tratamiento del carácter `-` | §4.7 (símbolo literal U+002D + separador posicional del display) |
| Checksum | §4.10 (NO; opcional 1 char = decisión de producto, no bloquea) |

## 7. Reglas aún no definidas

- **KAT oficial de M1:** pendiente de finalización. Los vectores esperados quedan
  **preparados** (sección 15) y requieren revisión independiente antes de declararse
  VERIFIED.
- **Checksum opcional de 1 carácter (spec §4):** decisión de producto pendiente,
  explícitamente no bloqueante.
- **Alfabeto del bootstrap code (`PHASE_2_BOOTSTRAP_POLICY`, 8 chars / 32 símbolos):**
  nunca literalizado; hallazgo adyacente **fuera del scope de FASE 2.1** — se
  recomienda decidir en el milestone de bootstrap (M0/M1) si comparte alfabeto y
  mapeo con el fingerprint. No se actúa sobre ello aquí.
- **Reglas requeridas para calcular el KAT:** **no falta ninguna** tras la corrección
  (input canónico §3, SHA-256, alfabeto+mapeo, bit-packing, truncamiento, longitud,
  normalización, case, padding, inválidos, canónica, `-`). Conforme al mandato CTO §7,
  **no se crea un blocker adicional** por reglas ausentes.

## 8. Auditoría de documentación

| Documento | Hallazgo | Acción |
|---|---|---|
| `PHASE_2_FINGERPRINT_SPEC.md` | §4 defectuoso (31 literal / 32 declarado) | **Actualizado**: §4 normativo (§4.1–§4.10), §6 (KAT), §8 (nota corrección), header |
| `PHASE_2_CONSISTENCY_MATRIX.md` | §15:336 "Base32 RFC 4648 …" — redacción imprecisa (el alfabeto no es el estándar) | **Actualizado**: "bit-packing RFC 4648 (5 bits/símbolo, MSB-first) con alfabeto propio de 32 símbolos `23456789ABCDEFGHJKMNPQRSTUVWXYZ-`" |
| `PHASE_2_IDENTITY_ARCHITECTURE.md` | §7:294 "32 símbolos (evita 0/O, 1/I/L)" — sigue siendo cierta con el alfabeto corregido | Sin cambios (no obsoleto) |
| `PHASE_2_DEVICE_MODEL.md` | Referencias a `fingerprint v1` (columnas diseñadas) | Sin cambios |
| `PHASE_2_SECURITY_INVARIANTS.md` | I-017/I-026 citan formato, no alfabeto literal | Sin cambios |
| `PHASE_2_CTO_SIGNOFF_PACK.md` | :319 "32 símbolos, sin 0/O/1/I/L" — sigue siendo cierta | Sin cambios |
| `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md` | Sin referencias a alfabeto/Base32 | Sin cambios |
| `PHASE_2_DECISION_RESOLUTION.md` / `PHASE_2_OPEN_DECISIONS.md` / `PHASE_2_THREAT_MODEL.md` | Referencias al fingerprint v1 sin alfabeto literal | Sin cambios |
| `PHASE_2_BOOTSTRAP_POLICY.md` | Alfabeto de bootstrap citado sin literalizar | Sin cambios (fuera de scope) |
| `PHASE_2.1_BLOCKER_REPORT.md` | Registro histórico del bloqueo | **Actualizado**: header + §17/§18 (resolución y estado final) |
| `lib/identity/base32_unambiguous.dart` | Constante con 31 símbolos (sin `-`) — esqueleto sin integrar, en reposo | **Sin cambios** (fuera del scope documental; se corregirá en la implementación autorizada) |

## 9. Auditoría de compatibilidad

Verificaciones ejecutadas (mandato CTO §9):

- `grep fingerprint|Fingerprint|ZONE-FP-1` en `lib/`: **no existe implementación de
  fingerprint en código de producción**. Únicos hallazgos: un icono `Icons.fingerprint`
  en `login_screen.dart:75` (UI, sin relación) y el esqueleto `lib/identity/` **no
  integrado** (ningún archivo rastreado lo importa).
- `supabase/`: **ninguna** referencia a fingerprint/columnas (sin SQL, sin migraciones).
- Las columnas `account_identity.identity_fingerprint` y `devices.device_fingerprint`
  existen **solo como diseño** (`PHASE_2_IDENTITY_ARCHITECTURE.md`, `PHASE_2_DEVICE_MODEL.md`),
  nunca aplicadas.
- **Conclusión:** no existe fingerprint persistido, publicado ni usado por código
  activo. La corrección del formato se establece **antes** de la implementación ⇒
  **SPECIFICATION CORRECTION BEFORE IMPLEMENTATION**, sin impacto de compatibilidad en
  datos existentes. **No se requiere parada por impacto** (no aplica el párrafo de
  compatibilidad del mandato §9).

Nota UX documentada: dado que `-` es un símbolo válido, el display agrupado puede
contener `-` literales dentro de un grupo (p. ej. `GSCB6-GVT6D-NV8C8-3-845` o
`3WMSU-NKRR4--9WV4-333FH`). Esto es correcto por diseño: la desagrupación es
posicional (spec §4.7/§4.8) y la forma canónica de 20 caracteres es la única
normativa para comparación/QR/almacenamiento.

## 10. Estado de KAT

```
KAT: VERIFIED (2026-09-25)
```

- **Método de verificación:** reproducidos por **tres implementaciones independientes**
  (Python 3.14 stdlib `hashlib`/`base64`; Node.js v24 `node:crypto`; PowerShell 5.1 /
  .NET `SHA256`) más **traza grupal del bit-packing** (60 grupos = 20 × 3 vectores,
  todos coincidentes). Detalle completo: `PHASE_2.1_KAT_VERIFICATION_REPORT.md`.
- **Vectores verificados:** ACC, DEV-A, DEV-B/reinstall (sección 15) — los valores
  esperados coinciden campo a campo (input canónico, SHA-256, Base32 completo de 52,
  fingerprint de 20 chars, display 4×5).
- **Versión de especificación:** `FINGERPRINT_SPEC_V1` (corrección 2026-09-25).
- **Sin ambigüedad pendiente:** ninguna regla necesaria para el cálculo del KAT quedó
  sin definir; no se requirió corregir silenciosamente nada (verificación report §12).
  Los vectores quedan **oficiales** para la implementación autorizada (criterio M1,
  spec §6). KAT **no** integrado en código de producción.

## 11. Archivos modificados

- `docs/PHASE_2_FINGERPRINT_SPEC.md` — §4 normativo completo, §6, §8, header.
- `docs/PHASE_2_CONSISTENCY_MATRIX.md` — §15:336 (célula Codificación).
- `docs/PHASE_2.1_BLOCKER_REPORT.md` — header + §17/§18.
- `docs/PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md` — **nuevo** (este reporte).

## 12. Archivos no modificados

- `lib/` completo (código de producción y esqueleto `lib/identity/` en reposo),
  `test/`, `supabase/`, `pubspec.yaml`, `pubspec.lock`, `lib/models/isar_models.*`.
- `docs/PHASE_2_IDENTITY_ARCHITECTURE.md`, `PHASE_2_DEVICE_MODEL.md`,
  `PHASE_2_SECURITY_INVARIANTS.md`, `PHASE_2_CTO_SIGNOFF_PACK.md`,
  `PHASE_2.0.2_CTO_GATE.md`, `PHASE_2.0.3.1_FINAL_DOCUMENTATION_AUDIT.md`,
  `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`, `PHASE_2_DECISION_RESOLUTION.md`,
  `PHASE_2_OPEN_DECISIONS.md`, `PHASE_2_THREAT_MODEL.md`, `PHASE_2_BOOTSTRAP_POLICY.md`
  y resto de docs FASE 2.0 (sin contenido factualmente obsoleto).

## 13. Estado de FASE 2.1

```
FINGERPRINT SPECIFICATION: VERIFIED
KAT: VERIFIED
ALPHABET: 32 SYMBOLS (VERIFIED)
PRODUCTION CODE: lib/identity/ IMPLEMENTED (no integrado al bootstrap)
TEST SUITE: 73/73 PASSED (ver PHASE_2.1_IMPLEMENTATION_REPORT.md / _TEST_MATRIX.md)
SUPABASE CHANGES: NONE
PHASE 2.1 IMPLEMENTATION: VERIFIED (2026-09-25)
FASE 2.2 / INTEGRATION / MIGRATION: BLOCKED (no autorizadas)
CTO REVIEW: REQUIRED
```

**STOP.** La spec y el KAT del fingerprint v1 quedan **VERIFICADOS** y la fundación de
identidad de FASE 2.1 queda **implementada y testada (73/73)** como código aislado y sin
integrar al bootstrap de producción. Implementación integral (bootstrap de red, recovery,
multi-device, migraciones, UI, Supabase) sigue **sin autorizar**; no se inicia FASE 2.2.
Detalle: `PHASE_2.1_IMPLEMENTATION_REPORT.md`, `PHASE_2.1_TEST_MATRIX.md`,
`PHASE_2.1_SECURITY_EVIDENCE.md`.

## 14. Validaciones matemáticas y documentales (mandato CTO §6)

Procedimiento reproducible (Python 3, sin dependencias de terceros):

```python
import hashlib, base64

ALPHA = "23456789ABCDEFGHJKMNPQRSTUVWXYZ-"

# 1) Cardinalidad y unicidad
assert len(ALPHA) == 32
assert len(set(ALPHA)) == 32          # sin duplicados
# 2) Biyección índice -> símbolo (cada posición k -> ALPHA[k], sin alias)
for i, s in enumerate(ALPHA):
    assert ALPHA.index(s) == i
# 3) 5 bits representan exactamente 32 valores
assert 2**5 == 32
# 4) El guion es ASCII U+002D (43 decimal)
assert ALPHA[31] == "-" and ord(ALPHA[31]) == 0x2D
print("VALIDATION OK: 32 símbolos únicos, biyección 0..31, 5 bits, `-`=U+002D")

def b32(bys):
    out = []
    carry, bits = 0, 0
    for b in bys:                     # MSB-first, byte a byte
        carry = (carry << 8) | b
        bits += 8
        while bits >= 5:
            out.append(ALPHA[(carry >> (bits - 5)) & 0x1f])
            bits -= 5
    if bits > 0:                      # bloque residual completado con ceros
        out.append(ALPHA[(carry << (5 - bits)) & 0x1f])
    return "".join(out)
```

Resultado:

- ✅ el alfabeto contiene exactamente **32** símbolos;
- ✅ cada símbolo es **único** (sin duplicados);
- ✅ cada índice 0..31 tiene **exactamente un** símbolo (biyección posicional);
- ✅ ningún índice queda sin representación;
- ✅ ningún símbolo mapea a dos índices (`ALPHA.index(s) == i`);
- ✅ 32 valores representables con 5 bits (2^5 = 32);
- ✅ sin caracteres implícitos ni alias (`ALPHA` es el literal íntegro);
- ✅ el guion es exactamente `-` **U+002D** (índice 31);
- ✅ restricciones de legibilidad conservadas: `0`, `1`, `I`, `L`, `O` ausentes
  (los pares confundibles 0/O y 1/I/L nunca coexisten).

## 15. Vectores KAT (VERIFICADOS 2026-09-25)

Inputs y valores verificados (deterministas, documentales; **oficiales** según la
verificación independiente 2026-09-25):

| Vector | account_id | device_id | pk Ed25519 (32 bytes raw, base64) |
|---|---|---|---|
| **ACC** | `1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d` | — | `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=` (= bytes 0x00..0x1F) |
| **DEV-A** | `1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d` | `2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e` | `//79/Pv6+fj39vX08/Lx8O/u7ezr6uno5+bl5OPi4eA=` (= bytes 0xFF..0xE0) |
| **DEV-B** (reinstall) | `1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d` | `3c4d5e6f-7a8b-9c0d-1e2f-3a4b5c6d7e8f` | `gIGCg4SFhoeIiYqLjI2Oj5CRkpOUlZaXmJmam5ydnp8=` (= bytes 0x80..0x9F) |

Valores esperados (SHA-256 → Base32 completo → primeros 20 → display):

| Vector | Input canónico (hex) | SHA-256 (hex) | Base32 completo (52) | Fingerprint (20) | Display 4×5 |
|---|---|---|---|---|---|
| ACC | `5a4f4e452d46502d310041434331613262336334642d356536662d376138622d396330642d31653266336134623563366441414543417751464267634943516f4c4441304f4478415245684d554652595847426b61477877644868383d` | `75d4923b5822e7a328c1f9843aba09a0377a4d4cf084daadcbcad6f6b239ac6c` | `GSCB6GVT6DNV8C83-845QGJBP2WSPNCEZ44FQDGDUDDHFEKUQKR2` | `GSCB6GVT6DNV8C83-845` | `GSCB6-GVT6D-NV8C8-3-845` |
| DEV-A | `5a4f4e452d46502d310044455631613262336334642d356536662d376138622d396330642d31653266336134623563366432623363346435652d366637612d386239632d306431652d3266336134623563366437652f2f37392f5076362b666a3339765830382f4c78384f2f7537657a7236756e6f352b626c354f50693465413d` | `0ee57cce36b0be7de841085af92f8bf5db33421b61e28fc820037a77034ab0a9` | `3WMSUNKRR4-9WV4333FHMDXDZSFN8JJWE9KA-M322FY9G2VCR4PJ` | `3WMSUNKRR4-9WV4333FH` | `3WMSU-NKRR4--9WV4-333FH` |
| DEV-B | `5a4f4e452d46502d310044455631613262336334642d356536662d376138622d396330642d31653266336134623563366433633464356536662d376138622d396330642d316532662d3361346235633664376538666749474367345346686f65496959714c6a49324f6a3543526b704f556c5a61586d4a6d616d3579646e70383d` | `9f51dd065a4c2804d55cf091b9b2bf2d772d61f374a8cadc59f77cc04121e4be` | `NYAYV3MVBJP2BQCXZ4AWNEQ-7QWMVTHNGMPEQS4UZYZE2JB3XM-2` | `NYAYV3MVBJP2BQCXZ4AW` | `NYAYV-3MVBJ-P2BQC-XZ4AW` |

Observaciones de demostración del tratamiento de `-` (spec §4.7):

- El vector **ACC** contiene un `-` símbolo literal en la posición 16 (0-based) del
  texto canónico (grupo 4 = `3-845`).
- El vector **DEV-A** muestra un `-` literal precediendo al separador en el display
  (`3WMSU-NKRR4--9WV4-333FH`); la desagrupación posicional elimina solo el separador
  de la posición 11 (0-based) → `3WMSUNKRR4-9WV4333FH`.
- El vector **DEV-B** contiene un `-` símbolo dentro del Base32 completo
  (posición 24) sin afectar a los primeros 20 caracteres.

**KAT STATUS: VERIFIED (2026-09-25)** — los tres vectores fueron reproducidos por
implementaciones independientes (Python 3.14 stdlib, Node.js v24 `node:crypto`,
PowerShell 5.1/.NET SHA-256) y por una traza grupo a grupo del bit-packing (60
grupos, todos coincidentes). Evidencia y procedimiento:
`PHASE_2.1_KAT_VERIFICATION_REPORT.md`. Los vectores quedan **oficiales** para la
implementación autorizada (criterio M1, spec §6).