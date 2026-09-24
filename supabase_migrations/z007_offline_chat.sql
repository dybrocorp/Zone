-- ============================================================
-- ZONE · Z-007 — Offline-first chat (delivery/read status) · APLICADA y
-- VERIFICADA en remoto 2026-09-23 (fase 1.5, aprobada CTO 2026-09-23).
--
-- 1) Columnas delivered_at / read_at en messages — estado de entrega y lectura.
-- 2) RPC mark_messages_read(p_match_id, p_reader_id) — marcar leídos al abrir chat.
-- 3) RPC mark_message_delivered(p_message_id, p_reader_id) — marcar entregado al recibir.
--    Ambos: SECURITY DEFINER + gate server-side auth.uid() == p_*_id (sin anon/PUBLIC),
--    verificación de match aceptado y participación server-side, grants
--    {authenticated, service_role}.
--
-- Idempotencia del outbox (Z-007): la app genera el PK `id` del mensaje como UUID v4
-- de cliente y usa INSERT ... ON CONFLICT (id) DO NOTHING vía PostgREST
-- (upsert con ignoreDuplicates: true). NO se añade columna client_id — el PK ya es
-- estable y único; los reintentos reutilizan el MISMO id → insert idempotente.
-- ============================================================

-- ----------------------------------------------------------------------------
-- A) Columnas de delivery/read en messages
-- ----------------------------------------------------------------------------
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- B) mark_messages_read — marcar como leídos los mensajes del otro al abrir el chat
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_messages_read(
  p_match_id UUID,
  p_reader_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Gate server-side: solo mi sesión autenticada puede marcar lectura.
  IF auth.uid() IS NULL OR auth.uid() <> p_reader_id THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  UPDATE public.messages
     SET read_at = COALESCE(read_at, now())
   WHERE match_id = p_match_id
     AND sender_id <> p_reader_id
     AND read_at IS NULL
     AND EXISTS (
       SELECT 1 FROM public.matches m
       WHERE m.id = messages.match_id
         AND m.status = 'accepted'
         AND (m.requester_id = p_reader_id OR m.receiver_id = p_reader_id)
     );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_messages_read(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_messages_read(uuid, uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- C) mark_message_delivered — marcar como entregado al recibirlo (sender != reader)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_message_delivered(
  p_message_id UUID,
  p_reader_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_reader_id THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  UPDATE public.messages
     SET delivered_at = COALESCE(delivered_at, now())
   WHERE id = p_message_id
     AND sender_id <> p_reader_id
     AND delivered_at IS NULL
     AND EXISTS (
       SELECT 1 FROM public.matches m
       WHERE m.id = messages.match_id
         AND m.status = 'accepted'
         AND (m.requester_id = p_reader_id OR m.receiver_id = p_reader_id)
     );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_message_delivered(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_message_delivered(uuid, uuid) TO authenticated, service_role;

-- ============================================================================
-- VERIFICACIÓN EN-TRANSACCIÓN (si una aserción falla → ROLLBACK automático)
-- ============================================================================

DO $verify$
DECLARE
    v_cols INT;
    v_bad  INT;
BEGIN
    -- Columnas presentes.
    SELECT count(*) INTO v_cols
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages'
      AND column_name IN ('delivered_at', 'read_at');
    IF v_cols <> 2 THEN
        RAISE EXCEPTION 'Z-007 VERIFICACION FALLIDA: columnas delivery %/2', v_cols;
    END IF;

    -- Ninguna RPC ejecutable por anon/PUBLIC.
    SELECT count(*) INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('mark_messages_read', 'mark_message_delivered')
      AND (has_function_privilege('anon', p.oid, 'EXECUTE')
        OR has_function_privilege('public', p.oid, 'EXECUTE'));
    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Z-007 VERIFICACION FALLIDA: % RPC ejecutable por anon/PUBLIC', v_bad;
    END IF;

    -- authenticated conserva EXECUTE en ambos.
    IF NOT (
        has_function_privilege('authenticated', 'public.mark_messages_read(uuid, uuid)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.mark_message_delivered(uuid, uuid)', 'EXECUTE')
    ) THEN
        RAISE EXCEPTION 'Z-007 VERIFICACION FALLIDA: authenticated debe ejecutar las RPC';
    END IF;
END;
$verify$;
