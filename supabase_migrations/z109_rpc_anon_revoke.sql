-- ============================================================
-- ZONE · Z-109 — Cerrar RPC drift con GRANT anon · APROBADO CTO 2026-09-23 (batch A–F)
-- Objetivo: ninguna función de datos del radar queda ejecutable por anon/PUBLIC,
-- y `get_active_users_for_radar` hereda el gating server-side de Z-002 (v_profile).
-- Aplicar vía Management API en transacción atómica (sb_apply.ps1 envuelve BEGIN/COMMIT).
-- TODO en este archivo es idempotente (CREATE OR REPLACE / REVOKE / GRANT).
-- ============================================================

-- ----------------------------------------------------------------------------
-- A) get_active_users_for_radar → SECURITY INVOKER sobre v_profile
--    Hereda todos los filtros de Z-002 (avatar_is_public, shadowban, bloqueos
--    mutuos) + el filtro stealth_mode que ya tenía la versión original.
--    anon/PUBLIC revocados → solo authenticated + service_role.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_users_for_radar(p_limit integer DEFAULT 1000)
 RETURNS TABLE(id uuid, zone_id text, display_name text, avatar_url text, public_key text, stealth_mode boolean)
 LANGUAGE sql
 SECURITY INVOKER
 SET search_path TO 'public'
AS $$
    SELECT v.id, v.zone_id, v.display_name, v.avatar_url, v.public_key, v.stealth_mode
    FROM public.v_profile v
    WHERE v.stealth_mode = FALSE
    ORDER BY v.updated_at DESC
    LIMIT p_limit;
$$;

REVOKE EXECUTE ON FUNCTION public.get_active_users_for_radar(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_users_for_radar(integer) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- B) get_radar_stats → gate de sesión + revoke anon (métricas agregadas = fuga P2).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_radar_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_stats JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM public.users WHERE is_shadowbanned = FALSE),
        'active_users_24h', (SELECT COUNT(*) FROM public.users WHERE updated_at > NOW() - INTERVAL '24 hours' AND is_shadowbanned = FALSE),
        'active_tokens', (SELECT COUNT(*) FROM public.bt_tokens WHERE expires_at > NOW()),
        'total_encounters', (SELECT COUNT(*) FROM public.encounters WHERE seen_at > NOW() - INTERVAL '24 hours')
    ) INTO v_stats;

    RETURN v_stats;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_radar_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_radar_stats() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- C) refresh_active_users_cache → solo mantenimiento (revoke anon/auth):
--    anon no debe poder disparar REFRESH MATERIALIZED VIEW CONCURRENTLY (abuso/DoS).
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.refresh_active_users_cache() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_active_users_cache() TO service_role;

-- ----------------------------------------------------------------------------
-- D) auto_cleanup_tokens → solo mantenimiento (revoke anon/auth).
--    El canon de limpieza que usa la app es `cleanup_expired_tokens` ({postgres, service_role}).
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.auto_cleanup_tokens() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_cleanup_tokens() TO service_role;

-- ----------------------------------------------------------------------------
-- E) update_bt_activity → revoke anon (la función usa auth.uid(); grant anon = superficie).
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.update_bt_activity() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_bt_activity() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- F) update_users_updated_at → revoke PUBLIC (defensivo; la invocación del
--    trigger no depende de grants EXECUTE).
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.update_users_updated_at() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- VERIFICACIÓN EN-TRANSACCIÓN (si una aserción falla → ROLLBACK automático)
-- ============================================================================

DO $verify$
DECLARE
    v_bad INT;
BEGIN
    -- Ninguna de las 6 debe quedar ejecutable por anon ni PUBLIC.
    SELECT count(*) INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'get_active_users_for_radar',
        'get_radar_stats',
        'refresh_active_users_cache',
        'auto_cleanup_tokens',
        'update_bt_activity',
        'update_users_updated_at'
      )
      AND (has_function_privilege('anon', p.oid, 'EXECUTE')
        OR has_function_privilege('public', p.oid, 'EXECUTE'));

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Z-109 VERIFICACION FALLIDA: % funcion(es) ejecutables por anon/PUBLIC', v_bad;
    END IF;
END;
$verify$;

DO $verify$
BEGIN
    -- get_active_users_for_radar debe ser SECURITY INVOKER (prosecdef = false) sobre v_profile.
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'get_active_users_for_radar'
          AND p.prosecdef = FALSE
          AND position('v_profile' in pg_get_functiondef(p.oid)) > 0
    ) THEN
        RAISE EXCEPTION 'Z-109: get_active_users_for_radar debe ser SECURITY INVOKER sobre v_profile';
    END IF;

    -- authenticated debe conservar EXECUTE en las 3 RPC que usa la app.
    IF NOT (
        has_function_privilege('authenticated', 'public.get_active_users_for_radar(integer)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.get_radar_stats()', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.update_bt_activity()', 'EXECUTE')
    ) THEN
        RAISE EXCEPTION 'Z-109: authenticated debe mantener EXECUTE en las RPC de app';
    END IF;
END;
$verify$;