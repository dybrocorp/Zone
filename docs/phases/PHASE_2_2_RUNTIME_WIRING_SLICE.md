# PHASE 2.2 — IDENTITY RUNTIME WIRING SLICE (REPORTE)

> **Fase**: 2.2 (pre 2.2.2) — Vertical slice de wiring de la Identity Foundation al runtime.
> **Autorización CTO**: 2026-09-25 (solo wiring mínimo; NO 2.2.2, NO migración, NO E2EE/Mesh/Auth/Radar/Messaging, NO refactor amplio).
> **Estado**: **COMPLETA Y VERDE** — `flutter analyze` PASS, `flutter test` 137/137 PASS, build PASS, install PASS, R01–R05 PASS en dispositivo físico.
> **Próximo**: **DETENERSE Y ESPERAR DECISIÓN CTO** (§20).

---

## 1. Objetivo

Conectar la Identity Foundation (`lib/identity/`, probada en 2.1/2.2.1) al boot
productivo de Zone en Android real: **SINGLE IDENTITY INITIALIZATION PATH**,
idempotente (1er arranque CREATE, siguientes LOAD), persistencia dedicada
`zone_identity.isar`, fail-closed, coexistencia legacy sin tocar nada legacy.

## 2. Implementación

| Archivo | Cambio |
| --- | --- |
| `lib/identity/identity_context.dart` | **Nuevo**: contexto público inmutable (account_id, device_id, device_status, fingerprints, migration_state, flags de creación). Sin material privado (I-004). |
| `lib/identity/identity_bootstrap.dart` | **Nuevo**: orquestador idempotente. Abre `zone_identity` → `ensureAccountIdentity` → ensure device_1 (crea SOLO si no existe; reutiliza el primario) → **integridad clave↔seed** (`InconsistentIdentityStateError` ante desajuste) → fingerprints → estado de migración **read-only** (`legacy`). Fail-closed, errores tipados. |
| `lib/services/zone_identity_bootstrap_service.dart` | **Nuevo**: punto único del producto (singleton estilo `IsarService`). Caché idempotente, cierre de instancia + rethrow ante fallo, logging seguro (`debugPrint` con account_id/device_id/fingerprints/estados, sin secretos). |
| `lib/screens/initial_loading_screen.dart` | **Editado**: paso 0 en `_startInitialization` (ANTES del gate de Supabase, para ser verificable en dispositivo sin `.env`). Fail-closed: error tipado ⇒ `[IdentityBootstrap] FAILED (fail-closed)` y bloqueo del arranque con mensaje claro. No modifica los pasos legacy. |

### Decisiones de diseño (slice)

- **SINGLE PATH**: la identidad se inicializa únicamente desde el boot productivo
  (paso 0 del InitialLoadingScreen). No hay bootstrap paralelo ni instanciación
  desde múltiples puntos.
- **Idempotencia**: `ensureAccountIdentity` (crea o carga). Device: si no hay
  ninguno ⇒ registra device_1 `pending`; si hay ⇒ reutiliza el más antiguo
  (determinista). Arranques repetidos NUNCA regeneran ni duplican.
- **Integridad**: las seeds del almacén seguro DEBEN derivar la misma clave
  pública que los metadatos (`loadAccountKeyMaterial`/`loadDeviceKeyMaterial` vs
  metadata). Fallo ⇒ `InconsistentIdentityStateError`.
- **Migración intacta**: el slice SOLO lee el estado (`migrationState` = `legacy`
  por ausencia de registro). Ningún evento se aplica; `MigrationDboSchema` queda
  sin registros.
- **Legacy coexistente**: no se toca `IsarService`, `default.isar`, auth,
  E2EE, Mesh, `users.public_key` ni X25519 legacy.

## 3. Tests

### UNIT — `test/identity/identity_bootstrap_test.dart` (7)
- 1er arranque: cuenta `active` + device_1 `pending`, contexto correcto, fingerprints 20 chars.
- Persistencia de las 3 seeds (`zid1.` envelopes versionados) en el almacén seguro.
- 2º arranque (nuevo bootstrap, mismo storage): LOAD, ids estables, 1 solo device, fingerprints iguales (id cola vacía ⇒ regeneración accidental = RangeError = FAIL).
- 3er arranque: estabilidad mantenida.
- Fail-closed: seed de cuenta borrada ⇒ `InconsistentIdentityStateError` (sin regenerar, sin devices nuevos).
- Fail-closed: metadata con clave pública alterada (seed intacta) ⇒ `InconsistentIdentityStateError`.
- Fail-closed: seed de firma de device borrada ⇒ `SecureKeyMissingError`.

