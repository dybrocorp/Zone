-- ============================================================
-- ZONE — Z-210 — Canonical encounter key (PHASE 2.2.3)
-- Objetivo: idempotencia determinista A↔B sin reestructurar RLS.
-- La app (lib/services/encounter_key.dart) deriva `encounter_key =
-- 'ZEN-1:' + hex(sha256('ZEN-1|zona|zona|yyyymmddhh')))` — el MISMO valor
-- en ambos dispositivos para un encuentro lógico (par ordenado de ZONE-IDs
-- + bucket horario UTC). El UPSERT sobre (user_id, encounter_key) converge
-- sin duplicados aunque un dispositivo sincronice tarde (offline-first).
-- Todo es idempotente (ADD COLUMN IF NOT EXISTS / CREATE UNIQUE INDEX IF
-- NOT EXISTS). RLS sin cambios: las políticas existentes ya cubren la
-- columna nueva (mismas filas, mismo user_id). Las filas históricas quedan
-- con encounter_key NULL (los NULL no colisionan en el índice único) y se
-- siguen sincronizando por la vía clásica.
-- ============================================================

ALTER TABLE public.encounters
    ADD COLUMN IF NOT EXISTS encounter_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_encounter_key
    ON public.encounters(user_id, encounter_key);
