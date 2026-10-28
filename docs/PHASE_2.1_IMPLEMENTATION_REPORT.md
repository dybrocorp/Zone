# PHASE 2.1 — Implementación de la fundación de identidad (IMPLEMENTATION REPORT)

> **Tipo:** Reporte de implementación autorizada de FASE 2.1 (masa CTO).
> **Fecha:** 2026-09-25 · **Resultado:** `PHASE 2.1 IMPLEMENTATION: VERIFIED` — tests 73/73.
> **Autoridad:** `PHASE_2_FINGERPRINT_SPEC.md` (spec corregida) ·
> `PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md` (vectores oficiales) ·
> `PHASE_2.1_KAT_VERIFICATION_REPORT.md` (KAT VERIFIED 3/3) ·
> `PHASE_2_SECURITY_INVARIANTS.md` (I-001…I-030) ·
> `PHASE_2_BOOTSTRAP_POLICY.md` §4 (máquina I-030) ·
> `PHASE_2_CRYPTO_DECISIONS.md` (D1/D2).

---

## 1. Alcance autorizado y frontera

Autorizado por CTO (2026-09-25) tras el gate de KAT: **implementar FASE 2.1** =
fingerprint v1 + claves Ed25519/X25519 + almacén seguro + persistencia Isar + tests KAT
+ 3 reportes. Reglas invariables aplicadas:

- **FASE 2.2 NO está autorizada.** No se implementó bootstrap de red, recovery,
  rotación, multi-device, transfer ni ninguna operación servidor/UI.
- **Sin costos de integración:** `lib/identity/` **no está integrado** al bootstrap de
  producción. `lib/services/initial_loading_screen.dart`,
  `lib/services/isar_service.dart`, `lib/services/zone_id_service.dart`, `pubspec.yaml`
  y todo el código legacy quedaron **sin tocar** (§5).
- Cada fase de la máquina de estados y cada domino criptográfico se validó con tests
  **independientes de las constantes** (evidencia intermedia, KAT no circulares).
- Seed/claves privadas: **nunca** en Isar, logs, JSON plano, `.env`, git ni Supabase
  (I-004). El almacén seguro es el único hogar.

## 2. Inventario de la implementación

### 2.1 `lib/identity/` — 14 archivos, 188 159 bytes

| Archivo | Rol (autoridad) |
|---|---|
| `base32_unambiguous.dart` | Alfabeto normativo de 32 símbolos `23456789ABCDEFGHJKMNPQRSTUVWXYZ-`, biyección 0..31, bit-packing MSB-first 5 bits, normalización posicional §4.8 (fail-closed), `groupFingerprint` 4×5 §4.7 |
| `canonical.dart` | Canonicalización de UUID (RFC 4122) y Base64 estándar con padding para el input §3 |
| `fingerprint_service.dart` | `FingerprintComputation` (kind, inputHex, sha256Hex, fullBase32, symbolIndices, text, display) + `accountFingerprint`/`deviceFingerprint` §3–§6 |
| `ed25519_identity_service.dart` | Identidad de **firma** Ed25519 (D1): `keyPairFromSeed` 32 B, `sign`, `verify`; sin API de cifrado |
| `x25519_device_service.dart` | Identidad de **cifrado** X25519 (D2): `keyPairFromSeed` 32 B, `sharedSecret` ECDH; sin API de firma (I-002) |
| `secure_key_store.dart` | Almacén seguro: envelope versionado `zidk1:<base64(seed)>`, namespace `zid1.`, fail-closed tipado (ausente/corrupto/versión) |
| `identity_registry.dart` | Facade: `ensureAccountIdentity` (nunca regenera), `registerDevice` (nace `pending`, I-013), `transitionDevice` (máquina I-030), fingerprints, `loadAccountKeyMaterial`/`loadDeviceKeyMaterial` (APIs de propósito estricto) |
| `device_lifecycle.dart` | Máquina de estados formal I-030: PENDING→ACTIVE→REVOKED/COMPROMISED; LOCKED/KILLED/GONE; transiciones prohibidas fail-closed |
| `identity_persistence.dart` + `identity_persistence_models.dart`(+`.g.dart`) | Repositorio Isar de **metadatos públicos** sobre instancia `zone_identity` (aislada de la base legacy); duplicados rechazados; corrupto ⇒ `IdentityPersistenceError` |
| `models.dart` | `AccountIdentity`/`DeviceProfile` (metadatos; `toJson` NUNCA incluye claves — I-004) |
| `keys.dart` | Constantes/enums: `DeviceStatus`, `AccountIdentityStatus`, `IdentityKeyAlgorithm`, `IdentityKeyVersion`, `kIdentitySeedLength=32`, envelope `zidk1`, namespace `zid1` |
| `identity_errors.dart` | Jerarquía sellada de errores tipados (`IdentityFoundationError`): seed ausente/corrupta/versión, longitud inválida, registro ausente (`IdentityNotFoundError`), estado inconsistente, transición inválida, persistencia, mismatch de propósito |

