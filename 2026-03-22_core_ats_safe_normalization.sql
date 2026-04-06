-- XPO ATS safe normalization for the three confusing tables:
--   profiles_database
--   applications_id
--   screenings
--
-- Goal:
-- 1. Keep the current live tables intact.
-- 2. Add normalized columns needed for the future clean schema.
-- 3. Backfill data in PostgreSQL without deleting existing fields first.
-- 4. Validate before any destructive cleanup.
--
-- Run this in parts, not blindly as one final cleanup script.

-- ============================================================
-- STEP 0: Profiles Database datatype fixes
-- ============================================================

-- Candidate phone must be TEXT, not NUMERIC, otherwise leading zeros are lost.
ALTER TABLE public.profiles_database
  ALTER COLUMN candidate_contact TYPE TEXT
  USING regexp_replace(candidate_contact::TEXT, '\.0+$', '');

-- Add a canonical vendor owner column for the future candidates model.
ALTER TABLE public.profiles_database
  ADD COLUMN IF NOT EXISTS vendor_owner_id UUID;

UPDATE public.profiles_database
SET vendor_owner_id = COALESCE(vendors_id, vendor_id)
WHERE vendor_owner_id IS NULL
  AND COALESCE(vendors_id, vendor_id) IS NOT NULL;

-- Helpful indexes for upcoming joins and validation.
CREATE INDEX IF NOT EXISTS idx_profiles_database_candidate_id
  ON public.profiles_database (candidate_id);

CREATE INDEX IF NOT EXISTS idx_profiles_database_vendor_owner_id
  ON public.profiles_database (vendor_owner_id);

CREATE INDEX IF NOT EXISTS idx_profiles_database_airtable_id
  ON public.profiles_database (airtable_id);

-- ============================================================
-- STEP 1: Applications normalization
-- Keep legacy columns, add normalized ones.
-- ============================================================

ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS candidate_id UUID,
  ADD COLUMN IF NOT EXISTS opening_id UUID,
  ADD COLUMN IF NOT EXISTS form_filled_by_id UUID,
  ADD COLUMN IF NOT EXISTS lyncogs TEXT,
  ADD COLUMN IF NOT EXISTS lyncogs_summary TEXT,
  ADD COLUMN IF NOT EXISTS lyncogs_violations TEXT,
  ADD COLUMN IF NOT EXISTS lyncogs_violations_remarks TEXT,
  ADD COLUMN IF NOT EXISTS edited_psr TEXT,
  ADD COLUMN IF NOT EXISTS pre_assessing_done BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pre_assessor_name TEXT,
  ADD COLUMN IF NOT EXISTS pre_assessing_remarks TEXT;

-- Backfill normalized FK aliases from existing columns.
UPDATE public.applications_id
SET candidate_id = profiles_database_id
WHERE candidate_id IS NULL
  AND profiles_database_id IS NOT NULL;

UPDATE public.applications_id
SET opening_id = openings_id
WHERE opening_id IS NULL
  AND openings_id IS NOT NULL;

-- Map "form_filled_by" Airtable text to screener UUID.
UPDATE public.applications_id a
SET form_filled_by_id = sp.id
FROM public.screeners_profile sp
WHERE a.form_filled_by_id IS NULL
  AND a.form_filled_by IS NOT NULL
  AND (
    a.form_filled_by = sp.airtable_id
    OR LOWER(a.form_filled_by) = LOWER(sp.name)
  );

-- Move application-scoped AI/report fields off profiles_database onto applications_id.
UPDATE public.applications_id a
SET
  lyncogs = COALESCE(a.lyncogs, p.lyncogs),
  lyncogs_summary = COALESCE(a.lyncogs_summary, p.lyncogs_summary),
  edited_psr = COALESCE(a.edited_psr, p.edited_psr)
FROM public.profiles_database p
WHERE a.profiles_database_id = p.id
  AND (
    p.lyncogs IS NOT NULL
    OR p.lyncogs_summary IS NOT NULL
    OR p.edited_psr IS NOT NULL
  );

