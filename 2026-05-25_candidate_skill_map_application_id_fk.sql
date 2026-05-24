-- Migration: candidate_skill_map.application_id  ->  FK to applications_id.id (uuid)
--
-- Context:
--   candidate_skill_map.application_id was a free-text column holding a mix of:
--     - applications_id.id (uuid)               ~3,005 rows
--     - applications_id.application_id (text)    ~7,386 rows  (e.g. "743_DD16167")
--     - applications_id.airtable_id (rec...)     ~3,472 rows  (Airtable record IDs)
--   plus ~115 orphans pointing at applications that no longer exist, and ~15,565 NULLs.
--
--   Peer tables (screenings, screening_invite_logs, screener_assignments) already use
--   application_id uuid -> applications_id.id. This migration makes candidate_skill_map
--   consistent: normalize all resolvable values to the uuid, backfill unambiguous NULLs,
--   convert the column to uuid, and add a real foreign key.
--
-- Safety:
--   - Runs in a single transaction.
--   - Snapshots the column to backup_candidate_skill_map_appid_20260525 first (reversible).
--   - Idempotent guards on the FK/index so it can be re-run.
--   - candidate_skill_map is NOT a sync target, so this does not conflict with the Airtable sync.

BEGIN;

-- Lift the pooler's per-statement timeout for this migration only (data rewrite + type change).
SET LOCAL statement_timeout = 0;

-- 0. Reversible backup of the affected column (old text values).
DROP TABLE IF EXISTS public.backup_candidate_skill_map_appid_20260525;
CREATE TABLE public.backup_candidate_skill_map_appid_20260525 AS
SELECT id, candidate_id, skill_id, application_id
FROM public.candidate_skill_map;

COMMENT ON TABLE public.backup_candidate_skill_map_appid_20260525 IS
  'Pre-FK snapshot of candidate_skill_map.application_id (old text values) taken 2026-05-25.';

-- 1. Normalize every resolvable non-null value to the canonical applications_id.id (as text).
--    Done as three index-friendly join-updates (priority: uuid id is already canonical;
--    then text application_id; then airtable_id rec-IDs). Each row resolves to exactly one
--    application (verified: 0 ambiguous multi-key matches).

-- 1a. Values that are the text application_id (e.g. "743_DD16167") -> applications_id.id
UPDATE public.candidate_skill_map c
SET application_id = a.id::text
FROM public.applications_id a
WHERE c.application_id = a.application_id
  AND c.application_id <> a.id::text;

-- 1b. Values that are an Airtable record id (rec...) -> applications_id.id
UPDATE public.candidate_skill_map c
SET application_id = a.id::text
FROM public.applications_id a
WHERE c.application_id = a.airtable_id
  AND c.application_id <> a.id::text;

-- 2. Null out the unresolvable orphans (values that match no application by any key).
UPDATE public.candidate_skill_map c
SET application_id = NULL
WHERE c.application_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.applications_id a WHERE a.id::text = c.application_id
  );

-- 3. Backfill NULL rows for candidates that map to exactly ONE application.
--    Uses the real relational path: candidate_id -> profiles_database -> applications_id.
WITH single_app AS (
  SELECT p.candidate_id AS cand, (array_agg(a.id))[1] AS app_id
  FROM public.applications_id a
  JOIN public.profiles_database p ON p.id = a.profiles_database_id
  WHERE p.candidate_id IS NOT NULL
  GROUP BY p.candidate_id
  HAVING count(DISTINCT a.id) = 1
)
UPDATE public.candidate_skill_map c
SET application_id = sa.app_id::text
FROM single_app sa
WHERE c.application_id IS NULL
  AND c.candidate_id = sa.cand;

-- 4. Convert the column to uuid (all remaining values are valid uuid-text or NULL).
ALTER TABLE public.candidate_skill_map
  ALTER COLUMN application_id TYPE uuid USING application_id::uuid;

-- 5. Add the foreign key (ON DELETE SET NULL so deleting an application keeps the skill rows).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'candidate_skill_map_application_id_fkey'
      AND conrelid = 'public.candidate_skill_map'::regclass
  ) THEN
    ALTER TABLE public.candidate_skill_map
      ADD CONSTRAINT candidate_skill_map_application_id_fkey
      FOREIGN KEY (application_id)
      REFERENCES public.applications_id (id)
      ON DELETE SET NULL;
  END IF;
END;
$$;

-- 6. Index the FK column.
CREATE INDEX IF NOT EXISTS idx_candidate_skill_map_application_id
  ON public.candidate_skill_map USING btree (application_id);

COMMIT;
