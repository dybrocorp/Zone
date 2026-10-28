\set ON_ERROR_STOP on

-- =============================================================================
-- Z-212 · Prueba conductual reproducible de la migración de hardening
-- =============================================================================
-- Requisitos:
--   * PostgreSQL 16+ (validado en PostgreSQL 18).
--   * Ejecutar en una base DESECHABLE: crea roles/stubs mínimos de Supabase.
--   * Uso:
--       psql -v ON_ERROR_STOP=1 -f supabase_migrations/tests/z212_behavioral_test.sql
--
-- Alcance:
--   * Ejercita las funciones/triggers de z212_security_hardening.sql.
--   * NO habilita RLS: las políticas se revisan por definición, no por
--     enforcement real (ver PHASE_2_SECURITY_HARDENING_Z212.md §Validación).
-- =============================================================================

-- Stubs mínimos de Supabase para una base de validación desechable.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

CREATE TABLE public.users (
    id UUID PRIMARY KEY,
    zone_id TEXT UNIQUE NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    avatar_is_public BOOLEAN DEFAULT FALSE,
    stealth_mode BOOLEAN DEFAULT FALSE,
    public_key TEXT,
    instagram_handle TEXT,
    ig_visible BOOLEAN DEFAULT FALSE,
    facebook_handle TEXT,
    fb_visible BOOLEAN DEFAULT FALSE,
    tiktok_handle TEXT,
    tiktok_visible BOOLEAN DEFAULT FALSE,
    reports_count INTEGER DEFAULT 0 NOT NULL,
    is_shadowbanned BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE public.bt_tokens (
    token TEXT PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE public.matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    encrypted_content TEXT NOT NULL,
    nonce TEXT NOT NULL,
    mac TEXT NOT NULL,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reported_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

\ir ../z212_security_hardening.sql

INSERT INTO public.users
    (id, zone_id, display_name, avatar_url, avatar_is_public,
     instagram_handle, ig_visible, reports_count, is_shadowbanned)
VALUES
    ('11111111-1111-4111-8111-111111111111', 'ZONE-AAAA1111', 'Alice',
     'http://a', FALSE, 'alice_ig', FALSE, 0, FALSE),
    ('22222222-2222-4222-8222-222222222222', 'ZONE-BBBB2222', 'Bob',
     'http://b', FALSE, 'bob_ig', FALSE, 0, FALSE);

INSERT INTO public.bt_tokens (token, user_id, expires_at)
VALUES ('tok-bob', '22222222-2222-4222-8222-222222222222', now() + interval '1 hour');

-- 1. claim_zone_id must fail closed.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
  BEGIN
    PERFORM public.claim_zone_id('ZONE-BBBB2222');
    RAISE EXCEPTION 'FAIL: claim_zone_id accepted a claim';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%Z-212%' THEN RAISE; END IF;
  END;
END $$;

-- 2. resolve_bt_token must require a session and hide private fields.
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
  r := public.resolve_bt_token('tok-bob');
  IF r IS NULL THEN RAISE EXCEPTION 'FAIL: token not resolved'; END IF;
  IF r->>'display_name' <> 'Bob' THEN RAISE EXCEPTION 'FAIL: wrong profile'; END IF;
  IF r->>'avatar_url' IS NOT NULL THEN RAISE EXCEPTION 'FAIL: private avatar exposed'; END IF;
  IF r->>'instagram_handle' IS NOT NULL THEN RAISE EXCEPTION 'FAIL: private handle exposed'; END IF;
END $$;

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  BEGIN
    PERFORM public.resolve_bt_token('tok-bob');
    RAISE EXCEPTION 'FAIL: resolve_bt_token worked without session';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%sesión%' THEN RAISE; END IF;
  END;
END $$;

-- 3. messages: content/identity immutable, delivery/read ticks allowed.
INSERT INTO public.matches (id, requester_id, receiver_id, status)
VALUES ('44444444-4444-4444-8444-444444444444',
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222', 'pending');

INSERT INTO public.messages (id, match_id, sender_id, encrypted_content, nonce, mac)
VALUES ('33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
        '11111111-1111-4111-8111-111111111111', 'cipher', 'nonce', 'mac');

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
  BEGIN
    UPDATE public.messages SET encrypted_content = 'tampered'
    WHERE id = '33333333-3333-4333-8333-333333333333';
    RAISE EXCEPTION 'FAIL: message content was mutable';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%inmutables%' THEN RAISE; END IF;
  END;
  UPDATE public.messages SET delivered_at = now()
  WHERE id = '33333333-3333-4333-8333-333333333333';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: delivered_at not updated'; END IF;
END $$;

-- 4. matches: participants immutable, accepted cannot degrade.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
  BEGIN
    UPDATE public.matches SET requester_id = '22222222-2222-4222-8222-222222222222'
    WHERE id = '44444444-4444-4444-8444-444444444444';
    RAISE EXCEPTION 'FAIL: match participants were mutable';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%inmutables%' THEN RAISE; END IF;
  END;
  UPDATE public.matches SET status = 'accepted'
  WHERE id = '44444444-4444-4444-8444-444444444444';
  BEGIN
    UPDATE public.matches SET status = 'rejected'
    WHERE id = '44444444-4444-4444-8444-444444444444';
    RAISE EXCEPTION 'FAIL: accepted match degraded';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%degradarse%' THEN RAISE; END IF;
  END;
END $$;

-- 5. users: protected columns immutable for authenticated, profile still editable.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
  BEGIN
    UPDATE public.users SET is_shadowbanned = TRUE
    WHERE id = '11111111-1111-4111-8111-111111111111';
    RAISE EXCEPTION 'FAIL: user changed protected moderation column';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%protegidas%' THEN RAISE; END IF;
  END;
  UPDATE public.users SET display_name = 'Alice2'
  WHERE id = '11111111-1111-4111-8111-111111111111';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: display_name not updated'; END IF;
END $$;

-- 6. moderation path still works through the trusted transaction flag.
DO $$
DECLARE c integer; sb boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
  INSERT INTO public.reports (reported_id) VALUES ('22222222-2222-4222-8222-222222222222');
  SELECT reports_count, is_shadowbanned INTO c, sb
  FROM public.users WHERE id = '22222222-2222-4222-8222-222222222222';
  IF c <> 1 THEN RAISE EXCEPTION 'FAIL: reports_count=% (expected 1)', c; END IF;

  INSERT INTO public.reports (reported_id) VALUES ('22222222-2222-4222-8222-222222222222');
  INSERT INTO public.reports (reported_id) VALUES ('22222222-2222-4222-8222-222222222222');
  SELECT reports_count, is_shadowbanned INTO c, sb
  FROM public.users WHERE id = '22222222-2222-4222-8222-222222222222';
  IF c <> 3 OR sb IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: moderation count=% shadowban=%', c, sb;
  END IF;
END $$;

-- 7. Migraciones históricas re-aplicadas después de Z-212: no deben regresar.
\ir ../fix_radar_bilateral.sql
\ir ../z106_z206_policies.sql

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'bt_tokens'
      AND policyname = 'Resolver token BT'
  ) THEN
    RAISE EXCEPTION 'FAIL: broad bt_tokens policy reintroduced';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'messages' AND cmd = 'UPDATE'
  ) THEN
    RAISE EXCEPTION 'FAIL: direct messages UPDATE policy reintroduced';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'messages'
      AND cmd = 'DELETE' AND policyname = 'Eliminar mensaje con match aceptado'
  ) THEN
    RAISE EXCEPTION 'FAIL: messages DELETE policy missing';
  END IF;
