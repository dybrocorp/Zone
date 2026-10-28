# PHASE 2.1-KAT — Independent Fingerprint KAT Verification Report

> **Tipo:** Gate de verificación independiente de los KAT del fingerprint v1 (masa CTO).
> **Fecha:** 2026-09-25 · **Resultado:** KAT VERIFIED (3/3 vectores)
> **Autoridad:** `PHASE_2_FINGERPRINT_SPEC.md` (spec corregida) ·
> `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md` (vectores) ·
> `PHASE_2.1_BLOCKER_REPORT.md` (registro del bloqueo)

---

## 1. Versión de especificación

- **Formato:** ZONE Fingerprint v1 (`ZONE-FP-1`).
- **Versión:** `FINGERPRINT_SPEC_V1` — corrección 2026-09-25 (decisión CTO OPTION A).
- **Puntos de la spec aplicados:** §3 (input canónico), §4.2–§4.5 (alfabeto, mapeo,
  encoding, truncamiento), §4.8 (normalización) — sin modificación.

## 2. Alfabeto

```
23456789ABCDEFGHJKMNPQRSTUVWXYZ-
```

Validación ejecutada (Python y Node, ambas):

- `len(alphabet) == 32` ✅
- 32 símbolos únicos (sin duplicados) ✅
- índice 0→`2`, 1→`3`, …, 7→`9`, 8→`A`, …, 15→`H`, 16→`J`, …, 23→`S`,
  24→`T`, …, 30→`Z`, 31→`-` — biyección exacta (comprobada posición a posición,
  `ALPHA.index(ALPHA[i]) == i` para i = 0..31) ✅
- `2^5 = 32` ⇒ cada valor de 5 bits 0..31 tiene **exactamente un** símbolo ✅
- `-` = ASCII U+002D (0x2D) ✅
- Sin caracteres implícitos ni alias: el literal íntegro es la única fuente ✅

## 3. Método de verificación independiente

Tres implementaciones independientes **sin ninguna dependencia de `lib/identity/`,
código de producción ni valores cacheados**, escritas únicamente a partir del texto
del spec:

| Ruta | Runtime | Hash | Base32 |
|---|---|---|---|
| A | Python 3.14.6 (stdlib) | `hashlib.sha256` | bit-stream propio (5 bits, MSB-first, alfabeto ZONE) |
| B | Node.js v24.18.0 | `node:crypto` `createHash('sha256')` | bit-stream propio (independiente) |
| C | PowerShell 5.1 / .NET Framework | `System.Security.Cryptography.SHA256` | — (solo cross-check del digest) |

Además, **traza grupo a grupo del bit-packing** (60 grupos = 20 × 3 vectores)
generada de forma explícita desde los bytes del digest (secciones 4–6).

Cada ruta reconstruyó el **input canónico desde los parámetros documentados**
(account_id, [device_id], pk base64 de 32 bytes) siguiendo el spec §3, verificó el
round-trip `pk b64 → 32 bytes raw → pk b64` (Standard Base64 con padding) y comparó
**campo a campo** contra los valores esperados documentados. No se alteró ningún
valor esperado para obtener coincidencia.

## 4. Vector ACC

| Para | Valor |
|---|---|
| kind | `ACC` |
| account_id | `1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d` |
| pk Ed25519 (32 raw) | `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=` (= 0x00..0x1F) |
| Input canónico (hex) | `5a4f…383d` (ver §7) |
| SHA-256 (hex) | `75d4923b5822e7a328c1f9843aba09a0377a4d4cf084daadcbcad6f6b239ac6c` |
| Bit-packing (Base32 completo, 52) | `GSCB6GVT6DNV8C83-845QGJBP2WSPNCEZ44FQDGDUDDHFEKUQKR2` |
| Fingerprint calculado (20) | `GSCB6GVT6DNV8C83-845` |
| Fingerprint esperado (20) | `GSCB6GVT6DNV8C83-845` |
| **MATCH** | **SÍ (todas las rutas)** |

Traza grupo a grupo (bits 0..99 del digest):

