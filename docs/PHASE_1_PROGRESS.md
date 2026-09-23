# PHASE_1_PROGRESS — Registro de avance FASE 1 · ZONE

> Protocolo: INSPECCIONAR → PLANIFICAR → MODIFICAR → ANALIZAR → TESTEAR → VERIFICAR → DOCUMENTAR → CHECKPOINT.
> Estados permitidos: OPEN · IN_PROGRESS · FIXED_LOCAL · VERIFIED_LOCAL · REQUIRES_REMOTE_VERIFICATION · BLOCKED · REQUIRES_CTO_REVIEW.
> Pendiente de decisión del CTO se registra en `docs/CTO_REVIEW_REQUIRED.md`.

**Última actualización:** 2026-09-22

---

## FASE 1.2 — Z-001 (+ Z-103) · Proteger `claim_zone_id` (decisión CTO: Opción 3, Fase A)

**ID:** Z-001 · Z-103
**Estado:** FIXED_LOCAL → REQUIRES_REMOTE_VERIFICATION (aplicar migración en Supabase vía CLI)
**Archivos:**
- `supabase_migrations/secure_claim_zone_id.sql` (NUEVO, idempotente) — RPCs endurecidos + tabla `zone_claim_attempts`.
- `supabase_schema.sql` / `supabase_deploy.sql` — baselines actualizados con el mismo hardening.
- `lib/services/zone_id_service.dart` — claim sin `p_public_key`; fin de rotación silenciosa (`ensureAuth`, `checkAndFixRegistration`); `updateProfile` preserva `public_key` archivada; `isValidZoneIdFormat` fail-fast.
- `test/zone_id_format_test.dart` (NUEVO) — contrato de formato compartido backend/cliente.
- Docs: `BUG_REGISTER` (Z-001, Z-103), `REMEDIATION_PLAN` (filas 2, 10), `CTO_REVIEW_REQUIRED` (decisión + Fase B).

**Cambio:** ver sección 0 de `docs/CTO_REVIEW_REQUIRED.md`. Fase A = controles de autorización:
REVOKE anon/PUBLIC (solo `authenticated`), formato estricto `^ZONE-[A-Z0-9]{8}$`, rate-limit
5 fallos/15 min por zone_id, `claim_zone_id` ya NO escribe `public_key`, `verify_zone_id`
sin oráculo (no expone `id`), auditoría en `zone_claim_attempts`. Cliente alineado: elimina
`p_public_key` de las 2 llamadas al RPC y deja de sobrescribir la identidad E2EE archivada.

**Pruebas ejecutadas:**
- `flutter test`: ✅ 5/5 (widget + 4 tests de contrato de formato).
- `flutter analyze`: ✅ 0 findings nuevos (solo 15 infos preexistentes).
- SQL: 7 pruebas de verificación incluidas en la migración (anon→403, formato, rate-limit,
  claim no altera public_key, idempotencia, sin oráculo). **Pendientes de ejecución remota.**

**Resultado:** el vector "robo de cuenta con ZONE-ID conocido vía anon RPC" queda cerrado
localmente; la rotación silenciosa de clave E2EE ya no es posible desde el código cliente.
Riesgo residual documentado: la toma de control con ZONE-ID conocido por un usuario
`authenticated` persiste hasta la Fase B (posesión por firma Ed25519 + códigos de recuperación).

**Riesgos:**
- Funciones en producción incompatibles (si el remoto tiene la variante 2-arg) → la migración
  hace `DROP FUNCTION claim_zone_id(text, text)` y crea la 1-arg endurecida; el cliente nueva
  versión ya llama 1-arg. Verificar remoto antes de lanzar apps existentes.
- `verify_zone_id` ya no devuelve `id` — el cliente actual no la usa (grep sin referencias), sin impacto.

**Supabase requerido:** SÍ — aplicar `supabase_migrations/secure_claim_zone_id.sql` en el proyecto
remoto (vía supabase CLI) y ejecutar las 7 pruebas SQL.

**Estado remoto:** REQUIRES_REMOTE_VERIFICATION (pendiente token CLI + project ref).

**Commit:** `2c36d9b` — `fix(auth): harden zone id claim authorization (Z-001 fase A + Z-103)`

