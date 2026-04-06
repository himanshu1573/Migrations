-- XPO ATS legacy-column cleanup
-- Date: 2026-03-24
--
-- Purpose:
-- 1. Archive legacy columns that were shifted or marked deleted in the worksheet.
-- 2. Provide a ready-to-run DROP section for final cleanup.
--
-- Notes:
-- - The ARCHIVE section is safe and non-destructive.
-- - The DROP section is intentionally commented out. Uncomment only after a final app/API check.
-- - This file keeps current table names as-is:
--     profiles_database
--     applications_id
--     screenings

SET lock_timeout = '15s';

-- ============================================================
-- 1. Archive legacy profile columns before dropping
-- ============================================================

CREATE TABLE IF NOT EXISTS public._legacy_profiles_database_cleanup_20260324 AS
SELECT
  id,
  airtable_id,
  candidate_cost,
  bench_type,
  candidate_type,
  recruitment_notes,
  tech_self_rating,
  comments,
  screening_report
FROM public.profiles_database;

-- ============================================================
-- 2. Archive legacy application columns before dropping
-- ============================================================

CREATE TABLE IF NOT EXISTS public._legacy_applications_id_cleanup_20260324 AS
SELECT
  id,
  airtable_id,
  update_airtable,
  pre_l1_transcript,
  screening_report_link,
  post_screening_report,
  transcript,
  form_filled_by
FROM public.applications_id;

-- ============================================================
-- 3. Archive legacy screening columns before dropping
-- ============================================================

CREATE TABLE IF NOT EXISTS public._legacy_screenings_cleanup_20260324 AS
SELECT
  id,
  airtable_id,
  candidate_name,
  skill,
  cv_link,
  candidate_profile_id,
  screener_assigned,
  ai_interview_link,
  screener_evaluation_report,
  test_date,
  date,
  slotkey
FROM public.screenings;

-- ============================================================
-- 4. Validation snapshot
-- ============================================================

SELECT
  (SELECT COUNT(*) FROM public._legacy_profiles_database_cleanup_20260324) AS profile_archive_rows,
  (SELECT COUNT(*) FROM public._legacy_applications_id_cleanup_20260324) AS application_archive_rows,
  (SELECT COUNT(*) FROM public._legacy_screenings_cleanup_20260324) AS screening_archive_rows;

SELECT
  (SELECT COUNT(*) FROM public.profiles_database WHERE candidate_cost IS NOT NULL) AS profiles_candidate_cost,
  (SELECT COUNT(*) FROM public.profiles_database WHERE bench_type IS NOT NULL) AS profiles_bench_type,
  (SELECT COUNT(*) FROM public.profiles_database WHERE candidate_type IS NOT NULL) AS profiles_candidate_type,
  (SELECT COUNT(*) FROM public.profiles_database WHERE recruitment_notes IS NOT NULL) AS profiles_recruitment_notes,
  (SELECT COUNT(*) FROM public.profiles_database WHERE tech_self_rating IS NOT NULL) AS profiles_tech_self_rating,
  (SELECT COUNT(*) FROM public.profiles_database WHERE comments IS NOT NULL) AS profiles_comments,
  (SELECT COUNT(*) FROM public.profiles_database WHERE screening_report IS NOT NULL) AS profiles_screening_report,
  (SELECT COUNT(*) FROM public.applications_id WHERE update_airtable IS NOT NULL) AS apps_update_airtable,
  (SELECT COUNT(*) FROM public.applications_id WHERE pre_l1_transcript IS NOT NULL) AS apps_pre_l1_transcript,
  (SELECT COUNT(*) FROM public.applications_id WHERE screening_report_link IS NOT NULL) AS apps_screening_report_link,
  (SELECT COUNT(*) FROM public.applications_id WHERE post_screening_report IS NOT NULL) AS apps_post_screening_report,
  (SELECT COUNT(*) FROM public.applications_id WHERE transcript IS NOT NULL) AS apps_transcript,
  (SELECT COUNT(*) FROM public.applications_id WHERE form_filled_by IS NOT NULL) AS apps_form_filled_by,
  (SELECT COUNT(*) FROM public.screenings WHERE candidate_name IS NOT NULL) AS screenings_candidate_name,
  (SELECT COUNT(*) FROM public.screenings WHERE skill IS NOT NULL) AS screenings_skill,
  (SELECT COUNT(*) FROM public.screenings WHERE cv_link IS NOT NULL) AS screenings_cv_link,
  (SELECT COUNT(*) FROM public.screenings WHERE candidate_profile_id IS NOT NULL) AS screenings_candidate_profile_id,
  (SELECT COUNT(*) FROM public.screenings WHERE screener_assigned IS NOT NULL) AS screenings_screener_assigned,
  (SELECT COUNT(*) FROM public.screenings WHERE ai_interview_link IS NOT NULL) AS screenings_ai_interview_link,
  (SELECT COUNT(*) FROM public.screenings WHERE screener_evaluation_report IS NOT NULL) AS screenings_screener_evaluation_report,
  (SELECT COUNT(*) FROM public.screenings WHERE test_date IS NOT NULL) AS screenings_test_date,
  (SELECT COUNT(*) FROM public.screenings WHERE date IS NOT NULL) AS screenings_date,
  (SELECT COUNT(*) FROM public.screenings WHERE slotkey IS NOT NULL) AS screenings_slotkey;

-- ============================================================
-- 5. Final DROP section
-- ============================================================
-- Executed on production on 2026-03-24.

ALTER TABLE public.profiles_database
  DROP COLUMN IF EXISTS candidate_cost,
  DROP COLUMN IF EXISTS bench_type,
  DROP COLUMN IF EXISTS candidate_type,
  DROP COLUMN IF EXISTS recruitment_notes,
  DROP COLUMN IF EXISTS tech_self_rating,
  DROP COLUMN IF EXISTS comments,
  DROP COLUMN IF EXISTS screening_report;

ALTER TABLE public.applications_id
  DROP COLUMN IF EXISTS update_airtable,
  DROP COLUMN IF EXISTS pre_l1_transcript,
  DROP COLUMN IF EXISTS screening_report_link,
  DROP COLUMN IF EXISTS post_screening_report,
  DROP COLUMN IF EXISTS transcript,
  DROP COLUMN IF EXISTS form_filled_by;

ALTER TABLE public.screenings
  DROP COLUMN IF EXISTS candidate_name,
  DROP COLUMN IF EXISTS skill,
  DROP COLUMN IF EXISTS cv_link,
  DROP COLUMN IF EXISTS candidate_profile_id,
  DROP COLUMN IF EXISTS screener_assigned,
  DROP COLUMN IF EXISTS ai_interview_link,
  DROP COLUMN IF EXISTS screener_evaluation_report,
  DROP COLUMN IF EXISTS test_date,
  DROP COLUMN IF EXISTS date,
  DROP COLUMN IF EXISTS slotkey;
