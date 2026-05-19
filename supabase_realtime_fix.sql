-- ============================================================
-- FIX: HABILITAR SUPABASE REALTIME (Mensajería instantánea)
-- Ejecutar en el SQL Editor de Supabase
-- ============================================================

-- 1. Habilitar la replicación (Postgres Changes) para los mensajes
-- Esto asegura que si el Broadcast falla, la base de datos empujará
-- los cambios al instante.
DO $$ 
BEGIN 
  -- Añadir tabla messages a la publicación si no está
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;

  -- Añadir tabla matches a la publicación si no está
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'matches'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.matches;
  END IF;
END $$;

-- 2. Asegurarnos que la tabla messages tiene permisos REPLICA correctos
ALTER TABLE public.messages REPLICA IDENTITY FULL;

-- Nota: Broadcast y Presence funcionan a nivel de WebSocket, 
-- por lo que si el canal se conecta correctamente, funcionarán de forma nativa.
