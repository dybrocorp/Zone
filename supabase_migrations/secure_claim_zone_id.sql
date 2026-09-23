-- ============================================================================
-- Z-001 (Fase A) + Z-103 · Hardening de claim_zone_id / verify_zone_id
-- Consolidado · ZONE · 2026-09-22
--
-- Decisión CTO (docs/CTO_REVIEW_REQUIRED.md): Opción 3 Híbrida por fases.
-- Fase A (este archivo): controles de AUTORIZACIÓN (no criptográficos):
--   • REVOKE anon/PUBLIC de claim_zone_id y verify_zone_id (solo authenticated).
--   • Validación de formato estricto del ZONE-ID en el servidor.
--   • Rate-limit de intentos fallidos por ZONE-ID (ventana deslizante 15 min).
--   • claim_zone_id YA NO escribe public_key (fin de la rotación silenciosa).
--   • verify_zone_id ya NO expone 'id' ni 'zone_id' (elimina el oráculo).
--   • Auditoría de intentos (éxito/fallo) en public.zone_claim_attempts.
--
-- Fase B (PUERTA CTO, posterior): identidad de firma Ed25519 + códigos de
-- recuperación + update_public_key firmado + transfer firmado.
-- ⚠️ No usar supabase_emergency_recovery.sql ni supabase_migration_fix.sql
--    (mantienen GRANT anon; migration_fix contiene un DELETE destructivo).
--
-- Idempotente: puede ejecutarse varias veces. Verificar en remoto con el
-- bloque "PRUEBAS SQL" al final.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tabla de auditoría / rate-limit (acceso SOLO vía SECURITY DEFINER)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.zone_claim_attempts (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  zone_id       TEXT NOT NULL,
  uid           UUID,
  success       BOOLEAN NOT NULL DEFAULT FALSE,
  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zone_claim_attempts_zone_time
  ON public.zone_claim_attempts (zone_id, attempted_at DESC);

-- Bloquear acceso directo (PostgREST / SQL): ni anon ni authenticated tocan la tabla.
REVOKE ALL ON public.zone_claim_attempts FROM anon, authenticated, PUBLIC;
ALTER TABLE public.zone_claim_attempts ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. claim_zone_id endurecido (solo authenticated, con rate-limit, sin public_key)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_zone_id(p_zone_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_failures   bigint;
  v_target     uuid;
BEGIN
  -- a) Autenticación obligatoria (doble compuerta: GRANT + chequeo)
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesión autenticada';
  END IF;

  -- b) Formato estricto: ZONE- + 8×[A-Z0-9]
  IF p_zone_id !~ '^ZONE-[A-Z0-9]{8}$' THEN
    RAISE EXCEPTION 'Formato de ZONE-ID inválido';
  END IF;

  -- c) Rate-limit: máx 5 intentos FALLIDOS por ZONE-ID en 15 min
  SELECT count(*) INTO v_failures
  FROM public.zone_claim_attempts
  WHERE zone_id = p_zone_id
    AND success = FALSE
    AND attempted_at > now() - interval '15 minutes';
  IF v_failures >= 5 THEN
    RAISE EXCEPTION 'Demasiados intentos para este ZONE-ID. Reintenta en 15 minutos.';
  END IF;

  -- d) ¿Existe la fila objetivo?
  SELECT id INTO v_target FROM public.users WHERE zone_id = p_zone_id;
  IF v_target IS NULL THEN
    INSERT INTO public.zone_claim_attempts (zone_id, uid, success)
    VALUES (p_zone_id, v_uid, FALSE);
    RAISE EXCEPTION 'ZONE-ID no encontrado';
  END IF;

  -- e) Reclamo de propiedad (idempotente). NO toca public_key.
  UPDATE public.users SET id = v_uid WHERE zone_id = p_zone_id;

  -- f) Auditoría (éxito)
  INSERT INTO public.zone_claim_attempts (zone_id, uid, success)
  VALUES (p_zone_id, v_uid, TRUE);
END;
$$;

-- Permisos: fuera anon/public; solo authenticated.
REVOKE EXECUTE ON FUNCTION public.claim_zone_id(text) FROM PUBLIC, anon;
DROP FUNCTION IF EXISTS public.claim_zone_id(text, text); -- variantes 2-arg obsoletas (emergencia / migration_fix)
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. verify_zone_id endurecido (solo authenticated, sin oráculo)
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

  -- Rate-limit compartido con claim (evita enumeración)
  SELECT count(*) INTO v_failures
  FROM public.zone_claim_attempts
  WHERE zone_id = p_zone_id
    AND success = FALSE
    AND attempted_at > now() - interval '15 minutes';
  IF v_failures >= 5 THEN
    RAISE EXCEPTION 'Demasiados intentos para este ZONE-ID. Reintenta en 15 minutos.';
  END IF;

  -- NO se expone 'id' ni se filtra mensajes distintos; solo existencia + datos públicos.
  SELECT jsonb_build_object(
    'exists', TRUE,
    'display_name', display_name,
    'avatar_url', avatar_url
  ) INTO v_user_data
  FROM public.users
  WHERE zone_id = p_zone_id;

  IF v_user_data IS NULL THEN
    INSERT INTO public.zone_claim_attempts (zone_id, uid, success)
    VALUES (p_zone_id, v_uid, FALSE);
  END IF;

  RETURN v_user_data; -- NULL si no existe
END;
$$;

-- Permisos: fuera anon/public; solo authenticated.
REVOKE EXECUTE ON FUNCTION public.verify_zone_id(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_zone_id(text) TO authenticated;

-- Seniales de compatibilidad: versión nueva en el cliente llama claim 1-arg.
-- El cliente (zone_id_service.dart) ya no envía p_public_key.

-- ============================================================================
-- PRUEBAS SQL (ejecutar en el SQL Editor de Supabase tras aplicar el archivo)
-- ============================================================================
-- 1. anon → claim/verify denegados:
--    set role anon; select public.claim_zone_id('ZONE-AAAAAAAA');
--    → ERROR: permission denied (403). set role authenticated; (restaurar)
-- 2. authenticated con formato inválido:
--    select public.claim_zone_id('nope');   → 'Formato de ZONE-ID inválido'
-- 3. authenticated con ZONE-ID inexistente → 'ZONE-ID no encontrado' (y genera intento fallido)
-- 4. Rate-limit: tras 5 formatos/existentes fallidos en 15 min → 'Demasiados intentos...'
-- 5. claim legítimo NO altera public_key:
--    select public_key from public.users where zone_id='ZONE-XXXXXXXX';
--    (el claim no cambia la fila) → el sistema de clave vieja queda intacto
-- 6. claim legítimo mueve id al uid actual y es idempotente (repetir 2× ok)
-- 7. verify_zone_id NO devuelve 'id'/'zone_id':
--    select public.verify_zone_id('ZONE-XXXXXXXX'); → {exists, display_name, avatar_url}
-- ============================================================================