### INTEGRATION — `test/identity/identity_bootstrap_integration_test.dart` (3, Isar REAL en temp dir)
- Arranque productivo materializa `zone_identity.isar` y NO crea `default.isar`.
- **Reinicio real** (cerrar instancia → reabrir misma ruta + mismo almacén):
  ids y fingerprints estables, único device_1, migración intacta (registro null).
- Fail-closed en dispositivo: seed borrada tras reinicio ⇒ `InconsistentIdentityStateError`, base intacta.

### SERVICIO — `test/identity/zone_identity_bootstrap_service_test.dart` (2)
- `bootstrap()` inicializa una sola vez por sesión (factory invocada 1 vez, contexto cacheado).
- Fail-closed: fallo ⇒ rethrow tipado, sin caché parcial, `onClose` ejecutado, `context` inaccesible.

**Total**: 125 → **137** (12 nuevos). `flutter analyze`: 0 issues.

## 4. Validación física (DEVICE LAB — HA26RCFN / LENOVO TB305FU, Android 15/API 35)

| Check | Resultado |
| --- | --- |
| `flutter build apk --debug --android-skip-build-dependency-validation` | **PASS** (60.4 s) |
| `adb install -r` (APK recién generada, no stale) | **PASS** |
| `am start -n com.dybrocorp.zone/.MainActivity` (1er arranque) | **PASS** — `[IdentityBootstrap] OK ... account_created=true device_created=true` |
| `zone_identity.isar` en dispositivo | **FOUND** (`app_flutter/zone_identity.isar`, 1 MB) |
| `default.isar` | **NOT FOUND** tras update in-place (hallazgo de entorno, ver §5) |
| 2º arranque (force-stop + relaunch) | **PASS** — `account_created=false device_created=false`, ids/fingerprints idénticos |
| MainActivity en foco; PID 9871 estable +100 s; crash buffer vacío | **PASS** |
| FATAL / AndroidRuntime / errores de identidad en logcat | **0** |
| Secretos en logs | **NO** |

**Veredictos**: R01 **PASS** · R02 **PASS** · R03 **PASS** · R04 **PASS** · R05 **PASS**.

### Evidencia
- `docs/device_lab/evidence/WIRING_R02-R05_identity_physical.txt`
- `docs/device_lab/evidence/WIRING_identity_bootstrap_R01.png`

## 5. Hallazgos (diagnóstico, sin corrección)

1. **`default.isar` ausente tras el update**: el instalador Android **recrea el
   directorio de documentos `app_flutter/`** durante la actualización in-place del
   APK debug. No es borrado por código de Zone (ningún cambio toca `default.isar`);
   la base legacy se recreará al ejecutar el flujo legacy con backend configurado.
   → Propuesta al CTO: evaluación de migración de documentos dir o respaldo del
   directorio en updates futuros.
2. Aviso preexistente de zona dev-check (`runZonedGuarded`/binding) — no fatal, ya
   documentado en TEST-R01; fuera del alcance de este slice.

## 6. Gate §18 — criterio de éxito

`analyze` ✓ · `test` ✓ · build ✓ · install ✓ · launch ✓ · R01 ✓ · R02 ✓ · R03 ✓ · R04 ✓ · R05 ✓

## 7. Invariantes cripto 2.2 preservadas

- No se deriva X25519 de Ed25519 (no se toca X25519 legacy).
- No se regeneran claves silenciosamente (LOAD probado en físico).
- `zone_id` no es trust anchor; no se importa key material.
- Fail-closed (errores tipados, sin identidad alternativa).
- Migración no ejecutada (estado `legacy`, registro ausente).
- `users.public_key` intacta (no autorizado, no tocado).
- Sin singletons ocultos de estado criptográfico (el servicio guarda solo contexto público y manijas).

## 8. Estado y siguiente paso

**STATUS: PASS** · **NEXT STEP: STOP AND WAIT FOR CTO** — no iniciar 2.2.2/2.2.3/2.2.4/2.2.5
hasta nueva autorización.