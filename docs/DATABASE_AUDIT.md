# DATABASE_AUDIT — Auditoría de Base de Datos · ZONE (FASE 0)

> Tablas, RLS, funciones, parches y divergencias repo↔DB.

## 1. Inventario de scripts

| Script | Rol | Estado |
|---|---|---|
| `supabase_schema.sql` | Schema completo (histórico) | Desactualizado vs app (faltan `updated_at`, `is_premium`, `delivered_at`/`read_at`, funciones radar/actividad) |
| `supabase_deploy.sql` | Script idempotente para SQL Editor | **No incluye** los parches del bloque siguiente → incompleto para el estado que el app espera |
| `supabase_multi_device_fix.sql` | `updated_at`+trigger, `get_active_users_for_radar`, `update_bt_activity`, `get_radar_stats`, "radar bilateral" | Parche suelto, requerido por la app (Z-109, Z-205) |
| `supabase_delete_fix.sql` | Policy DELETE matches/borrado | Parche suelto, requerido (Z-106) |
| `supabase_realtime_fix.sql` | Correcciones Realtime | Parche suelto |
| `supabase_emergency_recovery.sql` | Recuperación tras incidente (borrado de perfiles) | Evidencia de incidente histórico |
| `supabase_migration_fix.sql` | Normalización de migraciones | Parche suelto |
| `supabase_migrations/add_is_premium.sql` | `users.is_premium` | Migración suelta (app la degrada con catch) |
| `supabase_migrations/add_message_delivery_status.sql` | `delivered_at`/`read_at` + `mark_messages_read` | **NO TRACKEADA en git** (untracked) — crítico |
| `supabase_migrations/fix_radar_bilateral.sql` | Reemplaza policy de resolución BT + resetea `used=FALSE` | Contradice el diseño de consumo único (Z-104) |

## 2. Deficiencias del schema base (schema/deploy)

| Carencia | Consecuencia | Bug |
|---|---|---|
| `users.updated_at` ausente | Radar fallback `.gte('updated_at')` falla; sync LWW basado en timestamp roto | Z-205 |
| `users.is_premium` ausente | Premium leído del server no existe; solo local | Z-008 |
| `messages.delivered_at/read_at` ausentes | Receipts no pueden escribirse | Z-105 |
| Policy DELETE en `messages`/`matches` ausentes | Borrar match/mensaje falla por RLS | Z-106, Z-206 |
| Policy UPDATE en `messages` ausente | Imposible actualizar receipts aun con columnas | Z-206 |
| checkbox `used` en `bt_tokens` sin lógica | Tokens reutilizables | Z-104 |

## 3. Riesgo principal: divergencia repo ↔ instancia

- No hay indicios de que la instancia remota haya ejecutado `supabase_deploy.sql` tras los parches. 
- `add_message_delivery_status.sql` sin trackear: si la DB lo tiene pero un clone no, se pierde la feature; si la DB no lo tiene, la app invoca funciones inexistentes (silenciosamente falla).
- **Recomendación:** un solo `supabase_deploy.sql` consolidado e idempotente + `supabase db diff` para verificar.

## 4. Idempotencia y orden

- `supabase_deploy.sql` afirma ser idempotente (IF NOT EXISTS / DROP IF EXISTS); verificado: ✓ para tablas/policies/índices; ✓ `INSERT ... ON CONFLICT DO NOTHING` para buckets.
- Funciones `CREATE OR REPLACE` — seguro repetir.
- `fix_radar_bilateral.sql` linea 53 ejecuta `UPDATE public.bt_tokens SET used=FALSE` — destructivo si el diseño futuro dependiera de `used`.

## 5. Tratamiento de datos sensibles

- `public_key` guardada en claro (es pública por diseño E2EE — OK si se gestiona RLS (Z-002)).
- `encounters.other_zone_id` (user_id+other_zone_id+hour) con índice único horario — evita duplicados por hora (bien). `load_test_simulator` inyecta violencia ficticia (Z-203).
- `reports` con UNIQUE(reporter_id, reported_id) y trigger shadowban automático — correcto, pero sin revisión humana documentada.

## 6. Recomendaciones FASE 1

1. Consolidar parches en deploy; aplicar `supabase db push`/SQL Editor en cadena controlada.
2. Trackear `add_message_delivery_status.sql` y cargarlo como migración 000X.
3. Añadir `updated_at`+trigger e `is_premium` a schema base.
4. Policies UPDATE/DELETE para `messages`/`matches` (participantes).
5. Migración de consumo único de `bt_tokens` (delete o used+expirado).
6. Backup/restore + cron de `cleanup_expired_tokens`.

---
*Documento FASE 0 — no se aplicaron cambios.*