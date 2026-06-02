-- ============================================================
-- FIX: MEJORAR RENDIMIENTO PARA MÚLTIPLES DISPOSITIVOS (1000+ usuarios)
-- Ejecutar en el SQL Editor de Supabase
-- ============================================================

-- 0. Agregar columna updated_at a la tabla users si no existe
-- Esto es necesario para rastrear actividad reciente de usuarios
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Crear trigger para actualizar updated_at automáticamente cuando se actualiza el perfil
CREATE OR REPLACE FUNCTION public.update_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_updated_at_trigger ON public.users;
CREATE TRIGGER users_updated_at_trigger
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.update_users_updated_at();

-- 1. Agregar índice para soportar consultas de usuarios activos
-- Esto mejora el rendimiento de getActiveUsersForRadar()
CREATE INDEX IF NOT EXISTS idx_users_updated_at ON public.users(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_stealth_mode ON public.users(stealth_mode, is_shadowbanned);

-- 2. Agregar índice compuesto para encounters para mejor rendimiento
CREATE INDEX IF NOT EXISTS idx_encounters_user_seen ON public.encounters(user_id, seen_at DESC, other_zone_id);

-- 3. Crear función para obtener usuarios activos eficientemente
CREATE OR REPLACE FUNCTION public.get_active_users_for_radar(p_limit INT DEFAULT 1000)
RETURNS TABLE (
    id UUID,
    zone_id TEXT,
    display_name TEXT,
    avatar_url TEXT,
    public_key TEXT,
    stealth_mode BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.zone_id,
        u.display_name,
        u.avatar_url,
        u.public_key,
        u.stealth_mode
    FROM public.users u
    WHERE 
        u.is_shadowbanned = FALSE
        AND u.stealth_mode = FALSE
        AND u.updated_at > NOW() - INTERVAL '24 hours'
    ORDER BY u.updated_at DESC
    LIMIT p_limit;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_active_users_for_radar(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_users_for_radar(INT) TO authenticated;

-- 4. Crear vista materializada para caché de usuarios activos
-- Esto reduce la carga en consultas frecuentes
CREATE MATERIALIZED VIEW IF NOT EXISTS public.active_users_cache AS
SELECT 
    id,
    zone_id,
    display_name,
    avatar_url,
    public_key,
    stealth_mode,
    updated_at
FROM public.users
WHERE 
    is_shadowbanned = FALSE
    AND stealth_mode = FALSE
    AND updated_at > NOW() - INTERVAL '24 hours';

-- Crear índice único en la vista materializada
CREATE UNIQUE INDEX IF NOT EXISTS idx_active_users_cache_id ON public.active_users_cache(id);

-- Crear función para refrescar la vista materializada periódicamente
CREATE OR REPLACE FUNCTION public.refresh_active_users_cache()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.active_users_cache;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.refresh_active_users_cache() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_active_users_cache() TO authenticated;

-- 5. Configurar seguridad para la vista materializada
-- NOTA: Las vistas materializadas no soportan RLS directamente
-- En su lugar, usamos GRANT para controlar acceso
GRANT SELECT ON public.active_users_cache TO authenticated;

-- 6. Agregar columna para rastrear última actividad de Bluetooth
-- Esto permite filtrar usuarios realmente activos
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_bt_activity TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_bt_activity ON public.users(last_bt_activity DESC);

-- 7. Crear función para actualizar actividad BT
CREATE OR REPLACE FUNCTION public.update_bt_activity()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.users
    SET last_bt_activity = NOW(),
        updated_at = NOW()
    WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_bt_activity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_bt_activity() TO authenticated;

-- 8. Crear trigger para limpiar tokens antiguos automáticamente
CREATE OR REPLACE FUNCTION public.auto_cleanup_tokens()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM public.bt_tokens 
    WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_cleanup_tokens() FROM PUBLIC;

-- Programar limpieza automática (requiere pg_cron extension)
-- Si pg_cron no está disponible, esto se puede ejecutar manualmente
-- SELECT cron.schedule('cleanup-tokens', '*/30 * * * *', 'SELECT public.auto_cleanup_tokens()');

-- 9. Optimizar configuración de Realtime para alto volumen
-- Aumentar el tamaño del buffer de WebSocket si es posible
-- (Esto requiere configuración a nivel de servidor, no se puede hacer via SQL)

-- 10. Agregar estadísticas para monitoreo
CREATE OR REPLACE FUNCTION public.get_radar_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_stats JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM public.users WHERE is_shadowbanned = FALSE),
        'active_users_24h', (SELECT COUNT(*) FROM public.users WHERE updated_at > NOW() - INTERVAL '24 hours' AND is_shadowbanned = FALSE),
        'active_tokens', (SELECT COUNT(*) FROM public.bt_tokens WHERE expires_at > NOW()),
        'total_encounters', (SELECT COUNT(*) FROM public.encounters WHERE seen_at > NOW() - INTERVAL '24 hours')
    ) INTO v_stats;
    
    RETURN v_stats;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_radar_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_radar_stats() TO authenticated;