| # | bits | val | →` | exp | ✓ | # | bits | val | →` | exp | ✓ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 01110 | 14 | G | G | ✓ | 10 | 10011 | 19 | N | N | ✓ |
| 1 | 10111 | 23 | S | S | ✓ | 11 | 11010 | 26 | V | V | ✓ |
| 2 | 01010 | 10 | C | C | ✓ | 12 | 00110 | 6 | 8 | 8 | ✓ |
| 3 | 01001 | 9 | B | B | ✓ | 13 | 01010 | 10 | C | C | ✓ |
| 4 | 00100 | 4 | 6 | 6 | ✓ | 14 | 00110 | 6 | 8 | 8 | ✓ |
| 5 | 01110 | 14 | G | G | ✓ | 15 | 00001 | 1 | 3 | 3 | ✓ |
| 6 | 11010 | 26 | V | V | ✓ | 16 | **11111** | **31** | **-** | **-** | ✓ |
| 7 | 11000 | 24 | T | T | ✓ | 17 | 00110 | 6 | 8 | 8 | ✓ |
| 8 | 00100 | 4 | 6 | 6 | ✓ | 18 | 00010 | 2 | 4 | 4 | ✓ |
| 9 | 01011 | 11 | D | D | ✓ | 19 | 00011 | 3 | 5 | 5 | ✓ |

El grupo 16 ejercita el índice 31 (`11111` → `-`).

## 5. Vector DEV-A

| Para | Valor |
|---|---|
| kind | `DEV` |
| account_id | `1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d` |
| device_id | `2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e` |
| pk Ed25519 (32 raw) | `//79/Pv6+fj39vX08/Lx8O/u7ezr6uno5+bl5OPi4eA=` (= 0xFF..0xE0) |
| Input canónico (hex) | `5a4f…413d` (ver §7) |
| SHA-256 (hex) | `0ee57cce36b0be7de841085af92f8bf5db33421b61e28fc820037a77034ab0a9` |
| Bit-packing (Base32 completo, 52) | `3WMSUNKRR4-9WV4333FHMDXDZSFN8JJWE9KA-M322FY9G2VCR4PJ` |
| Fingerprint calculado (20) | `3WMSUNKRR4-9WV4333FH` |
| Fingerprint esperado (20) | `3WMSUNKRR4-9WV4333FH` |
| **MATCH** | **SÍ (todas las rutas)** |

Traza grupo a grupo (bits 0..99 del digest):

| # | bits | val | →` | exp | ✓ | # | bits | val | →` | exp | ✓ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 00001 | 1 | 3 | 3 | ✓ | 10 | **11111** | **31** | **-** | **-** | ✓ |
| 1 | 11011 | 27 | W | W | ✓ | 11 | 00111 | 7 | 9 | 9 | ✓ |
| 2 | 10010 | 18 | M | M | ✓ | 12 | 11011 | 27 | W | W | ✓ |
| 3 | 10111 | 23 | S | S | ✓ | 13 | 11010 | 26 | V | V | ✓ |
| 4 | 11001 | 25 | U | U | ✓ | 14 | 00010 | 2 | 4 | 4 | ✓ |
| 5 | 10011 | 19 | N | N | ✓ | 15 | 00001 | 1 | 3 | 3 | ✓ |
| 6 | 10001 | 17 | K | K | ✓ | 16 | 00001 | 1 | 3 | 3 | ✓ |
| 7 | 10110 | 22 | R | R | ✓ | 17 | 00001 | 1 | 3 | 3 | ✓ |
| 8 | 10110 | 22 | R | R | ✓ | 18 | 01101 | 13 | F | F | ✓ |
| 9 | 00010 | 2 | 4 | 4 | ✓ | 19 | 01111 | 15 | H | H | ✓ |

El grupo 10 ejercita el índice 31 (`11111` → `-`) — el `-` literal del display
`3WMSU-NKRR4--9WV4-333FH` (spec §4.7: desagrupación posicional).

## 6. Vector DEV-B (reinstall)

| Para | Valor |
|---|---|
| kind | `DEV` |
| account_id | `1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d` |
| device_id | `3c4d5e6f-7a8b-9c0d-1e2f-3a4b5c6d7e8f` |
| pk Ed25519 (32 raw) | `gIGCg4SFhoeIiYqLjI2Oj5CRkpOUlZaXmJmam5ydnp8=` (= 0x80..0x9F) |
| Input canónico (hex) | `5a4f…383d` (ver §7) |
| SHA-256 (hex) | `9f51dd065a4c2804d55cf091b9b2bf2d772d61f374a8cadc59f77cc04121e4be` |
| Bit-packing (Base32 completo, 52) | `NYAYV3MVBJP2BQCXZ4AWNEQ-7QWMVTHNGMPEQS4UZYZE2JB3XM-2` |
| Fingerprint calculado (20) | `NYAYV3MVBJP2BQCXZ4AW` |
| Fingerprint esperado (20) | `NYAYV3MVBJP2BQCXZ4AW` |
| **MATCH** | **SÍ (todas las rutas)** |