END $$;

-- 8. Tras re-aplicar el parche histórico, la RPC sigue exigiendo sesión y
--    ocultando campos privados. La prueba 6 shadowbaneó a Bob; limpiar el
--    estado de moderación (service path) para probar la resolución del token.
SELECT set_config('request.jwt.claim.sub', '', false);
UPDATE public.users SET reports_count = 0, is_shadowbanned = FALSE
WHERE id = '22222222-2222-4222-8222-222222222222';

DO $$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
  r := public.resolve_bt_token('tok-bob');
  IF r IS NULL THEN RAISE EXCEPTION 'FAIL: token not resolved after re-apply'; END IF;
  IF r->>'avatar_url' IS NOT NULL THEN RAISE EXCEPTION 'FAIL: private avatar exposed after re-apply'; END IF;
  IF r->>'instagram_handle' IS NOT NULL THEN RAISE EXCEPTION 'FAIL: private handle exposed after re-apply'; END IF;
END $$;

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  BEGIN
    PERFORM public.resolve_bt_token('tok-bob');
    RAISE EXCEPTION 'FAIL: resolve_bt_token worked without session after re-apply';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%sesión%' THEN RAISE; END IF;
  END;
END $$;

-- Idempotencia: validada por separado re-aplicando z212_security_hardening.sql
-- dos veces sobre el mismo esquema (RUN2_EXIT=0, sesión 2026-10-23).
SELECT 'ALL Z-212 SQL TESTS PASSED' AS result;
