-- User-approved XPO ATS schema updates based on the reviewed worksheet.
-- Date: 2026-03-24
--
-- This migration keeps current table names:
--   profiles_database
--   applications_id
--   screenings
--
-- It adds the columns required by the updated sync service and by the
-- review decisions confirmed on 2026-03-24.

SET lock_timeout = '15s';

-- ============================================================
-- 0. documents master
-- ============================================================

CREATE TABLE IF NOT EXISTS public.documents_master (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  airtable_id TEXT UNIQUE NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.documents_master_client_departments (
  document_master_id UUID NOT NULL REFERENCES public.documents_master(id) ON DELETE CASCADE,
  client_department_id UUID NOT NULL REFERENCES public.client_department(id) ON DELETE CASCADE,
  PRIMARY KEY (document_master_id, client_department_id)
);

-- ============================================================
-- 1. profiles_database
-- ============================================================

ALTER TABLE public.profiles_database
  ADD COLUMN IF NOT EXISTS edited_cv TEXT;

-- Candidate contact must remain candidate-level, but as TEXT.
ALTER TABLE public.profiles_database
  ALTER COLUMN candidate_contact TYPE TEXT
  USING regexp_replace(candidate_contact::TEXT, '\.0+$', '');

-- ============================================================
-- 2. applications_id
-- ============================================================

ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS candidate_type TEXT,
  ADD COLUMN IF NOT EXISTS bench_type TEXT,
  ADD COLUMN IF NOT EXISTS candidate_cost NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS recruitment_notes TEXT,
  ADD COLUMN IF NOT EXISTS candidate_document TEXT,
  ADD COLUMN IF NOT EXISTS form_filled_by_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'applications_id_form_filled_by_id_fkey'
  ) THEN
    ALTER TABLE public.applications_id
      ADD CONSTRAINT applications_id_form_filled_by_id_fkey
      FOREIGN KEY (form_filled_by_id)
      REFERENCES public.screeners_profile(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_applications_id_form_filled_by_id
  ON public.applications_id (form_filled_by_id);

-- Backfill from profile table for the newly shifted application-level fields.
UPDATE public.applications_id a
SET
  candidate_type = COALESCE(a.candidate_type, p.candidate_type),
  bench_type = COALESCE(a.bench_type, p.bench_type),
  candidate_cost = COALESCE(a.candidate_cost, p.candidate_cost),
  recruitment_notes = COALESCE(a.recruitment_notes, p.recruitment_notes),
  candidate_document = COALESCE(a.candidate_document, p.candidate_document)
FROM public.profiles_database p
WHERE a.profiles_database_id = p.id;

-- Backfill form_filled_by_id from existing legacy text if the value stores screener airtable ids.
UPDATE public.applications_id a
SET form_filled_by_id = sp.id
FROM public.screeners_profile sp
WHERE a.form_filled_by_id IS NULL
  AND a.form_filled_by IS NOT NULL
  AND (
    a.form_filled_by = sp.airtable_id
    OR LOWER(a.form_filled_by) = LOWER(sp.name)
  );

-- ============================================================
-- 3. rooms + room_vendors
-- ============================================================

ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS airtable_id TEXT;

DROP INDEX IF EXISTS uq_rooms_airtable_id;
CREATE UNIQUE INDEX IF NOT EXISTS uq_rooms_airtable_id
  ON public.rooms (airtable_id);

CREATE TABLE IF NOT EXISTS public.room_vendors (
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  vendor_id UUID NOT NULL REFERENCES public.vendor_master(id) ON DELETE CASCADE,
  PRIMARY KEY (room_id, vendor_id)
);

-- ============================================================
-- 4. screenings
-- ============================================================

ALTER TABLE public.screenings
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS slot_key TEXT,
  ADD COLUMN IF NOT EXISTS screener_id UUID,
  ADD COLUMN IF NOT EXISTS pre_screening_report TEXT,
  ADD COLUMN IF NOT EXISTS post_screening_report TEXT,
  ADD COLUMN IF NOT EXISTS screening_report_link TEXT,
  ADD COLUMN IF NOT EXISTS transcript TEXT,
  ADD COLUMN IF NOT EXISTS question_wise_assessment JSONB,
  ADD COLUMN IF NOT EXISTS coding_question_assessment JSONB,
  ADD COLUMN IF NOT EXISTS overall_coverage_pct NUMERIC,
  ADD COLUMN IF NOT EXISTS q1_assessed TEXT,
  ADD COLUMN IF NOT EXISTS q2_assessed TEXT,
  ADD COLUMN IF NOT EXISTS post_screening_audit_json JSONB,
  ADD COLUMN IF NOT EXISTS pre_screening_report_json JSONB;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'screenings_screener_id_fkey'
  ) THEN
    ALTER TABLE public.screenings
      ADD CONSTRAINT screenings_screener_id_fkey
      FOREIGN KEY (screener_id)
      REFERENCES public.screeners_profile(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_screenings_scheduled_at
  ON public.screenings (scheduled_at);

CREATE INDEX IF NOT EXISTS idx_screenings_slot_key
  ON public.screenings (slot_key);

CREATE INDEX IF NOT EXISTS idx_screenings_screener_id
  ON public.screenings (screener_id);

-- Non-destructive backfills from legacy screening columns.
UPDATE public.screenings
SET scheduled_at = COALESCE(scheduled_at, date)
WHERE date IS NOT NULL;

UPDATE public.screenings
SET slot_key = COALESCE(slot_key, slotkey)
WHERE slotkey IS NOT NULL;

UPDATE public.screenings s
SET screener_id = sp.id
FROM public.screeners_profile sp
WHERE s.screener_id IS NULL
  AND s.screener_assigned IS NOT NULL
  AND (
    s.screener_assigned = sp.airtable_id
    OR LOWER(s.screener_assigned) = LOWER(sp.name)
  );

-- User decision: profile screening report becomes pre_screening_report in screenings.
UPDATE public.screenings s
SET pre_screening_report = COALESCE(s.pre_screening_report, p.screening_report)
FROM public.profiles_database p
WHERE s.candidate_id = p.id
  AND p.screening_report IS NOT NULL;

-- User decision: edited_psr should be removed, with value landing on screenings.post_screening_report.
-- In the live PG snapshot this legacy column may already be gone, so guard it.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles_database'
      AND column_name = 'edited_psr'
  ) THEN
    EXECUTE $sql$
      UPDATE public.screenings s
      SET post_screening_report = COALESCE(s.post_screening_report, p.edited_psr)
      FROM public.profiles_database p
      WHERE s.candidate_id = p.id
        AND p.edited_psr IS NOT NULL
    $sql$;
  END IF;
END $$;

-- User decision: application transcript/report artifacts should sit on screenings.
UPDATE public.screenings s
SET
  screening_report_link = COALESCE(s.screening_report_link, a.screening_report_link),
  post_screening_report = COALESCE(s.post_screening_report, a.post_screening_report),
  transcript = COALESCE(s.transcript, a.transcript)
FROM public.applications_id a
WHERE s.application_id = a.id;

-- ============================================================
-- 5. Helpful validation queries
-- ============================================================

-- SELECT COUNT(*) FROM public.profiles_database WHERE edited_cv IS NOT NULL;
-- SELECT COUNT(*) FROM public.applications_id WHERE candidate_type IS NOT NULL;
-- SELECT COUNT(*) FROM public.screenings WHERE pre_screening_report IS NOT NULL;
-- SELECT COUNT(*) FROM public.screenings WHERE transcript IS NOT NULL;
-- SELECT COUNT(*) FROM public.rooms WHERE airtable_id IS NOT NULL;
