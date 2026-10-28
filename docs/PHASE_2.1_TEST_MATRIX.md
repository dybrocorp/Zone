# PHASE 2.1 — Test Matrix (73 tests — VERIFIED 2026-09-25)

> **Tipo:** Matriz de tests de la implementación de FASE 2.1 (masa CTO).
> **Fecha:** 2026-09-25 · **Resultado:** **73/73 passed, 0 failed, 0 skipped.**
> **Gate previo:** `dart format lib/identity test/identity` → `flutter analyze`
> (0 issues, proyecto completo) → `flutter test test/identity`.
> **Autoridad:** `PHASE_2.1_IMPLEMENTATION_REPORT.md` · `PHASE_2_SECURITY_INVARIANTS.md`
> (I-001…I-030) · `PHASE_2_FINGERPRINT_SPEC.md` · `PHASE_2_BOOTSTRAP_POLICY.md` §4.

---

## 1. Comandos de reproducción

```powershell
# Solo si el host no resuelve el núcleo nativo de Isar (Windows + flutter test):
$env:ZONE_ISAR_CORE_PATH = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\isar_flutter_libs-3.1.0+1\windows\isar.dll"

dart format lib/identity test/identity   # gate de resiliencia
flutter analyze                          # 0 issues
flutter test test/identity               # 73/73
```

**Nota honesta:** sin `ZONE_ISAR_CORE_PATH`, en este host los 10 tests de
`identity_persistence_test.dart` no pueden ejecutarse (`Failed to load dynamic library
'…\isar.dll': error code 126` — `flutter test` no registra plugins). No es un defecto de
código; la variable se documenta como bootstrap portable (§`PHASE_2.1_IMPLEMENTATION_REPORT.md` 3.1).
Con ella definida, la suite completa pasa **73/73**.

## 2. Resumen

| Archivo | Tests | KAT | Invariantes anclados |
|---|---|---|---|
| `base32_fingerprint_kat_test.dart` | 10 | ✅ ACC/DEV-A/DEV-B | I-017, I-026 |
| `fingerprint_normalization_test.dart` | 18 | (derivado §4.7–§4.9) | I-017 |
| `crypto_separation_test.dart` | 7 | — | I-002, D1/D2 |
| `secure_key_store_test.dart` | 9 | — | I-004, §9 |
| `identity_registry_test.dart` | 19 | — | I-013, I-015, I-020, I-027 (parcial), I-030 |
| `identity_persistence_test.dart` | 10 | — | I-004 (persistencia de metadatos), §8 fail-closed |
| **Total** | **73** | **3 vectores** | — |

## 3. `base32_fingerprint_kat_test.dart` — 10 tests

| # | Test | Resultado |
|---|---|---|
| 1 | Alfabeto normativo (§4.2/§4.3) — 32 símbolos únicos y biyección 0..31 exacta | ✅ |
| 2 | Alfabeto normativo — `2^5 = 32` ⇒ todo valor de 5 bits 0..31 tiene exactamente un símbolo | ✅ |
| 3 | Alfabeto normativo — índice 31 = `-` (U+002D) y símbolos confundibles fuera del alfabeto | ✅ |
| 4 | KAT oficial (§6) — **ACC**: input, digest, bit-packing, mapeo, truncado y display | ✅ |
| 5 | KAT oficial (§6) — **DEV-A**: idem | ✅ |
| 6 | KAT oficial (§6) — **DEV-B-reinstall**: idem | ✅ |
| 7 | KAT oficial (§6) — cada vector ejerce el índice 31 → `-` en algún grupo | ✅ |
| 8 | Validación de entrada (§3/§4.9) — rechaza clave pública con longitud ≠ 32 | ✅ |
| 9 | Validación de entrada — rechaza UUIDs no canónicos (no RFC 4122) | ✅ |
| 10 | Validación de entrada — acepta UUID canónico en minúsculas y lo canonicaliza igual | ✅ |

Los tests 4–6 comparan, por vector, la **evidencia intermedia** de
`FingerprintComputation` (input hex canónico, SHA-256 hex, Base32 completo de 52,
índices 0..31, texto de 20, display 4×5) contra los valores oficiales verificados de forma
independiente (KAT VERIFIED 2026-09-25) — sin circularidad.

