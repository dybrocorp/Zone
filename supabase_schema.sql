-- ============================================================
-- ZONE — Supabase Full Schema
-- Ejecutar en el SQL Editor de Supabase
-- ============================================================

-- Habilitar extensiones
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. USUARIOS (sin email, autenticación anónima por ZONE-ID)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.users (
    id UUID REFERENCES auth.users NOT NULL PRIMARY KEY,
    zone_id TEXT UNIQUE NOT NULL,           -- ZONE-XXXXXXXX visible públicamente
    display_name TEXT,                      -- Apodo opcional
    public_key TEXT NOT NULL,               -- Clave pública X25519 para E2EE (base64)
    avatar_hash TEXT,                       -- Hash de color/avatar generado
    stealth_mode BOOLEAN DEFAULT FALSE,     -- Modo timide: no aparece en radar de otros
    instagram_handle TEXT,
    ig_visible BOOLEAN DEFAULT TRUE,
    facebook_handle TEXT,
    fb_visible BOOLEAN DEFAULT TRUE,
    tiktok_handle TEXT,
    tiktok_visible BOOLEAN DEFAULT TRUE,
    reports_count INT DEFAULT 0,
    is_shadowbanned BOOLEAN DEFAULT FALSE,
    avatar_url TEXT,                        -- URL pública de la foto de perfil principal
    avatar_is_public BOOLEAN DEFAULT TRUE,  -- ¿La foto de perfil es pública para todos?
    gallery_photos JSONB DEFAULT '[]'::jsonb, -- Array de fotos de galería con permisos
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()   -- Última modificación (radar/pull-sync)
);

-- ============================================================
-- 2. TOKENS BLUETOOTH TEMPORALES (seguridad del radar)
-- El token efímero se comparte via Nearby Connections, NO el zone_id
-- ============================================================
CREATE TABLE IF NOT EXISTS public.bt_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    token TEXT UNIQUE NOT NULL,             -- UUID aleatorio efímero
    expires_at TIMESTAMPTZ NOT NULL,        -- Expira en 5 minutos
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ============================================================
-- 3. ENCUENTROS ("Nos cruzamos") — Feature diferencial CLAVE
-- Cada vez que dos usuarios se detectan por BT/Nearby, se guarda
-- ============================================================
CREATE TABLE IF NOT EXISTS public.encounters (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    other_zone_id TEXT NOT NULL,            -- ZONE-ID de la persona encontrada
    seen_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ============================================================
-- 4. MATCHES (solicitudes de conexión para chatear)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.matches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    requester_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(requester_id, receiver_id)
);

-- ============================================================
-- 5. MENSAJES E2EE (solo si hay match aceptado)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.users(id) ON UPDATE CASCADE NOT NULL,
    encrypted_content TEXT NOT NULL,        -- Texto cifrado con ChaCha20-Poly1305
    nonce TEXT NOT NULL,                    -- Nonce de cifrado (base64)
    mac TEXT NOT NULL,                      -- MAC de autenticación (base64)
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ============================================================
-- 6. REPORTES DE USUARIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    reporter_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    reported_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(reporter_id, reported_id)
);

-- ============================================================
-- 7. USUARIOS BLOQUEADOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    blocker_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    blocked_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(blocker_id, blocked_id)
);

-- ============================================================
-- FUNCIONES Y TRIGGERS
-- ============================================================

-- Trigger: incrementar reports_count y shadowban automático al llegar a 3
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

-- Revocar ejecución pública por seguridad (evitar acceso via REST API)
REVOKE EXECUTE ON FUNCTION public.handle_new_report() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_new_report ON public.reports;
CREATE TRIGGER on_new_report
    AFTER INSERT ON public.reports
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_report();

-- Función: limpiar tokens expirados (llamar periódicamente)
CREATE OR REPLACE FUNCTION public.cleanup_expired_tokens()
RETURNS void AS $$
BEGIN
    DELETE FROM public.bt_tokens WHERE expires_at < now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Revocar ejecución pública por seguridad
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_tokens() FROM PUBLIC, anon, authenticated;

-- Función: eliminar propia cuenta (Borrado total)
CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void AS $$
DECLARE
    current_uid UUID;
