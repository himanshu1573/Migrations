# XPO ATS Minimal Schema Analysis

Analyzed on: 2026-03-13

## Scope

This analysis is based on:

- Local XPO ATS application code in `/Users/himanshup/Expo/XPO-ATS`
- Local migration and schema artifacts in `/Users/himanshup/Expo/migrations`
- Official Airtable docs
- Official Supabase docs

Primary local evidence used:

- `XPO-ATS/lib/airtable.ts`: current Airtable read/write behavior for openings, candidates, applications, screenings, rooms, screeners, and users
- `XPO-ATS/lib/supabase.ts`: current Supabase read/write behavior for Naukri, skills, logs, and ranking
- `XPO-ATS/app/api/screeningList/route.ts`: strongest example of Airtable lookup-shaped API composition
- `XPO-ATS/app/api/book-slot/route.ts`: strongest example of scheduling business rules currently enforced in code
- `XPO-ATS/app/api/submit-recruitment/route.ts`: candidate dedup and candidate/application creation flow
- `XPO-ATS/app/api/submit-c2c/route.ts`: C2C candidate and application creation flow
- `migrations/live_supabase_schema_2026-03-12.sql`: current live PG schema snapshot
- `migrations/airtable-sync-service/sync.js`: actual Airtable-to-PG mapping logic
- `migrations/XPO_ATS_DATABASE_SCHEMA.md`: normalized target schema reference used by the project
- `XPO-ATS/scripts/airtable_audit_report.json`: useful counts and field-pattern evidence from Airtable

Key external references:

