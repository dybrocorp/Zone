# PHASE 2.0.2 — Fingerprint Specification v1 (FINGERPRINT_SPEC_V1)

> **Tipo:** Especificación canónica del fingerprint — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** RESOLVED — CTO PROPOSED (pendiente firma humana)
> **Corrección §4 (decisión CTO 2026-09-25, OPTION A):** alfabeto fijado a 32 símbolos —
> ver §4 y `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md`
> **Resuelve:** R-002 (C5) · R-014 (C2) · OPEN-002 · OPEN-016
> **Deroga el formato antiguo:** "7 letras" / hash de `identity_pk ‖ x25519_pk`
> (`CRYPTO_CTO_REVIEW.md` §5.1:213, §5.2:254-255, §10:388)
> **Invariantes:** I-017 (revisado) · I-026 (nuevo)

---

## 1. Principios

1. El fingerprint es una **verificación humana out-of-band**, **no** un secreto y **no**
   una credencial (prohibido por I-026). Su conocimiento no concede ninguna operación.
2. El fingerprint identifica a un **poseedor de clave de firma** (Ed25519), **jamás** una
   clave de cifrado que rota.
3. **La X25519 NUNCA entra en el input de un fingerprint** (estabilidad ante rotación +
   separación de roles, D2).
4. Dos implementaciones independientes deben producir exactamente los mismos bytes ⇒
   canonicalización estricta (§3) + **KAT obligatorio** en M1 (test vector oficial).

## 2. Dos fingerprints

Existen **dos** fingerprints, con inputs distintos:

| | ACCOUNT_FINGERPRINT | DEVICE_FINGERPRINT |
|---|---|---|
| Identifica | La cuenta (identity Ed25519) | Un dispositivo concreto (device Ed25519) |
| Input canónico | `"ZONE-FP-1\0" ‖ "ACC" ‖ account_id ‖ identity_public_key` | `"ZONE-FP-1\0" ‖ "DEV" ‖ account_id ‖ device_id ‖ device_public_key` |
| Largo/encoding | 20 chars Base32 (ver §4) | 20 chars Base32 (ver §4) |
| Presentación | 4 grupos × 5: `XXXXX-XXXXX-XXXXX-XXXXX` | 4 grupos × 5 |
| Estabilidad | Cambia solo si rota la Ed25519 de cuenta (OPEN-013) | Cambia si cambia el device o su Ed25519 (incl. reinstalación con device nuevo) |
| NO cambia con | Rotación de X25519 (v1→v3→v5) | Rotación de X25519 |
| Dónde se muestra | Alta de devices, recovery, transfer, lista de devices | Primer contacto mesh (M3), alta de device (QR/comparación), lista de devices |
| Para qué sirve | Verificar que se está vinculando a la cuenta correcta | Verificar que el peer mesh/device es el esperado (anti-MITM) |
| ¿Autenticación? | NO — verificación humana; la autenticación la hacen las firmas Ed25519 | NO — idem |

## 3. Input canónico (lenguaje máquina)

```
fp_input(kind, account_id, actor_id, pk_ed25519):
  utf8("ZONE-FP-1\0")                    # prefijo de versión; el byte NUL es PARTE del input
  ∥ utf8(kind)                           # "ACC" (3 bytes) o "DEV" (3 bytes)
  ∥ utf8(uuid_canonical(account_id))     # lowercase, con guiones, ASCII
  ∥ [si DEV:] utf8(uuid_canonical(device_id))
  ∥ base64_std_padded(pk_ed25519)        # 32 bytes crudos → 44 chars, con '=' padding

digest  = SHA-256(fp_input)
fp_text = base32_unambiguous(digest)     # ver §4 — 52 chars
fingerprint = grupos(primeros 20 chars)  # XXXX-XXXX-XXXX-XXXX
```

Canonicalización obligatoria (parte de OPEN-015):
- UUIDs: lowercase con guiones (RFC 4122 text).
- Clave pública Ed25519: los 32 bytes crudos de la key (Raw bytes del punto, sin compresión
  de objeto), codificados **Standard Base64 con padding** (44 chars) — fijado en §espec
  canónica §14.
- UTF-8 estricto; sin BOM; sin normalización Unicode (todo ASCII).

## 4. Alfabeto y encoding (NORMA)

> **Corrección (decisión CTO, 2026-09-25):** esta sección queda normativa y completa.
> Corrige la contradicción original (el spec declaraba 32 símbolos y escribía 31 —
> no existía símbolo para el índice 31). La corrección se registra como
> **SPECIFICATION CORRECTION BEFORE IMPLEMENTATION**: no hay formato publicado,
> fingerprints persistidos ni KAT oficial; **no** crea una versión de fingerprint
> nueva. Detalle: `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md`.

