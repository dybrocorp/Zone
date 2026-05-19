-- ============================================================
-- FIX: HABILITAR ELIMINACIÓN DE CHATS (MATCHES)
-- Ejecutar en el SQL Editor de Supabase
-- ============================================================

-- 1. Asegurar que no exista una política vieja con este nombre
DROP POLICY IF EXISTS "Eliminar propios matches" ON public.matches;

-- 2. Crear la política que permite a cualquiera de los dos participantes eliminar el chat
CREATE POLICY "Eliminar propios matches" ON public.matches
    FOR DELETE TO authenticated 
    USING (auth.uid() = requester_id OR auth.uid() = receiver_id);

-- Nota: Como public.messages tiene ON DELETE CASCADE, al eliminar 
-- el match, PostgreSQL borrará todos los mensajes asociados automáticamente,
-- ignorando el RLS para la cascada (lo cual es seguro y deseado).