### 2.2 `test/identity/` — 7 archivos, 57 766 bytes, **73 tests, 0 fallos**

| Archivo | Tests | Cubre |
|---|---|---|
| `base32_fingerprint_kat_test.dart` | 10 | Alfabeto/biyección §4.2–§4.5; **KAT oficial ACC/DEV-A/DEV-B** (input hex, digest, bit-packing, índice 31, truncado, display) contra evidencia intermedia de `FingerprintComputation`; validación de entrada §3/§4.9 |
| `fingerprint_normalization_test.dart` | 18 | §4.7–§4.9: desagrupación posicional, ingesta case-insensitive, rechazo, `groupFingerprint`, `sameFingerprint`, encoding residual |
| `crypto_separation_test.dart` | 7 | D1/D2/I-002: dominios distintos, firma Ed25519 (64 B, tamper ⇒ false), ECDH simétrico, **X25519 rechaza clave Ed25519** (`KeyPurposeMismatchError`), namespace `zid1.*` separa por ámbito/propósito |
| `secure_key_store_test.dart` | 9 | Envelope `zidk1:`, has/delete, longitud ≠ 32 ⇒ `InvalidSeedLengthError`, ausente ⇒ `SecureKeyMissingError`, versión ⇒ `SecureKeyVersionMismatchError`, corrupto ⇒ `SecureKeyCorruptError`, errores sin material (I-004) |
| `identity_registry_test.dart` | 19 | Idempotencia (nunca regenera), inconsistencias ⇒ `InconsistentIdentityStateError`, fingerprints estables, device nace `pending`, **máquina I-030 completa** (incl. GONE ⇒ GC de seeds), `IdentityNotFoundError`, borrado explícito |
| `identity_persistence_test.dart` | 10 | Isar **real** (instancia dedicada `zone_identity`, dir temporal): round-trip, duplicados, upsert, reinicio close/reopen, estado corrupto fail-closed |
| `test_doubles.dart` | 0 | `InMemoryKeyValueBackend` + `InMemoryIdentityRepository` (dobles fieles al contrato Isar) |

## 3. Gate de calidad — resultados reales

Procedimiento de resiliencia ejecutado en este orden:

1. `dart format lib/identity test/identity` → 21 archivos formateados.
2. `flutter analyze` (proyecto completo) → **No issues found!** (ran in 17.2s).
3. `flutter test test/identity` → **73/73 — All tests passed!** (≈12 s).

### 3.1 Nota honesta: Isar bajo `flutter test` en este host (Windows)

En una primera ejecución **sin configuración** la suite arrojó **63/73**: los 10 tests de
`identity_persistence_test.dart` fallaron por una sola causa de entorno —

```
Failed to load dynamic library 'D:\Proyectos\Zone\isar.dll': error code 126
```

`flutter test` no registra los plugins de Flutter (`isar_flutter_libs`), por lo que el
núcleo nativo no se resuelve con la ruta por defecto (`<dir del script>/isar.dll`).
**No era un defecto de código** (el análisis estático y el resto de la suite pasaban).

Resolución **reproducible y sin contaminar el repo**: el test lee (si existe) la variable
`ZONE_ISAR_CORE_PATH` y precarga la biblioteca vía la API pública `Isar.initializeIsarCore`
(diseñada para unit tests). En esta máquina se ejecutó:

```powershell
$env:ZONE_ISAR_CORE_PATH = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\isar_flutter_libs-3.1.0+1\windows\isar.dll"
flutter test test/identity
```

Resultado final: **`73/73 — All tests passed!`**. No se copió ninguna DLL al repo; la
resolución por defecto (dispositivo/emulador/CI con tooling completo) queda intacta cuando
la variable no está definida. Detalles de reproducción en `PHASE_2.1_TEST_MATRIX.md` §1.

## 4. Conformidad con la spec del fingerprint v1

- Alfabeto de 32 símbolos exacto (biyección 0..31, `-`=U+002D índice 31) — 3 tests.
- Input canónico §3: `utf8("ZONE-FP-1\0") ‖ utf8(kind) ‖ uuid_canonical(account_id)
  [‖ uuid_canonical(device_id)] ‖ base64_std_padded(pk_ed25519)` → SHA-256 → Base32
  5-bit MSB-first (52) → primeros 20.
