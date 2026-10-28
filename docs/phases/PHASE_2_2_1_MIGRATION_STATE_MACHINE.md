# PHASE 2.2.1 — MIGRATION STATE MACHINE (IMPLEMENTATION REPORT)

> PHASE 2.2 (implementación autorizada por CTO) · Subfase 2.2.1 · 2026-09-25.
> Branch `main` · HEAD `7f59b776c62cc131fd05dc999e99cbb7804385e8` (sin commits en FASE 2.x) ·
> Flutter 3.47.2 / Dart 3.13.2. Sin cambios rastreados: solo untracked de FASE 2.x.

---

## 0. Cabecera de estado (§24) — PHASE 2.2.1

```
PHASE:        2.2
SUBPHASE:     2.2.1 (Migration State Machine)
STATUS:       PASS
IMPLEMENTED:  máquina de estados pura + persistencia singleton + controlador
FILES CHANGED lib/identity/ (nuevos + 1 edit mínimo) · test/identity/ (nuevos)
TESTS:        125/125 PASS (96 baseline + 29 nuevos: 9 KAT máquina + 9 persistencia + 11 controlador)
ANALYZE:      flutter analyze → No issues found
BUILD:        (este slice es lógica pura Dart; sin cambios de build/plataforma)
REAL DEVICE:  BLOCKED-EMV — no hay dispositivo Android conectado ni adb en PATH
NEXT:         2.2.2 Legacy X25519 Import (gate: analyze+tests PASSS → autorizado)
```

---

## 1. Repository state

| Ítem | Valor | Evidencia |
| --- | --- | --- |
| Branch | `main` | `git branch --show-current` |
| HEAD | `7f59b776c62cc131fd05dc999e99cbb7804385e8` | `git rev-parse HEAD` |
| Working tree | sin cambios rastreados; solo untracked nuevos | `git diff`/`--cached` vacíos; `git status --short` |
| Gate previo | `flutter analyze` 0 issues · `flutter test` 96/96 | ejecutado al inicio de 2.2.1 |

## 2. Gate de entrada (POST-ratificación CTO)

| Check | Resultado |
| --- | --- |
| ADR-0001 ratificado (Architecture C) | Sí — import X25519 legacy como encryption key de device_1 |
| Baseline verde | analyze 0 issues; 96/96 tests |
| Dispositivos | `flutter devices`: Windows + Edge únicamente; `adb` **no** en PATH → gate REAL DEVICE queda pendiente de entorno (no bloquea lógica pura) |

## 3. IMPLEMENTADO (solo 2.2.1)

### 3.1 Máquina de estados pura — `lib/identity/migration_state_machine.dart`

- `enum MigrationState` (9 estados, `statusId` canónico persistido): `legacy, discovered,
  validated, bridged, authorized, migrated, verified, finalized, migrationFailed`.
- `enum MigrationEvent` (12 eventos): `migrationStarted, validationSucceeded, validationFailed,
  bridgeCompleted, bridgeFailed, bootstrapConfirmed, bootstrapFailed, singleWriterActivated,
  verificationSucceeded, verificationFailed, finalized, rollbackConfirmed`.
- `MigrationStateMachine.evaluate(current, event)` → `transitioned | invalid` (PURA, sin estado global).
- `MigrationStateMachine.nextState(...)` → API estricta: transición no permitida ⇒
  `InvalidMigrationStateTransitionError` (fail-closed).
- Transiciones exactas del diseño (sin saltos): ver §5.
- `kMigrationSingletonId = 'default'` (un registro de migración por instalación).

Patrón idéntico a `DeviceLifecycle` (I-030): enumeraciones explícitas, terminales modelados,
nada implícito.

### 3.2 Errores tipados — `lib/identity/identity_errors.dart` (extensión)

Se reutiliza la jerarquía `IdentityFoundationError` (sealed → las clases nuevas viven en la
misma librería, de acuerdo con bridge §9). Añadidos:

| Error | Semántica |
| --- | --- |
| `InvalidMigrationStateTransitionError(from,to)` | salto prohibido / evento no válido en estado actual |
| `MigrationAlreadyFinalizedError` | aplicar evento en `FINALIZED` (terminal) |
| `MigrationRollbackNotAllowedError(from)` | rollback desde estado ≠ `MIGRATION_FAILED` |
| `MigrationRecordCorruptError(cause)` | estado/evento persistido desconocido (nunca se inventa) |

Ningún mensaje expone material clave (I-004).

### 3.3 Modelo de dominio + persistencia — `migration_models.dart`, `migration_persistence.dart`

- `MigrationDbo` (@collection, instancia `zone_identity`): solo metadatos públicos (estado,
  bind de identificadores, fingerprints, checksum, causas tipadas, auditoría).
- Índice único `migrationId` (`replace: true`) + `putByMigrationId` → **escrituras idempotentes**
  (reintentos no duplican; testado con triple save → count == 1).
- `MigrationRepository` (abstracto, inyectable — sin singletons) + `IsarMigrationRepository`.
- Fail-closed: estado/evento persistido corrupto ⇒ `MigrationRecordCorruptError`.
- `openIdentityIsar` ahora registra `MigrationDboSchema` (único edit sobre código 2.1:
  `identity_persistence.dart`).
- `MigrationRecord` (dominio inmutable) + `MigrationRecord.initial()` (ausencia ⇒ `LEGACY`).

### 3.4 Controlador — `lib/identity/migration_controller.dart`

- `MigrationController(repository, log?)` — sin singletons, como `IdentityRegistry`.
- `apply(event, {cause?, legacyZoneId?, boundAccountId?, boundDeviceId?, fingerprintAcc?,
  fingerprintDev?})`: valida máquina estricta → actualiza → persiste con auditoría.
