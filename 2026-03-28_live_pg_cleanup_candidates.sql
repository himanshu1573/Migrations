-- Live PG cleanup candidates
-- Generated from live catalog inspection on 2026-03-28
--
-- Review first. This file is intentionally conservative.

SET lock_timeout = '15s';

-- ============================================================
-- 1. Archive cleanup tables from 2026-03-24
-- ============================================================
-- These tables are archive copies created during phase2 legacy-column cleanup.

DROP TABLE IF EXISTS public._legacy_profiles_database_cleanup_20260324;
DROP TABLE IF EXISTS public._legacy_applications_id_cleanup_20260324;
DROP TABLE IF EXISTS public._legacy_screenings_cleanup_20260324;

-- ============================================================
-- 2. Duplicate skill scratch table
-- ============================================================
-- Safe only if duplicate-skill cleanup is complete.

DROP TABLE IF EXISTS public.skill_master_duplicate;

-- ============================================================
-- 3. Optional old question-bank tables
-- ============================================================
-- Uncomment only after final confirmation that nothing depends on them.
-- `questions` is empty in live DB; `difficulties` appears to support only that older model.

-- DROP TABLE IF EXISTS public.questions;
-- DROP TABLE IF EXISTS public.difficulties;
