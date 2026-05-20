-- ============================================================
-- RECUPERACIÓN DE EMERGENCIA
-- Ejecuta este script INMEDIATAMENTE en el SQL Editor de Supabase
-- ============================================================

-- PASO 1: Restaurar la función claim_zone_id a su versión SEGURA
-- (La versión anterior tenía un DELETE peligroso que borró perfiles)
CREATE OR REPLACE FUNCTION public.claim_zone_id(p_zone_id text, p_public_key text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_uid UUID;
BEGIN
    current_uid := auth.uid();
    
    -- Solo actualizar el dueño y la clave pública, SIN borrar nada
    UPDATE public.users
    SET id = current_uid,
        public_key = COALESCE(p_public_key, public_key)
    WHERE zone_id = p_zone_id;
    
END;
$$;

-- Mantener permisos
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text, text) TO anon;

-- Mantener compatibilidad con versión anterior sin el segundo parámetro
DROP FUNCTION IF EXISTS public.claim_zone_id(text);

-- ============================================================
-- PASO 2: Ver qué usuarios quedaron en la base de datos
-- (Solo para diagnóstico, no modifica nada)
-- ============================================================
SELECT id, zone_id, display_name, public_key IS NOT NULL AS has_key, created_at
FROM public.users
ORDER BY created_at DESC
LIMIT 20;
