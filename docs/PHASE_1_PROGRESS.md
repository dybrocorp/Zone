# PHASE_1_PROGRESS — Registro de avance FASE 1 · ZONE

> Protocolo: INSPECCIONAR → PLANIFICAR → MODIFICAR → ANALIZAR → TESTEAR → VERIFICAR → DOCUMENTAR → CHECKPOINT.
> Estados permitidos: OPEN · IN_PROGRESS · FIXED_LOCAL · VERIFIED_LOCAL · REQUIRES_REMOTE_VERIFICATION · BLOCKED · REQUIRES_CTO_REVIEW.
> Pendiente de decisión del CTO se registra en `docs/CTO_REVIEW_REQUIRED.md`.

**Última actualización:** 2026-09-23

---

## FASE 1.6 — Batch CERRADO (Z-005, Z-106, Z-206, Z-207, Z-201/Z-303, Z-203, Z-209, Z-307) · 2026-09-23

**Estado:** ✅ CERRADA — mesh identity, policies RLS remotas, higiene analyze 0. Decisión CTO en `CTO_REVIEW_REQUIRED` §12.
**Alcance aprobado por el CTO:** batch ejecutable (sin decisiones criptográficas nuevas) + reporte obligatorio.

**`Z-005` — identidad de mensaje + dedup (P0 mesh)**
- `lib/services/mesh_policy.dart`: `msgId` ahora es **UUID v4** (`const Uuid().v4()`) en `ciphertextPacket`
  (antes epoch mS → colisiones); nueva clase pura **`MeshDedup` LRU + TTL 15 min** (eviction de UNA
  entrada, **sin `clear()` global** → replay cerrado).
- `lib/services/nearby_service.dart`: `_seenMessageIds` pasa de `Set<String>`+clear a `MeshDedup.register()`.
- `test/mesh_policy_test.dart`: +6 tests (UUID v4 único ×2, duplicado en ventana, distintos en el mismo ms,
  TTL olvida expirado, LRU evicta solo la más antigua, replay post-TTL).

**`Z-106` + `Z-206` — policies RLS (remoto aplicado + verificado)**
- `supabase_migrations/z106_z206_policies.sql` (NUEVO, idempotente, verificación en-transacción):
  `"Eliminar propio match"` (matches DELETE), `"Actualizar mensaje con match aceptado"` (UPDATE),
  `"Eliminar mensaje con match aceptado"` (DELETE) — solo `authenticated`, solo participantes.
- `supabase_schema.sql` / `supabase_deploy.sql` — consolidados (misma distribución).
- **✅ REMOTO APLICADO (2026-09-23, tx atómica) + VERIFICADO:** pg_policies con la 3 nuevas (roles
  `{authenticated}`); `anon` DELETE → 0 filas (bloqueado por RLS); `authenticated` sin sujeción → 0 filas;
  mensajes intactos (2). En remoto se dropeó la policy DELETE duplicada del parche suelto pre-existente
  (`"Eliminar propios matches"`, mismo qual) → producción = canon.

**`Z-207` — auto-claim eliminado**
- `lib/services/zone_id_service.dart`: el bloque de `claim_zone_id` del arranque (`ensureAuth`) se ELIMINÓ;
  el claim sigue solo en el login explícito (`loginWithExistingID`), con formato+rate-limit de FASE 1.2.

**`Z-201`/`Z-303` — `flutter analyze` 0 issues**
- `chats_list_screen.dart:228` → guard `sheetContext.mounted`; `donations_screen.dart:43-55` →
  `dialogContext.mounted` + `mounted` (reestructuración sin `if` anidado).
- `scripts/recolor.dart` + `tools/hard_transparent.dart`/`apply_transparency.dart`: `print` → `stdout.writeln`
  (13 `avoid_print` eliminados).
- ✅ `flutter analyze`: **0 errors / 0 warnings / 0 infos**.

