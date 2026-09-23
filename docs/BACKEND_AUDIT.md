# BACKEND_AUDIT — Auditoría del Backend (Supabase) · ZONE (FASE 0)

> Fuentes: `supabase_schema.sql`, `supabase_deploy.sql`, `supabase_*_fix.sql`, `supabase_migrations/*.sql`, uso en `lib/services/supabase_service.dart` y `zone_id_service.dart`.

## 1. Estado de las 7 tablas (RLS)

| Tabla | Tabla schema | RLS | Policies | Observaciones |
|---|---|---|---|---|
| `users` | ✓ | ✓ | SELECT (todos no-shadowbanned 🔴 Z-002), UPDATE (owner), INSERT (owner) | SELECT demasiado amplio; sin `updated_at` base (Z-205); sin `is_premium` (migración suelta) |
| `bt_tokens` | ✓ | ✓ | Ver/Crear propios + "Resolver token BT" (todos auth) | `resolve_bt_token` GRANT anon (Z-104); `used` sin uso |
| `encounters` | ✓ | ✓ | Ver/Crear propios | inserción masiva desde `load_test_simulator` (Z-203) |
| `matches` | ✓ | ✓ | SELECT (participantes), INSERT (requester), UPDATE (receiver) | **sin DELETE** → Z-106; parche `supabase_delete_fix.sql` suelto |
| `messages` | ✓ | ✓ | SELECT/INSERT (match aceptado) | **sin UPDATE ni DELETE** → Z-206/Z-105/Z-106; sin `delivered_at`/`read_at` base (Z-105) |
| `reports` | ✓ | ✓ | INSERT (propio), SELECT (propios) | trigger shadowban automático a 3 reportes |
| `blocked_users` | ✓ | ✓ | FOR ALL (owner) | — |

## 2. Funciones RPC

| Función | En schema | En deploy | GRANT | Observación |
|---|---|---|---|---|
| `handle_new_report` (trigger) | ✓ | ✓ | revocado ✓ | OK |
| `cleanup_expired_tokens` | ✓ | ✓ | revocado ✓ | nunca invocada desde la app (¿cron?) |
| `delete_own_account` | ✓ | ✓ | authenticated | SECURITY DEFINER correcto |
| `claim_zone_id(text)` | ✓ | ✓ | **authenticated + anon** | 🔴 Z-001; cliente la llama CON `p_public_key` (firma rota) |
| `verify_zone_id(text)` | ✓ | ✓ | **authenticated + anon** | 🔴 Z-103 oráculo; sin uso en app |
| `resolve_bt_token(text)` | ✓ | ✓ | **authenticated + anon** | 🔴 Z-104; no consume token |
| `get_active_users_for_radar(int)` | ✗ | ✗ | — | Solo en `supabase_multi_device_fix.sql` — Z-109 |
| `update_bt_activity()` | ✗ | ✗ | — | Solo en parche — Z-109 |
| `get_radar_stats()` | ✗ | ✗ | — | Solo en parche; llamado pero "no usado" por pantallas — Z-307 |
| `mark_messages_read(uuid,uuid)` | ✗ | ✗ | (solo migración untracked) | RPC esperado por app — Z-105 |
| `update_users_updated_at` (trigger) | ✗ | ✗ | — | Solo en parche — Z-205 |

## 3. Scripts "parche" pendientes (riesgo de divergencia DB ↔ repo)

- `supabase_multi_device_fix.sql` — `updated_at` + trigger + funciones radar/actividad. **Es requerido por la app** (Z-109).
- `supabase_delete_fix.sql` — policy DELETE para matches/manejo de borrados. **Es requerido para `deleteMatch`** (Z-106).
- `supabase_realtime_fix.sql` — correcciones de realtime. 
- `supabase_emergency_recovery.sql` — recuperación tras incidente de borrado de perfiles (evidencia de incidente histórico).
- `supabase_migration_fix.sql` — normalización de migraciones.
- `supabase_migrations/add_message_delivery_status.sql` — **UNTracked** (sin git): columnas `delivered_at`/`read_at` + `mark_messages_read`. Si la DB fue creada con este script pero el repo no lo tiene versionado, **cualquier clone nuevo pierde la feature**. Z-105.
- `supabase_migrations/add_is_premium.sql` — flag premium, sin aplicarlo el app asume que puede faltar (catch en premium_service:25-27).

> **Conclusión:** hay al menos 4 parches NECESARIOS que no están consolidados en `supabase_deploy.sql`. El estado de la DB remota es **NO VERIFICABLE** desde el repo; se recomienda `supabase db diff` + aplicar `supabase_deploy.sql` consolidado.

## 4. Realtime

- La app usa canales broadcast (`msgs:<match>`), `onPostgresChanges` global (`global_messages`) y presencia (chat).
- Comentario del schema: habilitar `public.messages`, `public.matches`; NO `encounters/bt_tokens/reports` — coherente.
- Riesgo: `global_messages` canal Postgres Changes INSERT sin filtro de match server-side → la notificación se filtra client-side (`senderId != myUid`) — leve exposición de metadatos (volumen de mensajes global) al autenticado con el canal. P2.

## 5. Storage

- Bucket `profiles` creado `public=true` (schema:313-315, deploy:332-334) → Z-111.
- Policies de objeto por `storage.foldername(name))[1] = auth.uid()` (directorio uid/usuario) — correcto en diseño, anulado por bucket público.
- `avatar_url`/`gallery_photos` accesibles sin auth.

## 6. Recomendaciones FASE 1 (backend)

1. Escribir `supabase_deploy.sql` **consolidado e idempotente** que incluya todos los parches requeridos (Z-105, Z-106, Z-109, Z-205).
2. Corregir GRANTs y firma de RPC (Z-001, Z-103, Z-104).
3. Remplazar RLS SELECT de `users` por RPC/vista filtrada (Z-002).
4. Añadir policies UPDATE/DELETE a `messages` (Z-206) y DELETE a `matches` (Z-106).
5. Bucket privado + URLs firmadas (Z-111).
6. Rate limiting y cron para `cleanup_expired_tokens`.

---
*Documento FASE 0. Estado DB remoto marcado NO VERIFICABLE.*