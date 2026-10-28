-- ============================================================================
-- Z-002 · Protección de exposición de perfiles (visibilidad estricta server-side)
-- ZONE · 2026-09-23
--
-- Decisiones CTO (registradas en docs/CTO_REVIEW_REQUIRED.md):
--   A. ESTRICTO SERVER-SIDE: avatar_url/gallery_photos se devuelven NULL cuando
--      avatar_is_public = false (ni el cliente puede saltárselo por la conexión mesh).
--   B. Vista public.v_profile como ÚNICO camino de lectura de perfiles de terceros
--      + claim_zone_id devuelve el perfil completo (jsonb) al reclamar la
--      propiedad (migración de login sin reintroducir la fuga).
--
-- Cambios (idempotente; constrúyela sobre secure_claim_zone_id.sql / Fase 1.2):
--   1. users: + updated_at (en remoto ya existe; alinea el esquema canónico).
--   2. RLS SELECT en users → self-scoped (auth.uid() = id). Nadie lee filas ajenas.
--   3. Vista v_profile (definida con privilegios del dueño para poder filtrar
--      server-side): excluye shadowbanned y bloqueos bidireccionales, y OCULTA
--      avatar/galería/handles no públicos.
--   4. claim_zone_id pasa a RETURNS jsonb → devuelve el perfil completo tras el
--      reclamo (para el login/transeferencia legítima). Ya no devuelve void.
--   5. verify_zone_id: avatar_url NULL si avatar_is_public = false.
--   6. Cliente: 4 lecturas de terceros migradas a v_profile (zona_id/radar/pull/privacy).
--
-- NO toca: resolve_bt_token (Z-104, lote aparte) ni criptografía (Fase B Z-001).
--
-- Z-212 (2026-10-23) — SUPERSEDED: el claim queda en cuarentena fail-closed.
-- Este archivo se conserva por historia, pero si se re-aplica instala la
-- cuarentena (NO el UPDATE users SET id) para no reintroducir account takeover.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. users.updated_at (el cliente lo usa para el radar/pull; en remoto existe)
-- ----------------------------------------------------------------------------
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- 2. RLS USERS → SELF-SCOPED: solo el dueño puede SELECT de su propia fila.
--    Cualquier lectura de terceros DEBE pasar por la vista v_profile (sección 3).
-- ----------------------------------------------------------------------------
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Elimina CUALQUIER politica SELECT ajena sobre users (p.ej. la historica
-- "Ver perfiles públicos", cuyo nombre puede variar por normalizacion Unicode
-- o codificacion) salvo la self-scoped (auth.uid() = id). Robusto e idempotente.
DO $$
DECLARE
  p record;
BEGIN
  FOR p IN
    SELECT pol.polname AS nm, pg_get_expr(pol.polqual, pol.polrelid) AS qexpr
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    WHERE c.relname = 'users' AND c.relnamespace = 'public'::regnamespace
      AND pol.polcmd = 'r'
  LOOP
    IF p.qexpr IS NULL OR position('auth.uid()' IN p.qexpr) = 0 THEN
      EXECUTE format('DROP POLICY %I ON public.users', p.nm);
    END IF;
  END LOOP;
END $$;

DROP POLICY IF EXISTS "Ver propio perfil" ON public.users;
CREATE POLICY "Ver propio perfil" ON public.users
    FOR SELECT TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Actualizar propio perfil" ON public.users;
CREATE POLICY "Actualizar propio perfil" ON public.users
    FOR UPDATE TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Registrar propio usuario" ON public.users;
CREATE POLICY "Registrar propio usuario" ON public.users
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- ----------------------------------------------------------------------------
-- 3. VISTA v_profile — único camino server-side de lectura de terceros
--    Semántica "security definer" (privilegios del dueño): puede leer todas las
--    filas base y aplica sus propios filtros. NO usar security_invoker (rompería
--    el radar al re-aplicar el RLS self-scoped de users).
--    Excluye: shadowban + bloqueos bidireccionales + privados (server-side).
-- ----------------------------------------------------------------------------
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