**`Z-203` — credenciales fuera del repo**
- `test/load_test_simulator.dart`: URL+anon key de otro proyecto ELIMINADAS → lee `SUPABASE_URL` /
  `SUPABASE_ANON_KEY` de `Platform.environment` y aborta (exit 1) si faltan.

**`Z-209` — artefactos y `.gitignore`**
- `.gitignore` + (`hs_err_pid*.log`, `replay_pid*.log`, `*.hprof`, `*.dex`); eliminados de la raíz
  `hs_err_pid1864/4976/22224.log`, `replay_pid1864/4976.log`, `Zone.apk` (ninguno estaba trackeado).

**`Z-307` — comentario engañoso** (parcial)
- `lib/services/sync_service.dart:28` documenta ahora outbox push idempotente (Z-007) + pull en chat;
  quedan pendientes de suerte `getRadarStats` (sin callers) y `verify_zone_id` de cliente.

**Verificación final:** ✅ `flutter analyze` 0 issues · ✅ `flutter test` 18/18 · ✅ remoto VERIFIED (Z-106/Z-206).
**Borrador eliminado:** `add_message_delivery_status.sql` (decisión del CTO — variante insegura superada).
**Reporte de cierre de FASE 1:** `docs/PHASE_1_COMPLETION_REPORT.md` (puerta obligatoria antes de P1).

**Checkpoint:** ✅ FASE 1.6 cerrada. Pendientes con decisión pendiente: P0 Z-004 (handshake Ed25519) y
Z-008 (IAP premium); P1/P2: Z-104, Z-105 (reste: cablear `markMessageDelivered`), Z-107 pull, Z-110 push,
Z-111 storage, Z-112 radar, epics Z-101/Z-102, y P2/P3 restantes (Z-202/308, Z-204, Z-208, Z-301/302/304/306).

---

## FASE 1.5 — Z-007 · Offline-first chat (delivery/read status) · CERRADA

**ID:** Z-007
**Estado:** ✅ CERRADA (FASE 1.5) — app + remoto + baselines + docs (2026-09-23).
**Decisión CTO (registrada en `CTO_REVIEW_REQUIRED` §11):** **Opción 1** — idempotencia por
PK estable de cliente: la app genera el `id` del mensaje como UUID v4 una sola vez y los
reintentos del outbox reutilizan el MISMO id → `upsert ON CONFLICT (id)` = no-op, sin duplicados;
**sin columna `client_id`** (el PK ya es estable). Cablear `markAllMessagesRead` al abrir el chat.
**Aplicación remota:** migración `supabase_migrations/z007_offline_chat.sql` aplicada en remoto
en transacción atómica + verificación en-transacción (V1–V6): columnas `delivered_at`/`read_at`,
RPCs `mark_messages_read`/`mark_message_delivered` SECURITY DEFINER con gate `auth.uid() == p_*_id`
y match aceptado server-side, **sin anon/PUBLIC**, grants `{authenticated, service_role}`, mensajes intactos.

**Archivos (app):**
- `lib/screens/chat_screen.dart` — **`markAllMessagesRead` cableado en `_setupChat`** (~221): al abrir
  el chat con `uid` listo se llama al RPC `mark_messages_read` → el tick "Leído" del otro deja de mentir
  (antes `read_at` quedaba NULL aunque el usuario YA vio los mensajes). **Merge del WIP curado en
  `_sendMessage`**: `encrypted` se cifra ANTES de `savePendingMessage` (estaba definido después dentro
  del `if online` → `encrypted['...']` undefined en el outbox) y la llamada a `_sendMessageIdempotent`
  (método INEXISTENTE) se reemplaza por `_supabaseService.sendMessageIdempotent(messageId, matchId,
  senderId, encryptedContent, nonce, mac) → bool`. Conservado el flujo mesh (`isPeerReachable`/
  `sendMeshMessage`) y el `throw` si ni online ni mesh. `outgoingMessageId = Uuid().v4()` se genera UNA
  vez por envío (estable para reintentos).
