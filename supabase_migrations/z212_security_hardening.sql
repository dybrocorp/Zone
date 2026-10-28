-- =============================================================================
-- Z-212 · Security hardening (2026-10-23)
-- =============================================================================
-- Cierra cuatro defectos demostrados en la auditoría CTO:
--
--   1. claim_zone_id permitía account takeover: cualquier usuario autenticado
--      reescribía users.id de un ZONE-ID ajeno sin prueba de posesión.
--      → La RPC conserva firma/grants pero falla cerrado (cuarentena).
--   2. messages UPDATE permitía a un participante reescribir sender_id,
--      ciphertext, nonce, mac o match_id (forgery/tampering).
--      → Se elimina el UPDATE directo; trigger de columnas inmutables.
--   3. matches UPDATE no tenía WITH CHECK ni protegía el par: el receiver
--      podía reescribir requester_id/receiver_id o degradar un accepted.
--      → WITH CHECK + trigger de identidad/estado.
--   4. La política SELECT amplia de bt_tokens exponía token → user_id de
--      todos los usuarios activos; resolve_bt_token devolvía handles/avatar
--      privados. → Se elimina la política; la RPC exige sesión y aplica
--      visibilidad server-side.
--
-- Idempotente. NO aplicar a producción sin autorización explícita.
-- =============================================================================

BEGIN;

-- ─── 1. claim_zone_id: cuarentena fail-closed ───────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_zone_id(p_zone_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesión autenticada';
  END IF;
  RAISE EXCEPTION
    'Reclamo de ZONE-ID deshabilitado temporalmente por seguridad (Z-212).';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_zone_id(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text) TO authenticated;

-- ─── 1b. users: moderación/identidad inmutables para autenticados ──────────
-- service_role (sin auth.uid()) conserva acceso administrativo. Las funciones
-- de moderación confiables marcan la transacción con
-- zone.allow_protected_user_write=1.
CREATE OR REPLACE FUNCTION public.enforce_user_protected_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND coalesce(
       current_setting('zone.allow_protected_user_write', true), ''
     ) <> '1' THEN
    IF NEW.id             IS DISTINCT FROM OLD.id
       OR NEW.zone_id     IS DISTINCT FROM OLD.zone_id
       OR NEW.reports_count IS DISTINCT FROM OLD.reports_count
       OR NEW.is_shadowbanned IS DISTINCT FROM OLD.is_shadowbanned
       OR NEW.created_at  IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'users: columnas protegidas inmutables (Z-212)';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_protected_columns ON public.users;
CREATE TRIGGER trg_users_protected_columns
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.enforce_user_protected_columns();

-- handle_new_report escribe reports_count/is_shadowbanned; debe marcar la
-- transacción como escritura de moderación confiable o el trigger anterior la
-- bloquearía y los reportes dejarían de aplicar shadowban.
CREATE OR REPLACE FUNCTION public.handle_new_report()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM set_config('zone.allow_protected_user_write', '1', true);
    UPDATE public.users
    SET reports_count = reports_count + 1,
        is_shadowbanned = CASE WHEN reports_count + 1 >= 3 THEN TRUE ELSE is_shadowbanned END
    WHERE id = NEW.reported_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.handle_new_report() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_new_report ON public.reports;
CREATE TRIGGER on_new_report
    AFTER INSERT ON public.reports
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_report();

-- ─── 2. bt_tokens: cerrar SELECT amplio ─────────────────────────────────────
DROP POLICY IF EXISTS "Resolver token BT" ON public.bt_tokens;

-- ─── 3. resolve_bt_token: sesión + visibilidad server-side ──────────────────
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

REVOKE EXECUTE ON FUNCTION public.resolve_bt_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_bt_token(text) TO authenticated;

-- ─── 4. matches: WITH CHECK + identidad/estado inmutables ───────────────────
DROP POLICY IF EXISTS "Aceptar o rechazar match" ON public.matches;
CREATE POLICY "Aceptar o rechazar match" ON public.matches
    FOR UPDATE TO authenticated
    USING (auth.uid() = receiver_id)
    WITH CHECK (auth.uid() = receiver_id);

CREATE OR REPLACE FUNCTION public.enforce_match_immutable_participants()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.id           IS DISTINCT FROM OLD.id
     OR NEW.requester_id IS DISTINCT FROM OLD.requester_id
     OR NEW.receiver_id  IS DISTINCT FROM OLD.receiver_id
     OR NEW.created_at   IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'matches: participantes e identidad son inmutables (Z-212)';
  END IF;
  IF OLD.status = 'accepted' AND NEW.status IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'matches: un match aceptado no puede degradarse (Z-212)';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matches_immutable_participants ON public.matches;
CREATE TRIGGER trg_matches_immutable_participants
    BEFORE UPDATE ON public.matches
    FOR EACH ROW EXECUTE FUNCTION public.enforce_match_immutable_participants();

-- ─── 5. messages: sin UPDATE directo + columnas inmutables ──────────────────
DROP POLICY IF EXISTS "Actualizar mensaje con match aceptado" ON public.messages;

CREATE OR REPLACE FUNCTION public.enforce_message_immutable_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.id              IS DISTINCT FROM OLD.id
     OR NEW.match_id     IS DISTINCT FROM OLD.match_id
     OR NEW.sender_id    IS DISTINCT FROM OLD.sender_id
     OR NEW.encrypted_content IS DISTINCT FROM OLD.encrypted_content
     OR NEW.nonce        IS DISTINCT FROM OLD.nonce
     OR NEW.mac          IS DISTINCT FROM OLD.mac
     OR NEW.created_at   IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'messages: identidad y contenido son inmutables (Z-212)';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_immutable ON public.messages;
CREATE TRIGGER trg_messages_immutable
    BEFORE UPDATE ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.enforce_message_immutable_columns();

COMMIT;
