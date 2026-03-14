# XPO-ATS — PostgreSQL Database Schema Reference
> **Source:** Live Supabase DB (`qurjkxotolzqmwjjaekp`) · `final_migration.sql` · `sync.js`  
> **Last updated:** March 2026  
> **Purpose:** API development reference for the current target schema.
>
> **Decision update:** `profiles_database.vendors_id` is the canonical vendor link.
> `profiles_database.vendor_id`, `prompts`, `interview_feedback`, and `interview_rounds`
> are being removed from the target schema and should not be used in new work.

--

## Table of Contents

1. [Schema Overview & ER Diagram](#1-schema-overview)
2. [Core Entity Tables](#2-core-entity-tables)
3. [Talent Pipeline Tables](#3-talent-pipeline-tables)
4. [Junction / Relationship Tables](#4-junction--relationship-tables)
5. [Skill System Tables](#5-skill-system-tables)
6. [Question Bank Tables](#6-question-bank-tables)
7. [Naukri Integration Tables](#7-naukri-integration-tables)
8. [AI / Job Ranking Tables](#8-ai--job-ranking-tables)
9. [Campaign / Notification Tables](#9-campaign--notification-tables)
10. [Configuration / Auth Tables](#10-configuration--auth-tables)
11. [Foreign Key Map](#11-foreign-key-map)
12. [API Query Patterns](#12-api-query-patterns)
13. [Data Notes for API Developers](#13-data-notes-for-api-developers)

---

## 1. Schema Overview

### Entity Relationship (Text Diagram)

```
vendor_master ──────────────────────────────────────────────────────────┐
    │ (1:N)                                                              │
    ├──→ screeners_profile                                               │
    │       └──(junction)──→ screener_assignments ←── applications_id   │
    ├──→ profiles_database                                │              │
    │       ├──→ candidate_skills                        │              │
    │       └──→ candidate_skill_map                     │              │
    └──→ (via vendor_openings) ──→ openings ─────────────┤              │
                                      │                  ▼              │
                             locations│          screenings             │
                      (via junction)◄─┘          └──→ rooms            │
client_master ──→ client_department ──→ openings                       │
    └──→ locations                                                      │
                                                                        │
applications_id ──→ selected_candidates ──→ onboarding_events          │
                                                                        │
naukri_folders ──→ naukri_candidates                                    │
users ──→ screeners_profile                                             │
```

### Active Tables

| Category | Tables |
|----------|--------|
| **Core Entities** | `vendor_master`, `client_master`, `client_department`, `locations`, `rooms`, `users`, `screeners_profile` |
| **Talent Pipeline** | `profiles_database`, `openings`, `applications_id`, `screenings`, `selected_candidates` |
| **Junction / Normalized** | `screener_assignments`, `vendor_openings`, `openings_locations_openings`, `onboarding_events` |
| **Skill System** | `skill_master`, `skill_level_master`, `skill_map`, `candidate_skills`, `candidate_skill_map`, `skill_sets` |
| **Question Bank** | `difficulties`, `questions` |
| **Naukri Integration** | `naukri_folders`, `naukri_candidates` |
| **AI / Ranking** | `ranking_jobs` |
| **Campaigns** | `campaign_subscription`, `campaign_trigger` |
| **Config / Auth** | `status_config`, `app_tokens` |

> **Convention:** Every Airtable-synced table has an `airtable_id TEXT NOT NULL UNIQUE` column. All primary keys are `UUID` via `uuid_generate_v4()`.

---

## 2. Core Entity Tables

### `vendor_master`
> Vendors (staffing agencies / partners) who submit candidates.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK**, auto-generated |
| `airtable_id` | `text` | NO | UNIQUE — Airtable record ID |
| `vendor_name` | `text` | YES | |
| `vendor_address` | `text` | YES | |
| `vendor_registration_date` | `date` | YES | |
| `vendor_profiles` | `text` | YES | Description of vendor services |
| `resource_location` | `varchar(100)` | YES | |
| `linkedin_url` | `text` | YES | |
| `vendor_status` | `varchar(100)` | YES | |
| `vendor_id_number` | `numeric` | YES | Legacy numeric Airtable ID |
| `revenue_model` | `varchar(100)` | YES | |
| `vendor_poc` | `varchar(255)` | YES | Point of contact name |
| `poc_contact_number` | `varchar(50)` | YES | |
| `poc_mail_id` | `varchar(255)` | YES | |
| `additional_poc_mail_ids` | `text` | YES | |
| `password` | `varchar(255)` | YES | ⚠️ Plain text — needs bcrypt |
| `vendor_type` | `varchar(100)` | YES | |
| `master_pid_document` | `text` | YES | |
| `status` | `varchar(100)` | YES | See `status_config` domain=`vendor` |
| `created_at` | `timestamptz` | YES | auto |
| `updated_at` | `timestamptz` | YES | auto-updated via trigger |

**Relationships OUT:**
- Has many `screeners_profile` (via `screeners_profile.vendor_id`)
- Has many `profiles_database` (via `profiles_database.vendors_id`)
- Has many `openings` (via `vendor_openings` junction)
- Has many `applications_id` (via `applications_id.vendor_id`)
- Has many `screenings` (via `screenings.vendor_id`)
- Has many `selected_candidates` (via `selected_candidates.whose_bench_id`)

---

### `client_master`
> Client companies that post job openings.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `client_name` | `varchar` | YES | |
| `client_industry` | `varchar` | YES | |
| `contact_email` | `varchar` | YES | |
| `contact_phone` | `varchar` | YES | |
| `spoc` | `varchar` | YES | Single point of contact |
| `client_requirements` | `varchar` | YES | |
| `location` | `varchar` | YES | Legacy text field |
| `requirements_type` | `varchar` | YES | |
| `linkedin_url` | `text` | YES | |
| `client_id` | `integer` | YES | Legacy numeric ID |
| `location_id` | `uuid` | YES | **FK** → `locations.id` (SET NULL) |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

**Relationships OUT:**
- `location_id` → `locations.id`
- Has many `client_department` (via `client_department.client_name_id`)
- Has many `openings` (via `openings.client_id`)

---

### `client_department`
> Departments within a client company.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `department_name` | `varchar` | YES | |
| `department_id` | `integer` | YES | Legacy numeric ID |
| `client_name_id` | `uuid` | YES | **FK** → `client_master.id` |
| `primary_poc` | `varchar` | YES | |
| `primary_poc_phone_number` | `varchar` | YES | |
| `primary_poc_role` | `varchar` | YES | |
| `secondary_poc` | `varchar` | YES | |
| `secondary_poc_phone_number` | `varchar` | YES | |
| `secondary_poc_role` | `varchar` | YES | |
| `primary_poc_email_id` | `varchar` | YES | |
| `secondary_poc_email_id` | `varchar` | YES | |
| `document_type` | `varchar` | YES | |
| `phone_screening_questionnaire` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

---

### `locations`
> Lookup table for city/area locations.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `name` | `varchar` | YES | City/area name |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

**Used in:** `client_master.location_id`, `profiles_database.location_id`, `openings_locations_openings`

---

### `rooms`
> Virtual/physical interview rooms.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `room_name` | `text` | YES | |
| `daily_start_time` | `time` | YES | |
| `daily_end_time` | `time` | YES | |
| `days_of_week` | `text[]` | YES | Array e.g. `{Mon,Tue,Wed}` |
| `slot_duration_minutes` | `integer` | YES | Default: 30 |
| `is_active` | `boolean` | YES | Default: true |
| `meeting_link` | `text` | YES | Zoom/Meet/Teams link |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

**Used in:** `screenings.room_id`

---

### `users`
> Internal XPO system users (admins, screeners, form-fillers).

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `username` | `text` | YES | |
| `password` | `text` | YES | ⚠️ Plain text — needs hashing |
| `type` | `varchar(100)` | YES | e.g. `admin`, `screener` |
| `screener_link` | `text` | YES | |
| `namemanual_entry` | `text` | YES | |
| `pid_authorization` | `varchar(100)` | YES | |
| `screener_profile_id` | `uuid` | YES | **FK** → `screeners_profile.id` (SET NULL) |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

---

### `screeners_profile`
> XPO technical screeners who conduct candidate interviews.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `name` | `varchar` | YES | |
| `number` | `varchar` | YES | Phone number |
| `status` | `varchar` | YES | See `status_config` domain=`screener` |
| `vendor_id` | `uuid` | YES | **FK** → `vendor_master.id` (SET NULL) |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

**Referenced by:** `screener_assignments.screener_id`, `users.screener_profile_id`

---

## 3. Talent Pipeline Tables

### `profiles_database`
> Master candidate profiles — single source of truth for a candidate.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `candidate_id` | `varchar` | YES | Legacy alphanumeric ID |
| `candidate_name` | `text` | YES | |
| `candidate_contact` | `text` | YES | Phone number |
| `candidate_email` | `text` | YES | |
| `current_company` | `text` | YES | |
| `skill` | `text` | YES | Primary skill tag |
| `notice_period` | `text` | YES | |
| `current_location` | `text` | YES | |
| `preferred_location` | `text` | YES | |
| `ctc_lpa` | `numeric` | YES | Current CTC in LPA |
| `ectc_lpa` | `numeric` | YES | Expected CTC in LPA |
| `candidate_cost` | `numeric` | YES | Vendor cost |
| `bench_type` | `varchar` | YES | |
| `candidate_type` | `varchar` | YES | |
| `govt_id` | `text` | YES | Aadhaar/PAN reference |
| `type_of_id` | `text` | YES | |
| `communication_rating` | `numeric` | YES | |
| `confidence_rating` | `numeric` | YES | |
| `tech_self_rating` | `numeric` | YES | Candidate's self-rating |
| `comments` | `text` | YES | |
| `creation_date` | `date` | YES | |
| `last_working_day` | `date` | YES | |
| `is_resigned` | `boolean` | YES | Default: false |
| `is_draft` | `boolean` | YES | Default: false |
| `career_gap` | `text` | YES | |
| `cv_link` | `text` | YES | Google Drive / URL |
| `edited_cv` | `text` | YES | Edited CV link |
| `edited_psr` | `text` | YES | Edited post-screening report |
| `screening_report` | `text` | YES | Raw screening report |
| `lyncogs` | `text` | YES | |
| `lyncogs_summary` | `text` | YES | |
| `project_summary` | `text` | YES | AI-generated |
| `employment_history` | `text` | YES | AI-generated |
| `gap_analysis` | `text` | YES | AI-generated |
| `jumping_frequency` | `numeric` | YES | Job-hopping metric |
| `extracted_skills` | `text` | YES | AI-extracted JSON blob |
| `recruitment_notes` | `text` | YES | |
| `candidate_document` | `text` | YES | |
| `autonumber` | `integer` | YES | Legacy ordering |
| `vendors_id` | `uuid` | YES | **FK** → `vendor_master.id` ✅ Use this |
| `location_id` | `uuid` | YES | **FK** → `locations.id` |
| `sync_status` | `varchar` | YES | |
| `last_sync_at` | `timestamptz` | YES | |
| `sync_error` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

> ⚠️ `vendors_id` is the vendor link to use in new APIs. `vendor_id` is being removed.

---

### `openings`
> Job openings posted by clients.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `opening_id` | `integer` | YES | Legacy numeric ID |
| `job_title` | `text` | YES | |
| `client_id` | `uuid` | YES | **FK** → `client_master.id` |
| `client_department_id` | `uuid` | YES | **FK** → `client_department.id` |
| `status` | `varchar` | YES | See `status_config` domain=`opening` |
| `experience_level` | `text` | YES | |
| `number_of_open_position` | `numeric` | YES | |
| `job_description` | `text` | YES | Raw JD |
| `jd_for_prompt` | `text` | YES | Cleaned JD for AI |
| `client_billing` | `numeric` | YES | |
| `duration_months` | `numeric` | YES | |
| `date_opened` | `date` | YES | |
| `onboarding_process_notes` | `text` | YES | |
| `comments` | `text` | YES | |
| `bline_id` | `varchar` | YES | Benchline ID |
| `ctc_lpa_limit_eg_14` | `text` | YES | Max CTC budget |
| `is_exclusive` | `varchar` | YES | |
| `max_vendor_budget` | `numeric` | YES | |
| `candidate_type` | `varchar` | YES | |
| `job_group` | `text[]` | YES | Array of groups |
| `job_id` | `numeric` | YES | |
| `interview_slots` | `text` | YES | |
| `questionnaire` | `text` | YES | |
| `master_pid_document` | `text` | YES | |
| `recruitment_target_ctc` | `numeric` | YES | |
| `naukri_folder` | `text` | YES | Naukri folder ID |
| `maximum_joining_period_days` | `numeric` | YES | |
| `maximum_notice_period_allowed` | `numeric` | YES | |
| `partner_recruitment_fees_of_annual_ctc` | `numeric` | YES | |
| `coding_q1` | `text` | YES | Coding question 1 |
| `coding_q2` | `text` | YES | Coding question 2 |
| `skill_coding_q1` | `text` | YES | |
| `skill_coding_q2` | `text` | YES | |
| `job_visibility` | `varchar` | YES | |
| `job_bench_type` | `varchar` | YES | |
| `advisory` | `text` | YES | |
| `raw_jd_from_client` | `jsonb` | YES | |
| `sync_status` | `text` | YES | Default: `SYNCED` |
| `last_sync_attempt` | `timestamptz` | YES | |
| `sync_error_details` | `text` | YES | |
| `screeners_profile` | `varchar` | YES | Legacy text ref (use junction tables) |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

---

### `applications_id`
> A candidate application for a specific opening via a vendor. Central pipeline tracking entity.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `vendor_id` | `uuid` | YES | **FK** → `vendor_master.id` |
| `openings_id` | `uuid` | YES | **FK** → `openings.id` |
| `profiles_database_id` | `uuid` | YES | **FK** → `profiles_database.id` |
| `pid_taken_by_id` | `uuid` | YES | **FK** → `users.id` |
| `status` | `varchar` | YES | See `status_config` domain=`application` |
| `status_remarks` | `text` | YES | |
| `next_task` | `varchar` | YES | |
| `internal_screening_time_and_date` | `date` | YES | |
| `link_post_interview_questionnaire` | `text` | YES | |
| `status_post_interview_questionnaire` | `varchar` | YES | |
| `screening_fathom_links` | `text` | YES | Fathom recording URL |
| `other_offers` | `text` | YES | |
| `screening_report_link` | `text` | YES | |
| `candidates_preferred_slot` | `text` | YES | |
| `experience_level_candidate` | `varchar` | YES | |
| `clients_interview_feedback` | `text` | YES | |
| `followup_email_status` | `varchar` | YES | |
| `send_mail` | `boolean` | YES | Default: false |
| `form_filled_by` | `varchar` | YES | |
| `lwd` | `date` | YES | Last working day |
| `follow_up_date` | `date` | YES | |
| `update_airtable` | `boolean` | YES | Default: false |
| `pre_l1_transcript` | `text` | YES | |
| `post_screening_report` | `text` | YES | |
| `screening_clear_date` | `date` | YES | |
| `revised_ctc_lpa` | `numeric` | YES | |
| `vs_remarks` | `text` | YES | Vendor Summary remarks |
| `send_to_client` | `varchar` | YES | |
| `tech_screening` | `text` | YES | |
| `cluely_report` | `text` | YES | Anti-cheat analysis report |
| `backup_candidate` | `varchar` | YES | |
| `tracker_remarks` | `text` | YES | |
| `cv_sent_to_client_date` | `timestamptz` | YES | |
| `cv_sent_to_client_date_last_updated` | `timestamptz` | YES | |
| `name_as_per_the_aadhar` | `text` | YES | |
| `backup_option_1` | `text` | YES | |
| `vendor_of_option_1` | `text` | YES | |
| `backup_option_2` | `text` | YES | |
| `vendor_of_option_2` | `text` | YES | |
| `id_type_submitted` | `text` | YES | |
| `transcript` | `text` | YES | |
| `morning_followup_status` | `varchar` | YES | |
| `panel_type` | `varchar` | YES | |
| `scheduling_coordination_started` | `varchar` | YES | |
| `interview_coordination` | `varchar` | YES | |
| `candidate_followup` | `varchar` | YES | |
| `offboarding` | `varchar` | YES | |
| `offboarding_status` | `varchar` | YES | |
| `opening_vendor_summary` | `varchar` | YES | |
| `clients_feedback_status` | `varchar` | YES | |
| `sow_signed_with_client_date` | `varchar` | YES | |
| `sow_signed_with_vendor_date` | `varchar` | YES | |
| `clients_onboarding_date` | `varchar` | YES | |
| `fnt_post_interview` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

> ⚠️ Interview round data stays on `applications_id` for now. Dedicated interview tables are not part of the active target schema.  
> ⚠️ **Screeners** → use `screener_assignments` table. `screener_id`/`tech_screener_id` columns are **dropped**.

---

### `screenings`
> XPO-internal screening sessions scheduled for candidates.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `candidate_id` | `uuid` | YES | **FK** → `profiles_database.id` |
| `vendor_id` | `uuid` | YES | **FK** → `vendor_master.id` |
| `application_id` | `uuid` | YES | **FK** → `applications_id.id` |
| `room_id` | `uuid` | YES | **FK** → `rooms.id` (SET NULL) |
| `candidate_name` | `varchar` | YES | Denormalized for speed |
| `date` | `timestamptz` | YES | Scheduled date/time |
| `test_date` | `timestamptz` | YES | |
| `meeting_link` | `text` | YES | |
| `admin_interview_link` | `text` | YES | |
| `ai_interview_link` | `text` | YES | |
| `skill` | `text` | YES | |
| `cv_link` | `text` | YES | |
| `organizer_email` | `text` | YES | |
| `event_id` | `text` | YES | Google Calendar event ID |
| `event_created_time` | `timestamptz` | YES | |
| `screener_assigned` | `varchar` | YES | Name text (denorm) |
| `created_email` | `text` | YES | |
| `slotkey` | `varchar` | YES | |
| `status` | `varchar` | YES | See `status_config` domain=`screening` |
| `comments` | `text` | YES | |
| `screener_evaluation_report` | `text` | YES | Raw evaluation report |
| `answer_of_coding_q1` | `text` | YES | |
| `answer_of_coding_q2` | `text` | YES | |
| `screener_audit_report` | `text` | YES | Audit report of screener quality |
| `interview_breadth_rating` | `numeric` | YES | |
| `interview_depth_rating` | `numeric` | YES | |
| `sop_flow_adherence_rating` | `numeric` | YES | |
| `communication_quality_rating` | `numeric` | YES | |
| `overall_screening_effectiveness_rating` | `numeric` | YES | |
| `candidate_profile_id` | `uuid` | YES | Alternate reference |
| `fetched_time` | `timestamptz` | YES | |
| `last_modified` | `timestamptz` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

---

### `selected_candidates`
> Candidates who passed screening and are in the onboarding process.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `airtable_id` | `text` | NO | UNIQUE |
| `candidate_from_applications_id` | `uuid` | YES | **FK** → `applications_id.id` |
| `whose_bench_id` | `uuid` | YES | **FK** → `vendor_master.id` |
| `assignee` | `varchar` | YES | |
| `status` | `varchar` | YES | See `status_config` domain=`selected` |
| `overall_status` | `varchar` | YES | |
| `selection_date` | `date` | YES | |
| `attachments` | `jsonb` | YES | |
| `pf_status` | `varchar` | YES | |
| `pf_doc_remarks` | `text` | YES | |
| `university_docs_check` | `varchar` | YES | |
| `university_docs_remarks` | `text` | YES | |
| `finalised_ctc_eg_1200000` | `numeric` | YES | Final CTC in absolute value |
| `is_this_fte` | `varchar` | YES | FTE vs contract |
| `invoice_raised` | `varchar` | YES | |
| `crc_confirmation_date` | `date` | YES | Client resource confirmation date |
| `offboarding` | `varchar` | YES | |
| `offboarding_status` | `varchar` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

> ⚠️ **Onboarding milestones** (BGV, SOW, etc.) are in `onboarding_events`. Flat date columns are **dropped**.

---

## 4. Junction / Relationship Tables

### `screener_assignments`
> Which screener is assigned to which application and in what role.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `screener_id` | `uuid` | NO | **FK** → `screeners_profile.id` (CASCADE) |
| `application_id` | `uuid` | NO | **FK** → `applications_id.id` (CASCADE) |
| `role` | `varchar(50)` | NO | `screener` \| `tech_screener` \| `form_filler` |
| `assigned_at` | `timestamptz` | YES | |

**Primary Key:** `(screener_id, application_id, role)`

```sql
-- Get all screeners for an application:
SELECT sp.name, sp.number, sa.role, sa.assigned_at
FROM screener_assignments sa
JOIN screeners_profile sp ON sp.id = sa.screener_id
WHERE sa.application_id = $1;
```

---

### `vendor_openings`
> Which vendors have access to which openings (M:N).

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `vendor_id` | `uuid` | NO | **FK** → `vendor_master.id` (CASCADE) |
| `opening_id` | `uuid` | NO | **FK** → `openings.id` (CASCADE) |
| `is_exclusive` | `boolean` | NO | Default: false |
| `assigned_at` | `timestamptz` | YES | |

**Primary Key:** `(vendor_id, opening_id)`

```sql
-- Get all vendors for an opening:
SELECT vm.vendor_name, vo.is_exclusive
FROM vendor_openings vo
JOIN vendor_master vm ON vm.id = vo.vendor_id
WHERE vo.opening_id = $1;
```

---

### `openings_locations_openings`
> M:N between openings and locations (an opening can be for multiple cities).

| Column | Type | Notes |
|--------|------|-------|
| `openings_id` | `uuid` | **FK** → `openings.id` (CASCADE) |
| `locations_id` | `uuid` | **FK** → `locations.id` (CASCADE) |

```sql
-- Get all locations for an opening:
SELECT l.name 
FROM openings_locations_openings olo
JOIN locations l ON l.id = olo.locations_id
WHERE olo.openings_id = $1;
```

---

### `onboarding_events`
> Normalized onboarding milestone events — replaces flat date columns on `selected_candidates`.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `selected_id` | `uuid` | NO | **FK** → `selected_candidates.id` (CASCADE) |
| `event_type` | `varchar(50)` | NO | `vendor_onboarding` \| `xpo_onboarding` \| `client_onboarding` \| `end_client_onboarding` \| `bgv` \| `bgv_doc_submission` \| `sow_signing` \| `crc_confirmation` |
| `event_date` | `date` | YES | |
| `status` | `varchar(100)` | YES | |
| `notes` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

```sql
-- Get onboarding timeline:
SELECT event_type, event_date, status
FROM onboarding_events
WHERE selected_id = $1
ORDER BY event_date;
```

---

## 5. Skill System Tables

### `skill_master`
| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` | **PK** |
| `skill_name` | `text` | NOT NULL, UNIQUE |

### `skill_level_master`
| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` | **PK** |
| `level` | `text` | NOT NULL (e.g. `Beginner`, `Intermediate`, `Expert`) |

### `skill_map`
> Maps required skills + levels to an opening (uses legacy integer opening_id).

| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` | **PK** |
| `opening_id` | `integer` | NOT NULL — legacy numeric ID |
| `skill_id` | `bigint` | **FK** → `skill_master.id` (CASCADE) |
| `level_id` | `bigint` | **FK** → `skill_level_master.id` (SET NULL) |

### `candidate_skills`
> A candidate's skills assessed for a specific opening (UUID-based, preferred).

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `candidate_id` | `uuid` | NO | **FK** → `profiles_database.id` (CASCADE) |
| `skill_id` | `bigint` | YES | **FK** → `skill_master.id` |
| `opening_id` | `uuid` | YES | **FK** → `openings.id` |
| `candidate_level` | `bigint` | YES | **FK** → `skill_level_master.id` |
| `projects_done` | `jsonb` | YES | Default: `[]` |
| `self_rating` | `numeric` | YES | |
| `assessment_rating` | `numeric` | YES | |
| `technical_fit_score_jd` | `numeric` | YES | AI JD match score |
| `assessment_notes` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

### `candidate_skill_map`
> Detailed AI screening skill assessments per candidate.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `bigint` | NO | **PK** |
| `candidate_id` | `text` | NO | Airtable record ID (not UUID!) |
| `skill_id` | `bigint` | NO | **FK** → `skill_master.id` (CASCADE) |
| `self_rating` | `integer` | YES | |
| `number_of_projects` | `integer` | YES | Default: 0 |
| `assessed` | `boolean` | YES | |
| `conceptual_rating` | `real` | YES | |
| `practical_rating` | `real` | YES | |
| `coding_rating` | `real` | YES | |
| `overall_rating` | `integer` | YES | |
| `pre_screening_ai_rating` | `integer` | YES | |
| `summary` | `jsonb` | YES | |
| `skill_rating_assessment` | `jsonb` | YES | |
| `skills_violation_justification` | `text` | YES | |
| `pre_screening_ai_summary` | `jsonb` | YES | |
| `created_at` | `timestamptz` | YES | |

> ⚠️ `candidate_id` is `TEXT` here — it's the Airtable record ID, **not** a UUID.

### `skill_sets`
| Column | Type | Notes |
|--------|------|-------|
| `id` | `text` | **PK** — `nanoid(12)` |
| `skill_name` | `text` | NOT NULL |
| `questions` | `jsonb` | Default: `[]` |

---

## 6. Question Bank Tables

### `difficulties`
| Column | Type | Notes |
|--------|------|-------|
| `id` | `integer` | **PK** — auto-increment |
| `level_name` | `text` | NOT NULL (e.g. `Easy`, `Medium`, `Hard`) |

### `questions`
| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `text` | NO | **PK** — `nanoid(12)` |
| `question_text` | `text` | NO | |
| `skill_id` | `bigint` | YES | **FK** → `skill_master.id` (CASCADE) |
| `difficulty_id` | `integer` | YES | **FK** → `difficulties.id` |

---

## 7. Naukri Integration Tables

### `naukri_folders`
> Naukri job folders linked to XPO openings.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `folder_id` | `text` | NO | Naukri folder ID (UNIQUE) |
| `folder_name` | `text` | NO | |
| `description` | `text` | YES | |
| `opening_id` | `text` | YES | Naukri text opening ID |
| `vendor_id` | `text` | YES | Naukri text vendor ID |
| `vendor_id_number` | `integer` | YES | |
| `airtable_record_id` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

### `naukri_candidates`
> Candidates sourced via the Naukri Chrome extension.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** — `gen_random_uuid()` |
| `unique_candidate_id` | `text` | NO | UNIQUE — Naukri candidate ID |
| `folder_id` | `uuid` | YES | **FK** → `naukri_folders.id` (SET NULL) |
| `candidate_name` | `text` | YES | |
| `email` | `text` | YES | |
| `phone` | `text` | YES | |
| `experience` | `text` | YES | |
| `current_ctc` | `text` | YES | |
| `expected_ctc` | `text` | YES | |
| `current_designation` | `text` | YES | |
| `highest_education` | `text` | YES | |
| `current_location` | `text` | YES | |
| `preferred_location` | `text` | YES | |
| `naukri_profile_link` | `text` | YES | |
| `screening_report_link` | `text` | YES | |
| `screening_report_summary` | `text` | YES | |
| `folder_description` | `text` | YES | |
| `match_score` | `integer` | YES | Default: 0 |
| `status` | `text` | YES | Default: `Candidate Created` |
| `resume_json` | `jsonb` | YES | Parsed resume data |
| `logs` | `jsonb` | YES | Default: `[]` — activity log |
| `vendor_name` | `text` | YES | |
| `draft_created` | `boolean` | YES | Default: false |
| `draft_created_time` | `timestamptz` | YES | |
| `candidate_id` | `text` | YES | Linked PG profile ID |
| `candidate_created` | `boolean` | YES | Default: false |
| `airtable_record_id` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

---

## 8. AI / Job Ranking Tables

### `ranking_jobs`
> Async AI ranking queue — ranks candidates against a job description.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `job_id` | `integer` | NO | Numeric opening ID |
| `jd` | `text` | NO | Job description text |
| `status` | `text` | NO | Default: `pending` |
| `to_rank` | `jsonb` | NO | Candidate IDs to rank |
| `results` | `jsonb` | YES | Ranking results |
| `error_message` | `text` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

---

## 9. Campaign / Notification Tables

### `campaign_subscription`
| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `name` | `text` | YES | |
| `table_name` | `text` | YES | Target DB table to watch |
| `webhook_url` | `text` | YES | |
| `filter` | `jsonb` | YES | |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

### `campaign_trigger`
| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `subscription_id` | `uuid` | YES | **FK** → `campaign_subscription.id` |
| `trigger_event` | `text` | YES | `INSERT` \| `UPDATE` |
| `condition` | `jsonb` | YES | Default: `{}` |
| `field_conversions` | `jsonb` | YES | |
| `offset` | `bigint` | YES | |
| `is_active` | `boolean` | NO | Default: false |
| `created_at` | `timestamptz` | NO | |
| `updated_at` | `timestamptz` | NO | |

---

## 10. Configuration / Auth Tables

### `status_config`
> Single source of truth for all status dropdown values.

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | `uuid` | NO | **PK** |
| `domain` | `varchar(50)` | NO | |
| `code` | `varchar(100)` | NO | Machine-readable |
| `label` | `text` | NO | Human-readable |
| `color_hex` | `varchar(7)` | YES | UI color e.g. `#FF5733` |
| `is_terminal` | `boolean` | YES | If true = final/terminal state |
| `sort_order` | `smallint` | YES | Display order |
| `created_at` | `timestamptz` | YES | |
| `updated_at` | `timestamptz` | YES | |

**UNIQUE:** `(domain, code)`

**Domains and their tables:**

| `domain` value | Used in column |
|----------------|----------------|
| `application` | `applications_id.status` |
| `opening` | `openings.status` |
| `screening` | `screenings.status` |
| `selected` | `selected_candidates.status` |
| `screener` | `screeners_profile.status` |
| `vendor` | `vendor_master.status` |

---

## 11. Foreign Key Map

| Source Table | Source Column | Target Table | Target Column | On Delete |
|---|---|---|---|---|
| `applications_id` | `openings_id` | `openings` | `id` | NO ACTION |
| `applications_id` | `pid_taken_by_id` | `users` | `id` | NO ACTION |
| `applications_id` | `profiles_database_id` | `profiles_database` | `id` | NO ACTION |
| `applications_id` | `vendor_id` | `vendor_master` | `id` | NO ACTION |
| `candidate_skill_map` | `skill_id` | `skill_master` | `id` | CASCADE |
| `candidate_skills` | `candidate_id` | `profiles_database` | `id` | CASCADE |
| `candidate_skills` | `candidate_level` | `skill_level_master` | `id` | SET NULL |
| `candidate_skills` | `opening_id` | `openings` | `id` | SET NULL |
| `candidate_skills` | `skill_id` | `skill_master` | `id` | SET NULL |
| `client_department` | `client_name_id` | `client_master` | `id` | NO ACTION |
| `client_master` | `location_id` | `locations` | `id` | SET NULL |
| `naukri_candidates` | `folder_id` | `naukri_folders` | `id` | SET NULL |
| `onboarding_events` | `selected_id` | `selected_candidates` | `id` | CASCADE |
| `openings` | `client_department_id` | `client_department` | `id` | NO ACTION |
| `openings` | `client_id` | `client_master` | `id` | NO ACTION |
| `openings_locations_openings` | `locations_id` | `locations` | `id` | CASCADE |
| `openings_locations_openings` | `openings_id` | `openings` | `id` | CASCADE |
| `profiles_database` | `location_id` | `locations` | `id` | NO ACTION |
| `profiles_database` | `vendors_id` | `vendor_master` | `id` | NO ACTION |
| `questions` | `difficulty_id` | `difficulties` | `id` | NO ACTION |
| `questions` | `skill_id` | `skill_master` | `id` | CASCADE |
| `screener_assignments` | `application_id` | `applications_id` | `id` | CASCADE |
| `screener_assignments` | `screener_id` | `screeners_profile` | `id` | CASCADE |
| `screeners_profile` | `vendor_id` | `vendor_master` | `id` | SET NULL |
| `screenings` | `application_id` | `applications_id` | `id` | NO ACTION |
| `screenings` | `candidate_id` | `profiles_database` | `id` | NO ACTION |
| `screenings` | `room_id` | `rooms` | `id` | SET NULL |
| `screenings` | `vendor_id` | `vendor_master` | `id` | NO ACTION |
| `selected_candidates` | `candidate_from_applications_id` | `applications_id` | `id` | NO ACTION |
| `selected_candidates` | `whose_bench_id` | `vendor_master` | `id` | NO ACTION |
| `skill_map` | `level_id` | `skill_level_master` | `id` | SET NULL |
| `skill_map` | `skill_id` | `skill_master` | `id` | CASCADE |
| `users` | `screener_profile_id` | `screeners_profile` | `id` | SET NULL |
| `vendor_openings` | `opening_id` | `openings` | `id` | CASCADE |
| `vendor_openings` | `vendor_id` | `vendor_master` | `id` | CASCADE |

---

## 12. API Query Patterns

### Full Candidate Profile
```sql
-- GET /candidates/:id
SELECT 
  pd.*,
  vm.vendor_name,
  l.name AS location_name
FROM profiles_database pd
LEFT JOIN vendor_master vm ON vm.id = pd.vendor_id
LEFT JOIN locations l ON l.id = pd.location_id
WHERE pd.id = $1;
```

### Application with Full Context
```sql
-- GET /applications/:id
SELECT 
  a.*,
  pd.candidate_name, pd.candidate_email, pd.skill, pd.ctc_lpa, pd.ectc_lpa,
  o.job_title, o.status AS opening_status,
  vm.vendor_name
FROM applications_id a
JOIN profiles_database pd ON pd.id = a.profiles_database_id
JOIN openings o ON o.id = a.openings_id
JOIN vendor_master vm ON vm.id = a.vendor_id
WHERE a.id = $1;
```

### Application → Screeners
```sql
-- GET /applications/:id/screeners
SELECT sp.name, sp.number, sa.role, sa.assigned_at
FROM screener_assignments sa
JOIN screeners_profile sp ON sp.id = sa.screener_id
WHERE sa.application_id = $1;
```

### Opening with Vendors + Locations
```sql
-- GET /openings/:id
SELECT 
  o.*,
  cm.client_name,
  cd.department_name,
  array_agg(DISTINCT l.name) FILTER (WHERE l.name IS NOT NULL) AS locations,
  array_agg(DISTINCT vm.vendor_name) FILTER (WHERE vm.vendor_name IS NOT NULL) AS vendors
FROM openings o
LEFT JOIN client_master cm ON cm.id = o.client_id
LEFT JOIN client_department cd ON cd.id = o.client_department_id
LEFT JOIN openings_locations_openings olo ON olo.openings_id = o.id
LEFT JOIN locations l ON l.id = olo.locations_id
LEFT JOIN vendor_openings vo ON vo.opening_id = o.id
LEFT JOIN vendor_master vm ON vm.id = vo.vendor_id
WHERE o.id = $1
GROUP BY o.id, cm.client_name, cd.department_name;
```

### Selected Candidate → Onboarding Timeline
```sql
-- GET /selected/:id/onboarding
SELECT event_type, event_date, status, notes
FROM onboarding_events
WHERE selected_id = $1
ORDER BY event_date;
```

### Status Config for Dropdowns
```sql
-- GET /config/statuses?domain=application
SELECT code, label, color_hex, is_terminal, sort_order
FROM status_config
WHERE domain = $1
ORDER BY sort_order;
```

### Vendor Pipeline View
```sql
-- GET /vendors/:id/pipeline
SELECT a.status, count(*) AS count
FROM applications_id a
WHERE a.vendor_id = $1
GROUP BY a.status
ORDER BY count DESC;
```

### Screener Upcoming Screenings
```sql
-- GET /screeners/:id/screenings
SELECT s.date, s.meeting_link, s.status, s.skill, s.candidate_name
FROM screenings s
JOIN screener_assignments sa ON sa.application_id = s.application_id
WHERE sa.screener_id = $1 AND s.date >= NOW()
ORDER BY s.date;
```

### Candidate Skills + Ratings for an Opening
```sql
-- GET /candidates/:candidateId/skills?opening=:openingId
SELECT 
  sm.skill_name,
  cs.self_rating, cs.assessment_rating, cs.technical_fit_score_jd,
  slm.level AS skill_level,
  cs.assessment_notes
FROM candidate_skills cs
JOIN skill_master sm ON sm.id = cs.skill_id
LEFT JOIN skill_level_master slm ON slm.id = cs.candidate_level
WHERE cs.candidate_id = $1 AND cs.opening_id = $2;
```

### Naukri Candidates Pipeline
```sql
-- GET /naukri/folders/:folderId/candidates
SELECT 
  nc.candidate_name, nc.email, nc.match_score, nc.status,
  nc.candidate_created, nc.draft_created
FROM naukri_candidates nc
WHERE nc.folder_id = $1
ORDER BY nc.match_score DESC;
```

---

## 13. Data Notes for API Developers

| Topic | Rule |
|-------|------|
| **All PKs** | `UUID` — always return as string in API responses |
| **airtable_id** | Present on every synced table — **do NOT expose externally** |
| **Interview rounds** | No dedicated PG round table in the active target schema. Keep interview-related fields on `applications_id` for now |
| **Screener assignment** | Use `screener_assignments` junction — `screener_id`/`tech_screener_id` no longer exist on `applications_id` |
| **Onboarding milestones** | Use `onboarding_events` — flat date columns no longer exist on `selected_candidates` |
| **Vendor on profile** | Use `profiles_database.vendors_id` |
| **Status values** | Always read from `status_config` table — never hardcode |
| **`candidate_skill_map.candidate_id`** | `TEXT` type — this is Airtable record ID, **not** a UUID |
| **`skill_map.opening_id`** | `INTEGER` — legacy numeric opening ID, not UUID |
| **Passwords** | `users.password` and `vendor_master.password` are plain text — must not be returned in API responses |
| **`rooms.days_of_week`** | PG `text[]` array — serialize as JSON array in API responses |
| **`openings.job_group`** | PG `text[]` array — serialize as JSON array in API responses |
| **`ranking_jobs.to_rank` / `results`** | `jsonb` — return as-is in API |