- `lib/services/supabase_service.dart` — `sendMessageIdempotent` (354-379): upsert `ON CONFLICT (id)`;
  `markAllMessagesRead` RPC `mark_messages_read` (399-409); `markMessageDelivered` RPC (384-394);
  duplicado de `markAllMessagesRead` ELIMINADO; método muerto `markMessageRead` ELIMINADO (quedó con
  cuerpo del merge roto: `matchId`/`myUid` undefined, y sin usos en la app).
- `lib/services/isar_service.dart` — `savePendingMessage` firma con `required String messageId`,
  setea `LocalPendingMessage.messageId` (PK estable @unique).
- `lib/services/sync_service.dart` — `_flushPendingMessages` **curado para idempotencia**: el batch del
  outbox reutiliza `p.messageId` (antes generaba un `Uuid().v4()` nuevo por reintento → habría DUPLICADO
  mensajes en remoto). Con la cura, reintento = `ON CONFLICT (id)` no-op. Eliminado `_uuid` residual.
- `lib/models/isar_models.dart` — `LocalPendingMessage.messageId` `@Index(unique: true, replace: true)`
  (106-107); `LocalMessage.deliveredAt/readAt`.
- Baselines `supabase_schema.sql`/`supabase_deploy.sql` — columnas + RPCs consolidadas byte a byte.

**Verificación local:** `flutter analyze` → **0 errores, 0 warnings** (solo los 15 `info`
pre-existentes en scripts/tools y 2 pantallas no tocadas). `flutter test` → **12/12**.

**Verificación remota por rol (2026-09-23, Management API vía PAT, en transacción ROLLBACK — producción intacta):**
| Proba | Resultado |
|---|---|
| `anon` → `mark_messages_read(...)` | **42501 permission denied** ✅ (REVOKE efectivo) |
| `authenticated` (claims `sub` del reader simulado) → `mark_messages_read` | RPC OK; `read_at` de 1 no-leído del otro → 0 ✅ |
| `service_role` → `mark_message_delivered(...)` | RPC OK ✅ |
| Estado persistido tras ROLLBACK | `unread=1`, `delivered=0` — sin cambios ✅ |

**Nota de convivencia con WIP:** `supabase_migrations/add_message_delivery_status.sql` (borrador S5+S6
del desarrollador) queda **SIN commitear y NO APLICAR**: su RPC `mark_messages_read` NO tiene gate
`auth.uid()` ni verificación de match aceptado (variante insegura). El canon seguro es
`z007_offline_chat.sql` (aplicado en remoto). El WIP del usuario en `nearby_service.dart` intacto.

**Checkpoint:** ✅ FASE 1.5 cerrada (Z-007) — offline-first chat con delivery/read honesto en app+remoto,
idempotencia de outbox verificada, verificación por rol OK. Fin de FASE 1 (Z-001→Z-007, Z-103, Z-109, Z-002, Z-003).

---

## FASE 1.3 — Z-002 · Proteger la exposición de perfiles (RLS `users`)

**ID:** Z-002
**Estado:** ✅ REMOTE_APPLIED + VERIFIED (2026-09-23, Management API vía PAT — SQL Editor engine)
**Aplicación remota:** migración `z002_profile_visibility.sql` aplicada en transacción atómica (BEGIN/COMMIT) + 8 verificaciones SQL + pull-check estructural. **Estado previo:** FIXED_LOCAL → REQUIRES_REMOTE_VERIFICATION.
**Decisión CTO (re-registrada tras interrupción):** **A. Estricto server-side** (avatar/galería NULL cuando `avatar_is_public=false`, sin bypass mesh en cliente) + **vista `v_profile`** como único camino de lectura de terceros y `claim_zone_id` devuelve el perfil completo (jsonb).
**Archivos:**
- `supabase_migrations/z002_profile_visibility.sql` (NUEVO, idempotente) — `users.updated_at`, RLS self-scoped, vista `v_profile` + grants, `claim_zone_id` → jsonb, `verify_zone_id` con gating de avatar.
- `supabase_schema.sql` / `supabase_deploy.sql` — baselines sincronizados (columna, policy, vista, funciones).
- `lib/services/zone_id_service.dart` — login usa el perfil devuelto por `claim` (sin releer `users`); `updateProfile` envía `updated_at` (snake_case).
- `lib/services/supabase_service.dart` — `getProfileByZoneId` y fallback del radar leen `v_profile`.
- `lib/screens/public_profile_sheet.dart` — privacidad vía `v_profile`; BYPASS MESH ELIMINADO (decodificación A).

