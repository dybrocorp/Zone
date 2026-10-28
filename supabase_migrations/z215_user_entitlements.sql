-- ============================================================================
-- Z-215 — Entitlements Premium verificados en backend (Google Play).
--
-- Diseño       : docs/redesign/ZONE_PREMIUM_BILLING.md · ZONE_FREEMIUM_ARCHITECTURE §4
-- Aplicación   : SOLO CON AUTORIZACIÓN DEL OWNER (no ejecutar en esta sesión).
-- Escritura    : EXCLUSIVA de service_role / funciones definer de verificación.
--                NINGÚN usuario puede auto-conceder Premium por REST.
-- Rollback     : docs/redesign/ZONE_DATA_MIGRATION.md §5.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLA
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_entitlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    product TEXT NOT NULL CHECK (product IN ('zone_premium_monthly','zone_premium_annual')),
    platform TEXT NOT NULL DEFAULT 'android' CHECK (platform IN ('android')),
    purchase_token TEXT NOT NULL,          -- token de compra (sensible, NO credencial de pago)
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    starts_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    renewal_state TEXT NOT NULL DEFAULT 'unknown'
        CHECK (renewal_state IN ('active','grace','canceled','expired','refunded','unknown')),
    last_verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Un token por plataforma: evita filas duplicadas de la misma compra
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_entitlements_token
    ON public.user_entitlements (platform, purchase_token);
CREATE INDEX IF NOT EXISTS idx_user_entitlements_user
    ON public.user_entitlements (user_id, verified, expires_at);

-- ----------------------------------------------------------------------------
-- 2. RLS: owner-SELECT de columnas no sensibles vía RPC; INSERT/UPDATE/DELETE
--    CERRADOS para authenticated (sin policy): solo service_role escribe.
-- ----------------------------------------------------------------------------
ALTER TABLE public.user_entitlements ENABLE ROW LEVEL SECURITY;

-- Sin policies de UPDATE/INSERT/DELETE → escritura imposible por REST para
-- anon/authenticated. SELECT se entrega vía RPC (jamás expone purchase_token).

-- ----------------------------------------------------------------------------
-- 3. RPC: ENTITLEMENTS DEL LLAMADOR (solo verificados; sin purchase_token)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_entitlements()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_rows jsonb;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado' USING ERRCODE = '42501';
    END IF;
    SELECT COALESCE(jsonb_agg(e), '[]'::jsonb) INTO v_rows
    FROM (
        SELECT jsonb_build_object(
            'product',          product,
            'platform',         platform,
            'verified',         verified,
            'starts_at',        starts_at,
            'expires_at',       expires_at,
            'renewal_state',    renewal_state,
            'last_verified_at', last_verified_at
        ) AS e
        FROM public.user_entitlements
        WHERE user_id = v_uid
          AND verified = TRUE
        ORDER BY expires_at DESC NULLS LAST
    ) sub;
    RETURN jsonb_build_object('entitlements', v_rows);
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. RPC: ¿ENTITLEMENT PREMIUM VIGENTE? (bool, consumo interno/cliente)
--    Política: al menos UNA fila verificada con expires_at > now() y renewal
--    state no refunded/expired. Fail-closed si no hay auth.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_bluetooth_premium()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_count integer;
BEGIN
    IF v_uid IS NULL THEN
        RETURN FALSE;
    END IF;
    SELECT COUNT(*) INTO v_count
    FROM public.user_entitlements
    WHERE user_id = v_uid
      AND verified = TRUE
      AND expires_at IS NOT NULL
      AND expires_at > now()
      AND renewal_state NOT IN ('refunded','expired');
    RETURN v_count > 0;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. GRANTS (REVOKE total; patrón canon)
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.get_my_entitlements() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_entitlements() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.has_bluetooth_premium() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_bluetooth_premium() TO authenticated, service_role;

-- La tabla no se manipula por REST (solo definer): revoca DML directo
REVOKE ALL ON public.user_entitlements FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- 6. VERIFY (post-conditions)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT (SELECT relrowsecurity FROM pg_class
             WHERE relname = 'user_entitlements') THEN
        RAISE EXCEPTION 'VERIFY FALLA: user_entitlements sin RLS';
    END IF;
    -- Sin policies DML para authenticated (solo service_role vía definer)
    IF (SELECT COUNT(*) FROM pg_policy
         WHERE polrelid = 'public.user_entitlements'::regclass) <> 0 THEN
        RAISE EXCEPTION 'VERIFY FALLA: user_entitlements no debe tener policies';
    END IF;
END $$;
