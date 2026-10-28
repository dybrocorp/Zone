# IDENTITY MIGRATION STATE MACHINE

> FASE 2.1.1 — Integration Readiness & Migration Bridge Design.
> READ-ONLY: diseño conceptual. No implementado. No autorizado fuera del alcance CTO.

## 1. Relación con la máquina I-030

La máquina **I-030** (`DeviceLifecycle`, `device_lifecycle.dart:65-156`) gobierna el ciclo de
vida de un **dispositivo** dentro de la fundación y permanece intacta. Esta máquina opera un
nivel **superior**: el ciclo de **migración de identidad** (LÉGAME→NUEVO) que orquesta el
bridge (`IDENTITY_MIGRATION_BRIDGE.md`) y que, en su estado `AUTHORIZED`, invoca transiciones
I-030 (confirm_bootstrap) para activar device_1.

## 2. Máquina de estados de migración

```
   LEGACY
     │  (arranque: detectar stores legacy — zone_id, private_key/public_key, supabase_uid)
     ▼
 DISCOVERED
     │  (validar coherencia: formato zone_id, par X25519 consistente, 1 sola cuenta)
     ├── inválido ─────────────────► MIGRATION_FAILED ──► (rollback) ─► LEGACY
     ▼
 VALIDATED
     │  (crear account + device_1 en zone_identity; importar X25519 legacy; bind zone_id)
     ├── InconsistentIdentityStateError / DuplicateIdentityRecordError ──► MIGRATION_FAILED
     ▼
  BRIDGED
     │  (confirm_bootstrap: código de 1 uso + firma → device_1 active [I-030])
     ├── confirmación falla / max_attempts ──► LOCKED (device) / MIGRATION_FAILED
     ▼
 AUTHORIZED
     │  (single-writer switch: consumidores nuevos pasan a leer zone_identity)
     ▼
 MIGRATED
     │  (verificar: fingerprints ACC/DEV estables, E2EE legacy descifra, sin huérfanos)
     ├── verificación falla ────────► MIGRATION_FAILED ──► ROLLBACK ─► LEGACY
     ▼
 VERIFIED
     │  (archivar/eliminar claves legacy SOLO aquí; dejar marca terminal)
     ▼
 FINALIZED
```

## 3. Estados (definición)

| Estado | Semántica | Artefactos opcionales (2.2) |
| --- | --- | --- |
| `LEGACY` | Identidad legacy activa; fundación ausente o no integrada | `migration_state = legacy`, marca `zone_id` legacy |
| `DISCOVERED` | Inventariados stores legacy + estado de `zone_identity` | inventario (claves presentes, uuid de sesión) |
| `VALIDATED` | Checks fail-closed aprobados (formato, unicidad, par X25519) | resultados de validación (públicos) |
| `BRIDGED` | Account + device_1 materializados en `zone_identity`; X25519 legacy importada | `fingerprint_acc`, `fingerprint_dev`, binds |
| `AUTHORIZED` | device_1 activo por confirmación I-030; single-writer activado | transición `pending→active` |
| `MIGRATED` | Escritores migrados; operación normal sobre identidad nueva | flag single-writer = true |
| `VERIFIED` | Post-checks aprobados (E2EE legacy, fingerprints, sin huérfanos) | checksum de verificación |
| `FINALIZED` | Terminal: legacy archivado/borrado; migración irrevocable | marca terminal + timestamp |
| `MIGRATION_FAILED` | Fallo irrecuperable; sistema vuelve a `LEGACY` | causa tipada (no expone secretos) |

## 4. Transiciones válidas

| Desde | Evento | A |
| --- | --- | --- |
| LEGACY | inicio de bridge | DISCOVERED |
| DISCOVERED | validación OK | VALIDATED |
| DISCOVERED | validación falla | MIGRATION_FAILED |
| VALIDATED | account+device materializados | BRIDGED |
| VALIDATED | inconsistencia estado | MIGRATION_FAILED |
| BRIDGED | confirm_bootstrap firmado | AUTHORIZED |
| BRIDGED | confirmación falla/lock/kill | MIGRATION_FAILED |
| AUTHORIZED | single-writer activo | MIGRATED |
| MIGRATED | verificación OK | VERIFIED |
| MIGRATED | verificación falla | MIGRATION_FAILED |
| VERIFIED | archivado/limpieza | FINALIZED |
| MIGRATION_FAILED | rollback confirmado | LEGACY |

## 5. Transiciones inválidas (prohibidas, fail-closed)

- Cualquier salto hacia delante (p.ej. `DISCOVERED → MIGRATED`) — requiere estados intermedios.
- `LEGACY → VERIFIED/FINALIZED` sin pasar por el bridge.
- `FINALIZED → *` (estado terminal, sin retorno).
- `MIGRATION_FAILED → *` excepto `→ LEGACY` (rollback).
- **Prohibido** regresar de `AUTHORIZED` en adelante a `LEGACY` sin pasar por
  `MIGRATION_FAILED → rollback` (protege contra rollback abusivo).

## 6. Estados de fallo

| Fallo | Detección | Comportamiento |
| --- | --- | --- |
| Crash/kill durante BRIDGED | marca incompleta en `zone_identity` | reiniciar desde DISCOVERED; idempotente (los writes usan `putBy*`, `identity_persistence.dart:87,151`) |
| Segunda migración | marca `FINALIZED` | rechazo; no re-generar (`ensureAccountIdentity` idempotente, `identity_registry.dart:156-158`) |
| seed sin metadatos / viceversa | `InconsistentIdentityStateError` | `MIGRATION_FAILED → LEGACY`; sin regeneración (`identity_errors.dart:114-120`) |
| Estado de device corrupto persistido | `IdentityPersistenceError` | aborte; no materializar estado inválido (test `identity_persistence_test.dart:59-60`) |

## 7. Estados terminales

- `FINALIZED` — terminal feliz.
- `MIGRATION_FAILED` — terminal de fallo, con retorno a `LEGACY` (rollback) como única salida.
- `GONE` — caso I-030 (device: garbage collection tras TTL, `identity_registry.dart:272-278`),
  NO aplica directamente a migración de cuenta.

## 8. Idempotencia y retry

- `ensureAccountIdentity` es idempotente (metadatos+seed presentes ⇒ carga sin regenerar,
  `identity_registry.dart:156-158`).
- `saveAccount`/`saveDevice` usan `putByAccountId`/`putByDeviceId` (índices `replace: true`,
  `identity_persistence_models.dart:24-25,54-55`) ⇒ reintentos no duplican.
- Deduplicación por índices únicos de `zone_identity`; la fila `users` ya tiene `zone_id UNIQUE`
  (`supabase_schema.sql:15`).

## 9. Requisito de diseño (no implementado)

En FASE 2.2 la máquina se materializará como módulo puro (tipo enum + función `next`)
**sin estado global**, siguiendo el patrón fail-closed de `DeviceLifecycle` y con tests KAT
de transiciones (gap de tests — ver `PHASE_2_1_1_FINAL_READINESS_REPORT.md` §11).