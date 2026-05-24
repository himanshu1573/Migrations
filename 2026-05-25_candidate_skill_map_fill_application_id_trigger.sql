-- Migration: auto-fill candidate_skill_map.application_id when NULL
--
-- candidate_skill_map is unique on (candidate_id, skill_id) -> one row per candidate per skill,
-- shared across all of that candidate's applications. So application_id is a "provenance" tag,
-- not a per-application key. Policy (per product decision):
--   - Do NOT bulk-backfill existing NULLs.
--   - Going forward, whenever application_id is NULL on insert/update, fill it from the
--     candidate's MOST-RECENT application (by created_time). Never overwrite a value that was
--     explicitly provided (e.g. the current assessment context set by /api/candidate-skills).
--
-- Existing NULL rows therefore fill in naturally the next time they are touched.
-- Candidates with no application at all simply stay NULL.

BEGIN;

CREATE OR REPLACE FUNCTION public.fill_candidate_skill_map_application_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only derive when nothing was provided; never clobber an explicit value.
  IF NEW.application_id IS NULL AND NEW.candidate_id IS NOT NULL THEN
    SELECT a.id
      INTO NEW.application_id
    FROM public.applications_id a
    JOIN public.profiles_database p ON p.id = a.profiles_database_id
    WHERE p.candidate_id = NEW.candidate_id
    ORDER BY a.created_time DESC NULLS LAST, a.id DESC
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_candidate_skill_map_fill_application_id
  ON public.candidate_skill_map;

CREATE TRIGGER trg_candidate_skill_map_fill_application_id
BEFORE INSERT OR UPDATE ON public.candidate_skill_map
FOR EACH ROW
EXECUTE FUNCTION public.fill_candidate_skill_map_application_id();

COMMIT;