BEGIN
    current_uid := auth.uid();
    IF current_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    -- 1. Eliminar archivos de almacenamiento (Storage)
    -- Los objetos de Storage se borran mediante la API de Supabase en Flutter.
    
    -- 2. Eliminar de public.users
    -- Las cascadas configuradas (ON DELETE CASCADE) se encargarán de encounters, matches, tokens, etc.
    DELETE FROM public.users WHERE id = current_uid;

    -- 3. Eliminar de auth.users (Requiere SECURITY DEFINER ya que auth es protegido)
    DELETE FROM auth.users WHERE id = current_uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- Revocar ejecución pública por seguridad
REVOKE EXECUTE ON FUNCTION public.delete_own_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;

-- [Ajuste de Terceros] Si rls_auto_enable existe, asegurarlo también
DO $$ 
BEGIN 
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rls_auto_enable') THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated';
        EXECUTE 'ALTER FUNCTION public.rls_auto_enable() SET search_path = public';
    END IF;
END $$;

-- ============================================================
-- ROW LEVEL SECURITY (RLS) — PRIORIDAD MÁXIMA
-- ============================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bt_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

-- ─── USERS ───────────────────────────────────────────────────
-- Z-002: SELECT self-scoped. Cualquier lectura de terceros pasa por v_profile.
DROP POLICY IF EXISTS "Ver perfiles públicos" ON public.users;
DROP POLICY IF EXISTS "Ver propio perfil" ON public.users;
CREATE POLICY "Ver propio perfil" ON public.users
    FOR SELECT TO authenticated USING (auth.uid() = id);

-- Solo el dueño puede actualizar su propio perfil
DROP POLICY IF EXISTS "Actualizar propio perfil" ON public.users;
CREATE POLICY "Actualizar propio perfil" ON public.users
    FOR UPDATE TO authenticated USING (auth.uid() = id);

-- Insertar solo con tu propio uid
DROP POLICY IF EXISTS "Registrar propio usuario" ON public.users;
CREATE POLICY "Registrar propio usuario" ON public.users
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- ─── VISTA v_profile (Z-002) — ÚNICO camino de lectura de terceros ────────
-- Semántica "security definer" (privilegios del dueño) para filtrar server-side:
-- excluye shadowban + bloqueos bidireccionales y NULIFICA avatar/galería/handles
-- no públicos. NO usar security_invoker (re-aplicaría el RLS self-scoped de users
-- y rompería el radar).
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

-- ─── BT_TOKENS ───────────────────────────────────────────────
-- Solo tu propio token
DROP POLICY IF EXISTS "Ver propio token" ON public.bt_tokens;
CREATE POLICY "Ver propio token" ON public.bt_tokens
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Insertar solo tu propio token
DROP POLICY IF EXISTS "Crear propio token" ON public.bt_tokens;
CREATE POLICY "Crear propio token" ON public.bt_tokens
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Cualquier usuario autenticado puede resolver un token (para el radar bilateral)
DROP POLICY IF EXISTS "Resolver token BT" ON public.bt_tokens;
CREATE POLICY "Resolver token BT" ON public.bt_tokens
    FOR SELECT TO authenticated USING (auth.role() = 'authenticated' AND expires_at > now());

-- ─── ENCOUNTERS ──────────────────────────────────────────────
-- Solo ver tus propios encuentros
DROP POLICY IF EXISTS "Ver propios encuentros" ON public.encounters;
CREATE POLICY "Ver propios encuentros" ON public.encounters
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Insertar tus propios encuentros
DROP POLICY IF EXISTS "Registrar encuentro" ON public.encounters;
CREATE POLICY "Registrar encuentro" ON public.encounters
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- ─── MATCHES ─────────────────────────────────────────────────
-- Ver matches donde participas
DROP POLICY IF EXISTS "Ver propios matches" ON public.matches;
CREATE POLICY "Ver propios matches" ON public.matches
    FOR SELECT TO authenticated USING (auth.uid() = requester_id OR auth.uid() = receiver_id);

-- Insertar solicitud de match como requester
DROP POLICY IF EXISTS "Solicitar match" ON public.matches;
CREATE POLICY "Solicitar match" ON public.matches
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = requester_id);

-- Solo el receiver puede actualizar el status
DROP POLICY IF EXISTS "Aceptar o rechazar match" ON public.matches;
CREATE POLICY "Aceptar o rechazar match" ON public.matches
    FOR UPDATE TO authenticated USING (auth.uid() = receiver_id);

