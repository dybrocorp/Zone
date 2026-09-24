-- ============================================================
-- ZONE · Z-106 + Z-206 — Policies RLS faltantes (DELETE/UPDATE) · FASE 1.6
--
-- Z-106: `matches` NO tenía policy FOR DELETE → `deleteMatch` fallaba
--        silenciosamente (derecho al borrado roto).
-- Z-206: `messages` solo tenía SELECT/INSERT → `deleteMessage` y las futuras
--        ediciones/receipts directos fallaban por RLS.
--
-- Práctica de mínima superficie (decisión CTO, ver CTO_REVIEW_REQUIRED §12):
--  - matches: DELETE solo para los dos participantes (requester/receiver).
--  - messages: UPDATE y DELETE solo para participantes de un match ACEPTADO,
--    con la MISMA semántica server-side que las RPC Z-007 (sin anon/PUBLIC).
--  - No se toca criptografía, ni columnas nuevas, ni funciones existentes.
-- ============================================================

-- ----------------------------------------------------------------------------
-- A) Z-106 — matches: permitir borrar SOLO los matches propios
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Eliminar propio match" ON public.matches;
CREATE POLICY "Eliminar propio match" ON public.matches
    FOR DELETE TO authenticated
    USING (auth.uid() = requester_id OR auth.uid() = receiver_id);

-- ----------------------------------------------------------------------------
-- B) Z-206 — messages: UPDATE/DELETE entre participantes de match aceptado
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Actualizar mensaje con match aceptado" ON public.messages;
CREATE POLICY "Actualizar mensaje con match aceptado" ON public.messages
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.matches m
            WHERE m.id = messages.match_id
              AND m.status = 'accepted'
              AND (m.requester_id = auth.uid() OR m.receiver_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Eliminar mensaje con match aceptado" ON public.messages;
CREATE POLICY "Eliminar mensaje con match aceptado" ON public.messages
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.matches m
            WHERE m.id = messages.match_id
              AND m.status = 'accepted'
              AND (m.requester_id = auth.uid() OR m.receiver_id = auth.uid())
        )
    );

-- ============================================================================
-- VERIFICACIÓN EN-TRANSACCIÓN (si una aserción falla → ROLLBACK automático)
-- ============================================================================

DO $verify$
DECLARE
    v_match_del   BOOLEAN;
    v_msg_upd     BOOLEAN;
    v_msg_del     BOOLEAN;
BEGIN
    -- matches: existe policy DELETE de participantes.
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'matches'
          AND cmd = 'DELETE' AND policyname = 'Eliminar propio match'
          AND roles :: text[] @> ARRAY['authenticated']
    ) INTO v_match_del;
    IF NOT v_match_del THEN
        RAISE EXCEPTION 'Z-106 VERIFICACION FALLIDA: sin policy DELETE en matches';
    END IF;

    -- messages: existen policy UPDATE y DELETE de participantes.
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'messages'
          AND cmd = 'UPDATE' AND policyname = 'Actualizar mensaje con match aceptado'
          AND roles :: text[] @> ARRAY['authenticated']
    ) INTO v_msg_upd;
    IF NOT v_msg_upd THEN
        RAISE EXCEPTION 'Z-206 VERIFICACION FALLIDA: sin policy UPDATE en messages';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'messages'
          AND cmd = 'DELETE' AND policyname = 'Eliminar mensaje con match aceptado'
          AND roles :: text[] @> ARRAY['authenticated']
    ) INTO v_msg_del;
    IF NOT v_msg_del THEN
        RAISE EXCEPTION 'Z-206 VERIFICACION FALLIDA: sin policy DELETE en messages';
    END IF;
END;
$verify$;