- `rollback({required cause})`: ÚNICO camino a `LEGACY`, exclusivo desde `MIGRATION_FAILED`
  (protege de rollback abusivo desde AUTHORIZED+). No destruye artefactos.
- `currentState()`, `isFinalized()`, `assertNotFinalized()`.
- Audit trail cronológico `iso|estado|evento|causa` (sin secretos; testado su formato).
- **Contrato de idempotencia para fases posteriores**: efectos secundarios (import,
  materialización) DEBEN ser idempotentes y ejecutarse ANTES de persistir el nuevo estado
  (semántica at-least-once → crash entre efecto y persistencia = re-aplicación segura sin
  duplicación). Documentado en el header del controlador.

## 4. TESTS (nuevos, LEVEL 1)

| Archivo | Coverage |
| --- | --- |
| `test/identity/migration_state_machine_test.dart` (9) | matriz exhaustiva 9×12 (108 combinaciones evaluadas), determinismo, camino legal LEGACY→FINALIZED, terminales (FINALIZED sin salida / MIGRATION_FAILED solo rollback), sin saltos, rollback abusivo rechazado, `fromStatusId` fail-closed |
| `test/identity/migration_persistence_test.dart` (9) | round-trip completo, singleton nunca duplicado, registro ajeno rechazado (`DuplicateIdentityRecordError`), ausencia ⇒ null, reinicio real en disco, estado corrupto ⇒ `MigrationRecordCorruptError`, evento corrupto ⇒ `MigrationRecordCorruptError`, sin material privado en errores |
| `test/identity/migration_controller_test.dart` (11) | camino feliz, estado inicial LEGACY, saltos inválidos, re-envío de evento tras superar estado ⇒ inválido, FINALIZED bloquea todo (apply y rollback), rollback solo desde MIGRATION_FAILED, rama de fallo (attemptCount++/causa tipada) + reinicio tras rollback, fallos tardíos (bridge) cuentan intentos, `rollbackConfirmed` inválido desde estados no fallidos, formato de auditoría parseable, JSON público sin secretos |

Desglose total suite: `flutter test test` → **125/125 PASS** (96 baseline + 29 nuevos).
`flutter analyze` → **No issues found**.

## 5. Máquina implementada (documento de referencia `IDENTITY_MIGRATION_STATE_MACHINE.md` §4/§5)

```
LEGACY ─migrationStarted─▶ DISCOVERED ─validationSucceeded─▶ VALIDATED ─bridgeCompleted─▶ BRIDGED
                                                                                 (import X25519 → device_1, ADR-0001)
   │                              │                            │                        │
   │                              ├─validationFailed─┐        ├─bridgeFailed─┐         ├─bootstrapFailed─┐
   │                              ▼                  │        ▼              │         ▼                 │
   │                        ┌─ MIGRATION_FAILED ◀────┴────────┴──────────────┴─────────┴─────────────────┘
   │◀──rollbackConfirmed────┘   (terminal de fallo; intentos/rollbackCount/auditoría)
BRIDGED ─bootstrapConfirmed─▶ AUTHORIZED ─singleWriterActivated─▶ MIGRATED
MIGRATED ─verificationSucceeded─▶ VERIFIED ─finalized─▶ FINALIZED (terminal feliz, sin salida)
MIGRATED ─verificationFailed─▶ MIGRATION_FAILED
```

- Sin saltos hacia delante; `FINALIZED` sin ninguna salida; `MIGRATION_FAILED → LEGACY`
  única transición hacia atrás (prohibido regresar de AUTHORIZED+ sin fallo explícito).

## 6. Decisiones tomadas en esta subfase

| Decisión | Justificación |
| --- | --- |
| Errores de migración en `identity_errors.dart` (misma librería) | `IdentityFoundationError` es `sealed`; reutilizar la jerarquía es el mandato del bridge §9 |
| Auditoría como `List<String>` en dominio / `String` newline-joined en Dbo | evita dependencia de listas Isar; separador `\n` seguro (ids/ISO nunca contienen `\n`) |
| Singleton de migración por instalación | la migración es unitaria por instalación; índice único + putBy* = idempotencia |
| `MIGRATION_FAILED` modelado como terminal **con salida designada** rollback-only | refleja el diseño; para la máquina, terminales = sin progreso hacia delante, con escape explícito a LEGACY |
| Contracto at-least-once (efecto → persistir) documentado en el controlador | base segura para 2.2.2/2.2.3 (import/materialización idempotentes) |

## 7. Fronteras respetadas

- NO tocados: boot screen, `zone_id_service.dart`, mensajería E2EE, mesh, backend, tests existentes.
- Única modificación sobre código 2.1: registro de `MigrationDboSchema` en `openIdentityIsar`.
- `users.public_key` NO se retira (precondiciones 2.1.2 incumplidas hasta MIGRATED+VERIFIED+BACKEND+MULTI-DEVICE).
- Sin commits: todo lo de FASE 2.x preservado en working tree (untracked).

## 8. Gate de salida 2.2.1

| Check | Resultado |
| --- | --- |
| `flutter analyze` | PASS (0 issues) |
| `flutter test test` | PASS 125/125 |
| KAT máquina (matriz 9×12) | 9/9 PASS |
| Persistencia (idempotencia, reinicio, fail-closed) | 9/9 PASS |
| Controlador (orquestación, rollback, bloqueos) | 11/11 PASS |
| Sin regresiones | 96/96 baseline intacto |
| Gate 2.2.1 → 2.2.2 | **AUTORIZADO** (procede Legacy X25519 Import) |

**Gaps de entorno para fases posteriores**: `adb` fuera de PATH y sin dispositivo Android
conectado → el gate REAL DEVICE requerirá plataforma-tools y dispositivo físico antes de la
prueba técnica de dos dispositivos (TEST-R01..R17).