# XPO ATS Minimal Schema Analysis

### Airtable-backed core ATS flows

//generate screening report from dashboard .
<!-- // edited_psr and tech self rating can be removed -->

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


### 1. Some PG columns exist but are not truly part of the working system

Examples:

- `screenings.room_id` exists, but scheduling still depends on Airtable `Rooms` and Airtable room lookups.
- `screeners_profile.vendor_id` exists but is not meaningfully used by the app.
- `users.screener_profile_id` exists but the create/update flows still operate against Airtable.

### 2. Room vendor exclusivity is missing from PG

The Airtable `Rooms` model includes `Exclusive Vendors`, and booking logic depends on it.
The current PG `rooms` table has no equivalent junction table.

This is a schema gap, not just a migration gap.


### A. Master tables

#### `vendor_master ✅`

Canonical vendor/partner master.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `vendor_code INTEGER UNIQUE NULL`
- `name TEXT NOT NULL`
- `type TEXT`
- `status TEXT`
- `revenue_model TEXT`
- `vendor_status TEXT`
- `primary_poc_name TEXT`
- `primary_poc_email TEXT`
- `primary_poc_phone TEXT`
- `additional_poc_emails TEXT[]`
- `access_naukri_folders`
- `created_at`
- `updated_at`

Notes:

- Do not store passwords here.
- `vendor_code` is the current `vendor_id_number`.

#### `client_master ✅`

Canonical client/company master.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `name TEXT NOT NULL`
- `industry TEXT`
- `requirements`
- `SPOC`
- `created_at`
- `updated_at`

#### `client_department ✅`

Department within a client.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `client_id UUID NOT NULL FK -> client_master.id`
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

- `UNIQUE (client_name_id, name)`

#### `locations ✅`

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

#### `openings ✅`

Canonical requisition record.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `opening_code INTEGER UNIQUE NOT NULL`
- `client_id UUID NOT NULL FK -> client_master.id`
- `client_department_id UUID NULL FK -> client_department.id`
- `job_title TEXT NOT NULL`
- `status TEXT NOT NULL`
- `experience_level TEXT`
- `number_of_open_positions NUMERIC`
- `job_description TEXT`
- `jd_for_prompt TEXT`
- `client_billing NUMERIC`
- `duration_months NUMERIC`
- `date_opened DATE`
- `onboarding_process_notes TEXT`
- `comments TEXT`
<!-- - `bline_id TEXT` -->
- `max_ctc_lpa NUMERIC`
- `max_vendor_budget NUMERIC`
- `candidate_type TEXT`
- `job_group TEXT[]`
- `job_visibility TEXT`
- `job_bench_type enum`
- `maximum_joining_period_days NUMERIC`
- `maximum_notice_period_allowed NUMERIC`
- `partner_recruitment_fee_pct NUMERIC`
- `interview_slots TEXT`
- `questionnaire TEXT`
- `coding_q1 TEXT`
- `coding_q2 TEXT`
- `skill_coding_q1 TEXT`
- `skill_coding_q2 TEXT`
- `advisory TEXT`
- `MASTER PID_document`
- `is_exclusive BOOLEAN NOT NULL DEFAULT FALSE`
- `raw_jd_from_client JSONB`
- `created_at`
- `updated_at`

Do not keep:

- copied vendor lists
- copied location rollups
- copied profile/application back-references

#### `openings_locations_openings`

Real many-to-many relation between openings and locations.

Columns:

- `opening_id UUID FK -> openings.id`
- `location_id UUID FK -> locations.id`

Constraint:

- `PRIMARY KEY (opening_id, location_id)`

#### `vendor_openings`

Real many-to-many relation between openings and vendors.

Columns:

- `opening_id UUID FK -> openings.id`
- `vendor_id UUID FK -> vendor_master.id`
<!-- - `is_exclusive BOOLEAN NOT NULL DEFAULT FALSE` this will be in opening level
- `assigned_at TIMESTAMPTZ` -->

