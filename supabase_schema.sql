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
CREATE TABLE public.users (
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
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ============================================================
-- 2. TOKENS BLUETOOTH TEMPORALES (seguridad del radar)
-- El token efímero se comparte via Nearby Connections, NO el zone_id
-- ============================================================
CREATE TABLE public.bt_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    token TEXT UNIQUE NOT NULL,             -- UUID aleatorio efímero
    expires_at TIMESTAMPTZ NOT NULL,        -- Expira en 5 minutos
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ============================================================
-- 3. ENCUENTROS ("Nos cruzamos") — Feature diferencial CLAVE
-- Cada vez que dos usuarios se detectan por BT/Nearby, se guarda
-- ============================================================
CREATE TABLE public.encounters (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    other_zone_id TEXT NOT NULL,            -- ZONE-ID de la persona encontrada
    seen_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(user_id, other_zone_id, (date_trunc('hour', seen_at))) -- 1 entrada por hora max
);

-- ============================================================
-- 4. MATCHES (solicitudes de conexión para chatear)
-- ============================================================
CREATE TABLE public.matches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    requester_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(requester_id, receiver_id)
);

-- ============================================================
-- 5. MENSAJES E2EE (solo si hay match aceptado)
-- ============================================================
CREATE TABLE public.messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.users(id) NOT NULL,
    encrypted_content TEXT NOT NULL,        -- Texto cifrado con ChaCha20-Poly1305
    nonce TEXT NOT NULL,                    -- Nonce de cifrado (base64)
    mac TEXT NOT NULL,                      -- MAC de autenticación (base64)
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ============================================================
-- 6. REPORTES DE USUARIOS
-- ============================================================
CREATE TABLE public.reports (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    reporter_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    reported_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(reporter_id, reported_id)
);

-- ============================================================
-- 7. USUARIOS BLOQUEADOS
-- ============================================================
CREATE TABLE public.blocked_users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    blocker_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    blocked_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_new_report
    AFTER INSERT ON public.reports
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_report();

-- Función: limpiar tokens expirados (llamar periódicamente)
CREATE OR REPLACE FUNCTION public.cleanup_expired_tokens()
RETURNS void AS $$
BEGIN
    DELETE FROM public.bt_tokens
    WHERE expires_at < now() OR used = TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
-- Ver perfiles no shadowbanned (para el radar)
CREATE POLICY "Ver perfiles públicos" ON public.users
    FOR SELECT USING (is_shadowbanned = FALSE);

-- Solo el dueño puede actualizar su propio perfil
CREATE POLICY "Actualizar propio perfil" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- Insertar solo con tu propio uid
CREATE POLICY "Registrar propio usuario" ON public.users
    FOR INSERT WITH CHECK (auth.uid() = id);

-- ─── BT_TOKENS ───────────────────────────────────────────────
-- Solo tu propio token
CREATE POLICY "Ver propio token" ON public.bt_tokens
    FOR SELECT USING (auth.uid() = user_id);

-- Insertar solo tu propio token
CREATE POLICY "Crear propio token" ON public.bt_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Cualquier usuario autenticado puede resolver un token (para el radar)
CREATE POLICY "Resolver token BT" ON public.bt_tokens
    FOR SELECT USING (auth.role() = 'authenticated' AND expires_at > now() AND used = FALSE);

-- ─── ENCOUNTERS ──────────────────────────────────────────────
-- Solo ver tus propios encuentros
CREATE POLICY "Ver propios encuentros" ON public.encounters
    FOR SELECT USING (auth.uid() = user_id);

-- Insertar tus propios encuentros
CREATE POLICY "Registrar encuentro" ON public.encounters
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ─── MATCHES ─────────────────────────────────────────────────
-- Ver matches donde participas
CREATE POLICY "Ver propios matches" ON public.matches
    FOR SELECT USING (auth.uid() = requester_id OR auth.uid() = receiver_id);

-- Insertar solicitud de match como requester
CREATE POLICY "Solicitar match" ON public.matches
    FOR INSERT WITH CHECK (auth.uid() = requester_id);

-- Solo el receiver puede actualizar el status
CREATE POLICY "Aceptar o rechazar match" ON public.matches
    FOR UPDATE USING (auth.uid() = receiver_id);

-- ─── MESSAGES ────────────────────────────────────────────────
-- Solo si hay match ACEPTADO entre los dos
CREATE POLICY "Ver mensajes con match aceptado" ON public.messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.matches m
            WHERE m.id = match_id
              AND m.status = 'accepted'
              AND (m.requester_id = auth.uid() OR m.receiver_id = auth.uid())
        )
    );

-- Solo el sender puede insertar, y debe haber match aceptado
CREATE POLICY "Enviar mensaje con match aceptado" ON public.messages
    FOR INSERT WITH CHECK (
        auth.uid() = sender_id
        AND EXISTS (
            SELECT 1 FROM public.matches m
            WHERE m.id = match_id
              AND m.status = 'accepted'
              AND (m.requester_id = auth.uid() OR m.receiver_id = auth.uid())
        )
    );

-- ─── REPORTS ─────────────────────────────────────────────────
CREATE POLICY "Reportar usuario" ON public.reports
    FOR INSERT WITH CHECK (auth.uid() = reporter_id);

CREATE POLICY "Ver propios reportes" ON public.reports
    FOR SELECT USING (auth.uid() = reporter_id);

-- ─── BLOCKED_USERS ───────────────────────────────────────────
CREATE POLICY "Gestionar bloqueos propios" ON public.blocked_users
    FOR ALL USING (auth.uid() = blocker_id);

-- ============================================================
-- REALTIME (SOLO MENSAJES — no exponer radar en tiempo real)
-- Activar en el panel de Supabase → Database → Replication
-- ============================================================
-- Habilitar: public.messages, public.matches
-- NO habilitar: encounters, bt_tokens, reports

-- ============================================================
-- ÍNDICES para rendimiento
-- ============================================================
CREATE INDEX idx_bt_tokens_token ON public.bt_tokens(token);
CREATE INDEX idx_bt_tokens_expires ON public.bt_tokens(expires_at);
CREATE INDEX idx_encounters_user ON public.encounters(user_id, seen_at DESC);
CREATE INDEX idx_matches_users ON public.matches(requester_id, receiver_id);
CREATE INDEX idx_messages_match ON public.messages(match_id, created_at ASC);
CREATE INDEX idx_users_zone_id ON public.users(zone_id);
