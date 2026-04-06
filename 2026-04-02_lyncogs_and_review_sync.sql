BEGIN;

ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS lyncogs_violations text,
  ADD COLUMN IF NOT EXISTS lyncogs_violations_remarks text;

ALTER TABLE public.screenings
  ADD COLUMN IF NOT EXISTS review_request_status text,
  ADD COLUMN IF NOT EXISTS review_request_comments text,
  ADD COLUMN IF NOT EXISTS review_requested_by text,
  ADD COLUMN IF NOT EXISTS review_request_date date,
  ADD COLUMN IF NOT EXISTS review_action_date date,
  ADD COLUMN IF NOT EXISTS review_done_by text;

COMMIT;