Constraint:

- `PRIMARY KEY (opening_id, vendor_id)`

This is the correct place for:

- vendor visibility
- exclusivity flags

# C. Candidate and application tables

#### `profiles_database`

Canonical candidate profile. One candidate should live here once.

**SECTION 1: Columns That STAY in `profiles_database` (Profile-Level Facts)**

Profile-specific information that belongs to the candidate identity, not changing per application or screening.

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `candidate_code TEXT UNIQUE NOT NULL`
- `name TEXT NOT NULL`
- `email TEXT`
- `phone TEXT`
- `current_company TEXT`
- `location_id UUID NULL FK -> locations.id` (candidate's home location)
- `notice_period TEXT` (career-wide notice period)
- `last_working_day DATE` (career-wide last day)
- `is_resigned BOOLEAN` (career status)
- `ctc_lpa NUMERIC` (current CTC - career fact)
- `ectc_lpa NUMERIC` (expected CTC - career expectations)
- `cv_link TEXT` (primary CV version)
- `edited_cv TEXT` (candidate's edited CV)
- `employment_history TEXT` (career progression)
- `gap_analysis TEXT` (general career gaps, not screening-specific)
- `jumping_frequency NUMERIC` (career pattern/volatility)
- `vendor_owner_id UUID NULL FK -> vendor_master.id` (who sourced this candidate)
- `is_draft BOOLEAN` (profile draft status)
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`


- `communication_rating NUMERIC` 
- `confidence_rating NUMERIC`
- `tech_self_rating NUMERIC` 
- `career_gap TEXT` ⬅️ 
- `govt_id` / `type_of_id` / `date_of_birth` / `linkedin_url` - OMITTED (Not Needed)
---

**SECTION 2: Columns MOVED to `applications_id` Table (Application-Level Facts)**

These are specific to a candidate's submission for a particular opening. Same candidate may have different values across different applications.

*Add these columns to `applications_id` table:*

- `candidate_type TEXT` ⬅️ **MOVED FROM profiles_database** — describes applicant type specifically for THIS opening
- `bench_type TEXT` ⬅️ **MOVED FROM profiles_database** — bench classification specifically for THIS role
- `candidate_cost NUMERIC` ⬅️ **MOVED FROM profiles_database** — cost to hire specifically for THIS position (varies per opening)
- `recruitment_notes TEXT` ⬅️ **MOVED FROM profiles_database** — notes specific to THIS submission
- 
<!-- - `lyncogs TEXT` ⬅️ **MOVED FROM profiles_database** — compliance check result for THIS application non needed
- `lyncogs_summary TEXT` ⬅️ **MOVED FROM profiles_database** — compliance summary for THIS application not needed
-->
---

**SECTION 3: Columns MOVED to `screenings` Table (Screening Event-Level Facts)**

These are evaluation outcomes from screening events, not candidate profile data. Same candidate may have different ratings across different screening rounds.

*Add these columns to `screenings` table:*


- `pre_screening_report TEXT` ⬅️ **MOVED FROM profiles_database** — assessment report generated from THIS screening event
- `post_screening_report TEXT` (rename from `edited_psr`) ⬅️ **MOVED FROM profiles_database** — PSR generated from THIS screening


**Recommended constraints for refactored `profiles_database`:**

- `UNIQUE (candidate_code)`
- partial unique index on normalized phone when present

**Reason:**
- current app already treats mobile number as a cross-vendor duplicate guard

------

**Clean Result:** `profiles_database` table now holds ONLY true candidate profile data (17 columns after cleanup)

#### `applications_id`
This is the real center of the ATS. Represents a candidate's submission for a specific opening with a specific vendor.

**Core/Foreign Key Columns:**

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `candidate_id UUID NOT NULL FK -> profiles_database.id`
- `opening_id UUID NOT NULL FK -> openings.id`
- `vendor_id UUID NOT NULL FK -> vendor_master.id`
- `pid_taken_by_user_id UUID NULL FK -> users.id`
screening id fk 

**SECTION 1: Existing Application-Level Columns (Keep)**

- `status TEXT NOT NULL`
- `next_task enum`
- `experience_level_candidate TEXT`
- `screening_clear_date DATE`??????
- `follow_up_date DATE`
- `followup_email_status TEXT`
- `send_mail BOOLEAN`
- `send_to_client enum`
- `cv_sent_to_client_date TIMESTAMPTZ`
- `cv_sent_to_client_date_last_updated TIMESTAMPTZ`
- `screening_report_link TEXT` this is moved to screening
- `screening_fathom_links_transcript TEXT this is prescreening report` this is moved screening
- `link_post_interview_questionnaire TEXT this is pid`
<!-- - `status_post_interview_questionnaire TEXT` -->
- `other_offers TEXT`
<!-- - `vs_remarks TEXT  ` not needed --> 
- `panel_type enum(direct client,end client,unconfirmed,..)`
<!-- - `tech_screening TEXT` -->
- `backup_candidate (enum(required ,not required))`
<!-- - `backup_option_1 TEXT` -->
<!-- - `vendor_of_option_1 TEXT `   ??? -->
<!-- - `backup_option_2 TEXT` not needed
- `vendor_of_option_2 TEXT` not needed -->

- `morning_followup_status enum`
- `interview_coordination TEXT`. who has coordinated with the person ??
- `candidate_followup TEXT`. is follow up done for this .??
- `scheduling_coordination_started enum` ??
- `form_filled_by TEXT` screening level
- `name_as_per_aadhar TEXT` candidate level
- `id_type_submitted TEXT` candidate level
- `revised_ctc_lpa NUMERIC`
- `offboarding TEXT`
- `offboarding_status TEXT`
- `preaccessing done` screening
- `pre assessor name` screening
- `pre assesssing remark` screening
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

**SECTION 2: NEW Columns MOVED from `profiles_database` (Application Context)**

These 7 columns are specific to THIS submission and may vary across different applications of the same candidate:

- `candidate_type TEXT` ⬅️ **FROM profiles_database** — applicant type for this opening
- `bench_type TEXT` ⬅️ **FROM profiles_database** — bench classification for this role
- `candidate_cost NUMERIC` ⬅️ **FROM profiles_database** — cost to hire for this position
- `recruitment_notes TEXT` ⬅️ **FROM profiles_database** — notes on this submission



---

**Critical constraint:**

- `UNIQUE (candidate_id, opening_id, vendor_id)`

That constraint is required because the current app already enforces exactly this in code.

#### `application_screeners` not needed 

Real many-to-many relation between applications and screeners.

Columns:

- `application_id UUID FK -> applications_id.id`
- `screener_id UUID FK -> screeners_profile.id`
- `role TEXT CHECK IN ('screener', 'tech_screener', 'form_filler')`
- `assigned_at TIMESTAMPTZ`

Constraint:

- `PRIMARY KEY (application_id, screener_id, role)`

#### `interview_rounds` (NEW TABLE)

Replaces 7 flat columns from applications (client_l1/l2/l3_meeting_link, client_l1/l2/l3_screening_at, pre_l1_date_and_time).

Core columns:

- `id UUID PK`
- `application_id UUID NOT NULL FK -> applications_id.id ON DELETE CASCADE`
- `round_type VARCHAR(20) NOT NULL CHECK (round_type IN ('pre_l1', 'l1', 'l2', 'l3'))`
- `scheduled_at TIMESTAMPTZ NOT NULL`
- `meeting_link TEXT NULL`
- `outcome VARCHAR(20) NULL CHECK (outcome IN ('pass', 'fail', 'no_show', 'rescheduled', 'awaited', 'cancelled'))`
- `notes TEXT NULL`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

Indexes:

- `idx_interview_rounds_application_id ON (application_id)`
- `idx_interview_rounds_scheduled_at ON (scheduled_at)`
- `idx_interview_rounds_round_type ON (round_type)`

Migration:

- Source: applications_id table (client_l1_screening_at, client_l1_meeting_link, client_l2_screening_at, client_l2_meeting_link, client_l3_screening_at, client_l3_meeting_link, pre_l1_date_and_time)
- Unpivot: One row per round (pre_l1, l1, l2, l3) for each application
- Drop from applications_id after backfill: 7 columns listed above

### D. Scheduling tables

#### `rooms✅`

Canonical room/schedule definition.

Core columns:

- `id UUID PK`
- `name TEXT UNIQUE NOT NULL`
- `daily_start_time TIME`
- `daily_end_time TIME`
- `days_of_week TEXT[]`
- `slot_duration_minutes INTEGER`
<!-- - `meeting_link TEXT not needed` -->
- `is_active BOOLEAN`
- `created_at`
- `updated_at`

#### `room_vendors`

Needed because Airtable `Rooms` currently supports `Exclusive Vendor_master`.

Columns:

- `room_id UUID FK -> rooms.id`
- `vendor_id UUID FK -> vendor_master.id`

Constraint:

- `PRIMARY KEY (room_id, vendor_id)`

Rule:

- no rows = room open to all vendors
- one or more rows = room restricted to those vendors

#### `screenings`

Scheduled screening events. Each row represents one screening event where a candidate is evaluated.

**Core/Foreign Key Columns:**

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `application_id UUID NOT NULL FK -> applications_id.id`
- `candidate_id UUID NOT NULL FK -> profiles_database.id`
<!-- - `vendor_id UUID NOT NULL FK -> vendor_master.id` -->
- `room_id UUID NULL FK -> rooms.id`
- `scheduled_at TIMESTAMPTZ NOT NULL`

**SECTION 1: Existing Screening-Level Columns (Keep)**

Scheduling and logistics info for this screening event:

- `status TEXT`
- `meeting_link TEXT`
- `admin_interview_link TEXT`
<!-- - `ai_interview_link TEXT` -->
- `organizer_email TEXT`
- `created_email TEXT`
- `event_id TEXT`
- `slot_key TEXT` 
- `comments TEXT`
- `screener_audit_report TEXT`
prescreening report 
prescrening jsonb
- `answer_of_coding_q1 TEXT`
- `post_screening_report TEXT`
- `post_screening_json jsonb`
- `transcript` vtt file
- `answer_of_coding_q2 TEXT`
- `interview_breadth_rating NUMERIC`
- `interview_depth_rating NUMERIC` audit 
- `sop_flow_adherence_rating NUMERIC`screener audit
- `communication_quality_rating NUMERIC` screener audit
- `overall_screening_effectiveness_rating NUMERIC`
- `question_wise assessment jsonb` 
- `Coding_Question_Assessment jsonb` 
- `screening_coverage jsonb` 
- `Q1 assessed` 
- `q2 assessed` 
- `answer of coding q1`
- `answer of coding q2` 
- `created_at TIMESTAMPTZ`
we can merge all the reports data of a post screening in to a single json review needed.
- `updated_at TIMESTAMPTZ`

**SECTION 2: NEW Columns MOVED from `profiles_database` (Screening Assessment Results)**

These 6 columns are evaluation results FROM this screening event. Same candidate may have different ratings across different screening rounds:


- `screening_report url` ⬅️ **FROM profiles_database** — assessment report generated from THIS screening event
- `post_screening_report TEXT` ⬅️ **FROM profiles_database** (rename from `edited_psr`) — PSR outcome from THIS screening

---
Recommended constraints:

- `UNIQUE (slot_key)`
- partial unique on `event_id` when not null

### E. Post-selection tables

<!-- #### `selected_candidates` not needed 

Keep separate because onboarding is a real post-selection workflow.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `application_id UUID NOT NULL FK -> applications_id.id`
- `bench_vendor_id UUID NULL FK -> vendor_master.id`
- `selection_date DATE`
- `status TEXT`
- `overall_status TEXT`
<!-- - `assignee TEXT` -->
<!-- - `attachments JSONB` -->
<!-- - `pf_status TEXT`
- `pf_doc_remarks TEXT`
- `university_docs_check TEXT`
- `university_docs_remarks TEXT`
<!-- - `finalized_ctc NUMERIC` -->
<!-- - `is_fte BOOLEAN`
<!-- - `invoice_raised TEXT` -->
<!-- - `crc_confirmation_date DATE`
- `offboarding TEXT`
- `offboarding_status TEXT`
- `xpo onboarding status`
- `bgv status`
- `bgv trigger date`
- `sow signing date`
- `offboarding_status TEXT`
- `synechron onboarding status`
- `synechron onboarding date`
- `created_at`
- `updated_at --> 

Recommended constraint:

- `UNIQUE (application_id)` (on applications_id table)


Constraint:

- `UNIQUE (selected_candidate_id, event_type)` -->

### F. People and auth tables

#### `screeners_profile ✅`

Internal screener directory.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `name TEXT NOT NULL`
- `phone TEXT`
- `status TEXT`
<!-- - `type TEXT` -->
- `created_at`
- `updated_at`

Recommendation:

- do not keep `vendor_id` here unless screeners are truly vendor-owned in the business model

#### `users ✅`

Application user profile only, not password store.

Core columns:

- `id UUID PK`
- `airtable_id TEXT UNIQUE NULL`
- `auth_user_id UUID UNIQUE`
- `username TEXT UNIQUE`
- `role or typoe TEXT`
- `screener_id UUID NULL FK -> screeners_profile.id`
- `pid_authorization TEXT`
- `created_at`
- `updated_at`

Recommendation:

- auth secrets belong in Supabase Auth, not here

### G. Skills tables  this tables are from pg so need to make the changes strictly do not change at all  .

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
- `candidate_id UUID FK -> profiles_database.id`
- `application_id UUID NULL FK -> applications_id.id`
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
| Vendor identity | `vendor_master` |
| Client identity | `client_master` |
| Department PoCs | `client_department` |
| Location vocabulary | `locations` |
| Opening/job requirements | `openings` |
| Opening to location relation | `openings_locations_openings` |
| Opening to vendor visibility/exclusivity | `vendor_openings` |
| Candidate profile | `profiles_database` |
| Candidate ownership/vendor source | `profiles_database.vendor_owner_id` |
| Candidate submitted to opening by vendor | `applications_id` |
| Screeners assigned to an application | `screener_assignments` |
| Room availability definition | `rooms` |
| Room exclusivity by vendor | `room_vendors` (MISSING in PG) |
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

- `applications_id UNIQUE (profiles_database_id, openings_id, vendor_id)`
- `screenings UNIQUE (slot_key)`
- `selected_candidates UNIQUE (application_id)` (MISSING in PG)

Should add:

- `profiles_database UNIQUE (candidate_id)` (Existing)
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

1. Backfill `applications_id.profiles_database_id`, `openings_id`, `vendor_id`.
2. Backfill `screenings.room_id`.
3. Backfill `openings_locations_openings` and `vendor_openings`.
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
  - opening to vendor_openings
  - openings to openings_locations_openings
  - applications_id to screener_assignments
  - rooms to vendor_openings (Missing Gap)
  - opening to required skills
- Collapse the current multi-model skill system into one UUID-based model.
- Keep Naukri, ranking, automation, and logs outside the core ATS design.
- Stop carrying Airtable lookup/rollup/copy fields into the relational schema.

That gives you a schema that is smaller than the current mixed model, more correct than Airtable, and directly compatible with Supabase nested relational APIs.
