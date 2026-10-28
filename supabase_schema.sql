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
    seen_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    -- Z-210 (PHASE 2.2.3): clave canónica del encuentro lógico
    -- 'ZEN-1:' + hex(sha256('ZEN-1|zona|zona|yyyymmddhh')). Nula solo en filas
    -- históricas; ver supabase_migrations/z210_encounter_key.sql.
    encounter_key TEXT
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
    -- Z-211 (PHASE 2.2.4): par canónico (min/max) para unicidad independiente
    -- de la dirección. requester/receiver conservan la dirección (RLS).
    canonical_low UUID GENERATED ALWAYS AS (LEAST(requester_id, receiver_id)) STORED,
    canonical_high UUID GENERATED ALWAYS AS (GREATEST(requester_id, receiver_id)) STORED,
    UNIQUE(requester_id, receiver_id),
    CONSTRAINT uq_matches_canonical_pair UNIQUE (canonical_low, canonical_high)
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
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    delivered_at TIMESTAMPTZ,               -- Z-007: tick entregado en el radar/chat offline
    read_at TIMESTAMPTZ                     -- Z-007: tick leído
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
    -- Z-212: marca la transacción como escritura de moderación confiable para
    -- que el trigger de columnas protegidas permita reports_count/shadowban.
    PERFORM set_config('zone.allow_protected_user_write', '1', true);
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

-- Z-212: un usuario autenticado no puede auto-modificar columnas de moderación
-- ni la identidad (id/zone_id/created_at). Sin esto, RLS permitía ponerse
-- is_shadowbanned=false / reports_count=0 y evadir el shadowban.
CREATE OR REPLACE FUNCTION public.enforce_user_protected_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- service_role (sin auth.uid()) conserva acceso administrativo. Las
  -- funciones de moderación confiables marcan la transacción con
  -- zone.allow_protected_user_write=1.
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

-- ─── BT_TOKENS ───────────────────────────────────────────────
-- Solo tu propio token
DROP POLICY IF EXISTS "Ver propio token" ON public.bt_tokens;
CREATE POLICY "Ver propio token" ON public.bt_tokens
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Insertar solo tu propio token
DROP POLICY IF EXISTS "Crear propio token" ON public.bt_tokens;
CREATE POLICY "Crear propio token" ON public.bt_tokens
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Z-212: la resolución de tokens pasa EXCLUSIVAMENTE por la RPC
-- `resolve_bt_token` (SECURITY DEFINER, con filtrado de visibilidad).
-- Se elimina la política SELECT amplia que exponía el mapping
-- token → user_id de TODOS los usuarios activos a cualquier autenticado.
DROP POLICY IF EXISTS "Resolver token BT" ON public.bt_tokens;

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

-- Solo el receiver puede actualizar el status. Z-212: WITH CHECK explícito
-- para que el receiver no pueda reescribir las columnas de identidad del par.
DROP POLICY IF EXISTS "Aceptar o rechazar match" ON public.matches;
CREATE POLICY "Aceptar o rechazar match" ON public.matches
    FOR UPDATE TO authenticated
    USING (auth.uid() = receiver_id)
    WITH CHECK (auth.uid() = receiver_id);

-- Z-106 (FASE 1.6): borrar un match solo por sus participantes (derecho al borrado)
DROP POLICY IF EXISTS "Eliminar propio match" ON public.matches;
CREATE POLICY "Eliminar propio match" ON public.matches
    FOR DELETE TO authenticated USING (auth.uid() = requester_id OR auth.uid() = receiver_id);

-- Z-212: el par y el id son inmutables; un match aceptado no puede degradarse
-- (el receiver solo puede mover pending → accepted/rejected).
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

-- Z-212: los mensajes son inmutables para los clientes. Las columnas de
-- identidad/contenido no pueden reescribirse (ni siquiera vía UPDATE directo
-- de un participante); los ticks de entrega/lectura usan las RPC Z-007.
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

DROP POLICY IF EXISTS "Eliminar mensaje con match aceptado" ON public.messages;
CREATE POLICY "Eliminar mensaje con match aceptado" ON public.messages
    FOR DELETE TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.matches m
            WHERE m.id = messages.match_id
              AND m.status = 'accepted'
              AND (m.requester_id = auth.uid() OR m.receiver_id = auth.uid())
        )
    );

-- ─── REPORTS ─────────────────────────────────────────────────
-- Z-007 (2026-09-23): RPCs de delivery/read del chat (consolidadas de la migración
-- del desarrollador `add_message_delivery_status.sql`, CORREGIDAS: gate de sesión
-- server-side en auth.uid(), verificación de match aceptado, sin anon, sin escapes
-- dinámicos, grants {authenticated, service_role} con revoke anon/PUBLIC).
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
-- Z-210 (PHASE 2.2.3): idempotencia canónica por dispositivo. Los NULL
-- (filas históricas) no colisionan entre sí en Postgres.
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_encounter_key ON public.encounters(user_id, encounter_key);

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

-- 7b. claim_zone_id — CUARENTENA DE SEGURIDAD Z-212 (2026-10-23).
--
-- El diseño anterior ejecutaba `UPDATE users SET id = auth.uid()` sobre el
-- ZONE-ID solicitado. Cualquier cuenta autenticada podía reclamar el ZONE-ID
-- de otra persona y apropiarse de su identidad/rows (account takeover): no
-- existía ninguna prueba de posesión de la clave del dispositivo.
--
-- La RPC se mantiene (misma firma/grants para no romper clientes) pero falla
-- cerrado. NO se re-habilita hasta implementar un challenge firmado con la
-- clave privada Ed25519/X25519 del dispositivo y verificado server-side con
-- la clave pública anclada al usuario. El login legacy ya está bloqueado
-- client-side por `SameAccountClaimPolicy`.
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

-- Resolución de token BT para radar (bypass RLS, soporta resolución bilateral).
-- Z-212: exige sesión y aplica visibilidad server-side (nunca devuelve handles
-- ni avatar que el dueño marcó como privados).
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
REVOKE EXECUTE ON FUNCTION public.resolve_bt_token(text) FROM anon; -- Z-104: cerrar vector anon
GRANT EXECUTE ON FUNCTION public.resolve_bt_token(text) TO authenticated;