**Cambio:** RLS `users` pasa a self-scoped (`auth.uid() = id`); la vista `v_profile` reemplaza la lectura directa de terceros filtrando server-side (shadowban, bloqueos bidireccionales, privacidad de avatar/galería/handles). El claim devuelve el perfil completo al transferir la propiedad (login/migración sin fuga).

**Pruebas ejecutadas:**
- `flutter test`: ✅ 5/5.
- `flutter analyze`: ✅ 0 findings nuevos (solo los 15 infos preexistentes, ninguno en archivos del lote).
- SQL: 8 pruebas de verificación en la migración (anon→denied vista/RPC, self-scoped, gating avatar/handles, bloqueos bidireccionales, claim jsonb, verify sin avatar no público). **✅ Ejecutadas en remoto (2026-09-23):**
  - `anon → v_profile/claim` = 42501 permission denied ✅
  - `users` self-scoped: `SET ROLE authenticated` (sin sesión) → `count(users)` = **0** ✅ (la lectura a ajena queda bloqueada por RLS)
  - Shadowbanned excluidos de `v_profile` ✅ · gating avatar/galería/handles confirmado en definición ✅ · bloqueo bidireccional en la vista ✅
  - `claim_zone_id` → `RETURNS jsonb` + payload completo (verified por `pg_get_functiondef`) ✅ · `verify_zone_id` con `CASE WHEN avatar_is_public` ✅
  - Políticas `users` finales: **solo 3 self-scoped** (`Ver propio perfil` SELECT, `Actualizar propio perfil` UPDATE, `Registrar propio usuario` INSERT); la histórica `"Ver perfiles públicos"` ELIMINADA ✅
  - ACL `v_profile`: `authenticated=r` (**solo SELECT**; se revocó el `arwdDxtm` heredado de default privileges) ✅

**Incidente de aplicación (registrado en CTO_REVIEW_REQUIRED §8):** el 1º intento envió la migración con doble codificación (PowerShell 5.1 `Get-Content` lee ANSI/cp1252 sin BOM → `ú`→`Ãº`): el `DROP POLICY "Ver perfiles públicos"` no impactó (no-op) y los textos de RAISE de claim/verify quedaron mojibake. Corregido:
1. Aplicador de migraciones con **lectura UTF-8 estricta** (`[IO.File]::ReadAllText`, `--data-binary`).
2. Migración Z-002 endurecida: bloque `DO` que elimina *cualquier* política SELECT ajena en `users` salvo la self-scoped (`auth.uid() = id`) — robusto ante variantes de nombre/encoding — + `REVOKE ALL FROM authenticated` en `v_profile` + `DROP FUNCTION claim_zone_id(text)` previo al cambio de tipo de retorno void→jsonb (Postgres 42P13).
3. Re-aplicación atómica: mojibake sana en la DB (hex RAISE = `73657369c3b36e20` = "sesión ") ✅.

**Resultado:** el vector "cualquier autenticado lee todas las columnas de perfiles ajenos" queda cerrado localmente (server-side + self-scoped). El flujo legítimo (radar, pull-sync, perfil público, login) migra a `v_profile`/claim jsonb y sigue funcionando.