-- Foreign keys on the new normalized aliases.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'applications_id_candidate_id_fkey'
  ) THEN
    ALTER TABLE public.applications_id
      ADD CONSTRAINT applications_id_candidate_id_fkey
      FOREIGN KEY (candidate_id) REFERENCES public.profiles_database(id) ON DELETE RESTRICT;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'applications_id_opening_id_fkey'
  ) THEN
    ALTER TABLE public.applications_id
      ADD CONSTRAINT applications_id_opening_id_fkey
      FOREIGN KEY (opening_id) REFERENCES public.openings(id) ON DELETE RESTRICT;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'applications_id_form_filled_by_id_fkey'
  ) THEN
    ALTER TABLE public.applications_id
      ADD CONSTRAINT applications_id_form_filled_by_id_fkey
      FOREIGN KEY (form_filled_by_id) REFERENCES public.screeners_profile(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_applications_id_candidate_id
  ON public.applications_id (candidate_id);

CREATE INDEX IF NOT EXISTS idx_applications_id_opening_id
  ON public.applications_id (opening_id);

CREATE INDEX IF NOT EXISTS idx_applications_id_form_filled_by_id
  ON public.applications_id (form_filled_by_id);

-- Only create the uniqueness once duplicate data is cleaned.
-- First check with the validation query in STEP 4.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'uq_applications_candidate_opening_vendor'
  ) AND NOT EXISTS (
    SELECT 1
    FROM (
      SELECT candidate_id, opening_id, vendor_id, COUNT(*) AS dup_count
      FROM public.applications_id
      WHERE candidate_id IS NOT NULL
        AND opening_id IS NOT NULL
        AND vendor_id IS NOT NULL
      GROUP BY 1, 2, 3
      HAVING COUNT(*) > 1
    ) d
  ) THEN
    ALTER TABLE public.applications_id
      ADD CONSTRAINT uq_applications_candidate_opening_vendor
      UNIQUE (candidate_id, opening_id, vendor_id);
  END IF;
END $$;

-- ============================================================
-- STEP 2: Screenings normalization
-- ============================================================

ALTER TABLE public.screenings
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS slot_key TEXT,
  ADD COLUMN IF NOT EXISTS screener_id UUID,
  ADD COLUMN IF NOT EXISTS communication_rating SMALLINT,
  ADD COLUMN IF NOT EXISTS confidence_rating SMALLINT,
  ADD COLUMN IF NOT EXISTS tech_self_rating TEXT,
  ADD COLUMN IF NOT EXISTS career_gap TEXT,
  ADD COLUMN IF NOT EXISTS question_wise_assessment JSONB,
  ADD COLUMN IF NOT EXISTS coding_question_assessment JSONB,
  ADD COLUMN IF NOT EXISTS post_screening_audit_json JSONB,
  ADD COLUMN IF NOT EXISTS overall_coverage_pct NUMERIC,
  ADD COLUMN IF NOT EXISTS screening_report TEXT,
  ADD COLUMN IF NOT EXISTS pre_screening_report TEXT,
  ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'screenings';

UPDATE public.screenings
SET scheduled_at = date
WHERE scheduled_at IS NULL
  AND date IS NOT NULL;

UPDATE public.screenings
SET slot_key = slotkey
WHERE slot_key IS NULL
  AND slotkey IS NOT NULL;

UPDATE public.screenings s
SET screener_id = sp.id
FROM public.screeners_profile sp
WHERE s.screener_id IS NULL
  AND s.screener_assigned IS NOT NULL
  AND (
    s.screener_assigned = sp.airtable_id
    OR LOWER(s.screener_assigned) = LOWER(sp.name)
  );

-- Move screening-scoped evaluation fields from profiles_database.
UPDATE public.screenings s
SET
  communication_rating = COALESCE(s.communication_rating, p.communication_rating::SMALLINT),
  confidence_rating = COALESCE(s.confidence_rating, p.confidence_rating::SMALLINT),
  tech_self_rating = COALESCE(s.tech_self_rating, p.tech_self_rating),
  career_gap = COALESCE(s.career_gap, p.career_gap),
  screening_report = COALESCE(s.screening_report, p.screening_report),
  post_screening_report = COALESCE(s.post_screening_report, p.edited_psr)
FROM public.profiles_database p
WHERE s.candidate_id = p.id
  AND (
    p.communication_rating IS NOT NULL
    OR p.confidence_rating IS NOT NULL
    OR p.tech_self_rating IS NOT NULL
    OR p.career_gap IS NOT NULL
    OR p.screening_report IS NOT NULL
    OR p.edited_psr IS NOT NULL
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'screenings_screener_id_fkey'
  ) THEN
    ALTER TABLE public.screenings
      ADD CONSTRAINT screenings_screener_id_fkey
      FOREIGN KEY (screener_id) REFERENCES public.screeners_profile(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_screenings_source'
  ) THEN
    ALTER TABLE public.screenings
      ADD CONSTRAINT chk_screenings_source
      CHECK (source IN ('screenings', 'screenings_copy'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_screenings_communication_rating'
  ) THEN
    ALTER TABLE public.screenings
      ADD CONSTRAINT chk_screenings_communication_rating
      CHECK (communication_rating IS NULL OR communication_rating BETWEEN 1 AND 5);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_screenings_confidence_rating'
  ) THEN
    ALTER TABLE public.screenings
      ADD CONSTRAINT chk_screenings_confidence_rating
      CHECK (confidence_rating IS NULL OR confidence_rating BETWEEN 1 AND 5);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_screenings_scheduled_at
  ON public.screenings (scheduled_at);