### 4.1 Nombre y versión del formato

- **Nombre:** ZONE Fingerprint v1.
- **Versión:** v1 (prefijo `"ZONE-FP-1\0"` en el input canónico, §3).

### 4.2 Alfabeto normativo — 32 símbolos (literal)

```
23456789ABCDEFGHJKMNPQRSTUVWXYZ-
```

- 8 dígitos: `2 3 4 5 6 7 8 9` (excluye `0` y `1`).
- 23 letras MAYÚSCULAS: `A B C D E F G H J K M N P Q R S T U V W X Y Z` (excluye `I`, `L`, `O`).
- 1 símbolo adicional: `-` (ASCII **U+002D**).
- **Total: 32.** Se conservan las exclusiones de legibilidad del diseño original
  (los pares confundibles 0/O y 1/I/L nunca coexisten; `0`, `1`, `I`, `L`, `O` quedan
  fuera del alfabeto).

### 4.3 Mapeo índice → símbolo (biyección 0..31)

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

Inverso (símbolo → índice): posición k-ésima del símbolo en la secuencia literal
`2 3 4 5 6 7 8 9 A B C D E F G H J K M N P Q R S T U V W X Y Z -`. Sin ordenamiento
implícito ni alias.

### 4.4 Codificación — 5 bits por símbolo

Hash: SHA-256 (RFC 6234).

1. `digest = SHA-256(fp_input)` — 32 bytes; input canónico §3.
2. Bit-stream de los 32 bytes del digest: **MSB-first, byte a byte** (el bit más
   significativo del byte 0 es el primero). El bit-packing es el del Base32 RFC 4648,
   pero aplicado con el alfabeto propio §4.2 (el alfabeto **NO** es el estándar de
   RFC 4648).
3. Agrupar el stream en bloques de 5 bits; cada bloque vale 0..31 y se codifica con
   el símbolo del §4.3.
4. **Sin padding** de salida (`=` prohibido) ni símbolos de relleno.
5. La codificación completa de 256 bits produce **52 símbolos**: 51 bloques completos
   de 5 (255 bits) + 1 bloque final que transporta el bit restante (1 bit, completado
   con ceros a la derecha).

### 4.5 Truncamiento y longitud

- Longitud del fingerprint: **20 caracteres** = primeros 20 símbolos de la
  codificación completa (**100 bits** = 20 bloques completos; el truncado no corta
  ningún bloque residual).
- Los 32 símbolos restantes se descartan y no forman parte del fingerprint.

### 4.6 Representación canónica

- **Canónica (normativa):** 20 caracteres MAYÚSCULAS sin separadores; puede contener
  `-` como símbolo literal. Ej.: `GSCB6GVT6DNV8C83-845`.
- **Display (derivada, cosmética):** 4 grupos de 5 unidos por el separador `-`
  (U+002D) en posiciones fijas (tras el 5º, 10º y 15º carácter). Ej.:
  `GSCB6-GVT6D-NV8C8-3-845`.
- Almacenamiento, QR y comparación usan **siempre** la forma canónica.

### 4.7 Tratamiento del carácter `-` (U+002D)

- Dentro del texto canónico de 20 caracteres es un **símbolo literal** (índice 31):
  no es separador, operador ni carácter opcional.
- En el display actúa además como **separador de grupo** en posiciones fijas
  (5ª, 11ª y 17ª del string de 23 caracteres, contando desde 0).
- **Desagrupación posicional:** para derivar la forma canónica desde un display se
  eliminan **solo** los separadores de las posiciones fijas 5/11/17; cualquier otro
  `-` es símbolo y se conserva. El procedimiento es determinista incluso cuando un
  `-` literal precede a un separador (p. ej. `3WMSU-NKRR4--9WV4-333FH` →
  `3WMSUNKRR4-9WV4333FH`).

### 4.8 Normalización (comparación)

1. `upper(s)` — ingesta case-insensitive (todo se compara en MAYÚSCULAS).
2. Si la longitud es 23 y los caracteres en las posiciones 5, 11 y 17 (0-based) son
   `-` → eliminarlos (desagrupar §4.7) y esperar 20 caracteres.
3. Si la longitud es 20 → continuar.
4. Validar que todo carácter ∈ alfabeto §4.2.
5. Comparar por igualdad byte a byte de las formas canónicas.

### 4.9 Símbolos inválidos

- Tras la normalización §4.8, cualquier carácter fuera del alfabeto §4.2 es
  **inválido** ⇒ validación rechazada (no-match).
- En una entrada de 23 caracteres, un `-` en posición distinta de 5/11/17 (0-based),
  o una entrada de longitud distinta de 20/23 con separadores, es **inválida**
  (rechazar; no corregir).