## 4. `fingerprint_normalization_test.dart` — 18 tests

| # | Test | Resultado |
|---|---|---|
| 1 | canónico con `-` literal se conserva intacto | ✅ |
| 2 | display ACC → canónico (los separadores fijos se eliminan) | ✅ |
| 3 | ejemplo del spec §4.7: `-` literal adyacente a separador | ✅ |
| 4 | ingesta case-insensitive | ✅ |
| 5 | canónico (20) sin separadores y display (23) coinciden | ✅ |
| 6 | round-trip grupo → canónico para los tres vectores KAT | ✅ |
| 7 | firmas distintas no coinciden | ✅ |
| 8 | longitudes distintas de 20/23 con separadores son inválidas | ✅ |
| 9 | símbolos fuera del alfabeto son inválidos (rechazo, no-match) | ✅ |
| 10 | `-` literal en canónico es válido (es símbolo, no separador) | ✅ |
| 11 | `normalizeFingerprint` lanza error tipado ante entradas inválidas | ✅ |
| 12 | `sameFingerprint` nunca lanza y devuelve no-match ante inválidas | ✅ |
| 13 | inserta separadores tras el 5º/10º/15º carácter | ✅ |
| 14 | `-` literal al comienzo de grupo produce `--` en el límite | ✅ |
| 15 | longitud incorrecta lanza | ✅ |
| 16 | bloque final de 1 bit se completa con ceros a la derecha (MSB-first) | ✅ |
| 17 | 32 bytes (digest) → 52 símbolos | ✅ |

*(Los números 13–17 son del grupo de `groupFingerprint`/`encodeBase32Unambiguous`.)*

## 5. `crypto_separation_test.dart` — 7 tests

| # | Test | Resultado |
|---|---|---|
| 1 | dominios distintos: mismo seed ⇒ claves de tipo y bytes distintos (Ed25519 vs X25519) | ✅ |
| 2 | Ed25519 firma y verifica firmas de 64 bytes; firma adulterada ⇒ false | ✅ |
| 3 | ECDH X25519 es simétrico (32 bytes); X25519 no tiene API de firma (solo `sharedSecret`) | ✅ |
| 4 | **X25519 nunca firma**: ECDH con clave pública Ed25519 ⇒ `KeyPurposeMismatchError` | ✅ |
| 5 | claves X25519 de longitud inválida se rechazan (fail-closed) | ✅ |
| 6 | seeds distintas producen claves fehacientemente distintas | ✅ |
| 7 | namespace `zid1.*` separa el material por ámbito y propósito (storageKeys distintos) | ✅ |

## 6. `secure_key_store_test.dart` — 9 tests

| # | Test | Resultado |
|---|---|---|
| 1 | write/read round-trip con envelope `zidk1:` + payload base64 | ✅ |
| 2 | `hasSecret` refleja presencia de envelope con versión soportada | ✅ |
| 3 | write con longitud ≠ 32 ⇒ `InvalidSeedLengthError` (fail-closed) | ✅ |
| 4 | lectura ausente ⇒ `SecureKeyMissingError` y no se regenera | ✅ |
| 5 | envelope de versión no soportada ⇒ `SecureKeyVersionMismatchError` (y no cuenta como presente) | ✅ |
| 6 | envelope con base64 inválido ⇒ `SecureKeyCorruptError` | ✅ |
| 7 | payload de longitud incorrecta ⇒ `SecureKeyCorruptError` | ✅ |
| 8 | borrado por prefijo elimina solo el namespace `zid1.*` (clave legacy intacta) | ✅ |
| 9 | los errores tipados no exponen el material secreto (I-004) | ✅ |

## 7. `identity_registry_test.dart` — 19 tests

