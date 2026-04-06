BEGIN;

CREATE OR REPLACE FUNCTION public.ensure_status_config_row(
  p_domain text,
  p_label text
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_label text := btrim(coalesce(p_label, ''));
  v_code_base text;
  v_code_candidate text;
  v_id uuid;
  v_attempt integer := 0;
  v_sort_order smallint;
BEGIN
  IF btrim(coalesce(p_domain, '')) = '' OR v_label = '' THEN
    RETURN NULL;
  END IF;

  SELECT sc.id
  INTO v_id
  FROM public.status_config sc
  WHERE sc.domain = p_domain
    AND lower(btrim(sc.label)) = lower(v_label)
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  v_code_base := upper(regexp_replace(v_label, '[^a-zA-Z0-9]+', '_', 'g'));
  v_code_base := trim(both '_' FROM v_code_base);

  IF v_code_base = '' THEN
    v_code_base := 'STATUS';
  END IF;

  SELECT coalesce(max(sc.sort_order), 0)::smallint
  INTO v_sort_order
  FROM public.status_config sc
  WHERE sc.domain = p_domain;

  LOOP
    v_code_candidate := CASE
      WHEN v_attempt = 0 THEN left(v_code_base, 100)
      ELSE left(v_code_base || '_' || v_attempt::text, 100)
    END;

    BEGIN
      INSERT INTO public.status_config (
        domain,
        code,
        label,
        is_terminal,
        sort_order
      )
      VALUES (
        p_domain,
        v_code_candidate,
        v_label,
        false,
        (v_sort_order + 1 + v_attempt)::smallint
      )
      RETURNING id
      INTO v_id;

      RETURN v_id;
    EXCEPTION
      WHEN unique_violation THEN
        SELECT sc.id
        INTO v_id
        FROM public.status_config sc
        WHERE sc.domain = p_domain
          AND lower(btrim(sc.label)) = lower(v_label)
        LIMIT 1;

        IF v_id IS NOT NULL THEN
          RETURN v_id;
        END IF;

        v_attempt := v_attempt + 1;
        IF v_attempt > 1000 THEN
          RAISE EXCEPTION 'Unable to generate unique status_config code for domain % and label %', p_domain, v_label;
        END IF;
    END;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_status_config_reference()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_domain text;
BEGIN
  v_domain := CASE TG_TABLE_NAME
    WHEN 'applications_id' THEN 'application'
    WHEN 'openings' THEN 'opening'
    WHEN 'screenings' THEN 'screening'
    ELSE NULL
  END;

  IF v_domain IS NULL THEN
    RAISE EXCEPTION 'sync_status_config_reference() does not support table %', TG_TABLE_NAME;
  END IF;

  IF NEW.status IS NULL OR btrim(NEW.status) = '' THEN
    NEW.status_config_id := NULL;
    RETURN NEW;
  END IF;

  NEW.status := btrim(NEW.status);
  NEW.status_config_id := public.ensure_status_config_row(v_domain, NEW.status);
  RETURN NEW;
END;
$$;

ALTER TABLE public.applications_id
  ADD COLUMN IF NOT EXISTS status_config_id uuid;

ALTER TABLE public.openings
  ADD COLUMN IF NOT EXISTS status_config_id uuid;

ALTER TABLE public.screenings
  ADD COLUMN IF NOT EXISTS status_config_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'applications_id_status_config_id_fkey'
      AND conrelid = 'public.applications_id'::regclass
  ) THEN
    ALTER TABLE public.applications_id
      ADD CONSTRAINT applications_id_status_config_id_fkey
      FOREIGN KEY (status_config_id)
      REFERENCES public.status_config (id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'openings_status_config_id_fkey'
      AND conrelid = 'public.openings'::regclass
  ) THEN
    ALTER TABLE public.openings
      ADD CONSTRAINT openings_status_config_id_fkey
      FOREIGN KEY (status_config_id)
      REFERENCES public.status_config (id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'screenings_status_config_id_fkey'
      AND conrelid = 'public.screenings'::regclass
  ) THEN
    ALTER TABLE public.screenings
      ADD CONSTRAINT screenings_status_config_id_fkey
      FOREIGN KEY (status_config_id)
      REFERENCES public.status_config (id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_applications_id_status_config_id
  ON public.applications_id (status_config_id);

CREATE INDEX IF NOT EXISTS idx_openings_status_config_id
  ON public.openings (status_config_id);

CREATE INDEX IF NOT EXISTS idx_screenings_status_config_id
  ON public.screenings (status_config_id);

UPDATE public.applications_id a
SET status_config_id = public.ensure_status_config_row('application', a.status)
WHERE a.status IS NOT NULL
  AND btrim(a.status) <> ''
  AND (
    a.status_config_id IS NULL
    OR a.status_config_id <> public.ensure_status_config_row('application', a.status)
  );

UPDATE public.openings o
SET status_config_id = public.ensure_status_config_row('opening', o.status)
WHERE o.status IS NOT NULL
  AND btrim(o.status) <> ''
  AND (
    o.status_config_id IS NULL
    OR o.status_config_id <> public.ensure_status_config_row('opening', o.status)
  );

UPDATE public.screenings s
SET status_config_id = public.ensure_status_config_row('screening', s.status)
WHERE s.status IS NOT NULL
  AND btrim(s.status) <> ''
  AND (
    s.status_config_id IS NULL
    OR s.status_config_id <> public.ensure_status_config_row('screening', s.status)
  );

DROP TRIGGER IF EXISTS trg_applications_id_status_config_ref ON public.applications_id;
CREATE TRIGGER trg_applications_id_status_config_ref
BEFORE INSERT OR UPDATE OF status
ON public.applications_id
FOR EACH ROW
EXECUTE FUNCTION public.sync_status_config_reference();

DROP TRIGGER IF EXISTS trg_openings_status_config_ref ON public.openings;
CREATE TRIGGER trg_openings_status_config_ref
BEFORE INSERT OR UPDATE OF status
ON public.openings
FOR EACH ROW
EXECUTE FUNCTION public.sync_status_config_reference();

DROP TRIGGER IF EXISTS trg_screenings_status_config_ref ON public.screenings;
CREATE TRIGGER trg_screenings_status_config_ref
BEFORE INSERT OR UPDATE OF status
ON public.screenings
FOR EACH ROW
EXECUTE FUNCTION public.sync_status_config_reference();

COMMIT;
