# ZONE — MODELO DE DATOS, MIGRACIONES SQL Y ROLLBACK

**Etapa:** A (Diseño) · **Fecha:** 2026-10-28

Serie de migraciones aditivas para el rediseño freemium. **Ninguna migración se
aplica a producción en esta sesión.** Los archivos se versionan en
`supabase_migrations/` siguiendo el esquema `zNNN_*.sql` del repo (canon actual
hasta z213).

---

## 1. Entidades nuevas

### 1.1 `discovery_preferences` — preferencias (1 fila por usuario)
| Columna | Tipo | Notas |
|---|---|---|
| `user_id` | uuid pk → `users.id` ON DELETE CASCADE | identidad, coherente con el resto del canon |
| `discovery_enabled` | boolean NOT NULL DEFAULT false | aparecer en descubrimiento |
| `location_sharing_enabled` | boolean NOT NULL DEFAULT false | consentimiento explícito de publicación de ubicación |
| `radius_m` | integer NOT NULL DEFAULT 500 | clamp server → {250,500,1000,2000} |
| `updated_at` | timestamptz NOT NULL DEFAULT now() | trazabilidad |

RLS: ENABLED. Policies owner-only (`auth.uid() = user_id`) para SELECT/UPDATE;
INSERT/DELETE cerrados (los upserts van por RPC). anon: cero permisos.

### 1.2 `discovery_presence` — presencia temporal (1 fila por usuario)
| Columna | Tipo | Notas |
|---|---|---|
| `user_id` | uuid pk → `users.id` ON DELETE CASCADE | |
| `lat` / `lng` | double precision | ONLY escritura vía RPC definer |
| `accuracy_m` | integer | precisión reportada (≥0) |
| `source` | text check ('gps','network') | híbrido reportado por el cliente |
| `updated_at` | timestamptz | cadencia anti-abuso |
| `expires_at` | timestamptz | TTL 30 min recalculado por servidor |

RLS: **ENABLED sin policies** → deny-all para todos los roles (ni siquiera el
dueño lee por REST; puede hacerlo vía RPC si hiciera falta en debug). Índices:
`(expires_at)` para GC, `(lat, lng)` para la consulta b-box.

### 1.3 `user_entitlements` — suscripciones verificadas
| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid pk default gen_random_uuid() | |
| `user_id` | uuid → `users.id` CASCADE | |
| `product` | text check ('zone_premium_monthly','zone_premium_annual') | IDs Play |
| `platform` | text check ('android') | v1: solo Google Play |
| `purchase_token` | text | token de compra (sensible, no credencial de pago) |
| `verified` | boolean | true solo tras verificación backend |
| `starts_at` / `expires_at` | timestamptz | fechas de Play |
| `renewal_state` | text check ('active','grace','canceled','expired','refunded','unknown') | estado de renovación |
| `last_verified_at` | timestamptz | marca de última validación |

RLS: ENABLED. SELECT owner-only con columnas no sensibles (el cliente no ve
`purchase_token` — se oculta en la RPC `get_my_entitlements`). INSERT/UPDATE/
DELETE cerrados a `authenticated`: **solo service_role y funciones definer
escriben**. Un usuario no puede auto-conceder Premium por ninguna vía REST.

## 2. RPC (todas autenticadas; REVOKE anon/PUBLIC)

| RPC | Returns | Controles |
|---|---|---|
| `set_discovery_preference(p_enabled, p_location_consent, p_radius_m)` | void | auth.uid(); clamp radius; upsert |
| `get_discovery_preferences()` | jsonb | auth.uid() |
| `upsert_discovery_presence(p_lat, p_lng, p_accuracy_m, p_source, p_radius_m)` | void | auth.uid(); consent on; visibility on; clamp radius; intervalo ≥15 s vs `updated_at`; TTL = now()+30 min |
| `discover_nearby_users(p_lat, p_lng, p_radius_m, p_limit)` | TABLE(id, zone_id, display_name, avatar_url, public_key, distance_m) | auth.uid(); clamp radius≤2000/limit≤50; filtra presencia válida + shadowban + bloqueos mutuos + discovery_enabled del candidato; distancia redondeada a grid 10 m; SIN coords devueltas |
| `expire_my_presence()` | void | auth.uid(); DELETE fila |
| `get_my_entitlements()` | jsonb | auth.uid(); solo filas `verified`; expone product/platform/renewal_state/starts_at/expires_at/last_verified_at; NUNCA `purchase_token` |

