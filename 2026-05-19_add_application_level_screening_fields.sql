-- ============================================================
-- Migration: Add application-level AI screening fields
-- Date: 2026-05-19
-- Reason: A candidate can have multiple applications (different
--   openings/vendors). Previously gap_analysis, employment_history,
--   jumping_frequency, and edited_cv lived only on profiles_database,
--   so the last AI screening would overwrite earlier ones.
--   Moving these fields to applications_id fixes the per-application
--   isolation problem.
--   cv_link_override is a new application-level URL field.
--
-- Dual-write note: profiles_database columns are NOT dropped here.
--   The sync service will write to BOTH tables during transition.
--   A separate migration will drop profiles_database columns once
--   everything is validated.
-- ============================================================

-- 1. Gap Analysis — mirrors profiles_database.gap_analysis (text)
ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS gap_analysis text;

-- 2. Employment History — mirrors profiles_database.employment_history (text)
ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS employment_history text;

-- 3. Jumping Frequency — mirrors profiles_database.jumping_frequency (numeric)
ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS jumping_frequency numeric;

-- 4. Edited CV — mirrors profiles_database.edited_cv (text / URL)
ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS edited_cv text;

-- 5. CV Link Override — new application-level URL field (text)
ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS cv_link_override text;

-- ============================================================
-- Verify columns were added
-- ============================================================
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'applications_id'
  AND column_name IN (
    'gap_analysis',
    'employment_history',
    'jumping_frequency',
    'edited_cv',
    'cv_link_override'
  )
ORDER BY column_name;