- Airtable Web API overview: [https://support.airtable.com/docs/public-rest-api](https://support.airtable.com/docs/public-rest-api)
- Airtable API limits: [https://support.airtable.com/docs/managing-api-call-limits-in-airtable](https://support.airtable.com/docs/managing-api-call-limits-in-airtable)
- Airtable linked records: [https://support.airtable.com/docs/linking-records-in-airtable](https://support.airtable.com/docs/linking-records-in-airtable)
- Airtable lookup fields: [https://support.airtable.com/docs/lookup-field-overview](https://support.airtable.com/docs/lookup-field-overview)
- Airtable rollup fields: [https://support.airtable.com/docs/rollup-field-overview](https://support.airtable.com/docs/rollup-field-overview)
- Supabase joins and nesting: [https://supabase.com/docs/guides/database/joins-and-nesting](https://supabase.com/docs/guides/database/joins-and-nesting)
- Supabase Data API hardening: [https://supabase.com/docs/guides/database/hardening-data-api](https://supabase.com/docs/guides/database/hardening-data-api)
- Supabase password security: [https://supabase.com/docs/guides/auth/password-security](https://supabase.com/docs/guides/auth/password-security)

## Executive Result

The repo is currently in a mixed state:

- Airtable is still the operational source of truth for the core ATS workflow.
- Supabase/Postgres is already the source of truth for newer modules like skills, Naukri, ranking, logging, and campaign automation.
- The migration direction is correct, but the current PG model still carries legacy inconsistencies, and the app still depends on Airtable lookup/rollup/copy fields in several hot paths.

The concrete recommendation is:

1. Keep the ATS core on a normalized Postgres schema with UUID foreign keys.
2. Treat Airtable only as a migration bridge and temporary sync input, not as the long-term relational model.
3. Keep only the junction tables that represent real many-to-many relationships.
4. Remove copied fields, reverse links, and mixed key strategies.
5. Split "core ATS" tables from "sidecar product" tables like Naukri, ranking, prompts, logs, and campaign automation.

## What The App Actually Uses Today

### Airtable-backed core ATS flows

The following business-critical routes still read or write Airtable directly:

- `submit-recruitment`, `submit-c2c`
- `screeningList`
- `book-slot`
- `dashboard`
- `screening-opening`
- `generateScreenerAudit`
- `generate_post_Screeningaudit_report`
- `admin/screeners`
- vendor opening visibility logic in `lib/airtable.ts`

The main Airtable tables used by the app are:

- `Openings`
- `Profiles Database`
- `Applications_ID`
- `Screenings`
- `Vendor Master`
- `Screeners Profile`
- `Users`
- `Rooms`

### Supabase-backed modules already in production

The following areas are already PG/Supabase-based:

- `skill_master`
- `skill_level_master`
- `skill_map`
- `candidate_skill_map`
- `skill_sets`
- `naukri_folders`
- `naukri_candidates`
- `ranking_jobs`
- `campaign_subscription`
- `campaign_trigger`
- `openai_call_logs`
- `app_tokens`

### Important mixed-mode reality

The most important hybrid areas are:

- `screeningList`: Airtable for screenings/applications/openings/profiles, Supabase for skill evaluation data.
- `book-slot`: Airtable for screening creation and candidate/application validation, Supabase for skill-violation justification updates.
- `naukri/create-draft`: Supabase folder lookup, then Airtable draft candidate creation.

This means the schema design must prioritize the core ATS entities first, then fold in sidecar modules.

## Airtable And API Constraints That Matter For Schema Design

From the current official Airtable docs:

- Airtable linked records are the actual relationship primitive.
- Lookup fields and rollup fields are derived from linked records, not canonical source data.
- Lookup values behave like arrays and can change shape based on linked records.
- Airtable Web API omits empty fields in responses.
- Airtable Web API rate limiting is strict enough that lookup-heavy wide reads do not scale well as a core transactional API shape.

Design implication:

- Do not model the Postgres schema around Airtable lookup columns like `Candidate Name (from Candidate Unique ID)` or `Locations_Openings_Rollup (from Openings) (from Candidate ID)`.
- Model only the base facts and recreate projections through SQL joins, views, or API composition.

From the current official Supabase docs:

- The data API automatically detects foreign-key relationships.
- Nested joins work best when the schema uses real foreign keys and real join tables.
- Public-schema API exposure must be protected with RLS.
- Auth should not rely on plaintext passwords stored in application tables.

Design implication:

- A normalized Postgres schema is not only acceptable, it is the shape that Supabase APIs work best with.
- If you normalize correctly, the API layer becomes simpler, not harder.

## Current Problems In The Existing Model

### 1. Core ATS is still Airtable-shaped in the app layer

The app still reads many copied and lookup fields such as:

- `Name (from Screener) (from Applications_ID) (from Candidate ID)`
- `Locations_Openings_Rollup (from Openings) (from Candidate ID)`
- `Screening Report (from Candidate Unique ID)`
- `Interview slots (from Openings) (from Candidate ID)`

These are presentation fields, not source-of-truth fields.

### 2. Skills are split across three inconsistent designs

Current skill-related tables are inconsistent:

- `skill_map` uses legacy numeric `opening_id`
- `candidate_skill_map` uses text `candidate_id`
- `candidate_skills` uses UUID foreign keys

This is the clearest place where the schema is currently not normalized enough.

### 3. Naukri tables use text IDs instead of real FKs

Current `naukri_folders` stores:

- `opening_id TEXT`
- `vendor_id TEXT`

In practice these are not canonical Postgres foreign keys. They are bridge values.

### 4. Important business rules exist only in application code

The app enforces rules in code that should exist in the database:

- one application per `(candidate, opening, vendor)`
- one room booking per slot
- duplicate-candidate detection by contact data

The live schema does not currently enforce the most important of these.

### 5. Security is still legacy-style

Current tables still contain plaintext passwords:

- `vendor_master.password`
- `users.password`

This should not exist in the target design.

### 6. Some PG columns exist but are not truly part of the working system

Examples:

- `screenings.room_id` exists, but scheduling still depends on Airtable `Rooms` and Airtable room lookups.
- `screeners_profile.vendor_id` exists but is not meaningfully used by the app.
- `users.screener_profile_id` exists but the create/update flows still operate against Airtable.

### 7. Room vendor exclusivity is missing from PG

The Airtable `Rooms` model includes `Exclusive Vendors`, and booking logic depends on it.
The current PG `rooms` table has no equivalent junction table.

This is a schema gap, not just a migration gap.

## Minimal Canonical ATS Schema

This is the recommended long-term core schema.

Only tables that represent real business entities or real many-to-many relationships are included.

### A. Master tables

#### `vendors`

Canonical vendor/partner master.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `vendor_code INTEGER UNIQUE NULL`
- `name TEXT NOT NULL`
- `type TEXT`
- `status TEXT`
- `linkedin_url TEXT`
- `revenue_model TEXT`
- `vendor_status TEXT`
- `primary_poc_name TEXT`
- `primary_poc_email TEXT`
- `primary_poc_phone TEXT`
- `additional_poc_emails TEXT[]`
- `created_at`
- `updated_at`

Notes:

- Do not store passwords here.
- `vendor_code` is the current `vendor_id_number`.

#### `clients master`

Canonical client/company master.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `name TEXT NOT NULL`
- `industry TEXT`
- `requirements`
- `created_at`
- `updated_at`

#### `client_departments`

Department within a client.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `client_id UUID NOT NULL FK -> clients.id`
- `Department_name TEXT NOT NULL`
- `primary_poc_name TEXT`
- `primary_poc_email TEXT`
- `primary_poc_phone TEXT`
- `primary_poc_role TEXT`
- `secondary_poc_name TEXT`
- `secondary_poc_email TEXT`
- `secondary_poc_phone TEXT`
- `secondary_poc_role TEXT`
- `document_type uuid not null fk `
- `created_at`
- `updated_at`

Constraint:

- `UNIQUE (client_id, name)`

#### `locations`

Reusable location lookup.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `name TEXT NOT NULL`
- `created_at`
- `updated_at`

Constraint:

- unique normalized location name

### B. Opening tables

#### `openings`

Canonical requisition record.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `opening_code INTEGER UNIQUE NOT NULL`
- `client_id UUID NOT NULL FK -> clients.id`
- `client_department_id UUID NULL FK -> client_departments.id`
- `job_title TEXT NOT NULL`
- `status TEXT NOT NULL`
- `experience_level TEXT`
- `number_of_open_positions NUMERIC`
- `job_description TEXT`
- `jd_for_prompt TEXT`
- `client_billing NUMERIC`
- `duration_months NUMERIC`
- `date_opened DATE`
- `onboarding_process_notes TEXT confusion--X`
- `comments TEXT`
<!-- - `bline_id TEXT` -->
- `max_ctc_lpa NUMERIC`
- `max_vendor_budget NUMERIC`
- `candidate_type TEXT`
- `job_group TEXT[]`
<!-- - `job_visibility TEXT` -->
- `job_bench_type TEXT`
- `maximum_joining_period_days NUMERIC`
- `maximum_notice_period_allowed NUMERIC`
<!-- - `partner_recruitment_fee_pct NUMERIC` -->
- `interview_slots TEXT`
- `questionnaire TEXT`
<!-- - `coding_q1 TEXT`
- `coding_q2 TEXT`
- `skill_coding_q1 TEXT`
- `skill_coding_q2 TEXT` -->
- `advisory TEXT`
- `MASTER PID_document`
- `raw_jd_from_client JSONB`
- `created_at`
- `updated_at`

Do not keep:

- copied vendor lists
- copied location rollups
- copied profile/application back-references

#### `opening_locations`

Real many-to-many relation between openings and locations.

Columns:

- `opening_id UUID FK -> openings.id`
- `location_id UUID FK -> locations.id`

Constraint:

- `PRIMARY KEY (opening_id, location_id)`

#### `opening_vendors`

Real many-to-many relation between openings and vendors.

Columns:

- `opening_id UUID FK -> openings.id`
- `vendor_id UUID FK -> vendors.id`
- `is_exclusive BOOLEAN NOT NULL DEFAULT FALSE`
- `assigned_at TIMESTAMPTZ`

Constraint:

- `PRIMARY KEY (opening_id, vendor_id)`

This is the correct place for:

- vendor visibility
- exclusivity flags

# C. Candidate and application tables

#### `candidates`

Canonical candidate profile. One candidate should live here once.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `candidate_code TEXT UNIQUE NOT NULL`
- `name TEXT NOT NULL`
- `email TEXT`
- `phone TEXT`
- `current_company TEXT`
- `current_location TEXT`
- `preferred_location_text TEXT`
- `location_id UUID NULL FK -> locations.id`
- `primary_skill TEXT`
- `candidate_type TEXT`
- `bench_type TEXT`
- `notice_period TEXT`
- `last_working_day DATE`
- `is_resigned BOOLEAN`
- `ctc_lpa NUMERIC`
- `ectc_lpa NUMERIC`
- `candidate_cost NUMERIC`
- `govt_id TEXT`
- `type_of_id TEXT`
- `communication_rating NUMERIC`
- `confidence_rating NUMERIC`
- `tech_self_rating NUMERIC`
- `career_gap TEXT`
- `recruitment_notes TEXT`
- `cv_link TEXT`
- `edited_cv TEXT`
- `screening_report TEXT`
- `edited_psr TEXT`
- `candidate_document TEXT`
- `lyncogs TEXT`
- `lyncogs_summary TEXT`
- `project_summary TEXT`
- `employment_history TEXT`
- `gap_analysis TEXT`
- `jumping_frequency NUMERIC`
- `extracted_skills TEXT`
- `vendor_owner_id UUID NULL FK -> vendors.id`
- `is_draft BOOLEAN`
- `created_at`
- `updated_at`

Recommended constraints:

- `UNIQUE (candidate_code)`
- partial unique index on normalized phone when present

Reason:

- current app already treats mobile number as a cross-vendor duplicate guard

#### `applications`

This is the real center of the ATS.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `candidate_id UUID NOT NULL FK -> candidates.id`
- `opening_id UUID NOT NULL FK -> openings.id`
- `vendor_id UUID NOT NULL FK -> vendors.id`
- `pid_taken_by_user_id UUID NULL FK -> internal_users.id`
- `status TEXT NOT NULL`
- `status_remarks TEXT`
- `next_task TEXT`
- `experience_level_candidate TEXT`
- `screening_clear_date DATE`
- `follow_up_date DATE`
- `followup_email_status TEXT`
- `clients_feedback_status TEXT`
- `clients_interview_feedback TEXT`
- `send_mail BOOLEAN`
- `send_to_client TEXT`
- `cv_sent_to_client_date TIMESTAMPTZ`
- `cv_sent_to_client_date_last_updated TIMESTAMPTZ`
- `screening_report_link TEXT`
- `screening_fathom_links TEXT`
- `post_screening_report TEXT`
- `pre_l1_transcript TEXT`
- `transcript TEXT`
- `link_post_interview_questionnaire TEXT`
- `status_post_interview_questionnaire TEXT`
- `other_offers TEXT`
- `vs_remarks TEXT`
- `opening_vendor_summary TEXT`
- `panel_type TEXT`
- `tech_screening TEXT`
- `backup_candidate TEXT`
- `backup_option_1 TEXT`
- `vendor_of_option_1 TEXT`
- `backup_option_2 TEXT`
- `vendor_of_option_2 TEXT`
- `morning_followup_status TEXT`
- `interview_coordination TEXT`
- `candidate_followup TEXT`
- `scheduling_coordination_started TEXT`
- `form_filled_by TEXT`
- `name_as_per_aadhar TEXT`
- `id_type_submitted TEXT`
- `revised_ctc_lpa NUMERIC`
- `offboarding TEXT`
- `offboarding_status TEXT`
- `created_at`
- `updated_at`

Critical constraint:

- `UNIQUE (candidate_id, opening_id, vendor_id)`

That constraint is required because the current app already enforces exactly this in code.

#### `application_screeners`

Real many-to-many relation between applications and screeners.

Columns:

- `application_id UUID FK -> applications.id`
- `screener_id UUID FK -> screeners.id`
- `role TEXT CHECK IN ('screener', 'tech_screener', 'form_filler')`
- `assigned_at TIMESTAMPTZ`

Constraint:

- `PRIMARY KEY (application_id, screener_id, role)`

### D. Scheduling tables

#### `rooms`

Canonical room/schedule definition.

Core columns:

- `id UUID PK`
- `name TEXT UNIQUE NOT NULL`
- `daily_start_time TIME`
- `daily_end_time TIME`
- `days_of_week TEXT[]`
- `slot_duration_minutes INTEGER`
- `meeting_link TEXT`
- `is_active BOOLEAN`
- `created_at`
- `updated_at`

#### `room_vendors`

Needed because Airtable `Rooms` currently supports `Exclusive Vendors`.

Columns:

- `room_id UUID FK -> rooms.id`
- `vendor_id UUID FK -> vendors.id`

Constraint:

- `PRIMARY KEY (room_id, vendor_id)`

Rule:

- no rows = room open to all vendors
- one or more rows = room restricted to those vendors

#### `screenings`

Scheduled screening events.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `application_id UUID NOT NULL FK -> applications.id`
- `candidate_id UUID NOT NULL FK -> candidates.id`
- `vendor_id UUID NOT NULL FK -> vendors.id`
- `room_id UUID NULL FK -> rooms.id`
- `scheduled_at TIMESTAMPTZ NOT NULL`
- `status TEXT`
- `meeting_link TEXT`
- `admin_interview_link TEXT`
- `ai_interview_link TEXT`
- `organizer_email TEXT`
- `created_email TEXT`
- `event_id TEXT`
- `slot_key TEXT`
- `comments TEXT`
- `screener_evaluation_report TEXT`
- `screener_audit_report TEXT`
- `answer_of_coding_q1 TEXT`
- `answer_of_coding_q2 TEXT`
- `interview_breadth_rating NUMERIC`
- `interview_depth_rating NUMERIC`
- `sop_flow_adherence_rating NUMERIC`
- `communication_quality_rating NUMERIC`
- `overall_screening_effectiveness_rating NUMERIC`
- `created_at`
- `updated_at`

Recommended constraints:

- `UNIQUE (slot_key)`
- partial unique on `event_id` when not null

Do not keep as canonical columns:

- candidate name copy
- vendor name copy
- room name copy
- skill copy
- CV link copy

Those can come from joins to `applications`, `candidates`, `openings`, and `rooms`.

### E. Post-selection tables

#### `selected_candidates`

Keep separate because onboarding is a real post-selection workflow.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `application_id UUID NOT NULL FK -> applications.id`
- `bench_vendor_id UUID NULL FK -> vendors.id`
- `selection_date DATE`
- `status TEXT`
- `overall_status TEXT`
- `assignee TEXT`
- `attachments JSONB`
- `pf_status TEXT`
- `pf_doc_remarks TEXT`
- `university_docs_check TEXT`
- `university_docs_remarks TEXT`
- `finalized_ctc NUMERIC`
- `is_fte BOOLEAN`
- `invoice_raised TEXT`
- `crc_confirmation_date DATE`
- `offboarding TEXT`
- `offboarding_status TEXT`
- `created_at`
- `updated_at`

Recommended constraint:

- `UNIQUE (application_id)`

#### `onboarding_events`

Normalized onboarding milestones.

Columns:

- `id UUID PK`
- `selected_candidate_id UUID FK -> selected_candidates.id`
- `event_type TEXT`
- `event_date DATE`
- `status TEXT`
- `notes TEXT`
- `created_at`
- `updated_at`

Constraint:

- `UNIQUE (selected_candidate_id, event_type)`

### F. People and auth tables

#### `screeners`

Internal screener directory.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `name TEXT NOT NULL`
- `phone TEXT`
- `status TEXT`
- `created_at`
- `updated_at`

Recommendation:

- do not keep `vendor_id` here unless screeners are truly vendor-owned in the business model

#### `internal_users`

Application user profile only, not password store.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `auth_user_id UUID UNIQUE`
- `username TEXT UNIQUE`
- `role TEXT`
- `screener_id UUID NULL FK -> screeners.id`
- `pid_authorization TEXT`
- `created_at`
- `updated_at`

Recommendation:

- auth secrets belong in Supabase Auth, not here

### G. Skills tables

This is where the current schema should be simplified most aggressively.

#### `skills`

- `id BIGINT PK`
- `name TEXT UNIQUE NOT NULL`

#### `skill_levels`

- `id BIGINT PK`
- `name TEXT UNIQUE NOT NULL`

#### `opening_skill_requirements`

This replaces the current long-term role of `skill_map`.

Columns:

- `opening_id UUID FK -> openings.id`
- `skill_id BIGINT FK -> skills.id`
- `required_level_id BIGINT FK -> skill_levels.id`

Constraint:

- `PRIMARY KEY (opening_id, skill_id)`

#### `candidate_skill_assessments`

This replaces the split between `candidate_skill_map` and `candidate_skills`.

Columns:

- `id UUID PK`
- `candidate_id UUID FK -> candidates.id`
- `application_id UUID NULL FK -> applications.id`
- `opening_id UUID NULL FK -> openings.id`
- `skill_id BIGINT FK -> skills.id`
- `required_level_id BIGINT NULL FK -> skill_levels.id`
- `self_rating NUMERIC`
- `pre_screening_ai_rating NUMERIC`
- `conceptual_rating NUMERIC`
- `practical_rating NUMERIC`
- `coding_rating NUMERIC`
- `overall_rating NUMERIC`
- `projects_count INTEGER`
- `projects_done JSONB`
- `summary JSONB`
- `pre_screening_ai_summary JSONB`
- `skill_rating_assessment JSONB`
- `skills_violation_justification TEXT`
- `assessed BOOLEAN`
- `assessment_stage TEXT`
- `created_at`
- `updated_at`

Constraint:

- `UNIQUE (candidate_id, application_id, skill_id, assessment_stage)`

This change fixes the current inconsistency where:

- opening skills are keyed by numeric opening code
- candidate skills are keyed by Airtable record id text
- other candidate skills are keyed by UUID

The target design should use UUID foreign keys everywhere.

## What Should Be Kept Out Of The Core ATS Schema

These are valid product tables, but they should not shape the ATS core:

- `naukri_folders`
- `naukri_candidates`
- `ranking_jobs`
- `openai_call_logs`
- `campaign_subscription`
- `campaign_trigger`
- `app_tokens`
- prompt storage
- raw automation payload tables

Recommendation:

- keep them in a sidecar area of the schema
- do not let their bridge IDs define the ATS primary model

## Concrete "One Fact In One Place" Mapping

Use this as the rulebook.

| Fact | Canonical table |
| --- | --- |
| Vendor identity | `vendors` |
| Client identity | `clients` |
| Department PoCs | `client_departments` |
| Location vocabulary | `locations` |
| Opening/job requirements | `openings` |
| Opening to location relation | `opening_locations` |
| Opening to vendor visibility/exclusivity | `opening_vendors` |
| Candidate profile | `candidates` |
| Candidate ownership/vendor source | `candidates.vendor_owner_id` |
| Candidate submitted to opening by vendor | `applications` |
| Screeners assigned to an application | `application_screeners` |
| Room availability definition | `rooms` |
| Room exclusivity by vendor | `room_vendors` |
| Scheduled screening event | `screenings` |
| Selected/onboarding candidate record | `selected_candidates` |
| Onboarding milestone | `onboarding_events` |
| Skill vocabulary | `skills` |
| Required skills for opening | `opening_skill_requirements` |
| Candidate skill assessment | `candidate_skill_assessments` |
| Workflow status dictionary | `status_config` |

Do not duplicate these facts into:

- lookup fields
- rollup fields
- `from ...` columns
- "copy" columns
- reverse-link columns

## Tables And Columns That Should Be Removed Or Avoided

Avoid in the target schema:

- plaintext passwords on any business table
- `candidate_skill_map.candidate_id TEXT`
- `skill_map.opening_id INTEGER` as the long-term relation key
- `screenings.candidate_name`, `screenings.skill`, `screenings.cv_link` as canonical fields
- `screeners_profile.vendor_id` unless the business truly requires it
- any `temp_*` columns after migration
- any `...copy`, `...rollup`, `...from_...`, or reverse-reference columns

Already correct to remove or keep out:

- `prompts`
- `interview_feedback`
- `interview_rounds`

## Immediate Gaps To Fix Before Declaring PG As System Of Record

### 1. Add database uniqueness that the app already assumes

Must add:

- `applications UNIQUE (candidate_id, opening_id, vendor_id)`
- `screenings UNIQUE (slot_key)`
- `selected_candidates UNIQUE (application_id)`

Should add:

- `candidates UNIQUE (candidate_code)`
- partial unique on normalized phone
- partial unique on `screenings.event_id`

### 2. Fix room exclusivity in PG

Add:

- `room_vendors`

Without this, booking logic cannot migrate cleanly off Airtable.

### 3. Unify skill keys

Move all skill relations to:

- `candidate_id UUID`
- `opening_id UUID`
- `application_id UUID`

Stop using:

- numeric opening ids as join keys for skill requirements
- Airtable record ids as join keys for skill assessments

### 4. Move auth out of business tables

Replace:

- `vendor_master.password`
- `users.password`

With:

- Supabase Auth users
- role/profile metadata in separate tables

### 5. Stop building API responses from Airtable lookup fields

Instead:

- query base entities
- join through FKs and junctions
- expose dedicated read views if necessary

## Recommended Migration Order

### Phase 1: Lock the target shape

1. Freeze the core table names and FK directions.
2. Add missing uniqueness constraints.
3. Add `room_vendors`.
4. Introduce unified UUID-based skill relations.

### Phase 2: Backfill and validate

1. Backfill `applications.candidate_id`, `opening_id`, `vendor_id`.
2. Backfill `screenings.room_id`.
3. Backfill `opening_locations` and `opening_vendors`.
4. Backfill unified skill assessment tables.
5. Validate counts and random linked-record samples.

### Phase 3: Switch read APIs

Switch these routes first:

- `screeningList`
- `dashboard`
- `screening-opening`
- `application-violations`
- skills APIs

These are the routes most harmed by Airtable lookup-shape coupling.

### Phase 4: Switch write APIs

Switch:

- candidate submission
- application creation
- booking
- screener assignment
- onboarding updates

### Phase 5: Retire Airtable-shaped compatibility fields

Only after the APIs no longer consume them.

## Final Recommendation

If the goal is "only needed tables, no duplicated facts, proper junctions, and one source of truth", then the right answer is:

- Keep a normalized Postgres ATS core of about 15 to 18 tables.
- Use junction tables only where the business is truly many-to-many:
  - opening to vendors
  - opening to locations
  - application to screeners
  - room to vendors
  - opening to required skills
- Collapse the current multi-model skill system into one UUID-based model.
- Keep Naukri, ranking, automation, and logs outside the core ATS design.
- Stop carrying Airtable lookup/rollup/copy fields into the relational schema.

That gives you a schema that is smaller than the current mixed model, more correct than Airtable, and directly compatible with Supabase nested relational APIs.
