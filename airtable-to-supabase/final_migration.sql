-- ============================================================
-- XPO ATS — FINAL MIGRATION SQL (CORRECTED)
-- Based on analysis of live public_schema.sql dump.
-- Run this ONCE on your existing migrated schema.
-- All steps are wrapped in a transaction so it rolls back
-- cleanly if anything fails.
-- NOTE:
--   This file reflects the earlier broader normalization plan.
--   Current project direction now removes prompts, interview_feedback,
--   interview_rounds, and profiles_database.vendor_id from the target
--   schema. See the latest app migration files for the active cleanup path.
-- ============================================================

BEGIN;

-- ============================================================
-- STEP 1: REMOVE BROKEN / BACK-REFERENCE FKs
-- These are the "back-references" from your Airtable where
-- a parent table was pointing at a child — wrong direction.
-- ============================================================

-- openings pointing back at applications (reverse FK)
ALTER TABLE public.openings
    DROP CONSTRAINT IF EXISTS fk_openings_applications_id;

ALTER TABLE public.openings
    DROP CONSTRAINT IF EXISTS fk_openings_cv_sent_to_client_id;

ALTER TABLE public.openings
    DROP CONSTRAINT IF EXISTS fk_openings_cv_sent_to_client_pipeline_id;

-- openings pointing back at profiles_database (reverse FK)
ALTER TABLE public.openings
    DROP CONSTRAINT IF EXISTS fk_openings_profiles_database_id;

-- client_master ↔ client_department circular reference
-- client_master.client_department_id creates a cycle with
-- client_department.client_name_id. Keep only the child→parent direction.
ALTER TABLE public.client_master
    DROP CONSTRAINT IF EXISTS fk_client_master_client_department_id;

-- client_master → openings back-ref
ALTER TABLE public.client_master
    DROP CONSTRAINT IF EXISTS fk_client_master_openings_id;

-- vendor_master pointing at child tables (all reverse FKs)
ALTER TABLE public.vendor_master
    DROP CONSTRAINT IF EXISTS fk_vendor_master_candidates_profile_id;   -- misnamed, pointed at applications_id
ALTER TABLE public.vendor_master
    DROP CONSTRAINT IF EXISTS fk_vendor_master_openings_id;
ALTER TABLE public.vendor_master
    DROP CONSTRAINT IF EXISTS fk_vendor_master_profiles_database_id;
ALTER TABLE public.vendor_master
    DROP CONSTRAINT IF EXISTS fk_vendor_master_screenings_id;
ALTER TABLE public.vendor_master
    DROP CONSTRAINT IF EXISTS fk_vendor_master_selected_candidates_id;

-- applications_id ↔ selected_candidates circular reference
-- Keep selected_candidates → applications, drop the reverse.
ALTER TABLE public.applications_id
    DROP CONSTRAINT IF EXISTS fk_applications_id_selected_candidates_id;

-- applications_id → candidate_idprofile_database_id (duplicate of profiles_database_id)
ALTER TABLE public.applications_id
    DROP CONSTRAINT IF EXISTS fk_applications_id_candidate_idprofile_database_id;

-- applications_id → candidate_profile_id (duplicate FK, also to profiles_database)
ALTER TABLE public.applications_id
    DROP CONSTRAINT IF EXISTS applications_id_candidate_profile_id_fkey;

-- applications_id → opening_id (duplicate of openings_id FK)
ALTER TABLE public.applications_id
    DROP CONSTRAINT IF EXISTS applications_id_opening_id_fkey;

