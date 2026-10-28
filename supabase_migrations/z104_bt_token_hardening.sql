-- Z-104 (FASE 1.7) — Endurecer resolve_bt_token: cerrar el vector anon.
-- ---------------------------------------------------------------------------
-- Problema: con un token BT válido (TTL 10 min), CUALQUIER llamada anon al RPC
-- devolvía el perfil completo del dueño (zone_id, uid, public_key, handles).
-- Además el flag `used` nunca se marca (reuso ilimitado dentro del TTL).
--
-- Decisión CTO (2026-09-23): NO aplicar single-use estricto (`used=TRUE` bloquea
-- la resolución tras el primer consumo) porque rompería el radar bilateral:
-- el MIMO token se comparte por Nearby a TODOS los vecinos, y cada uno lo
-- resuelve contra el mismo usuario dentro del TTL. La mitigación elegida:
--   1) REVOKE EXECUTE a `anon` → solo `authenticated` (y postgres/service_role).
--   2) El acceso directo a `bt_tokens` queda self-scoped (policy
--      "Ver propio token"). Z-212 (2026-10-23) ELIMINÓ la policy amplia
--      "Resolver token BT"; la resolución pasa solo por esta RPC.
--   3) TTL corto (10 min, client) + rotación periódica (cada 5 min) ya limitan
--      la ventana de reuso a usuarios autenticados legítimos.
-- (Criptografía NO tocada: la resolución sigue sin exponer secretos de cifrado;
--  `public_key` del perfil ya se filtra a autenticados igual que v_profile.)
-- ---------------------------------------------------------------------------

-- 1) Revocar EXECUTE a anon/PUBLIC; dejar SOLO authenticated (+ roles superiores).
REVOKE EXECUTE ON FUNCTION public.resolve_bt_token(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.resolve_bt_token(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_bt_token(text) TO authenticated;

-- 2) Verificación en-transacción (FALLA la migración si el resultado es el esperado).
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.resolve_bt_token(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Z-104: anon todavía puede ejecutar resolve_bt_token';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.resolve_bt_token(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Z-104: authenticated NO puede ejecutar resolve_bt_token';
  END IF;
END $$;