**Hallazgos colaterales (sondeo remoto 2026-09-23, Z-001/1.2):**
- Remoto: `claim_zone_id(text)` y `claim_zone_id(text,text)` COEXISTEN (300 PGRST203) y la 2-arg ejecuta a **anon** (204) → **producción vulnerable**, migración obligatoria.
- `verify_zone_id` responde 200 sin sesión (oráculo vivo) → REVOCAR.
- `users.updated_at` EXISTE en remoto; columna `bio` NO existe (el pull-sync enviaba `bio` → 400; corregido quitándola del SELECT).
- RPC `get_active_users_for_radar` / `update_bt_activity` / `get_radar_stats`: drift SOLO-REMOTO (sin definición canónica en el repo).
- `supabase` CLI: login + init + link OK (project `tdacwsbghmjnrbawxhjk`); `db diff` requiere Docker (no disponible) → vía de verificación/aplicación: **SQL Editor** o `db push` con password de DB.

**Supabase requerido:** ✅ APLICADO — migración Z-002 aplicada y verificada en remoto (2026-09-23) vía Management API con PAT (mismo motor del SQL Editor).

**Estado remoto:** ✅ REMOTE_VERIFIED — evidencia completa en la sección "Pruebas ejecutadas". Fuga por la política `"Ver perfiles públicos"` cerrada (self-scope operativo: `authenticated` ve 0 filas ajenas).

**Commit:** `ca456eb` — `fix(auth): enforce server-side profile privacy via v_profile view (Z-002)` · `6cd231d` — docs FASE 1.3 · (enmendada en la cola de aplicación remota con DO-block+REVOKE+encoding).

**Checkpoint:** ✅ FASE 1.3 completada y verificada localmente. FASE 1.4 (Z-003) IMPLEMENTADA (commit `fd1e60d`). Siguiente: FASE 1.5 — Z-007 (offline-first chat).

---

## FASE 1.2 — Z-001 (+ Z-103) · Proteger `claim_zone_id` (decisión CTO: Opción 3, Fase A)

**ID:** Z-001 · Z-103
**Estado:** ✅ REMOTE_APPLIED + VERIFIED (2026-09-23, Management API en transacción atómica). **Estado previo:** FIXED_LOCAL → REQUIRES_APPLICATION_EN_REMOTO (sondeo REST confirmó producción VULNERABLE: 2-arg con GRANT anon viva; oráculo verify anon vivo).
**Aplicación remota:** `secure_claim_zone_id.sql` aplicada (BEGIN/COMMIT). ACL finales: `claim_zone_id(text)` y `verify_zone_id(text)` = `{postgres, authenticated, service_role}` — **anon/PUBLIC fuera**; variante 2-arg `(text,text)` DROPEADA; `zone_claim_attempts` con RLS y sin acceso anon/auth directo.
**Pruebas de rol en vivo:** `SET ROLE anon` → `claim`/`verify` = 42501 permission denied ✅; con `SET ROLE authenticated` sin JWT → doble compuerta activa ("Se requiere sesión autenticada", `auth.uid()` NULL) ✅; rate-limit y registro de intentos por inspección de definición (requieren sesión JWT real). Mojibake de RAISE sanado tras re-aplicación de Z-002 (hex verificado).
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
  claim no altera public_key, idempotencia, sin oráculo). **✅ Ejecutadas en remoto** (2026-09-23):
  1. anon → claim/verify `permission denied` (42501) en vivo ✅
  2. authenticated con formato inválido → bloqueado por chequeo de sesión previo (doble compuerta: GRANT + `auth.uid()`); textos de RAISE sanados ✅
  3-4. Rate-limit e intentos fallidos: verificados por `pg_get_functiondef` (insert en `zone_claim_attempts` tras el chequeo de sesión; ejercitación completa requiere JWT real — documentado como limitación de la sonda) ✅
  5-6. Claim idempotente y sin escritura de `public_key`: confirmados por definición (`SET id = v_uid` únicamente) ✅
  7. `verify_zone_id` sin `id`/`zone_id` en el payload (solo `exists`/`display_name`/`avatar_url`) ✅

**Resultado:** el vector "robo de cuenta con ZONE-ID conocido vía anon RPC" queda cerrado
localmente; la rotación silenciosa de clave E2EE ya no es posible desde el código cliente.
Riesgo residual documentado: la toma de control con ZONE-ID conocido por un usuario
`authenticated` persiste hasta la Fase B (posesión por firma Ed25519 + códigos de recuperación).