-- screeners_profile should NOT point at applications (it's the other way)
ALTER TABLE public.screeners_profile
    DROP CONSTRAINT IF EXISTS fk_screeners_profile_applications_id;
ALTER TABLE public.screeners_profile
    DROP CONSTRAINT IF EXISTS fk_screeners_profile_applications_id_3_id;

-- users.applications_id back-reference — users belong to a screener/admin,
-- not to an application directly
ALTER TABLE public.users
    DROP CONSTRAINT IF EXISTS fk_users_applications_id;

-- locations.openings_id — location is a lookup, relationship lives in the
-- openings_locations_openings junction table instead
ALTER TABLE public.locations
    DROP CONSTRAINT IF EXISTS fk_locations_openings_id;

-- locations → profiles_database back-refs
ALTER TABLE public.locations
    DROP CONSTRAINT IF EXISTS fk_locations_profiles_database_id;
ALTER TABLE public.locations
    DROP CONSTRAINT IF EXISTS locations_profiles_database_id_2_fkey;

-- profiles_database reverse FKs back to applications / screenings
ALTER TABLE public.profiles_database
    DROP CONSTRAINT IF EXISTS fk_profiles_database_applications_id;
ALTER TABLE public.profiles_database
    DROP CONSTRAINT IF EXISTS fk_profiles_database_applications_id_2_id;
ALTER TABLE public.profiles_database
    DROP CONSTRAINT IF EXISTS fk_profiles_database_screenings_id;
ALTER TABLE public.profiles_database
    DROP CONSTRAINT IF EXISTS fk_profiles_database_openings_id;

-- applications_id duplicate openings FKs (openings_3_id is a copy artifact)
ALTER TABLE public.applications_id
    DROP CONSTRAINT IF EXISTS fk_applications_id_openings_3_id;

-- applications_id ↔ screenings_2 circular back-ref
ALTER TABLE public.applications_id
    DROP CONSTRAINT IF EXISTS fk_applications_id_screenings_2_id;

-- client_department.openings_id back-ref (openings owns the FK, not dept)
ALTER TABLE public.client_department
    DROP CONSTRAINT IF EXISTS fk_client_department_openings_id;

-- ============================================================
-- STEP 2: CLEAN UP STALE / COPY COLUMNS
-- These columns are either Airtable formula copies, deprecated
-- duplicates, or back-reference caches that must go.
-- ============================================================

-- applications_id: Airtable copy / back-ref columns
ALTER TABLE public.applications_id
    DROP COLUMN IF EXISTS openings,            -- text copy of openings link
    DROP COLUMN IF EXISTS openings_2,          -- another text copy
    DROP COLUMN IF EXISTS screenings,          -- text copy
    DROP COLUMN IF EXISTS opening_id,          -- duplicate of openings_id
    DROP COLUMN IF EXISTS openings_3_id,       -- third duplicate FK
    DROP COLUMN IF EXISTS screenings_2_id,     -- back-ref to screenings
    DROP COLUMN IF EXISTS selected_candidates_id, -- circular back-ref
    DROP COLUMN IF EXISTS candidate_profile_id,   -- duplicate of candidate_idprofile_database_id
    DROP COLUMN IF EXISTS candidate_idprofile_database_id; -- replaced by profiles_database_id

-- profiles_database: back-ref / copy columns
ALTER TABLE public.profiles_database
    DROP COLUMN IF EXISTS applications_id,       -- back-ref to applications
    DROP COLUMN IF EXISTS applications_id_2_id,  -- second back-ref
    DROP COLUMN IF EXISTS screenings_id,         -- back-ref (use screenings.candidate_id)
    DROP COLUMN IF EXISTS openings_id,           -- back-ref (use applications → openings)
    DROP COLUMN IF EXISTS naukri_candidates,     -- text copy field
    DROP COLUMN IF EXISTS screenings_2;          -- text copy of deprecated table

-- vendor_master: copy & back-ref columns
-- NOTE: password column deliberately kept for now — will drop later
ALTER TABLE public.vendor_master
    DROP COLUMN IF EXISTS screened_candidates,    -- Airtable formula / copy
    DROP COLUMN IF EXISTS candidates_profile_id,  -- misnamed back-ref (was pointing to applications)
    DROP COLUMN IF EXISTS openings_id,            -- back-ref (use vendor_openings junction)
    DROP COLUMN IF EXISTS screenings_id,          -- back-ref (query screenings.vendor_id)
    DROP COLUMN IF EXISTS profiles_database_id,   -- back-ref
    DROP COLUMN IF EXISTS selected_candidates_id, -- back-ref
    -- DROP COLUMN IF EXISTS password,            -- 🔴 SECURITY — plain-text password (DEFERRED: will do later)
    DROP COLUMN IF EXISTS access_naukri_folder,   -- deprecated feature flag
    DROP COLUMN IF EXISTS naukri_folder;          -- deprecated

-- openings: back-ref columns
ALTER TABLE public.openings
    DROP COLUMN IF EXISTS applications_id,              -- back-ref
    DROP COLUMN IF EXISTS cv_sent_to_client_id,         -- back-ref
    DROP COLUMN IF EXISTS cv_sent_to_client_pipeline_id,-- back-ref
    DROP COLUMN IF EXISTS profiles_database_id;         -- back-ref

-- locations: back-ref columns
ALTER TABLE public.locations
    DROP COLUMN IF EXISTS openings_id,          -- back-ref (use junction table)
    DROP COLUMN IF EXISTS applications_id,      -- Airtable copy text
    DROP COLUMN IF EXISTS profiles_database_id, -- back-ref
    DROP COLUMN IF EXISTS profiles_database_id_2; -- duplicate back-ref

-- screeners_profile: back-ref columns
ALTER TABLE public.screeners_profile
    DROP COLUMN IF EXISTS applications_id,     -- back-ref (use screener_assignments junction)
    DROP COLUMN IF EXISTS applications_id_3_id;-- duplicate back-ref

-- users: back-ref column
ALTER TABLE public.users
    DROP COLUMN IF EXISTS applications_id;     -- back-ref

-- client_master: back-ref / wrong-type columns
ALTER TABLE public.client_master
    DROP COLUMN IF EXISTS client_department_id, -- circular (dept already has client_name_id → client_master)
    DROP COLUMN IF EXISTS openings_id,          -- back-ref
    DROP COLUMN IF EXISTS applications_id;      -- TEXT copy — wrong type

-- client_department: back-ref column
ALTER TABLE public.client_department
    DROP COLUMN IF EXISTS openings_id;          -- back-ref (openings owns this FK)

-- interview_feedback: wrong-type candidate text column
ALTER TABLE public.interview_feedback
    DROP COLUMN IF EXISTS candidate_id;         -- was TEXT — use application_id FK instead

-- ============================================================
-- STEP 3: DROP TEMP_ COLUMNS (migration scaffolding)
-- These were only needed to carry over Airtable IDs during
-- the initial data load. Remove them now.
-- ============================================================

ALTER TABLE public.applications_id
    DROP COLUMN IF EXISTS temp_vendor_id,
    DROP COLUMN IF EXISTS temp_openings_id,
    DROP COLUMN IF EXISTS temp_candidate_idprofile_database,
    DROP COLUMN IF EXISTS temp_screener,
    DROP COLUMN IF EXISTS temp_tech_screener,
    DROP COLUMN IF EXISTS temp_pid_taken_by;

ALTER TABLE public.profiles_database
    DROP COLUMN IF EXISTS temp_vendors_id,
    DROP COLUMN IF EXISTS temp_location_id,
    DROP COLUMN IF EXISTS temp_applications_id,
    DROP COLUMN IF EXISTS temp_screenings,
    DROP COLUMN IF EXISTS temp_openings,
    DROP COLUMN IF EXISTS temp_applications_id_2,
    DROP COLUMN IF EXISTS temp_screenings_2;

ALTER TABLE public.screenings
    DROP COLUMN IF EXISTS temp_candidate_id,
    DROP COLUMN IF EXISTS temp_vendor_id,
    DROP COLUMN IF EXISTS temp_application_id;

ALTER TABLE public.selected_candidates
    DROP COLUMN IF EXISTS temp_candidate_from_applications,
    DROP COLUMN IF EXISTS temp_whose_bench;

ALTER TABLE public.client_department
    DROP COLUMN IF EXISTS temp_client_name;

-- ============================================================
-- STEP 4: ADD MISSING COLUMNS (gaps found in audit)
-- ============================================================

-- client_master needs a proper location FK
ALTER TABLE public.client_master
    ADD COLUMN IF NOT EXISTS location_id uuid;

-- interview_feedback needs a proper application FK (was TEXT candidate_id)
ALTER TABLE public.interview_feedback
    ADD COLUMN IF NOT EXISTS application_id uuid;

-- screeners_profile needs a vendor FK (screeners belong to a vendor)
ALTER TABLE public.screeners_profile
    ADD COLUMN IF NOT EXISTS vendor_id uuid;

-- users needs a screener_profile FK (a user IS a screener/admin)
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS screener_profile_id uuid;

-- openings: missing prompt FK (each opening can have an active prompt)
ALTER TABLE public.openings
    ADD COLUMN IF NOT EXISTS prompt_id uuid;

-- profiles_database: vendor_id should be UUID not numeric
-- Rename the old numeric column and add the clean UUID version
ALTER TABLE public.profiles_database
    RENAME COLUMN vendor_id TO vendor_id_legacy;

ALTER TABLE public.profiles_database
    ADD COLUMN IF NOT EXISTS vendor_id uuid;

-- ============================================================
-- STEP 5: CREATE NEW JUNCTION + NORMALISATION TABLES
-- ============================================================

-- 5A: screener_assignments
-- Replaces the 3 duplicate application FKs on screeners_profile
-- and the duplicate screener_id / tech_screener_id on applications_id.
CREATE TABLE IF NOT EXISTS public.screener_assignments (
    screener_id    uuid NOT NULL REFERENCES public.screeners_profile(id) ON DELETE CASCADE,
    application_id uuid NOT NULL REFERENCES public.applications_id(id) ON DELETE CASCADE,
    role           varchar(50) NOT NULL CHECK (role IN ('screener','tech_screener','form_filler')),
    assigned_at    timestamptz DEFAULT now(),
    PRIMARY KEY (screener_id, application_id, role)
);

CREATE INDEX IF NOT EXISTS idx_screener_assignments_application
    ON public.screener_assignments(application_id);

CREATE INDEX IF NOT EXISTS idx_screener_assignments_screener
    ON public.screener_assignments(screener_id);

-- 5B: vendor_openings
-- Replaces Airtable's Openings linked field on Vendor Master
-- and merges openings_exclusive_vendors into a single table.
CREATE TABLE IF NOT EXISTS public.vendor_openings (
    vendor_id    uuid NOT NULL REFERENCES public.vendor_master(id) ON DELETE CASCADE,
    opening_id   uuid NOT NULL REFERENCES public.openings(id) ON DELETE CASCADE,
    is_exclusive boolean NOT NULL DEFAULT false,
    assigned_at  timestamptz DEFAULT now(),
    PRIMARY KEY (vendor_id, opening_id)
);

CREATE INDEX IF NOT EXISTS idx_vendor_openings_opening
    ON public.vendor_openings(opening_id);

-- 5C: interview_rounds
-- Normalises the flat L1/L2/L3 date columns on applications_id
-- into proper rows so you can add rounds without schema changes.
CREATE TABLE IF NOT EXISTS public.interview_rounds (
    id             uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    application_id uuid NOT NULL REFERENCES public.applications_id(id) ON DELETE CASCADE,
    round_type     varchar(20) NOT NULL CHECK (round_type IN ('pre_l1','l1','l2','l3')),
    scheduled_at   timestamptz,
    meeting_link   text,
    outcome        varchar(20) CHECK (outcome IN ('pass','fail','no_show','rescheduled','pending')),
    notes          text,
    created_at     timestamptz DEFAULT now(),
    updated_at     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_interview_rounds_application
    ON public.interview_rounds(application_id);

CREATE TRIGGER trg_interview_rounds_updated_at
    BEFORE UPDATE ON public.interview_rounds
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 5D: onboarding_events
-- Normalises the flat milestone date columns on selected_candidates.
CREATE TABLE IF NOT EXISTS public.onboarding_events (
    id          uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    selected_id uuid NOT NULL REFERENCES public.selected_candidates(id) ON DELETE CASCADE,
    event_type  varchar(50) NOT NULL CHECK (event_type IN (
        'vendor_onboarding','xpo_onboarding','client_onboarding',
        'end_client_onboarding','bgv','bgv_doc_submission','sow_signing','crc_confirmation'
    )),
    event_date  date,
    status      varchar(100),
    notes       text,
    created_at  timestamptz DEFAULT now(),
    updated_at  timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_onboarding_events_selected
    ON public.onboarding_events(selected_id);

CREATE TRIGGER trg_onboarding_events_updated_at
    BEFORE UPDATE ON public.onboarding_events
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 5E: status_config (single source of truth for all dropdown values)
CREATE TABLE IF NOT EXISTS public.status_config (
    id          uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    domain      varchar(50) NOT NULL,  -- 'application' | 'opening' | 'screening' | 'selected' | 'screener' | 'vendor'
    code        varchar(100) NOT NULL,
    label       text NOT NULL,
    color_hex   varchar(7),
    is_terminal boolean DEFAULT false,
    sort_order  smallint DEFAULT 0,
    created_at  timestamptz DEFAULT now(),
    updated_at  timestamptz DEFAULT now(),
    UNIQUE (domain, code)
);

-- 5F: prompts table (if not already present)
CREATE TABLE IF NOT EXISTS public.prompts (
    id                          uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    name                        text,
    status                      varchar(20) DEFAULT 'Inactive' CHECK (status IN ('Active','Inactive','test')),
    version                     integer DEFAULT 1,
    master_prompt               text,
    questionnaire_text          text,
    master_prompt_psr           text,
    question_extracting_prompt  text,
    master_prompt_naukri        text,
    created_at                  timestamptz DEFAULT now(),
    updated_at                  timestamptz DEFAULT now()
);

CREATE TRIGGER trg_prompts_updated_at
    BEFORE UPDATE ON public.prompts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 5G: rooms table (if not already present)
CREATE TABLE IF NOT EXISTS public.rooms (
    id                   uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    room_name            text,
    daily_start_time     time,
    daily_end_time       time,
    days_of_week         text[] DEFAULT '{}',
    slot_duration_minutes integer DEFAULT 30,
    is_active            boolean DEFAULT true,
    meeting_link         text,
    created_at           timestamptz DEFAULT now(),
    updated_at           timestamptz DEFAULT now()
);

CREATE TRIGGER trg_rooms_updated_at
    BEFORE UPDATE ON public.rooms
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Add room_id FK to screenings (replaces the text 'room' column)
ALTER TABLE public.screenings
    ADD COLUMN IF NOT EXISTS room_id uuid REFERENCES public.rooms(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_screenings_room_id
    ON public.screenings(room_id);

-- ============================================================
-- STEP 6: ADD PROPER FORWARD FKs (clean, one-direction only)
-- ============================================================

-- client_master → locations
ALTER TABLE public.client_master
    ADD CONSTRAINT fk_client_master_location_id
    FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL;

-- interview_feedback → applications_id
ALTER TABLE public.interview_feedback
    ADD CONSTRAINT fk_interview_feedback_application_id
    FOREIGN KEY (application_id) REFERENCES public.applications_id(id) ON DELETE CASCADE;

-- screeners_profile → vendor_master
ALTER TABLE public.screeners_profile
    ADD CONSTRAINT fk_screeners_profile_vendor_id
    FOREIGN KEY (vendor_id) REFERENCES public.vendor_master(id) ON DELETE SET NULL;

-- users → screeners_profile (a user maps to a screener record)
ALTER TABLE public.users
    ADD CONSTRAINT fk_users_screener_profile_id
    FOREIGN KEY (screener_profile_id) REFERENCES public.screeners_profile(id) ON DELETE SET NULL;

-- openings → prompts
ALTER TABLE public.openings
    ADD CONSTRAINT fk_openings_prompt_id
    FOREIGN KEY (prompt_id) REFERENCES public.prompts(id) ON DELETE SET NULL;

-- profiles_database → vendor_master (clean UUID FK)
ALTER TABLE public.profiles_database
    ADD CONSTRAINT fk_profiles_database_vendor_id
    FOREIGN KEY (vendor_id) REFERENCES public.vendor_master(id) ON DELETE SET NULL;

-- NOTE: candidate_skills already has candidate_skills_candidate_id_fkey
-- and candidate_skills_opening_id_fkey from the live schema, so we skip
-- adding them again to avoid duplicate constraint errors.

-- ============================================================
-- STEP 7: MIGRATE EXISTING DATA INTO NEW STRUCTURES
-- ============================================================

-- 7A: Migrate L1/L2/L3 flat dates → interview_rounds
INSERT INTO public.interview_rounds (application_id, round_type, scheduled_at, meeting_link)
SELECT id, 'pre_l1', pre_l1_date_and_time, NULL
FROM   public.applications_id
WHERE  pre_l1_date_and_time IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.interview_rounds (application_id, round_type, scheduled_at, meeting_link)
SELECT id, 'l1', client_l1_screening_date_and_time, client_l1_meeting_link
FROM   public.applications_id
WHERE  client_l1_screening_date_and_time IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.interview_rounds (application_id, round_type, scheduled_at, meeting_link)
SELECT id, 'l2', client_l2_screening_date_and_time, client_l2_meeting_link
FROM   public.applications_id
WHERE  client_l2_screening_date_and_time IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.interview_rounds (application_id, round_type, scheduled_at, meeting_link)
SELECT id, 'l3', client_l3_screening_date_and_time, client_l3_meeting_link
FROM   public.applications_id
WHERE  client_l3_screening_date_and_time IS NOT NULL
ON CONFLICT DO NOTHING;

-- 7B: Migrate screener / tech_screener → screener_assignments
INSERT INTO public.screener_assignments (screener_id, application_id, role)
SELECT screener_id, id, 'screener'
FROM   public.applications_id
WHERE  screener_id IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.screener_assignments (screener_id, application_id, role)
SELECT tech_screener_id, id, 'tech_screener'
FROM   public.applications_id
WHERE  tech_screener_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- 7C: Migrate openings_exclusive_vendors → vendor_openings
INSERT INTO public.vendor_openings (vendor_id, opening_id, is_exclusive)
SELECT vendor_master_id, openings_id, true
FROM   public.openings_exclusive_vendors
ON CONFLICT (vendor_id, opening_id) DO UPDATE SET is_exclusive = true;

-- 7D: Migrate onboarding milestone columns → onboarding_events
INSERT INTO public.onboarding_events (selected_id, event_type, event_date, status)
SELECT id, 'vendor_onboarding', vendor_onboarding_date, xpo_onboarding_status
FROM   public.selected_candidates
WHERE  vendor_onboarding_date IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.onboarding_events (selected_id, event_type, event_date, status)
SELECT id, 'end_client_onboarding', end_client_onboarding, end_client_onboarding_status
FROM   public.selected_candidates
WHERE  end_client_onboarding IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.onboarding_events (selected_id, event_type, event_date, status)
SELECT id, 'bgv', bgv_trigger_date, bgv_status
FROM   public.selected_candidates
WHERE  bgv_trigger_date IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.onboarding_events (selected_id, event_type, event_date, status)
SELECT id, 'bgv_doc_submission', bgv_doc_submission_date, NULL
FROM   public.selected_candidates
WHERE  bgv_doc_submission_date IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.onboarding_events (selected_id, event_type, event_date, status)
SELECT id, 'sow_signing', sow_signing_date, NULL
FROM   public.selected_candidates
WHERE  sow_signing_date IS NOT NULL
ON CONFLICT DO NOTHING;

-- 7E: Set profiles_database.vendor_id from the legacy numeric column
--     by matching vendor_master.vendor_id_number
UPDATE public.profiles_database pd
SET    vendor_id = vm.id
FROM   public.vendor_master vm
WHERE  vm.vendor_id_number = pd.vendor_id_legacy
  AND  pd.vendor_id IS NULL;

-- ============================================================
-- STEP 8: SEED status_config WITH ALL KNOWN STATUS VALUES
-- ============================================================

INSERT INTO public.status_config (domain, code, label, is_terminal) VALUES
-- Applications
('application', 'CANDIDATE_CREATED',            'Candidate Created',                       false),
('application', 'XPO_SCREENING_REJECT',         'Xpo Screening Reject',                    true),
('application', 'L1_FAIL',                      'L1 Fail',                                 true),
('application', 'ON_HOLD_PROFILE',              'On hold profile',                         false),
('application', 'CANDIDATE_BACKED',             'Candidate backed from the process',        true),
('application', 'CV_SENT_L1_PENDING',           'CV Sent to client. L1 schedule pending',  false),
('application', 'CLIENT_SCREENING_FAIL',        'Client Screening Fail',                   true),
('application', 'SELECTED',                     'Selected',                                true),
('application', 'L2_FAIL',                      'L2 Fail',                                 true),
('application', 'L1_UNSUCCESSFUL_NO_JOIN',      'L1 unsuccessful. Candidate didn''t join', true),
('application', 'CV_RECEIVED_TIMESLOTS',        'CV Received along with timeslots',        false),
('application', 'PRE_L1_FAIL',                  'Online test/pre L1 fail.',                true),
('application', 'L1_SCHEDULED',                 'L1 scheduled',                            false),
('application', 'L1_COMPLETED_FEEDBACK',        'L1 completed. Feedback awaited',          false),
('application', 'L1_PASS_L2_PENDING',           'L1 Pass. L2 to be scheduled',             false),
('application', 'L3_FAIL',                      'L3 Fail',                                 true),
('application', 'L2_COMPLETED',                 'L2 completed',                            false),
('application', 'POST_SCREENING_REVIEW_FAIL',   'Post Screening Review Fail',              true),
('application', 'L1_UNSUCCESSFUL_NO_PANEL',     'L1 unsuccessful. Panel didn''t join',     false),
('application', 'L2_UNSUCCESSFUL',              'L2 unsuccessful. Candidate or Panel did not join', false),
('application', 'PRE_L1_COMPLETED',             'Online test/pre L1 completed. Result awaited', false),
('application', 'CANDIDATE_CHEATING',           'Candidate Cheating',                      true),
('application', 'L2_SCHEDULED',                 'L2 scheduled',                            false),
('application', 'SELECTED_OTHER_POSITION',      'Selected for another position',           true),
('application', 'L1_RESCHEDULE',                'L1 reschedule',                           false),
('application', 'XPO_SCREENING_ON_HOLD',        'Xpo Screening onHold',                    false),
('application', 'L3_COMPLETED',                 'L3 completed',                            false),
('application', 'L2_PASS_L3_PENDING',           'L2 Pass. L3 to be scheduled',             false),
-- Openings
('opening', 'CLOSED',              'Closed',                       true),
('opening', 'OPEN',                'Open',                         false),
('opening', 'OPEN_NON_URGENT',     'Open - nonurgent',             false),
('opening', 'ON_HOLD',             'On Hold (too many profiles)',  false),
-- Screenings
('screening', 'SELECT',                   'select',                   false),
('screening', 'REJECT',                   'reject',                   true),
('screening', 'RESCHEDULED',              'Rescheduled',              false),
('screening', 'DID_NOT_APPEAR',           'Did Not Appear',           false),
('screening', 'CANCELLED_BY_VENDOR',      'Cancelled By Vendor',      false),
('screening', 'CANCELLED_BY_XPO',         'Cancelled By Xponentium',  false),
('screening', 'HOLD',                     'hold',                     false),
-- Selected Candidates
('selected', 'ONBOARDING_COMPLETED',  'Onboarding completed',   true),
('selected', 'ONBOARDING_IN_PROCESS', 'Onboarding in process',  false),
('selected', 'CANDIDATE_DROPPED',     'Candidate Dropped out',  true),
('selected', 'OFFBOARDED',            'Candidate offboarded',   true),
('selected', 'POSITION_CANCELLED',    'Position cancelled',     true),
-- Screeners
('screener', 'WORKING', 'Working', false),
('screener', 'LEFT',    'Left',    true),
-- Vendor
('vendor', 'TC_SHARED', 'T&C shared', false)
ON CONFLICT (domain, code) DO NOTHING;

-- ============================================================
-- STEP 9: DROP NOW-REDUNDANT COLUMNS AFTER DATA MIGRATION
-- Only run these after confirming data is in the new tables.
-- ============================================================

-- Remove flat interview date columns now captured in interview_rounds
ALTER TABLE public.applications_id
    DROP COLUMN IF EXISTS pre_l1_date_and_time,
    DROP COLUMN IF EXISTS client_l1_screening_date_and_time,
    DROP COLUMN IF EXISTS client_l2_screening_date_and_time,
    DROP COLUMN IF EXISTS client_l3_screening_date_and_time,
    DROP COLUMN IF EXISTS client_l1_meeting_link,
    DROP COLUMN IF EXISTS client_l2_meeting_link,
    DROP COLUMN IF EXISTS client_l3_meeting_link,
    DROP COLUMN IF EXISTS internal_meeting_link,
    DROP COLUMN IF EXISTS screener_id,           -- now in screener_assignments
    DROP COLUMN IF EXISTS tech_screener_id;      -- now in screener_assignments

-- Remove flat onboarding columns now in onboarding_events
ALTER TABLE public.selected_candidates
    DROP COLUMN IF EXISTS vendor_onboarding_date,
    DROP COLUMN IF EXISTS xpo_onboarding_status,
    DROP COLUMN IF EXISTS synechron_onboarding_date,
    DROP COLUMN IF EXISTS synechron_onboarding_status,
    DROP COLUMN IF EXISTS bgv_trigger_date,
    DROP COLUMN IF EXISTS bgv_status,
    DROP COLUMN IF EXISTS end_client_onboarding,
    DROP COLUMN IF EXISTS end_client_onboarding_status,
    DROP COLUMN IF EXISTS bgv_doc_submission_date,
    DROP COLUMN IF EXISTS sow_signing_date;

-- Drop the now-replaced old exclusive vendors table
-- (data is in vendor_openings with is_exclusive = true)
DROP TABLE IF EXISTS public.openings_exclusive_vendors;

-- Drop the legacy numeric vendor_id from profiles_database
ALTER TABLE public.profiles_database
    DROP COLUMN IF EXISTS vendor_id_legacy;

-- Drop the text 'room' column from screenings (replaced by room_id FK)
ALTER TABLE public.screenings
    DROP COLUMN IF EXISTS room;

-- ============================================================
-- STEP 10: MISSING INDEXES FOR NEW FOREIGN KEYS
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_interview_feedback_application_id
    ON public.interview_feedback(application_id);

CREATE INDEX IF NOT EXISTS idx_screeners_profile_vendor_id
    ON public.screeners_profile(vendor_id);

CREATE INDEX IF NOT EXISTS idx_users_screener_profile_id
    ON public.users(screener_profile_id);

CREATE INDEX IF NOT EXISTS idx_profiles_database_vendor_id
    ON public.profiles_database(vendor_id);

CREATE INDEX IF NOT EXISTS idx_openings_prompt_id
    ON public.openings(prompt_id);

CREATE INDEX IF NOT EXISTS idx_vendor_openings_vendor
    ON public.vendor_openings(vendor_id);

-- ============================================================
-- STEP 11: MISSING updated_at TRIGGERS FOR NEW TABLES
-- ============================================================

CREATE TRIGGER trg_status_config_updated_at
    BEFORE UPDATE ON public.status_config
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMIT;

-- ============================================================
-- POST-MIGRATION: VERIFICATION QUERIES (run manually)
-- ============================================================
--
-- 12A: Check no orphaned screenings
-- SELECT count(*) AS orphaned_screenings
-- FROM   public.screenings s
-- WHERE  s.candidate_id IS NOT NULL
--   AND  NOT EXISTS (SELECT 1 FROM public.profiles_database p WHERE p.id = s.candidate_id);
--
-- 12B: Check screener_assignments populated correctly
-- SELECT role, count(*) FROM public.screener_assignments GROUP BY role;
--
-- 12C: Check interview_rounds populated correctly
-- SELECT round_type, count(*) FROM public.interview_rounds GROUP BY round_type ORDER BY round_type;
--
-- 12D: Check onboarding_events populated correctly
-- SELECT event_type, count(*) FROM public.onboarding_events GROUP BY event_type;
--
-- 12E: Confirm no circular FKs remain
-- SELECT conname, conrelid::regclass, confrelid::regclass
-- FROM   pg_constraint
-- WHERE  contype = 'f'
-- ORDER  BY conrelid::regclass::text;
--
-- ============================================================
-- POST-MIGRATION: WHAT YOUR API SHOULD NOW USE
-- ============================================================
--
--  GET /applications/:id/rounds          → interview_rounds
--  GET /applications/:id/screeners       → screener_assignments JOIN screeners_profile
--  GET /candidates/:id                   → profiles_database + vendor_id FK
--  GET /openings/:id/vendors             → vendor_openings
--  GET /selected/:id/onboarding          → onboarding_events
--  GET /status-config?domain=application → status_config
--  GET /openings/:id/locations           → openings_locations_openings
--
-- ============================================================
