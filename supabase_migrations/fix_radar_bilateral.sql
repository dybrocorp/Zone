-- Ejecutar en Supabase SQL Editor si el radar no resuelve usuarios.
-- Corrige la asimetría: la política exigía used=FALSE aunque el cliente ya no marca tokens usados.

DROP POLICY IF EXISTS "Resolver token BT" ON public.bt_tokens;
CREATE POLICY "Resolver token BT" ON public.bt_tokens
    FOR SELECT TO authenticated
    USING (auth.role() = 'authenticated' AND expires_at > now());

-- RPC centralizado: resolución bilateral sin depender de joins RLS del cliente
CREATE OR REPLACE FUNCTION public.resolve_bt_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile jsonb;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'id', u.id,
    'zone_id', u.zone_id,
    'display_name', u.display_name,
    'avatar_url', u.avatar_url,
    'stealth_mode', u.stealth_mode,
    'public_key', u.public_key,
    'instagram_handle', u.instagram_handle,
    'ig_visible', u.ig_visible,
    'facebook_handle', u.facebook_handle,
    'fb_visible', u.fb_visible,
    'tiktok_handle', u.tiktok_handle,
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
GRANT EXECUTE ON FUNCTION public.resolve_bt_token(text) TO anon;

-- Limpiar tokens marcados como usados (legado) para no bloquear resolución
UPDATE public.bt_tokens SET used = FALSE WHERE used = TRUE;

GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;