Todas declaradas `SECURITY DEFINER SET search_path = TO 'public'` (patrón del
canon), `REVOKE EXECUTE ON FUNCTION ... FROM anon, PUBLIC` + `GRANT ... TO
authenticated` (y `service_role` cuando corresponda).

## 3. Cómo se integra `discover_nearby_users` con la visibilidad existente

La consulta replica el gating de `v_profile` (Z-002/Z-109) sobre:
- `users.is_shadowbanned = false`
- bloqueos bidireccionales: `NOT EXISTS (blocked_users ...)`
- avatar/handles: mismos criterios server-side (campos NULL si privados) — la
  RPC usa `public.v_profile` como fuente de lecturas de terceros (SECURITY
  INVOKER sobre la vista ya la aplica), o el definer revalida explícitamente
  según el SQL final; la migración elige UNA vía y la documenta inline.
- extra exclusivo del geo: `disc.discovery_enabled = true` y presencia TTL viva.

## 4. Migraciones versionadas (archivos)

| Archivo | Contenido |
|---|---|
| `supabase_migrations/z214_discovery_geo.sql` | tablas discovery_preferences/presence + RLS + índices + RPCs de descubrimiento |
| `supabase_migrations/z215_user_entitlements.sql` | tabla entitlements + RLS + RPC `get_my_entitlements` + estructura para escritura por service_role |
| `test/sql_discovery_regression_test.dart` | guarda estática (misma técnica que `sql_security_regression_test.dart`): RLS, revokes, search_path, ausencia de SELECT de coordenadas ajenas, sin grants de escritura authenticated→entitlements |

Propiedades exigidas a las migraciones:
- Aditivas: no ALTER sobre tablas existentes (excepto NO-op seguras si hiciera
  falta; v1 no necesita ninguna).
- Idempotentes: `CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`,
  `DROP POLICY IF EXISTS` + CREATE, `DO $$` para grants condicionales.
- Post-verificación: bloque `-- VERIFY` con asserts (excepciones si RLS off,
  si anon mantiene EXECUTE, etc.).
- `CREATE EXTENSION postgis` **NO se incluye** (decisión D2).

## 5. Rollback (documentado; solo toca objetos nuevos)

```sql
-- Rollback completo del rediseño (no toca canon existente):
DROP FUNCTION IF EXISTS public.get_my_entitlements();
DROP FUNCTION IF EXISTS public.discover_nearby_users(double precision, double precision, integer, integer);
DROP FUNCTION IF EXISTS public.upsert_discovery_presence(double precision, double precision, integer, text, integer);
DROP FUNCTION IF EXISTS public.set_discovery_preference(boolean, boolean, integer);
DROP FUNCTION IF EXISTS public.get_discovery_preferences();
DROP FUNCTION IF EXISTS public.expire_my_presence();
DROP TABLE IF EXISTS public.user_entitlements CASCADE;
DROP TABLE IF EXISTS public.discovery_presence CASCADE;
DROP TABLE IF EXISTS public.discovery_preferences CASCADE;
```

Riesgo de rollback: bajo (objetos nuevos aislados; los datos de presencia son
temporales y su pérdida no rompe matches/mensajes). Los datos de entitlements
perdidos en rollback se reconstruyen re-validando compras en Play (documentado
en ZONE_PREMIUM_BILLING §7).

## 6. Aplicación en producción (PROCEDIMIENTO; requiere owner)

1. Backup: `pg_dump` completo del proyecto (owner) — pre-requisito.
2. Aplicar `z214` y `z215` vía SQL Editor o `supabase db push` autorizado.
3. Post-verificar con `-- VERIFY` de cada archivo + pruebas conductuales (staging).
4. Solo después: habilitar el feature en la app (los RPC fallarán con 404 hasta
   entonces → el cliente lo presenta como "discovery no disponible aún", estado
   tipado, sin crash).
5. Rollback: sección 5.

> Regla del prompt §8: "No ejecutes migraciones remotas todavía" — cumplido:
> esta sesión solo versiona archivos y sus guardas estáticas.
