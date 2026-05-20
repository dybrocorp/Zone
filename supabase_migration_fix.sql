-- Actualización del sistema de reclamo de Zone ID para evitar duplicados y errores de clave
CREATE OR REPLACE FUNCTION public.claim_zone_id(p_zone_id text, p_public_key text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_uid UUID;
BEGIN
    current_uid := auth.uid();
    
    -- 1. Eliminar cualquier fila temporal que se haya creado para el UID actual
    -- (A veces la app crea una fila vacía antes de que el usuario restaure su ID)
    DELETE FROM public.users 
    WHERE id = current_uid 
      AND zone_id != p_zone_id;

    -- 2. Actualizar la fila antigua con el nuevo UID y la nueva clave pública (si existe)
    UPDATE public.users
    SET id = current_uid,
        public_key = COALESCE(p_public_key, public_key)
    WHERE zone_id = p_zone_id;
    
    -- 3. Si por alguna razón la actualización anterior no afectó a ninguna fila,
    -- significa que el zone_id no existe, entonces no hacemos nada (idempotente).
END;
$$;

-- Asegurar permisos
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text, text) TO anon;
