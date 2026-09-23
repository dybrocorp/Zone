-- =============================================================================
-- ZONE — Script completo para Supabase SQL Editor
-- =============================================================================
-- Uso: copiar TODO este archivo en SQL Editor → Run
-- Seguro en proyecto nuevo o existente (idempotente: IF NOT EXISTS / DROP IF EXISTS)
--
-- Incluye:
--   • Tablas, índices, RLS, Storage
--   • Radar bilateral (tokens BT sin bloqueo used=FALSE)
--   • RPC resolve_bt_token, verify_zone_id, claim_zone_id, delete_own_account
--   • Corrección de datos legados (tokens marcados used)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- TABLAS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.users (
    id UUID REFERENCES auth.users NOT NULL PRIMARY KEY,
    zone_id TEXT UNIQUE NOT NULL,
    display_name TEXT,
    public_key TEXT NOT NULL,
    avatar_hash TEXT,
    stealth_mode BOOLEAN DEFAULT FALSE,
    instagram_handle TEXT,
    ig_visible BOOLEAN DEFAULT TRUE,
    facebook_handle TEXT,
    fb_visible BOOLEAN DEFAULT TRUE,
    tiktok_handle TEXT,
    tiktok_visible BOOLEAN DEFAULT TRUE,
    reports_count INT DEFAULT 0,
    is_shadowbanned BOOLEAN DEFAULT FALSE,
    avatar_url TEXT,
    avatar_is_public BOOLEAN DEFAULT TRUE,
    gallery_photos JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Trigger: actualiza updated_at en cada UPDATE (existente en remoto 2026-09-23; alineado en baseline)
CREATE OR REPLACE FUNCTION public.update_users_updated_at()
RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_updated_at_trigger ON public.users;
CREATE TRIGGER users_updated_at_trigger BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_users_updated_at();

-- Z-109: función de trigger no expuesta a la red (defensivo; los triggers no dependen de grants EXECUTE).
REVOKE EXECUTE ON FUNCTION public.update_users_updated_at() FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.bt_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    token TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.encounters (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    other_zone_id TEXT NOT NULL,
    seen_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.matches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    requester_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(requester_id, receiver_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.users(id) ON UPDATE CASCADE NOT NULL,
    encrypted_content TEXT NOT NULL,
    nonce TEXT NOT NULL,
    mac TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.reports (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    reporter_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    reported_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(reporter_id, reported_id)
);

CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    blocker_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    blocked_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(blocker_id, blocked_id)
);

-- =============================================================================
-- FUNCIONES Y TRIGGERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_report()
RETURNS TRIGGER AS $$
BEGIN
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

CREATE OR REPLACE FUNCTION public.cleanup_expired_tokens()
RETURNS void AS $$
BEGIN
    DELETE FROM public.bt_tokens WHERE expires_at < now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_tokens() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE EXECUTE ON FUNCTION public.delete_own_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;

-- Tabla de auditoría / rate-limit de claim_zone_id y verify_zone_id (Z-001 Fase A)
-- Acceso SOLO vía las funciones SECURITY DEFINER; sin grants a anon/authenticated.
CREATE TABLE IF NOT EXISTS public.zone_claim_attempts (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  zone_id       TEXT NOT NULL,
  uid           UUID,
  success       BOOLEAN NOT NULL DEFAULT FALSE,
  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_zone_claim_attempts_zone_time
  ON public.zone_claim_attempts (zone_id, attempted_at DESC);
REVOKE ALL ON public.zone_claim_attempts FROM anon, authenticated, PUBLIC;
ALTER TABLE public.zone_claim_attempts ENABLE ROW LEVEL SECURITY;

-- claim_zone_id endurecido → RETORNA jsonb (perfil completo tras el reclamo).
-- (Z-001: auth + formato + rate-limit, NO escribe public_key · Z-002: devuelve
--  el perfil migrado para el login sin releer 'users', ahora self-scoped)
CREATE OR REPLACE FUNCTION public.claim_zone_id(p_zone_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_failures   bigint;
  v_target     uuid;
  v_profile    jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesión autenticada';
  END IF;
  IF p_zone_id !~ '^ZONE-[A-Z0-9]{8}$' THEN
    RAISE EXCEPTION 'Formato de ZONE-ID inválido';
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
$$;

REVOKE EXECUTE ON FUNCTION public.claim_zone_id(text) FROM PUBLIC, anon;
DROP FUNCTION IF EXISTS public.claim_zone_id(text, text); -- variantes obsoletas 2-arg
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text) TO authenticated;

-- verify_zone_id endurecido (solo authenticated, sin oráculo: no expone 'id';
-- Z-002: avatar_url NULL si avatar_is_public = false)
CREATE OR REPLACE FUNCTION public.verify_zone_id(p_zone_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_failures   bigint;
  v_user_data  jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesión autenticada';
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
$$;

REVOKE EXECUTE ON FUNCTION public.verify_zone_id(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_zone_id(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_bt_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE EXECUTE ON FUNCTION public.resolve_bt_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_bt_token(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_bt_token(text) TO anon;

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bt_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver perfiles públicos" ON public.users;
DROP POLICY IF EXISTS "Ver propio perfil" ON public.users;
CREATE POLICY "Ver propio perfil" ON public.users
    FOR SELECT TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Actualizar propio perfil" ON public.users;
CREATE POLICY "Actualizar propio perfil" ON public.users
    FOR UPDATE TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Registrar propio usuario" ON public.users;
CREATE POLICY "Registrar propio usuario" ON public.users
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- ─── VISTA v_profile (Z-002) — único camino de lectura de terceros ────────
-- Semántica "security definer" (privilegios del dueño) para poder filtrar
-- server-side: excluye shadowban + bloqueos bidireccionales y NULIFICA
-- avatar/galería/handles no públicos. NO usar security_invoker (rompería el
-- radar al re-aplicar el RLS self-scoped de users).
CREATE OR REPLACE VIEW public.v_profile AS
SELECT
  u.id,
  u.zone_id,
  u.display_name,
  CASE WHEN u.avatar_is_public THEN u.avatar_url ELSE NULL END      AS avatar_url,
  u.avatar_is_public,
  CASE WHEN u.avatar_is_public
       THEN (SELECT jsonb_agg(p ORDER BY ord)
             FROM jsonb_array_elements(u.gallery_photos) WITH ORDINALITY AS t(p, ord)
             WHERE p->>'is_public' = 'true')::jsonb
       ELSE NULL END                                                AS gallery_photos,
  u.public_key,
  u.stealth_mode,
  CASE WHEN u.ig_visible THEN u.instagram_handle ELSE NULL END      AS instagram_handle,
  u.ig_visible,
  CASE WHEN u.fb_visible THEN u.facebook_handle ELSE NULL END       AS facebook_handle,
  u.fb_visible,
  CASE WHEN u.tiktok_visible THEN u.tiktok_handle ELSE NULL END     AS tiktok_handle,
  u.tiktok_visible,
  u.created_at,
  u.updated_at
FROM public.users u
WHERE u.is_shadowbanned = FALSE
  AND NOT EXISTS (
    SELECT 1 FROM public.blocked_users b
    WHERE (b.blocker_id = u.id      AND b.blocked_id = auth.uid())
       OR (b.blocker_id = auth.uid() AND b.blocked_id = u.id)
  );
REVOKE ALL ON public.v_profile FROM anon, PUBLIC;
GRANT SELECT ON public.v_profile TO authenticated;

-- ─── Z-109 (2026-09-23): RPCs radar/mantenimiento consolidadas en canon ──────
-- Versiones CORREGIDAS: nada ejecutable por anon/PUBLIC. get_active_users_for_radar
-- es SECURITY INVOKER sobre v_profile (hereda gating de Z-002: avatar_is_public,
-- shadowban, bloqueos mutuos) + filtro stealth_mode. Va DESPUÉS de v_profile
-- (la RPC LANGUAGE sql la referencia en creación).
-- ----------------------------------------------------------------------------

-- Radar global: usuarios activos 24h (SECURITY INVOKER + v_profile)
CREATE OR REPLACE FUNCTION public.get_active_users_for_radar(p_limit integer DEFAULT 1000)
 RETURNS TABLE(id uuid, zone_id text, display_name text, avatar_url text, public_key text, stealth_mode boolean)
 LANGUAGE sql
 SECURITY INVOKER
 SET search_path TO 'public'
AS $$
    SELECT v.id, v.zone_id, v.display_name, v.avatar_url, v.public_key, v.stealth_mode
    FROM public.v_profile v
    WHERE v.stealth_mode = FALSE
    ORDER BY v.updated_at DESC
    LIMIT p_limit;
$$;

REVOKE EXECUTE ON FUNCTION public.get_active_users_for_radar(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_users_for_radar(integer) TO authenticated, service_role;

-- Métricas del radar (diagnóstico): gate de sesión + sin anon
CREATE OR REPLACE FUNCTION public.get_radar_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_stats JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM public.users WHERE is_shadowbanned = FALSE),
        'active_users_24h', (SELECT COUNT(*) FROM public.users WHERE updated_at > NOW() - INTERVAL '24 hours' AND is_shadowbanned = FALSE),
        'active_tokens', (SELECT COUNT(*) FROM public.bt_tokens WHERE expires_at > NOW()),
        'total_encounters', (SELECT COUNT(*) FROM public.encounters WHERE seen_at > NOW() - INTERVAL '24 hours')
    ) INTO v_stats;
    RETURN v_stats;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_radar_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_radar_stats() TO authenticated, service_role;

-- Refrescar la caché materializada del radar: solo mantenimiento (service_role)
CREATE OR REPLACE FUNCTION public.refresh_active_users_cache()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.active_users_cache;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.refresh_active_users_cache() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_active_users_cache() TO service_role;

-- Limpieza de tokens BT expirados con margen: solo mantenimiento (service_role)
CREATE OR REPLACE FUNCTION public.auto_cleanup_tokens()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM public.bt_tokens
    WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_cleanup_tokens() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_cleanup_tokens() TO service_role;

-- Actividad BT del usuario actual (usa auth.uid()): solo authenticated/service_role
CREATE OR REPLACE FUNCTION public.update_bt_activity()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.users
    SET last_bt_activity = NOW(),
        updated_at = NOW()
    WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_bt_activity() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_bt_activity() TO authenticated, service_role;

-- Función dormida presente en remoto (2026-09-23): event-trigger de red de seguridad
-- para auto-RLS. NO se cablea como event trigger (Supabase gestiona auto-RLS vía su
-- propio event trigger `ensure_rls`). Se conserva en canon solo por fidelidad con el
-- estado remoto; grants restringidos por defecto.
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
        RAISE LOG 'rls_auto_enable: skip % (system schema or not in enforced list)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;

DROP POLICY IF EXISTS "Ver propio token" ON public.bt_tokens;
CREATE POLICY "Ver propio token" ON public.bt_tokens
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Crear propio token" ON public.bt_tokens;
CREATE POLICY "Crear propio token" ON public.bt_tokens
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Resolver token BT" ON public.bt_tokens;
CREATE POLICY "Resolver token BT" ON public.bt_tokens
    FOR SELECT TO authenticated
    USING (auth.role() = 'authenticated' AND expires_at > now());

DROP POLICY IF EXISTS "Ver propios encuentros" ON public.encounters;
CREATE POLICY "Ver propios encuentros" ON public.encounters
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Registrar encuentro" ON public.encounters;
CREATE POLICY "Registrar encuentro" ON public.encounters
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Ver propios matches" ON public.matches;
CREATE POLICY "Ver propios matches" ON public.matches
    FOR SELECT TO authenticated USING (auth.uid() = requester_id OR auth.uid() = receiver_id);

DROP POLICY IF EXISTS "Solicitar match" ON public.matches;
CREATE POLICY "Solicitar match" ON public.matches
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = requester_id);

DROP POLICY IF EXISTS "Aceptar o rechazar match" ON public.matches;
CREATE POLICY "Aceptar o rechazar match" ON public.matches
    FOR UPDATE TO authenticated USING (auth.uid() = receiver_id);

DROP POLICY IF EXISTS "Ver mensajes con match aceptado" ON public.messages;
CREATE POLICY "Ver mensajes con match aceptado" ON public.messages
    FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.matches m
            WHERE m.id = match_id
              AND m.status = 'accepted'
              AND (m.requester_id = auth.uid() OR m.receiver_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Enviar mensaje con match aceptado" ON public.messages;
CREATE POLICY "Enviar mensaje con match aceptado" ON public.messages
    FOR INSERT TO authenticated WITH CHECK (
        auth.uid() = sender_id
        AND EXISTS (
            SELECT 1 FROM public.matches m
            WHERE m.id = match_id
              AND m.status = 'accepted'
              AND (m.requester_id = auth.uid() OR m.receiver_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Reportar usuario" ON public.reports;
CREATE POLICY "Reportar usuario" ON public.reports
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);

DROP POLICY IF EXISTS "Ver propios reportes" ON public.reports;
CREATE POLICY "Ver propios reportes" ON public.reports
    FOR SELECT TO authenticated USING (auth.uid() = reporter_id);

DROP POLICY IF EXISTS "Gestionar bloqueos propios" ON public.blocked_users;
CREATE POLICY "Gestionar bloqueos propios" ON public.blocked_users
    FOR ALL TO authenticated USING (auth.uid() = blocker_id);

-- =============================================================================
-- ÍNDICES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_bt_tokens_token ON public.bt_tokens(token);
CREATE INDEX IF NOT EXISTS idx_bt_tokens_expires ON public.bt_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_bt_tokens_user ON public.bt_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_encounters_user ON public.encounters(user_id, seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_matches_users ON public.matches(requester_id, receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_match ON public.messages(match_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_users_zone_id ON public.users(zone_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_encounter_hourly
    ON public.encounters(user_id, other_zone_id, (date_trunc('hour', seen_at AT TIME ZONE 'UTC')));

-- =============================================================================
-- STORAGE (avatars)
-- =============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('profiles', 'profiles', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Avatar publico" ON storage.objects;
DROP POLICY IF EXISTS "Avatar propio select" ON storage.objects;
CREATE POLICY "Avatar propio select" ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Avatar propio upload" ON storage.objects;
CREATE POLICY "Avatar propio upload" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Avatar propio update" ON storage.objects;
CREATE POLICY "Avatar propio update" ON storage.objects
    FOR UPDATE TO authenticated
    USING (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Avatar propio delete" ON storage.objects;
CREATE POLICY "Avatar propio delete" ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

-- =============================================================================
-- DATOS / MANTENIMIENTO (radar bilateral)
-- =============================================================================

UPDATE public.bt_tokens SET used = FALSE WHERE used = TRUE;
DELETE FROM public.bt_tokens WHERE expires_at < now();

-- =============================================================================
-- REALTIME (activar manualmente en Dashboard → Database → Replication)
--   Habilitar: public.messages, public.matches
--   NO habilitar: bt_tokens, encounters, reports
-- =============================================================================