| # | Test | Resultado |
|---|---|---|
| 1 | `ensureAccountIdentity` crea (id determinista) y es **idempotente** (nunca regenera) | ✅ |
| 2 | el material de cuenta firma con Ed25519 y verifica | ✅ |
| 3 | inconsistente (metadatos sin seed) ⇒ `InconsistentIdentityStateError` — no regenera | ✅ |
| 4 | inconsistente (seed sin metadatos) ⇒ `InconsistentIdentityStateError` — no regenera | ✅ |
| 5 | cuenta desconocida ⇒ `IdentityNotFoundError` (key material y fingerprint) | ✅ |
| 6 | account fingerprint es estable y coincide con `FingerprintService` | ✅ |
| 7 | device fingerprint es estable y distinto del de cuenta | ✅ |
| 8 | `registerDevice` crea device **pending** con firma Ed25519 + cifrado X25519 y seeds separadas | ✅ |
| 9 | `registerDevice` con cuenta inexistente ⇒ `IdentityNotFoundError` | ✅ |
| 10 | carga/transición de device desconocido ⇒ `IdentityNotFoundError` | ✅ |
| 11 | pending → `bootstrapConfirmed` → **ACTIVE** (sin derechos antes) | ✅ |
| 12 | ACTIVE → `deviceRevoked` → **REVOKED** (`revokedAt` + motivo) | ✅ |
| 13 | ACTIVE → `deviceCompromised` → **COMPROMISED** | ✅ |
| 14 | terminales no admiten salida (fail-closed) | ✅ |
| 15 | **PENDING + revoke/compromiso son prohibidos** (PENDING sin derechos) | ✅ |
| 16 | pending → `maxAttemptsReached` → **LOCKED** | ✅ |
| 17 | pending → `cancelled` → **KILLED** | ✅ |
| 18 | pending → `bootstrapExpired` ⇒ **GONE**: GC de artefactos y registro (cuenta intacta) | ✅ |
| 19 | `removeDevice` borra seeds y metadatos | ✅ |

## 8. `identity_persistence_test.dart` — 10 tests (Isar real)

| # | Test | Resultado |
|---|---|---|
| 1 | round-trip completo de `AccountIdentity` (todos los campos) | ✅ |
| 2 | cuenta con accountId distinto ⇒ `DuplicateIdentityRecordError` | ✅ |
| 3 | upsert de la misma cuenta actualiza campos (`updatedAt` cambia) | ✅ |
| 4 | `deleteAccount` borra el registro de cuenta (sin tocar devices — cascada fuera de alcance) | ✅ |
| 5 | save/load device por id y lista por cuenta | ✅ |
| 6 | device con accountId distinto ⇒ `DuplicateIdentityRecordError` (device-account mismatch) | ✅ |
| 7 | `deleteDevice` elimina solo el dispositivo indicado | ✅ |
| 8 | **reinicio**: los metadatos sobreviven a cerrar y reabrir la instancia en el mismo directorio | ✅ |
| 9 | device con status desconocido ⇒ `IdentityPersistenceError` (no materializa estado inválido) | ✅ |
| 10 | account con status desconocido ⇒ `IdentityPersistenceError` | ✅ |

## 9. `test_doubles.dart` — apoyo (0 tests)

- `InMemoryKeyValueBackend`: doble del backend de `flutter_secure_storage`.
- `InMemoryIdentityRepository`: doble del contrato Isar (incluye el contrato exacto de
  `deleteAccount` = solo registro de cuenta, alineado con la implementación real).

## 10. Defectos encontrados y resueltos durante el gate

1. `saveDevice` en `identity_persistence.dart` **no re-enviaba** `IdentityFoundationError`
   (convertía `DuplicateIdentityRecordError` en `IdentityPersistenceError`); `saveAccount`
   sí lo hacía. **Corregido** (`if (e is IdentityFoundationError) rethrow;`) — detectado
   por el test de mismatch (matriz §8.6).
2. `InMemoryIdentityRepository.deleteAccount` borraba devices; la implementación Isar no
   (contrato = solo registro de cuenta). **Alineado el doble** a la implementación real.
3. Invalidos de test (28 no era `-T` sino `-X` para 0xFF; string de 23 chars mal contado)
   corregidos antes de la primera ejecución verde.

## 11. Clasificación

```
TEST SUITE FASE 2.1: VERIFIED — 73/73 passed
```