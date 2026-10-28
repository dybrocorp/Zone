-- ============================================================
-- ZONE — Z-211 — Canonical match pair (PHASE 2.2.4)
-- Objetivo: un solo match lógico por par de usuarios, independiente de la
-- dirección requester/receiver. `requester_id`/`receiver_id` SE CONSERVAN
-- (expresan quién pidió y quién puede aceptar; RLS sin cambios).
-- Todo es idempotente (ADD COLUMN IF NOT EXISTS / DROP+ADD CONSTRAINT).
-- Compatibilidad PostgreSQL: columnas generadas STORED (PG ≥ 12; Supabase
-- ejecuta PG 15+) con LEAST/GREATEST sobre UUID (operadores btree de uuid,
-- expresiones inmutables, aptas para columnas generadas e índices únicos).
-- Reconciliación histórica: si existen duplicados reversos (dos filas A→B y
-- B→A), se conserva deterministamente la MÁS ANTIGUA (created_at, desempate
-- por id); si alguna duplicada estaba `accepted`, la superviviente se
-- promueve a `accepted` (se preserva el estado más fuerte, nunca se degrada).
-- Solo entonces se eliminan las filas sobrantes, con NOTICE de reporte (sin
-- destrucción silenciosa).
-- ============================================================

ALTER TABLE public.matches
    ADD COLUMN IF NOT EXISTS canonical_low UUID
        GENERATED ALWAYS AS (LEAST(requester_id, receiver_id)) STORED,
    ADD COLUMN IF NOT EXISTS canonical_high UUID
        GENERATED ALWAYS AS (GREATEST(requester_id, receiver_id)) STORED;

DO $$
DECLARE
  pair RECORD;
  keep_id UUID;
  removed INT;
  total_pairs INT := 0;
  total_rows INT := 0;
BEGIN
  FOR pair IN
    SELECT canonical_low AS lo, canonical_high AS hi, COUNT(*) AS c
      FROM public.matches
     GROUP BY 1, 2
    HAVING COUNT(*) > 1
  LOOP
    total_pairs := total_pairs + 1;
    SELECT m.id INTO keep_id
      FROM public.matches m
     WHERE m.canonical_low = pair.lo AND m.canonical_high = pair.hi
     ORDER BY m.created_at ASC, m.id ASC
     LIMIT 1;
    IF EXISTS (SELECT 1 FROM public.matches m
                WHERE m.canonical_low = pair.lo
                  AND m.canonical_high = pair.hi
                  AND m.status = 'accepted') THEN
      UPDATE public.matches SET status = 'accepted' WHERE id = keep_id;
    END IF;
    DELETE FROM public.matches
     WHERE canonical_low = pair.lo
       AND canonical_high = pair.hi
       AND id <> keep_id;
    GET DIAGNOSTICS removed = ROW_COUNT;
    total_rows := total_rows + removed;
    RAISE NOTICE 'Z-211: pair (%, %) kept %, removed % row(s)',
      pair.lo, pair.hi, keep_id, removed;
  END LOOP;
  RAISE NOTICE 'Z-211: % duplicate pair(s) reconciled, % row(s) removed',
    total_pairs, total_rows;
END $$;

ALTER TABLE public.matches
    DROP CONSTRAINT IF EXISTS uq_matches_canonical_pair;
ALTER TABLE public.matches
    ADD CONSTRAINT uq_matches_canonical_pair
    UNIQUE (canonical_low, canonical_high);