**Riesgos:**
- Funciones en producción incompatibles (si el remoto tiene la variante 2-arg) → la migración
  hace `DROP FUNCTION claim_zone_id(text, text)` y crea la 1-arg endurecida; el cliente nueva
  versión ya llama 1-arg. Verificar remoto antes de lanzar apps existentes.
- `verify_zone_id` ya no devuelve `id` — el cliente actual no la usa (grep sin referencias), sin impacto.

**Supabase requerido:** ✅ APLICADO — `supabase_migrations/secure_claim_zone_id.sql` aplicada y verificada en remoto (2026-09-23) vía Management API en transacción atómica.

**Estado remoto:** ✅ REMOTE_VERIFIED — ACL finales sin anon; 2-arg dropeada; oráculo verify cerrado; `zone_claim_attempts` RLS. Ver "Aplicación remota" arriba.

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
| 1.3 | Z-002 — corregir exposición RLS de `users` | ✅ REMOTE_APPLIED + VERIFIED (ver sección superior) |
| 1.4 | Z-003 — detener mesh en claro y diseñar protocolo seguro | ✅ IMPLEMENTED — fail-closed aprobado (CTO 2026-09-23): emisor nunca envía en claro (cola con reintento), relay/receptor descartan `isEncrypted != true` (commit `fd1e60d`, tests 12/12) |
| 1.5 | Z-007 — implementar verdadero offline-first en chat | ✅ CERRADA (2026-09-23): mark-leídos al abrir chat + outbox idempotente (PK estable ON CONFLICT id) + merge curado. Ver sección FASE 1.5 arriba |

## Operativos cerrados (2026-09-23, mismo checkpoint remoto)

- **Acceso remoto:** Management API vía PAT (mismo motor del SQL Editor) — migraciones 1.2/1.3 aplicadas
  en transacciones atómicas y verificadas; PAT conservado hasta el fin de FASE 1 (decisión CTO).
- **Drift SOLO-REMOTO (Z-109):** dump read-only completo de funciones `public.*` guardado en
  `docs/REMOTE_DRIFT_SNAPSHOT_2026-09-23.sql`; **batch Z-109 ✅ CERRADO en remoto (2026-09-23)** —
  ver sección "Z-109" abajo.
- **Trigger `updated_at`:** confirmado EXISTENTE en remoto (`users_updated_at_trigger` BEFORE UPDATE);
  `supabase_schema.sql` / `supabase_deploy.sql` alineados con la definición (solo baseline, sin cambio remoto).
- **`supabase/` (CLI):** añadido a `.gitignore` (config local del CLI, no va al repo).
- **Incidente de encoding** durante la aplicación remota de Z-002: documentado en `CTO_REVIEW_REQUIRED` §8
  con la corrección (DO-block anti-drift de policies, REVOKE de default privileges en `v_profile`,
  lectura UTF-8 estricta en el aplicador).

## Z-109 — RPC drift con `GRANT anon` · CERRADO (aprobado CTO 2026-09-23, batch A–F)

**ID:** Z-109 · **Estado:** ✅ REMOTE_APPLIED + VERIFIED (commit de esta tanda; aprobación y detalle en `CTO_REVIEW_REQUIRED` §10).
**Migración:** `supabase_migrations/z109_rpc_anon_revoke.sql` (transacción atómica + verificación en-transacción).

**Hallazgo raíz:** 6 funciones `public.*` remotas con `SECURITY DEFINER` y `GRANT EXECUTE to anon/PUBLIC` —
la más crítica, `get_active_users_for_radar`, anulaba el gating de Z-002 (anon enumeraba usuarios activos,
sus claves públicas y avatares no públicos).

**Remediación aplicada en remoto (verificado en vivo):**
- `get_active_users_for_radar` → **`SECURITY INVOKER` sobre `v_profile`** + filtro `stealth_mode=false`:
  hereda `avatar_is_public`, shadowban y bloqueos mutuos. anon/PUBLIC revocados (solo `authenticated`+`service_role`).