Traza grupo a grupo (bits 0..99 del digest):

| # | bits | val | →` | exp | ✓ | # | bits | val | →` | exp | ✓ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 10011 | 19 | N | N | ✓ | 10 | 10100 | 20 | P | P | ✓ |
| 1 | 11101 | 29 | Y | Y | ✓ | 11 | 00000 | 0 | 2 | 2 | ✓ |
| 2 | 01000 | 8 | A | A | ✓ | 12 | 01001 | 9 | B | B | ✓ |
| 3 | 11101 | 29 | Y | Y | ✓ | 13 | 10101 | 21 | Q | Q | ✓ |
| 4 | 11010 | 26 | V | V | ✓ | 14 | 01010 | 10 | C | C | ✓ |
| 5 | 00001 | 1 | 3 | 3 | ✓ | 15 | 11100 | 28 | X | X | ✓ |
| 6 | 10010 | 18 | M | M | ✓ | 16 | 11110 | 30 | Z | Z | ✓ |
| 7 | 11010 | 26 | V | V | ✓ | 17 | 00010 | 2 | 4 | 4 | ✓ |
| 8 | 01001 | 9 | B | B | ✓ | 18 | 01000 | 8 | A | A | ✓ |
| 9 | 10000 | 16 | J | J | ✓ | 19 | 11011 | 27 | W | W | ✓ |

## 7. Valores SHA-256 intermedios

| Vector | Input canónico reconstruido (hex) | Digest SHA-256 (hex) | Coincide .NET |
|---|---|---|---|
| ACC | `5a4f4e452d46502d310041434331613262336334642d356536662d376138622d396330642d31653266336134623563366441414543417751464267634943516f4c4441304f4478415245684d554652595847426b61477877644868383d` | `75d4923b5822e7a328c1f9843aba09a0377a4d4cf084daadcbcad6f6b239ac6c` | ✅ |
| DEV-A | `5a4f4e452d46502d310044455631613262336334642d356536662d376138622d396330642d31653266336134623563366432623363346435652d366637612d386239632d306431652d3266336134623563366437652f2f37392f5076362b666a3339765830382f4c78384f2f7537657a7236756e6f352b626c354f50693465413d` | `0ee57cce36b0be7de841085af92f8bf5db33421b61e28fc820037a77034ab0a9` | ✅ |
| DEV-B | `5a4f4e452d46502d310044455631613262336334642d356536662d376138622d396330642d31653266336134623563366433633464356536662d376138622d396330642d316532662d3361346235633664376538666749474367345346686f65496959714c6a49324f6a3543526b704f556c5a61586d4a6d616d3579646e70383d` | `9f51dd065a4c2804d55cf091b9b2bf2d772d61f374a8cadc59f77cc04121e4be` | ✅ |

Los input hex reconstruidos son **idénticos byte a byte** a los documentados en la
resolución §15 (round-trip base64→bytes→base64 verificado en Python y Node).

## 8. Fingerprints finales calculados

| Vector | Fingerprint canónico (20) | Display 4×5 |
|---|---|---|
| ACC | `GSCB6GVT6DNV8C83-845` | `GSCB6-GVT6D-NV8C8-3-845` |
| DEV-A | `3WMSUNKRR4-9WV4333FH` | `3WMSU-NKRR4--9WV4-333FH` |
| DEV-B | `NYAYV3MVBJP2BQCXZ4AW` | `NYAYV-3MVBJ-P2BQC-XZ4AW` |

## 9. Fingerprints esperados

Idénticos a la sección 8 — los documentados en `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md`
§15 (inputs fijos de la spec; ver §4–§6 de este reporte).

## 10. Resultados de la comparación

| Campo comparado | ACC | DEV-A | DEV-B |
|---|---|---|---|
| Input canónico (hex) | ✅ | ✅ | ✅ |
| SHA-256 (hex) | ✅ | ✅ | ✅ |
| Base32 completo (52) | ✅ | ✅ | ✅ |
| Fingerprint (20) | ✅ | ✅ | ✅ |
| Display 4×5 | ✅ | ✅ | ✅ |
| Traza grupo a grupo (20 grupos) | ✅ 20/20 | ✅ 20/20 | ✅ 20/20 |

**Resultado: KAT STATUS = VERIFIED (3/3 vectores).** La ruta C (.NET SHA-256) confirma
los tres digests; las rutas A y B confirman además input, bit-packing y salida. No se
modificó ningún valor esperado.

## 11. Procedimiento de reproducibilidad

