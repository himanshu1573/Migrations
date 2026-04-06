BEGIN;

ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS pre_assessing_done boolean,
  ADD COLUMN IF NOT EXISTS pre_assessor_name text,
  ADD COLUMN IF NOT EXISTS pre_assessing_remarks text;

ALTER TABLE public.screenings
  ADD COLUMN IF NOT EXISTS pre_assessing_done boolean,
  ADD COLUMN IF NOT EXISTS pre_assessor_name text,
  ADD COLUMN IF NOT EXISTS pre_assessing_remarks text;

COMMIT;