- **KAT oficiales integrados en el test** con los vectores verificados
  independientemente (Python/Node/PowerShell, 2026-09-25): ACC
  `GSCB6GVT6DNV8C83-845`, DEV-A `3WMSUNKRR4-9WV4333FH`, DEV-B
  `NYAYV3MVBJP2BQCXZ4AW`. Los tests comparan **evidencia intermedia** (input hex,
  digest hex, base32 52, índices 0..31, texto, display), no solo la salida final —
  sin circularidad.
- Normalización §4.8/§4.9: ingesta case-insensitive, separadores 4×5 posicionales,
  rechazo fail-closed, `sameFingerprint` nunca lanza.
- Determinismo: mismo seed ⇒ misma clave pública y mismo fingerprint (tests).

## 5. Frontera de integración — cero costos

| Archivo de producción | Estado |
|---|---|
| `lib/services/initial_loading_screen.dart` | **Sin tocar** — la fundación no se instancia en el arranque |
| `lib/services/isar_service.dart` | **Sin tocar** — la fundación usa su propia instancia `zone_identity` (§6) |
| `lib/services/zone_id_service.dart` | **Sin tocar** |
| `lib/models/isar_models.*` / `pubspec.yaml` / `pubspec.lock` / `supabase/` | **Sin tocar** — sin cambios de dependencias |

La integración (bootstrap real de `IdentityRegistry` en el arranque, sustitución del
flujo legacy, migraciones, RPCs, UI) corresponde a fases posteriores **no autorizadas**.
`lib/identity/` permanece como fundación aislada y testeable; todo su estado es inyectado
(sin singletons — mandato §18).

## 6. Coexistencia con el sistema legacy

- **Almacén seguro:** namespace propio `zid1.` y envelope `zidk1:`. No colisiona con las
  claves legacy (`zone_id`, `private_key`, `public_key`, `supabase_uid`, `sk_*`,
  `pseudo_*`). El borrado por prefijo (`deleteByPrefix('zid1.')`) nunca toca claves
  legacy (test cubre `private_key` intacta).
- **Isar:** la fundación abre la instancia **`zone_identity`** con esquemas propios
  (`AccountIdentityDbo`, `DeviceDbo`); la base de mensajes legacy permanece en su
  instancia sin nombre. No hay colisión de colecciones ni de datos.
- **Criptografía:** la fundación genera material nuevo tipo Ed25519/X25519; no reutiliza
  ni lee `private_key`/`public_key` legacy. Sin migración de datos en esta fase.

## 7. Estado Git exacto (sin commits, sin staging)

- `HEAD`: `7f59b776c62cc131fd05dc999e99cbb7804385e8` (sin cambios).
- `git diff` (rastreados): **vacío**. `git diff --cached`: **vacío**. Ningún commit creado.
- `git status --short`: solo entradas **untracked**: `lib/identity/`, `test/identity/`,
  y los docs FASE 2.0/2.1 (25 previos + los 3 nuevos reportes de esta iteración).
- No se generaron secretos/claves en el repositorio; ninguna DLL de test quedó en
  `lib/`, `test/`, ni en la raíz del proyecto.

## 8. Archivos modificados/creados en esta iteración

- `lib/identity/` — 14 archivos (**nuevos/reescritos**, anteriores al gate KAT o creados
  en esta iteración; todos formateados y analizados).
- `test/identity/` — 7 archivos (**nuevos**; incluye KAT, normalización, cripto,
  almacén, registro/lifecycle, persistencia, dobles).
- `docs/PHASE_2.1_IMPLEMENTATION_REPORT.md` — **nuevo** (este reporte).
- `docs/PHASE_2.1_TEST_MATRIX.md` — **nuevo** (matriz 73 tests).
- `docs/PHASE_2.1_SECURITY_EVIDENCE.md` — **nuevo** (evidencia I-001…I-030, threat
  model, coexistencia legacy).
- `docs/PHASE_2.1_FINGERPRINT_SPEC_RESOLUTION.md` — §13 (estado FASE 2.1) actualizado.

## 9. Clasificación final

```
PHASE 2.1 IMPLEMENTATION: VERIFIED
TEST SUITE: 73/73 PASSED
FLUTTER ANALYZE: 0 ISSUES
KAT FINGERPRINT: VERIFIED (3/3 vectores integrados en test)
PRODUCTION INTEGRATION: NONE (frontera documentada, §5)
SUPABASE / LEGACY CODE: UNCHANGED
PHASE 2.2: NOT AUTHORIZED — BLOCKED
CTO REVIEW: REQUIRED
```

**STOP.** La implementación de FASE 2.1 termina aquí, cerrada y verificada. No se
inicia FASE 2.2 ni ninguna pieza del alcance prohibido (bootstrap de red, recovery,
rotación, multi-device, migraciones, UI, supabase). El código permanece sin integrar al
bootstrap de producción a la espera de la revisión CTO.