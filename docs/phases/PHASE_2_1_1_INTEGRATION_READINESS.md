# PHASE 2.1.1 — INTEGRATION READINESS & MIGRATION BRIDGE DESIGN

> Análisis 100% **READ-ONLY** del estado post-FASE 2.1.
> No se modificó código Dart/nativo, config, esquemas, migraciones, dependencias,
> tests ni API. Ningún `dart format`, ningún fix, ningún refactor.
> Fecha: 2026-09-25 · Branch `main` · HEAD `7f59b776c62cc131fd05dc999e99cbb7804385e8`.

## 1. Objetivo

Determinar si la fundación de identidad autorizada (FASE 2.1) está lista para convertirse
en la identidad de producción de la app, diseñar el **puente de migración
legacy→identidad autorizada** a nivel arquitectónico, y emitir un gate formal **GO/NO-GO**
para la siguiente fase. **No se implementa nada.**

El sistema se diseña alrededor de **security + correctness + identidad canónica**, no de
la facilidad de migración (criterio rector del encargo).

## 2. Metodología

1. Verificación de baseline: branch, HEAD, `git status`/`git diff` (sin modificaciones rastreadas).
2. Inventario estático: `glob` de todo `lib/` y `test/`, dependencias de `pubspec.yaml`.
3. Lectura íntegra de la fundación (`lib/identity/`, 14 archivos) y de los servicios legacy
   que portan identidad (`zone_id_service`, `p2p_security_service`, `chat_e2ee_service`,
   `isar_service`, `supabase_service`, `nearby_service`, `sync_service`, `mesh_policy`,
   `connection_service`, `initial_loading_screen`, `main`).
4. Lectura del backend (`supabase_schema.sql` completo: tablas, RLS, RPC `claim_zone_id`,
   `delete_own_account`, `resolve_bt_token`, `verify_zone_id`).
5. Grep repo-wide de importadores de la fundación (resultado: **0 en producción**).
6. Gates de evidencia ejecutados (no destructivos):
   - `flutter analyze` → **No issues found** (9.0s).
   - `flutter test test` (con `ZONE_ISAR_CORE_PATH` para isar.dll) → **96/96 All tests passed!**.

## 3. Baseline verificado

| Ítem | Resultado |
| --- | --- |
| Branch | `main` |
| HEAD | `7f59b776c62cc131fd05dc999e99cbb7804385e8` |
| `git diff` / `--cached` | vacíos (solo untracked = docs FASE 2.x + `lib/identity/` + `test/identity/`) |
| Flutter | 3.47.2 stable (2026-08-26) · Dart 3.13.2 · SDK `^3.10.8` |
| Paquete | `zone` v1.0.4+5 |
| Análisis estático | `flutter analyze` → 0 issues |
| Tests | `flutter test test` → 96/96 passed (73 identity + 23 legacy) |
| Importadores de `lib/identity` | 0 en `lib/` (solo `test/identity/` + fundación misma) |

## 4. Estado de la fundación (FASE 2.1)

- 14 archivos en `lib/identity/` (13 Dart + 1 `.g.dart`), 6 archivos de test en
  `test/identity/` (+ `test_doubles.dart`).
- KAT v1 verificado: 3/3 (ACC, DEV-A, DEV-B) — `PHASE_2.1_KAT_VERIFICATION_REPORT.md`.
- Invariantes clave implantadas y testeadas:
  - **I-004**: ningún material privado en metadatos/modelos/logs/errores.
  - **I-013/I-030**: device_1 nace `pending` sin derechos; activación solo por
    `confirm_bootstrap` (código de un uso + firma).
  - **D1/D2**: Ed25519 firma (cuenta y dispositivo), X25519 ECDH (dispositivo); sin coerción
    de rol (`KeyPurposeMismatchError`).
  - Fail-closed: seed ausente/corrupta/versión errónea ⇒ errores tipados; **nunca**
    regeneración silenciosa (`InconsistentIdentityStateError`).
  - Persistencia en instancia Isar dedicada `zone_identity` (sin tocar la base legacy).
- Cero integración en producción (mandato cumplido): la fundación es hoy código muerto por diseño.

## 5. Hallazgos principales (resumen — detalle en los documentos de arquitectura)

1. **Identidad canónica**: debe ser `account_id` (UUID v4 inmutable). `auth.uid()` es mutable
   (`claim_zone_id` reescribe `users.id`, `supabase_schema.sql:673`) y `zone_id` es un handle
   público tipo bearer (`zone_id_service.dart:553-556`); ninguno sirve como clave canónica.
2. **Choice de ownership X25519 (CONFLICTING)**: legacy = **una X25519 por cuenta**
   (`users.public_key`, `supabase_schema.sql:17`; difundida a pares en
   `nearby_service.dart:177-182`); fundación = **una X25519 por dispositivo**
   (`DeviceDbo.deviceEncryptionPublicKeyBase64`). Resolver en el bridge (import vs rotate).
3. **Zero importers**: la fundación no toca producción; la integración sin bridge crearía un
   segundo source of truth — por eso la migración requiere máquina de estados + marca.
4. **Deuda documentada (NO corregida)**: singletons legacy comparten las mismas claves
   (`private_key`/`public_key` en `zone_id_service.dart:23-26` y `p2p_security_service.dart:20-21`),
   con auto-sanación destructiva (`deleteAll` en `zone_id_service.dart:78`) y regeneración
   silenciosa de clave local (`ensureAuth`, `:268-294`).
5. **Threats críticos** (T1 spoofing, T2 substitution, T5 downgrade, T6 legacy bypass,
   T8 key/identity mismatch, T9 state desync, T10 partial migration) requieren implementación
   antes de integrar — diseño listo en `IDENTITY_MIGRATION_THREAT_MODEL.md`.

## 6. Documentos de esta fase

| Documento | Ruta |
| --- | --- |
| Boundary de identidad | `docs/architecture/IDENTITY_INTEGRATION_BOUNDARY.md` |
| Puente de migración | `docs/architecture/IDENTITY_MIGRATION_BRIDGE.md` |
| Matriz de dependencias | `docs/architecture/IDENTITY_DEPENDENCY_MATRIX.md` |
| Threat model de migración | `docs/security/IDENTITY_MIGRATION_THREAT_MODEL.md` |
| Máquina de estados de migración | `docs/migration/IDENTITY_MIGRATION_STATE_MACHINE.md` |
| Rollback de migración | `docs/migration/IDENTITY_MIGRATION_ROLLBACK.md` |
| Matriz de compatibilidad | `docs/migration/IDENTITY_COMPATIBILITY_MATRIX.md` |
| Informe final con gate | `docs/phases/PHASE_2_1_1_FINAL_READINESS_REPORT.md` |

## 7. Resultado del gate

**NO-GO para iniciar FASE 2.2** hasta que se resuelvan las condiciones de bloqueo y se
autorice el puente. La razón NO es la fundación (que está verificada y estable), sino que la
migración es una operación de seguridad y no se puede desacoplar del resto del sistema
(auth, RLS, E2EE, malla) sin implementar — y eso excede el alcance read-only de esta fase.

Detalles, condiciones y acciones requeridas en el informe final.