-- ─── MESSAGES ────────────────────────────────────────────────
-- Solo si hay match ACEPTADO entre los dos
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

-- Solo el sender puede insertar, y debe haber match aceptado
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

-- ─── REPORTS ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "Reportar usuario" ON public.reports;
CREATE POLICY "Reportar usuario" ON public.reports
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);

DROP POLICY IF EXISTS "Ver propios reportes" ON public.reports;
CREATE POLICY "Ver propios reportes" ON public.reports
    FOR SELECT TO authenticated USING (auth.uid() = reporter_id);

-- ─── BLOCKED_USERS ───────────────────────────────────────────
DROP POLICY IF EXISTS "Gestionar bloqueos propios" ON public.blocked_users;
CREATE POLICY "Gestionar bloqueos propios" ON public.blocked_users
    FOR ALL TO authenticated USING (auth.uid() = blocker_id);

-- ============================================================
-- REALTIME (SOLO MENSAJES — no exponer radar en tiempo real)
-- Activar en el panel de Supabase → Database → Replication
-- ============================================================
-- Habilitar: public.messages, public.matches
-- NO habilitar: encounters, bt_tokens, reports

-- ============================================================
-- ÍNDICES para rendimiento
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_bt_tokens_token ON public.bt_tokens(token);
CREATE INDEX IF NOT EXISTS idx_bt_tokens_expires ON public.bt_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_encounters_user ON public.encounters(user_id, seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_matches_users ON public.matches(requester_id, receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_match ON public.messages(match_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_users_zone_id ON public.users(zone_id);

-- Índices ÚNICOS funcionales
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_encounter_hourly ON public.encounters(user_id, other_zone_id, (date_trunc('hour', seen_at AT TIME ZONE 'UTC')));

-- ============================================================
-- 8. STORAGE (Foto de Perfil)
-- ============================================================
-- Crear bucket si no existe (Requiere permisos de administrador o superuser)
-- Nota: En Supabase esto suele hacerse via panel, pero incluimos política
INSERT INTO storage.buckets (id, name, public) 
VALUES ('profiles', 'profiles', true)
ON CONFLICT (id) DO NOTHING;

-- Política: Avatar publico eliminada (los buckets públicos no necesitan política SELECT global)
DROP POLICY IF EXISTS "Avatar publico" ON storage.objects;

-- Política: El dueño puede ver sus propios archivos (Requisito para que funcione el upload con Upsert)
DROP POLICY IF EXISTS "Avatar propio select" ON storage.objects;
CREATE POLICY "Avatar propio select" ON storage.objects 
    FOR SELECT TO authenticated USING (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Política: El dueño puede subir/borrar su propis foto
DROP POLICY IF EXISTS "Avatar propio upload" ON storage.objects;
CREATE POLICY "Avatar propio upload" ON storage.objects 
    FOR INSERT TO authenticated WITH CHECK (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Avatar propio update" ON storage.objects;
CREATE POLICY "Avatar propio update" ON storage.objects 
    FOR UPDATE TO authenticated USING (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Avatar propio delete" ON storage.objects;
CREATE POLICY "Avatar propio delete" ON storage.objects 
    FOR DELETE TO authenticated USING (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);

-- 7. Tabla de auditoría / rate-limit para claim_zone_id y verify_zone_id (Z-001 Fase A)
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

-- 7b. claim_zone_id endurecido → RETORNA jsonb. Z-001: solo authenticated, formato
-- estricto, rate-limit, NO escribe public_key (fin de la rotación silenciosa).
-- Z-002: devuelve el perfil completo tras el reclamo (login sin releer 'users',
-- que ahora es self-scoped).
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

-- Solo authenticated. Fuera anon/public y fuera las variantes 2-arg obsoletas.
REVOKE EXECUTE ON FUNCTION public.claim_zone_id(text) FROM PUBLIC, anon;
DROP FUNCTION IF EXISTS public.claim_zone_id(text, text);
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text) TO authenticated;

-- 8. verify_zone_id endurecido: solo authenticated, sin oráculo (no expone 'id'/'zone_id');
-- Z-002: avatar_url NULL si avatar_is_public = false
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

-- Resolución de token BT para radar (bypass RLS, soporta resolución bilateral)
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