Reproducible únicamente desde el spec (sin código Dart ni caches). Scripts íntegros
ejecutados (resumen las tres rutas):

**Ruta A — Python 3.14 (stdlib):**

```python
import hashlib, base64

ALPHA = "23456789ABCDEFGHJKMNPQRSTUVWXYZ-"
assert len(ALPHA) == 32 and len(set(ALPHA)) == 32 and ALPHA[31] == "-" and ord(ALPHA[31]) == 0x2D

def b32(bys):
    out, carry, bits = [], 0, 0
    for b in bys:
        carry = (carry << 8) | b; bits += 8
        while bits >= 5:
            out.append(ALPHA[(carry >> (bits - 5)) & 0x1f]); bits -= 5
    if bits > 0: out.append(ALPHA[(carry << (5 - bits)) & 0x1f])
    return "".join(out)

def make_input(kind, account_id, device_id, pk_b64):
    pk = base64.b64decode(pk_b64, validate=True)
    assert len(pk) == 32 and base64.b64encode(pk).decode() == pk_b64
    parts = [b"ZONE-FP-1\x00", kind.encode(), account_id.encode()]
    if device_id: parts.append(device_id.encode())
    parts.append(base64.b64encode(pk))
    return b"".join(parts)

def fp(kind, account_id, device_id, pk_b64):
    inp = make_input(kind, account_id, device_id, pk_b64)
    full = b32(hashlib.sha256(inp).digest())
    assert len(full) == 52
    text = full[:20]
    return inp.hex(), hashlib.sha256(inp).hexdigest(), full, text, "-".join(text[i:i+5] for i in range(0, 20, 5))
```

**Ruta B — Node.js v24 (`node:crypto`):** equivalente (bit-stream propio, `Buffer`/
`createHash('sha256').digest()`); ver §3. **Ruta C — PowerShell 5.1 (.NET):**
`[System.Security.Cryptography.SHA256]::Create().ComputeHash([byte[]]…)` sobre los
input hex documentados; compara digest.

**Ruta de traza:** los grupos se derivaron de los bytes del digest
(`bits = "".join(f"{b:08b}" for b in digest)` → grupos de 5 → valor → `ALPHA[valor]`).

## 12. Ambigüedades descubiertas

**Ninguna.** Todas las reglas necesarias para el cálculo del KAT estaban definidas en
el spec corregido (input canónico §3; alfabeto/mapeo/bit-packing/truncamiento/longitud
§4.2–§4.5; normalización/case/padding §4.8). No se corrigió silenciosamente ninguna
ambigüedad; no se usaron constantes ocultas ni transformaciones no documentadas. Los
únicos defectos encontrados durante el gate fueron **errores de herramienta en los
scripts de verificación** (Push de string a `Buffer.concat` en Node; APIs .NET 5
ausentes en PowerShell 5.1), corregidos y re-ejecutados sin afectar a los vectores.

## 13. Archivos modificados

- `docs/PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md` — §10 (KAT: VERIFIED), §13 (estado
  FASE 2.1), §15 (vectores oficiales).
- `docs/PHASE_2_FINGERPRINT_SPEC.md` — §6 (estado KAT).
- `docs/PHASE_2.1_KAT_VERIFICATION_REPORT.md` — **nuevo** (este reporte).

## 14. Estado Git

- `HEAD`: `7f59b776c62cc131fd05dc999e99cbb7804385e8` (sin cambios).
- `git diff` / `git diff --cached` (rastreados): **vacíos** — cero modificaciones,
  cero staging, cero commits.
- Untracked esperados: 23 docs FASE 2.0/2.1 (incl. el nuevo reporte) + esqueleto
  `lib/identity/` sin integrar. Sin secretos ni claves generados en el repositorio.

## 15. Estado del código de producción y veredicto

- **Código de producción:** **sin cambios** — no se implementó fingerprint, no se tocó
  `lib/`, `test/`, `supabase/`, `pubspec.yaml`, ni el crypto legacy; no se generaron
  claves; no se integró identidad/device ni migraciones.
- La implementación de producción permanece **bloqueada** hasta la revisión CTO.

```
FINGERPRINT SPECIFICATION: VERIFIED
KAT: VERIFIED
PRODUCTION IMPLEMENTATION: NOT YET IMPLEMENTED
PHASE 2.1: READY FOR CTO IMPLEMENTATION REVIEW
```

**STOP.** No se continúa hacia la implementación de identidad ni de dispositivos.
Se espera la revisión del CTO para autorizar la implementación.