- `get_radar_stats` → gate `auth.uid()` + revoke anon (P2).
- `refresh_active_users_cache` y `auto_cleanup_tokens` → solo `service_role` (mantenimiento; cierra DoS por
  `REFRESH MATERIALIZED VIEW CONCURRENTLY` disparado por anon).
- `update_bt_activity` → revoke anon (usaba `auth.uid()`).
- `update_users_updated_at` → REVOKE `PUBLIC` (defensivo).
- `resolve_bt_token` → **sin cambios** (canon ya `{authenticated, anon}` por diseño; tokens UUIDv4 → sin
  riesgo de fuerza bruta; rate-limit futuro en Z-104).
- **Consolidación en canon:** versiones corregidas (A–F + `rls_auto_enable` dormida, documentada) añadidas a
  `supabase_schema.sql`/`supabase_deploy.sql` tras la creación de `v_profile`.

**Verificación remota en vivo (2026-09-23):**
| Proba | Resultado |
|---|---|
| ACL 6 funciones | `{postgres, auth/service_role}` — **sin anon ni PUBLIC** ✅ |
| `anon` → radar / stats / activity / refresh / cleanup | **42501 permission denied** (6/6) ✅ |
| `authenticated` → `get_active_users_for_radar(1000)` | 2 filas, avatares ok (app intacta) ✅ |
| `authenticated` sin sesión → `get_radar_stats` | `null` (gate `auth.uid()`) ✅ |
| `get_active_users_for_radar` | `prosecdef=false` (INVOKER) + lee `v_profile` ✅ |
| Conteos globales | usuarios 2, visibles 2, `zone_claim_attempts` 0 ✅ |

**Conclusión:** la superficie anon queda cerrada; la app conserva su funcionalidad (las 3 RPC de app
siguen en `authenticated`, con fallbacks intactos).

## FASE 1.4 — Z-003 · Mesh en claro → fail-closed IMPLEMENTADO (decisión CTO 2026-09-23)

**ID:** Z-003 · **Estado:** ✅ IMPLEMENTADO + VERIFICADO localmente (commit `fd1e60d`, 2026-09-23).
**Decisión CTO (2026-09-23, registrada en `CTO_REVIEW_REQUIRED` §9):** Opción 1 **fail-closed mínimo** —
la malla NUNCA transporta `mesh_msg` en claro:
- **Emisor** (`sendMeshMessage`): si no hay llave de sesión o el cifrado AEAD falla, el mensaje se
  ENCOLA (`_pendingMeshMessages`, tope 200 con eviction FIFO) y se reintenta automáticamente cuando la
  llave se deriva (`_handleProfileExchange` → `_flushPendingMeshMessages`). El paquete se construye solo
  vía `MeshPolicy.ciphertextPacket(...)` (API que no acepta texto en claro por construcción).
- **Relay/receptor** (`_handleMeshMessage`): descarta al inicio cualquier paquete con `isEncrypted != true`
  (`MeshPolicy.decideRelay`), antes de dedup y de propagar.
- **Receptor local** (`_processIncomingMeshMessage`): guard previo — nunca procesa texto en claro.
- **Nueva pieza pura y testeable:** `lib/services/mesh_policy.dart` (sin dependencias Flutter:
  `decideSend`, `decideRelay`, `ciphertextPacket`) + `test/mesh_policy_test.dart` (7 casos fail-closed).
- **Consistente con tu WIP** (stash→implementar→pop): la llave ya se lee/guarda vía Secure Storage
  (`_security.getSessionKey` / `saveSessionKey`); no se usa `LocalProfile.sessionKey` (removido).
- **Sin criptografía nueva:** reutiliza X25519/ECDH + AEAD existentes.
- **Verificación local:** `flutter test` 12/12 ✅ · `flutter analyze` 0 errores (15 infos preexistentes) ✅.
- Tu WIP en `nearby_service.dart` quedó intacto y sin commitear (documentado en la sección inferior).