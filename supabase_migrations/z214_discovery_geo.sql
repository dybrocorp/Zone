-- ============================================================================
-- Z-214 — Descubrimiento geográfico (GPS + Red): preferencias, presencia
--         temporal y RPCs autorizadas.
--
-- Diseño   : docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md (D2, D3, D7, D8)
-- Privacidad: docs/redesign/ZONE_DISCOVERY_PRIVACY.md
-- Aplicación: SOLO CON AUTORIZACIÓN DEL OWNER (no ejecutar en esta sesión).
--             Aditivo: no toca tablas canon existentes.
-- Postgres moderno compatible (no requiere PostGIS; decisión D2).
--
-- Semántica de visibilidad (server-side, no negociable):
--   location_sharing_enabled = FALSE  → NINGUNA coordenada almacenada; sin fila.
--   discovery_enabled       = FALSE  → presencia puede existir (consentimiento
--                                       activo) pero NUNCA aparece en búsquedas.
--
-- Rollback: docs/redesign/ZONE_DATA_MIGRATION.md §5.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PREFERENCIAS DE DESCUBRIMIENTO (1 fila por usuario)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discovery_preferences (
    user_id UUID PRIMARY KEY
        REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    discovery_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    location_sharing_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    radius_m INTEGER NOT NULL DEFAULT 500
        CHECK (radius_m >= 250 AND radius_m <= 2000),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.discovery_preferences ENABLE ROW LEVEL SECURITY;

-- Owner-only: SELECT/UPDATE con WITH CHECK. INSERT/DELETE CERRADOS (sin policy):
-- los upserts únicamente vía RPC definer (canal único seguro).
DROP POLICY IF EXISTS "discovery_prefs_owner_select" ON public.discovery_preferences;
CREATE POLICY "discovery_prefs_owner_select" ON public.discovery_preferences
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "discovery_prefs_owner_update" ON public.discovery_preferences;
CREATE POLICY "discovery_prefs_owner_update" ON public.discovery_preferences
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 2. PRESENCIA TEMPORAL (1 fila por usuario; TTL 30 min server-side)
--    RLS ENABLED sin policies → deny-all total por REST. Solo funciones
--    SECURITY DEFINER leen/escriben (patrón canon: update_bt_activity).
--    NUNCA se expone lat/lng de otros usuarios por API.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discovery_presence (
    user_id UUID PRIMARY KEY
        REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lng DOUBLE PRECISION NOT NULL CHECK (lng BETWEEN -180 AND 180),
    accuracy_m INTEGER NOT NULL CHECK (accuracy_m >= 0 AND accuracy_m <= 1000),
    source TEXT NOT NULL DEFAULT 'network' CHECK (source IN ('gps','network')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
        CHECK (expires_at > now())      -- nunca entra sin TTL futuro
);

ALTER TABLE public.discovery_presence ENABLE ROW LEVEL SECURITY;
-- DELIBERADO: sin ninguna policy → ningún rol lee por REST (ni el dueño;
-- sus propios datos regresan vía RPC autenticadas si el diseño lo requiere).

CREATE INDEX IF NOT EXISTS idx_discovery_presence_expires
    ON public.discovery_presence (expires_at);
CREATE INDEX IF NOT EXISTS idx_discovery_presence_bbox
    ON public.discovery_presence (lat, lng);

-- ----------------------------------------------------------------------------
-- 3. DISTANCIA GEODÉSICA (helper interno; NO ejecutable por clientes)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.zone_geo_distance_m(
    lat1 double precision, lng1 double precision,
    lat2 double precision, lng2 double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT 6371000.0 * acos(
        least(1.0, greatest(-1.0,
            sin(radians(lat1)) * sin(radians(lat2)) +
            cos(radians(lat1)) * cos(radians(lat2)) * cos(radians(lng2 - lng1))
        ))
    );
$$;

REVOKE EXECUTE ON FUNCTION public.zone_geo_distance_m(double precision, double precision, double precision, double precision)
    FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. RPC: PREFERENCIA (canal único, aplica cleanup de coords al revoke)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_discovery_preference(
    p_enabled boolean,
    p_location_consent boolean,
    p_radius_m integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_radius integer := LEAST(GREATEST(COALESCE(p_radius_m, 500), 250), 2000);
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.discovery_preferences
        (user_id, discovery_enabled, location_sharing_enabled, radius_m, updated_at)
    VALUES (v_uid, COALESCE(p_enabled, FALSE), COALESCE(p_location_consent, FALSE), v_radius, now())
    ON CONFLICT (user_id) DO UPDATE
        SET discovery_enabled        = COALESCE(p_enabled, FALSE),
            location_sharing_enabled = COALESCE(p_location_consent, FALSE),
            radius_m                 = v_radius,
            updated_at               = now();

    -- Revocación del consentimiento de ubicación: ninguna coordenada del
    -- usuario puede permanecer en el servidor (privacidad §4 / §1.9).
    IF NOT COALESCE(p_location_consent, FALSE) THEN
        DELETE FROM public.discovery_presence WHERE user_id = v_uid;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. RPC: PING DE PRESENCIA (auth + consent + clamp + anti-abuso + TTL)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_discovery_presence(
    p_lat double precision,
    p_lng double precision,
    p_accuracy_m integer,
    p_source text,
    p_radius_m integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_prefs public.discovery_preferences;
    v_existing public.discovery_presence;
    v_now timestamptz := now();
    v_jump_m double precision;
    v_elapsed_s double precision;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_prefs FROM public.discovery_preferences WHERE user_id = v_uid;

    -- Sin consentimiento de ubicación: sin presencia, sin coordenadas (§4.2).
    IF NOT COALESCE(v_prefs.location_sharing_enabled, FALSE) THEN
        DELETE FROM public.discovery_presence WHERE user_id = v_uid;
        RETURN;
    END IF;

    -- Anti-abuso (excesivas peticiones): máximo un ping vigente cada 15 s.
    -- Silencioso (no error): los re-pings agresivos simplemente no-op.
    SELECT * INTO v_existing FROM public.discovery_presence
     WHERE user_id = v_uid FOR UPDATE;
    IF v_existing.user_id IS NOT NULL
       AND v_existing.updated_at > v_now - INTERVAL '15 seconds' THEN
        RETURN;
    END IF;

    -- Anti-teleport: velocidad física imposible (> 350 m/s) conserva estado.
    IF v_existing.user_id IS NOT NULL THEN
        v_elapsed_s := GREATEST(1, EXTRACT(EPOCH FROM (v_now - v_existing.updated_at)));
        v_jump_m := public.zone_geo_distance_m(
            v_existing.lat, v_existing.lng, p_lat, p_lng);
        IF (v_jump_m / v_elapsed_s) > 350.0::float8 THEN
            RETURN;
        END IF;
    END IF;

    INSERT INTO public.discovery_presence
        (user_id, lat, lng, accuracy_m, source, updated_at, expires_at)
    VALUES (
        v_uid,
        p_lat,
        p_lng,
        LEAST(GREATEST(COALESCE(p_accuracy_m, 1000), 0), 1000),
        CASE WHEN p_source = 'gps' THEN 'gps' ELSE 'network' END,
        v_now,
        v_now + INTERVAL '30 minutes'      -- TTL server-side (decisión D7)
    )
    ON CONFLICT (user_id) DO UPDATE
        SET lat         = EXCLUDED.lat,
            lng         = EXCLUDED.lng,
            accuracy_m  = EXCLUDED.accuracy_m,
            source      = EXCLUDED.source,
            updated_at  = EXCLUDED.updated_at,
            expires_at  = EXCLUDED.expires_at;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. RPC: BÚSQUEDA GEOGRÁFICA
--    - auth + presencia válida del llamador (anti-enumeración)
--    - clamp de radius (≤ 2000) y limit (≤ 50) server-side
--    - filtra: presencia TTL viva del candidato, shadowban, bloqueos mutuos,
--      discovery_enabled del candidato (visibilidad autoritativa server)
--    - devuelve SOLO campos de perfil autorizados + distancia truncada (grid
--      10 m). NUNCA lat/lng de otros usuarios.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.discover_nearby_users(
    p_lat double precision,
    p_lng double precision,
    p_radius_m integer,
    p_limit integer
)
RETURNS TABLE(id uuid, zone_id text, display_name text, avatar_url text,
              public_key text, distance_m integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    WITH params AS (
        SELECT
            LEAST(GREATEST(COALESCE(p_radius_m, 500), 250), 2000)::double precision
                AS radius_m,
            LEAST(GREATEST(COALESCE(p_limit,    50),    1),   50)::bigint
                AS row_limit
    )
    SELECT
        vp.id,
        vp.zone_id,
        vp.display_name,
        CASE WHEN vp.avatar_is_public THEN vp.avatar_url ELSE NULL END,
        vp.public_key,
        (ROUND(public.zone_geo_distance_m(p_lat, p_lng, pres.lat, pres.lng) / 10) * 10)::integer
            AS distance_m
    FROM public.discovery_presence pres
    JOIN params prm ON TRUE
    JOIN public.discovery_preferences dp
        ON dp.user_id = pres.user_id AND dp.discovery_enabled = TRUE
    JOIN public.users vp ON vp.id = pres.user_id
    WHERE
        -- Anti-enumeración: el llamador debe tener presencia propia vigente.
        EXISTS (
            SELECT 1
            FROM public.discovery_presence me
            JOIN public.discovery_preferences mp ON mp.user_id = me.user_id
            WHERE me.user_id = auth.uid()
              AND me.expires_at > now()
              AND mp.location_sharing_enabled = TRUE
        )
        -- Privacidad del candidato
        AND pres.user_id <> auth.uid()
        AND pres.expires_at > now()
        AND vp.is_shadowbanned = FALSE
        -- Bloqueos mutuos: igual gating que el radar BT y la vista v_profile
        AND NOT EXISTS (
            SELECT 1 FROM public.blocked_users b
            WHERE (b.blocker_id = pres.user_id AND b.blocked_id = auth.uid())
               OR (b.blocker_id = auth.uid() AND b.blocked_id = pres.user_id)
        )
        -- Circunferencia exacta (haversine) dentro del radio
        AND public.zone_geo_distance_m(p_lat, p_lng, pres.lat, pres.lng) <= (prm.radius_m + 50.0)
        -- Prefiltro b-box (índice idx_discovery_presence_bbox)
        AND pres.lat BETWEEN (p_lat - (prm.radius_m / 111320.0))
                         AND (p_lat + (prm.radius_m / 111320.0))
        AND pres.lng BETWEEN (p_lng - (prm.radius_m / (111320.0 * GREATEST(0.2, cos(radians(p_lat))))))
                         AND (p_lng + (prm.radius_m / (111320.0 * GREATEST(0.2, cos(radians(p_lat))))))
    ORDER BY distance_m ASC
    LIMIT prm.row_limit;
$$;

-- ----------------------------------------------------------------------------
-- 7. RPC: OCULTARSE INMEDIATO
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_my_presence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado' USING ERRCODE = '42501';
    END IF;
    DELETE FROM public.discovery_presence WHERE user_id = auth.uid();
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. RPC: MIS PREFERENCIAS (lectura autenticada de la fila propia)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_discovery_preferences()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_prefs public.discovery_preferences;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_prefs FROM public.discovery_preferences WHERE user_id = v_uid;
    RETURN jsonb_build_object(
        'discovery_enabled',        COALESCE(v_prefs.discovery_enabled, FALSE),
        'location_sharing_enabled', COALESCE(v_prefs.location_sharing_enabled, FALSE),
        'radius_m',                 COALESCE(v_prefs.radius_m, 500)
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. GRANTS DE RPC (REVOKE total + GRANT solo authenticated; patrón canon)
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.set_discovery_preference(boolean, boolean, integer)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_discovery_preference(boolean, boolean, integer)
    TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.upsert_discovery_presence(double precision, double precision, integer, text, integer)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_discovery_presence(double precision, double precision, integer, text, integer)
    TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.discover_nearby_users(double precision, double precision, integer, integer)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discover_nearby_users(double precision, double precision, integer, integer)
    TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.expire_my_presence()
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_my_presence()
    TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_discovery_preferences()
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_discovery_preferences()
    TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 10. LIMPIEZA DE PRESENCIA EXPIRADA (service_role/cron; seguro por defecto)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_cleanup_discovery_presence()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    deleted integer;
BEGIN
    DELETE FROM public.discovery_presence
     WHERE expires_at < now() - INTERVAL '1 day';
    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_cleanup_discovery_presence()
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_cleanup_discovery_presence() TO service_role;

-- ----------------------------------------------------------------------------
-- 11. VERIFY (post-conditions; falla el UPDATE si algo quedó mal)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    -- RLS actives
    IF NOT (SELECT relrowsecurity FROM pg_class
             WHERE relname = 'discovery_preferences') THEN
        RAISE EXCEPTION 'VERIFY FALLA: discovery_preferences sin RLS';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class
             WHERE relname = 'discovery_presence') THEN
        RAISE EXCEPTION 'VERIFY FALLA: discovery_presence sin RLS';
    END IF;
    -- Sin políticas de lectura sobre presence (deny-all)
    IF (SELECT COUNT(*) FROM pg_policy
         WHERE polrelid = 'public.discovery_presence'::regclass) <> 0 THEN
        RAISE EXCEPTION 'VERIFY FALLA: discovery_presence no debe tener policies';
    END IF;
END $$;