### 4.10 Síntesis

| | Valor |
|---|---|
| Formato / versión | ZONE Fingerprint v1 (`ZONE-FP-1`) |
| Hash | SHA-256 (RFC 6234) |
| Encoding | 5 bits/símbolo, MSB-first (bit-packing RFC 4648, alfabeto propio §4.2) |
| Alfabeto | `23456789ABCDEFGHJKMNPQRSTUVWXYZ-` |
| Cardinalidad | **32** (biyección 0..31, §4.3) |
| Codificación completa | 52 símbolos (256 bits) |
| Fingerprint | 20 primeros símbolos = **100 bits** |
| Longitud | 20 caracteres |
| Display | 4×5, separador `-` en posiciones fijas (§4.6/§4.7) |
| Case | MAYÚSCULAS canónico; ingesta normaliza a MAYÚSCULAS (§4.8) |
| Padding | **NO** — prohibido |
| Checksum | **NO** (100 bits; checksum opcional de 1 carácter = decisión de producto, no bloquea el spec) |
| Símbolos inválidos | fuera de alfabeto ⇒ rechazo (§4.9) |

Ejemplos de display (posiciones fijas; no deterministas por diseño):
`FP7GK-3KQ9W-MJ2X8-PDVTC` (sin `-` literal) · `GSCB6-GVT6D-NV8C8-3-845` (el grupo 4
es `3-845`, con `-` literal U+002D como símbolo).

## 5. Reglas de uso

1. **Nunca** usar el fingerprint como entrada de autenticación (ni clave de RPC, ni "prueba
   de posesión", ni de recovery). I-026.
2. En **mesh (M3)**: se compara el **DEVICE_FINGERPRINT** del emisor (OPEN-016). El
   ACCOUNT_FINGERPRINT se usa en flujos de cuenta (alta de device, recovery, transfer).
3. En **QR de alta de device (D4/OPEN-005)**: el QR transporta el `device_fingerprint` del
   device nuevo como dato de comparación y de binding (nunca como secreto).
4. Los fingerprints de cuenta y device se almacenan en `account_identity.identity_fingerprint`
   y `devices.device_fingerprint` (campos ya diseñados).
5. El handshake `profile_exchange v2` (M3) incluye `device_pk` + `device_fingerprint` y la
   firma Ed25519 sobre el transcript; si el fingerprint previamente anclado difiere ⇒ abortar
   (posible reinstall o MITM).

## 6. Determinismo entre implementaciones — criterio

- Mismo input canónico (§3) + mismo alfabeto (§4) + misma canonicalización ⇒ mismo texto.
- El **KAT del fingerprint v1** se fija en M1 con al menos 3 vectores (cuenta, device,
  reinstall) y se ejecuta contra la implementación `cryptography` de referencia
  (Ed25519 bytes RAW → SHA-256 → Base32).
- **Estado (2026-09-25):** **KAT VERIFIED.** Los 3 vectores (cuenta, device, reinstall)
  definidos en `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md` §15 fueron reproducidos por
  **tres implementaciones independientes** (Python stdlib, Node.js `node:crypto`,
  PowerShell/.NET SHA-256) más traza manual del bit-packing (60 grupos, todos
  coincidentes). Detalle: `PHASE_2.1_KAT_VERIFICATION_REPORT.md`.

## 7. Actualizaciones documentales

- `CRYPTO_CTO_REVIEW.md` §5.1:213 · §5.2:254-255 · §10:388 → reemplazado por esta spec.
- `PHASE_2_IDENTITY_ARCHITECTURE.md` §7 (ya canónico) → gana esta spec como autoridad.
- `PHASE_2_THREAT_MODEL.md` T6/T16 → mitigación "fingerprint v1 (SPEC)".
- `PHASE_2_DEVICE_MODEL.md` §3/§5.2 → referencia a `fingerprint v1`.

## 8. Estado

> **RESOLVED — CTO PROPOSED** (ACCOUNT_FINGERPRINT + DEVICE_FINGERPRINT, sin X25519 en el
> input, Base32 20 chars). Aprobación final: humano/CTO.
>
> **Corrección aplicada (2026-09-25, decisión CTO OPTION A):** §4 quedó normativo con el
> alfabeto de 32 símbolos `23456789ABCDEFGHJKMNPQRSTUVWXYZ-` (índice 31 = `-` U+002D),
> mapeo 0..31 cerrado y 5 bits/símbolo — **SPECIFICATION CORRECTION BEFORE
> IMPLEMENTATION** (sin formato publicado ni fingerprints persistidos). No modifica
> SHA-256, inputs canónicos, longitud, versión ni canonicalización. Detalle:
> `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md`.