-- Sin acceso a anon/public ni DML de authenticated; solo SELECT.
REVOKE ALL ON public.v_profile FROM anon, PUBLIC, authenticated;
GRANT SELECT ON public.v_profile TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. claim_zone_id → RETURNS jsonb (HISTÓRICO: sustituido por Z-212)
--    La firma se conserva para no romper grants/clientes, pero el cuerpo está
--    en cuarentena fail-closed: NO mueve users.id ni devuelve perfil.
--    (Texto original conservado como historia: devolvía el perfil completo tras
--    el reclamo para que el login no releyera 'users', self-scoped. NO tocaba
--    public_key.)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_zone_id(text);
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

  -- Z-212 (2026-10-23): cuarentena fail-closed. El UPDATE users SET id = v_uid
  -- permitía account takeover sin prueba de posesión. No se re-habilita hasta
  -- implementar un challenge firmado verificado server-side.
  RAISE EXCEPTION
    'Reclamo de ZONE-ID deshabilitado temporalmente por seguridad (Z-212).';
  RETURN NULL; -- inalcanzable; satisface el tipo de retorno jsonb
END;
$$;

-- Solo authenticated. Fuera anon/public y fuera las variantes 2-arg obsoletas.
REVOKE EXECUTE ON FUNCTION public.claim_zone_id(text) FROM PUBLIC, anon;
DROP FUNCTION IF EXISTS public.claim_zone_id(text, text);
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. verify_zone_id: avatar_url NULL si avatar_is_public = false
--    (coherencia con la política A estricta server-side)
-- ----------------------------------------------------------------------------
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

-- ============================================================================
-- PRUEBAS SQL (ejecutar en el SQL Editor de Supabase tras aplicar este archivo)
-- ============================================================================
-- 1. Restricción anon:
--    set role anon; select * from public.v_profile limit 5;  → permission denied
--    set role anon; select public.claim_zone_id('ZONE-AAAAAAAA');  → permission denied
--    set role authenticated;  (restaurar)
--
-- 2. RLS users self-scoped (solo la fila propia):
--    set role authenticated; select count(*) from public.users;  → 0 o 1 (solo tu fila)
--
-- 3. Vista no expone shadowbanned:
--    ✗ mal (shadowban se filtra en la vista): select count(*) from public.v_profile v
--      where v.id in (select id from public.users where is_shadowbanned = TRUE);  → 0
--
-- 4. Gating server-side de avatar/galería:
--    select id, avatar_url, gallery_photos from public.v_profile
--      where avatar_is_public = FALSE;  → avatar_url y gallery_photos NULL
--    (comparar contra public.users donde la URL SÍ existe → la vista no la filtra)
--
-- 5. Gating de handles:
--    select id, instagram_handle from public.v_profile v
--      join public.users u on u.id = v.id where u.ig_visible = FALSE;  → instagram_handle NULL
--
-- 6. Bloqueo bidireccional: si existe un par (A bloquea a B), ni A ni B ven al
--    otro en v_profile:
--    select count(*) from public.v_profile v join public.blocked_users b
--      on (b.blocker_id = v.id OR b.blocked_id = v.id)
--      where (b.blocked_id = auth.uid() OR b.blocker_id = auth.uid());  → 0
--
-- 7. Z-212 (2026-10-23): claim queda en cuarentena fail-closed. CUALQUIER
--    llamada autenticada falla con
--    'Reclamo de ZONE-ID deshabilitado temporalmente por seguridad (Z-212).'
--    El comportamiento histórico (mover id + devolver jsonb) ya NO aplica.
--
-- 8. verify oculta avatar no público:
--    select public.verify_zone_id('ZONE-XXXXXXXX');
--    (para un usuario con avatar_is_public=false → avatar_url NULL, existe display_name)
-- ============================================================================