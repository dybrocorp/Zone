-- ============================================================================
-- HISTÓRICO — fix_radar_bilateral.sql (pre Z-104 / Z-212)
-- Ejecutar en Supabase SQL Editor si el radar no resuelve usuarios.
-- Corrige la asimetría: la política exigía used=FALSE aunque el cliente ya no
-- marca tokens usados.
--
-- Z-212 (2026-10-23) — SUPERSEDED: este archivo se conserva por historia, pero
-- si se re-aplica instala el estado seguro y NO reintroduce los vectores:
--   1. NO crea la policy SELECT amplia "Resolver token BT" (la elimina).
--      El acceso directo a bt_tokens queda self-scoped; la resolución pasa
--      exclusivamente por la RPC.
--   2. resolve_bt_token exige auth.uid() y aplica visibilidad server-side
--      (avatar/handles privados nunca se devuelven).
--   3. NO resetea `used` (flag obsoleto; mutación de datos innecesaria).
-- ============================================================================

DROP POLICY IF EXISTS "Resolver token BT" ON public.bt_tokens;

-- RPC centralizado: resolución bilateral sin depender de joins RLS del cliente.
-- Z-212: gate de sesión + filtrado de visibilidad (equivalente al canónico).
CREATE OR REPLACE FUNCTION public.resolve_bt_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesión autenticada';
  END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 OR trim(p_token) = 'ZONE-INIT' THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'id', u.id,
    'zone_id', u.zone_id,
    'display_name', u.display_name,
    'avatar_url', CASE WHEN u.avatar_is_public THEN u.avatar_url ELSE NULL END,
    'stealth_mode', u.stealth_mode,
    'public_key', u.public_key,
    'instagram_handle', CASE WHEN u.ig_visible THEN u.instagram_handle ELSE NULL END,
    'ig_visible', u.ig_visible,
    'facebook_handle', CASE WHEN u.fb_visible THEN u.facebook_handle ELSE NULL END,
    'fb_visible', u.fb_visible,
    'tiktok_handle', CASE WHEN u.tiktok_visible THEN u.tiktok_handle ELSE NULL END,
    'tiktok_visible', u.tiktok_visible
  ) INTO v_profile
  FROM public.bt_tokens t
  INNER JOIN public.users u ON u.id = t.user_id
  WHERE t.token = p_token
    AND t.expires_at > now()
    AND u.is_shadowbanned = FALSE
    AND u.stealth_mode = FALSE;

  RETURN v_profile;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.resolve_bt_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_bt_token(text) TO authenticated;
-- Z-104 (FASE 1.7): anon YA NO ejecuta (ver supabase_migrations/z104_bt_token_hardening.sql).
-- Este parche histórico queda solo para re-ejecución segura sin reintroducir el vector.
REVOKE EXECUTE ON FUNCTION public.resolve_bt_token(text) FROM anon;

-- Nota Z-212: el GRANT de delete_own_account que tenía este parche histórico se
-- elimina de aquí; pertenece al esquema canónico y no a la resolución de tokens.