CREATE INDEX IF NOT EXISTS idx_screenings_slot_key
  ON public.screenings (slot_key);

CREATE INDEX IF NOT EXISTS idx_screenings_screener_id
  ON public.screenings (screener_id);

-- Protect against double-booking only when duplicates are gone.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'uq_screenings_slot_key'
  ) AND NOT EXISTS (
    SELECT 1
    FROM (
      SELECT slot_key, COUNT(*) AS dup_count
      FROM public.screenings
      WHERE slot_key IS NOT NULL
      GROUP BY 1
      HAVING COUNT(*) > 1
    ) d
  ) THEN
    ALTER TABLE public.screenings
      ADD CONSTRAINT uq_screenings_slot_key
      UNIQUE (slot_key);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_screenings_event_id_non_null
  ON public.screenings (event_id)
  WHERE event_id IS NOT NULL;

-- ============================================================
-- STEP 3: Validation queries
-- Run these after each section before dropping anything old.
-- ============================================================

-- 3.1 Profiles Database checks
-- SELECT COUNT(*) AS null_vendor_owner_id
-- FROM public.profiles_database
-- WHERE COALESCE(vendors_id, vendor_id) IS NOT NULL
--   AND vendor_owner_id IS NULL;
--
-- SELECT id, candidate_contact
-- FROM public.profiles_database
-- WHERE candidate_contact IS NOT NULL
-- LIMIT 20;

-- 3.2 Applications checks
-- SELECT COUNT(*) AS null_candidate_id
-- FROM public.applications_id
-- WHERE profiles_database_id IS NOT NULL
--   AND candidate_id IS NULL;
--
-- SELECT COUNT(*) AS null_opening_id
-- FROM public.applications_id
-- WHERE openings_id IS NOT NULL
--   AND opening_id IS NULL;
--
-- SELECT candidate_id, opening_id, vendor_id, COUNT(*)
-- FROM public.applications_id
-- WHERE candidate_id IS NOT NULL
--   AND opening_id IS NOT NULL
--   AND vendor_id IS NOT NULL
-- GROUP BY 1, 2, 3
-- HAVING COUNT(*) > 1;
--
-- SELECT COUNT(*) AS lyncogs_backfilled
-- FROM public.applications_id
-- WHERE lyncogs IS NOT NULL OR lyncogs_summary IS NOT NULL OR edited_psr IS NOT NULL;

-- 3.3 Screenings checks
-- SELECT COUNT(*) AS null_scheduled_at
-- FROM public.screenings
-- WHERE date IS NOT NULL
--   AND scheduled_at IS NULL;
--
-- SELECT COUNT(*) AS null_slot_key
-- FROM public.screenings
-- WHERE slotkey IS NOT NULL
--   AND slot_key IS NULL;
--
-- SELECT COUNT(*) AS screener_text_only
-- FROM public.screenings
-- WHERE screener_assigned IS NOT NULL
--   AND screener_id IS NULL;
--
-- SELECT slot_key, COUNT(*)
-- FROM public.screenings
-- WHERE slot_key IS NOT NULL
-- GROUP BY 1
-- HAVING COUNT(*) > 1;
--
-- SELECT event_id, COUNT(*)
-- FROM public.screenings
-- WHERE event_id IS NOT NULL
-- GROUP BY 1
-- HAVING COUNT(*) > 1;

-- ============================================================
-- STEP 4: Cleanup only after app + sync switch
-- Keep commented for now on purpose.
-- ============================================================

-- Example future cleanup, only after validation and API cutover:
-- ALTER TABLE public.applications_id DROP COLUMN IF EXISTS profiles_database_id;
-- ALTER TABLE public.applications_id DROP COLUMN IF EXISTS openings_id;
-- ALTER TABLE public.applications_id DROP COLUMN IF EXISTS form_filled_by;
-- ALTER TABLE public.screenings DROP COLUMN IF EXISTS date;
-- ALTER TABLE public.screenings DROP COLUMN IF EXISTS slotkey;
-- ALTER TABLE public.screenings DROP COLUMN IF EXISTS screener_assigned;
-- ALTER TABLE public.profiles_database DROP COLUMN IF EXISTS lyncogs;
-- ALTER TABLE public.profiles_database DROP COLUMN IF EXISTS lyncogs_summary;
-- ALTER TABLE public.profiles_database DROP COLUMN IF EXISTS screening_report;
-- ALTER TABLE public.profiles_database DROP COLUMN IF EXISTS edited_psr;