**Checkpoint:** ✅ FASE 1.2 completada y verificada localmente. Siguiente: FASE 1.3 — Z-002 (RLS `users`).

---

## FASE 1.1 — Z-006 · Recuperar el arranque de forma segura

**ID:** Z-006
**Estado:** VERIFIED_LOCAL → REQUIRES_REMOTE_VERIFICATION (build release en dispositivo pendiente)
**Archivos:**
- `lib/utils/env_config.dart` (NUEVO) — configuración compile-time `String.fromEnvironment` + fallback dev tolerante vía `flutter_dotenv`.
- `lib/screens/initial_loading_screen.dart` — arranque sin `dotenv.load` obligatorio, sin `!`; mensaje claro si falta configuración.
- `README.md` / `CONTRIBUTING.md` — documentado `flutter run/build --dart-define-from-file=.env`.
- `docs/BUG_REGISTER.md` (Z-006), `docs/REMEDIATION_PLAN.md` (fila 1).

**Cambio:** El `.env` ya NO se empaqueta como asset (se preserva el pubspec local del dueño). La configuración de Supabase (`SUPABASE_URL`, `SUPABASE_ANON_KEY` — claves *publishable*) se inyecta en compilación vía `--dart-define-from-file=.env` para producción, con un fallback de desarrollo tolerante a `flutter_dotenv`. Si no hay ninguna fuente, la app muestra "Falta la configuración del servidor. Reinstala la app." en lugar de crashear o entrar en bucle de reintento.

**Causa raíz confirmada:** `flutter_dotenv` 5.x lee `.env` desde el bundle de assets; al quitar el asset del pubspec, `rootBundle.load('.env')` lanzaba `FileNotFoundError` → bucle "Error al iniciar. Reintenta por favor."

**Pruebas ejecutadas:**
- `flutter test` (suite): ✅ 1/1 pasa. Salida previa: `[Startup] ERROR CRÍTICO: Instance of 'FileNotFoundError'`. Salida nueva: `[Startup] Configuración de Supabase ausente` (degradación controlada, sin crash).
- Sonda temporal `test/_env_probe_test.dart` (ELIMINADA tras validar):
  - Sin dart-define → `url=null anon=null`, sin excepción (reproducía `NotInitializedError` de `DotEnv.env` tras `load()` fallido; corregido leyendo dentro del mismo `try/catch`).
  - Con `--dart-define-from-file=.env` → `url=https://tdacwsbghmjnrbawxhjk.supabase.co anon=set` ✅ (ruta de producción verificada).
- `flutter analyze`: ✅ 0 findings nuevos (solo los 15 infos preexistentes).

**Resultado:** `FileNotFoundError` y `NotInitializedError` eliminados. Arranque degradable verificado por test. La ruta de producción queda probada a nivel de resolución de config; falta validación de build release (apk/appbundle) en dispositivo.

**Riesgos:
- Dev ejecuta `flutter run` sin flags y sin `.env` en assets → verá el mensaje de configuración ausente (esperado; se resuelve con `--dart-define-from-file=.env`). Mitigado con la doc en README/CONTRIBUTING y el fallback dev.
- Las anon keys son *publishable* por diseño (PostgREST las expone igualmente en el binario); no se añadieron secretos nuevos ni al repo ni a assets.

**Supabase requerido:** Ninguno (cambio 100% cliente). Requiere build release en dispositivo para cerrar la validación.

**Estado remoto:** N/A (sin cambios de backend).

**Commit:** `156ed7a` — `fix(zone): restore secure startup configuration (Z-006)`

**Checkpoint:** ✅ FASE 1.1 completada y verificada localmente. Siguiente: FASE 1.2 — Z-001 (`claim_zone_id`).

---

## Próximos lotes (no iniciados)

| Fase | Bug | Estado |
|------|-----|--------|
| 1.3 | Z-002 — corregir exposición RLS de `users` | OPEN |
| 1.4 | Z-003 — detener mesh en claro y diseñar protocolo seguro | OPEN |
| 1.5 | Z-007 — implementar verdadero offline-first en chat | OPEN |

> **FASE 1.2 (Z-001 + Z-103) completada** — ver sección superior.
> Al completar 1.1–1.5 se emitirá `docs/PHASE_1_COMPLETION_REPORT.md` antes de continuar con los P1 restantes.