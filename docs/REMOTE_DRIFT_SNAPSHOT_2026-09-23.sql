-- ============================================================
-- ZONE Â· SNAPSHOT DRIFT SOLO-REMOTO (Z-109) Â· 2026-09-23
-- Dump read-only via Management API de funciones public.* en produccion
-- Proposito: consolidar la definicion canonica en supabase_schema.sql/deploy
-- ============================================================

-- >>> fn: auto_cleanup_tokens () RETURNS void
-- >>> acl: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.auto_cleanup_tokens()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    DELETE FROM public.bt_tokens 
    WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$function$

;

-- >>> fn: claim_zone_id (p_zone_id text) RETURNS jsonb
-- >>> acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.claim_zone_id(p_zone_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_failures   bigint;
  v_target     uuid;
  v_profile    jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesi├│n autenticada';
  END IF;

  IF p_zone_id !~ '^ZONE-[A-Z0-9]{8}$' THEN
    RAISE EXCEPTION 'Formato de ZONE-ID inv├ílido';
  END IF;

  SELECT count(*) INTO v_failures
  FROM public.zone_claim_attempts
  WHERE zone_id = p_zone_id
    AND success = FALSE
    AND attempted_at > now() - interval '15 minutes';
  IF v_failures >= 5 THEN
    RAISE EXCEPTION 'Demasiados intentos para este ZONE-ID. Reintenta en 15 minutos.';
  END IF;

  SELECT id INTO v_target FROM public.users WHERE zone_id = p_zone_id;
  IF v_target IS NULL THEN
    INSERT INTO public.zone_claim_attempts (zone_id, uid, success)
    VALUES (p_zone_id, v_uid, FALSE);
    RAISE EXCEPTION 'ZONE-ID no encontrado';
  END IF;

  -- Reclamo idempotente + devoluci├│n del perfil completo migrado a este UID.
  UPDATE public.users u SET id = v_uid
  WHERE u.zone_id = p_zone_id
  RETURNING jsonb_build_object(
    'id',               u.id,
    'zone_id',          u.zone_id,
    'display_name',     u.display_name,
    'public_key',       u.public_key,
    'avatar_hash',      u.avatar_hash,
    'stealth_mode',     u.stealth_mode,
    'instagram_handle', u.instagram_handle,
    'ig_visible',       u.ig_visible,
    'facebook_handle',  u.facebook_handle,
    'fb_visible',       u.fb_visible,
    'tiktok_handle',    u.tiktok_handle,
    'tiktok_visible',   u.tiktok_visible,
    'reports_count',    u.reports_count,
    'is_shadowbanned',  u.is_shadowbanned,
    'avatar_url',       u.avatar_url,
    'avatar_is_public', u.avatar_is_public,
    'gallery_photos',   u.gallery_photos,
    'created_at',       u.created_at,
    'updated_at',       u.updated_at
  ) INTO v_profile;

  INSERT INTO public.zone_claim_attempts (zone_id, uid, success)
  VALUES (p_zone_id, v_uid, TRUE);

  RETURN v_profile;
END;
$function$

;

-- >>> fn: cleanup_expired_tokens () RETURNS void
-- >>> acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cleanup_expired_tokens()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    DELETE FROM public.bt_tokens WHERE expires_at < now();
END;
$function$

;

-- >>> fn: delete_own_account () RETURNS void
-- >>> acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.delete_own_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
    current_uid UUID;
BEGIN
    current_uid := auth.uid();
    IF current_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;
    DELETE FROM public.users WHERE id = current_uid;
    DELETE FROM auth.users WHERE id = current_uid;
END;
$function$

;

-- >>> fn: get_active_users_for_radar (p_limit integer) RETURNS record
-- >>> acl: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.get_active_users_for_radar(p_limit integer DEFAULT 1000)
 RETURNS TABLE(id uuid, zone_id text, display_name text, avatar_url text, public_key text, stealth_mode boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.zone_id,
        u.display_name,
        u.avatar_url,
        u.public_key,
        u.stealth_mode
    FROM public.users u
    WHERE 
        u.is_shadowbanned = FALSE
        AND u.stealth_mode = FALSE
        AND u.updated_at > NOW() - INTERVAL '24 hours'
    ORDER BY u.updated_at DESC
    LIMIT p_limit;
END;
$function$

;

-- >>> fn: get_radar_stats () RETURNS jsonb
-- >>> acl: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.get_radar_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_stats JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM public.users WHERE is_shadowbanned = FALSE),
        'active_users_24h', (SELECT COUNT(*) FROM public.users WHERE updated_at > NOW() - INTERVAL '24 hours' AND is_shadowbanned = FALSE),
        'active_tokens', (SELECT COUNT(*) FROM public.bt_tokens WHERE expires_at > NOW()),
        'total_encounters', (SELECT COUNT(*) FROM public.encounters WHERE seen_at > NOW() - INTERVAL '24 hours')
    ) INTO v_stats;
    
    RETURN v_stats;
END;
$function$

;

-- >>> fn: handle_new_report () RETURNS trigger
-- >>> acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.handle_new_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    UPDATE public.users
    SET reports_count = reports_count + 1,
        is_shadowbanned = CASE WHEN reports_count + 1 >= 3 THEN TRUE ELSE is_shadowbanned END
    WHERE id = NEW.reported_id;
    RETURN NEW;
END;
$function$

;

-- >>> fn: refresh_active_users_cache () RETURNS void
-- >>> acl: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.refresh_active_users_cache()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.active_users_cache;
END;
$function$

;

-- >>> fn: resolve_bt_token (p_token text) RETURNS jsonb
-- >>> acl: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.resolve_bt_token(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile jsonb;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) = 0 OR trim(p_token) = 'ZONE-INIT' THEN
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
$function$

;

-- >>> fn: rls_auto_enable () RETURNS event_trigger
-- >>> acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$

;

-- >>> fn: update_bt_activity () RETURNS void
-- >>> acl: {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.update_bt_activity()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    UPDATE public.users
    SET last_bt_activity = NOW(),
        updated_at = NOW()
    WHERE id = auth.uid();
END;
$function$

;

-- >>> fn: update_users_updated_at () RETURNS trigger
-- >>> acl: {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.update_users_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$

;

-- >>> fn: verify_zone_id (p_zone_id text) RETURNS jsonb
-- >>> acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.verify_zone_id(p_zone_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_failures   bigint;
  v_user_data  jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesi├│n autenticada';
  END IF;

  IF p_zone_id !~ '^ZONE-[A-Z0-9]{8}$' THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_failures
  FROM public.zone_claim_attempts
  WHERE zone_id = p_zone_id
    AND success = FALSE
    AND attempted_at > now() - interval '15 minutes';
  IF v_failures >= 5 THEN
    RAISE EXCEPTION 'Demasiados intentos para este ZONE-ID. Reintenta en 15 minutos.';
  END IF;

  SELECT jsonb_build_object(
    'exists', TRUE,
    'display_name', display_name,
    'avatar_url', CASE WHEN avatar_is_public THEN avatar_url ELSE NULL END
  ) INTO v_user_data
  FROM public.users
  WHERE zone_id = p_zone_id;

  IF v_user_data IS NULL THEN
    INSERT INTO public.zone_claim_attempts (zone_id, uid, success)
    VALUES (p_zone_id, v_uid, FALSE);
  END IF;

  RETURN v_user_data;
END;
$function$

;
