# XPO ATS PG Final Schema And API Plan

**Date:** 24 March 2026  
**Scope:** Live Supabase/PostgreSQL schema snapshot + ATS API migration plan  
**Source of truth:** Live `public` schema, current app routes in [XPO-ATS](/Users/himanshup/Expo/XPO-ATS), and the `migration` branch diff

## 1. Executive Summary

The PostgreSQL schema is now good enough to start migrating ATS APIs in waves.

What is already in place:

- Core ATS tables exist and are populated:
  - `profiles_database`: `11105`
  - `applications_id`: `9603`
  - `screenings`: `11081`
  - `openings`: `348`
  - `rooms`: `7`
  - `documents_master`: `5`
  - `room_vendors`: `1`
- The main schema cleanup has already happened:
  - shifted fields are now on the intended tables
  - unused legacy columns were archived and dropped
  - `documents_master` and `room_vendors` now exist
- The sync service is already aligned to the chosen table names:
  - `profiles_database`
  - `applications_id`
  - `screenings`

What is still not fully closed:

- Some important uniqueness constraints are still missing because the data is not clean enough yet
- The `migration` branch has started moving some APIs to PG, but the shared helper code still assumes a few old column names and one missing table name

The practical conclusion:

- We can start writing and switching PG-backed APIs now
- We should not do a destructive rename of tables/columns right now
- We should use the live PG names in new APIs and clean the remaining schema risks in parallel

## 2. Live PG Core Schema Snapshot

### 2.1 Canonical ATS tables to use now

| Table | Purpose | Important join columns | Notes |
|---|---|---|---|
| `vendor_master` | Vendor master | `id`, `airtable_id`, `vendor_id_number` | Still contains plaintext password |
| `client_master` | Client master | `id`, `airtable_id` | Stable |
| `client_department` | Client department | `id`, `client_name_id` | Stable, used by openings |
| `documents_master` | Document master | `id`, `airtable_id`, `name` | New, synced from Airtable |
| `documents_master_client_departments` | M:N document mapping | `document_master_id`, `client_department_id` | Stable |
| `locations` | Location vocabulary | `id`, `airtable_id`, `name` | Stable |
| `openings` | Opening master | `id`, `airtable_id`, `opening_id`, `client_id`, `client_department_id` | Use `opening_id` as business code |
| `openings_locations_openings` | Opening-location junction | `openings_id`, `locations_id` | Stable |
| `vendor_openings` | Opening-vendor visibility junction | `vendor_id`, `opening_id` | Present in PG |
| `profiles_database` | Candidate profile | `id`, `airtable_id`, `candidate_id`, `vendors_id`, `location_id` | Keep table name as-is |
| `applications_id` | Candidate application/submission | `id`, `airtable_id`, `openings_id`, `profiles_database_id`, `vendor_id` | Keep table name as-is |
| `screenings` | Screening event | `id`, `airtable_id`, `application_id`, `candidate_id`, `room_id`, `scheduled_at`, `slot_key` | Core booking/event table |
| `rooms` | Room master | `id`, `airtable_id`, `room_name` | Stable |
| `room_vendors` | Room exclusivity junction | `room_id`, `vendor_id` | Needed for booking visibility |
| `screeners_profile` | Screener master | `id`, `airtable_id` | Stable |
| `users` | Internal user/auth metadata | `id`, `airtable_id`, `role`, `vendor_id`, `screener_profile_id` | Still contains plaintext password |

### 2.2 Actual live join paths to use in APIs

Use these join paths exactly as they exist today:

- `screenings.application_id -> applications_id.id`
- `screenings.candidate_id -> profiles_database.id`
- `screenings.room_id -> rooms.id`
- `applications_id.openings_id -> openings.id`
- `applications_id.profiles_database_id -> profiles_database.id`
- `applications_id.vendor_id -> vendor_master.id`
- `applications_id.form_filled_by_id -> screeners_profile.id`
- `openings.client_id -> client_master.id`
- `openings.client_department_id -> client_department.id`
- `openings.id -> openings_locations_openings.openings_id -> locations.id`
- `rooms.id -> room_vendors.room_id -> vendor_master.id`
- `documents_master.id -> documents_master_client_departments.document_master_id -> client_department.id`

### 2.3 Important naming reality

Do not assume the idealized column names from the design doc are already live.

Use the live names:

- `applications_id.openings_id`
- `applications_id.profiles_database_id`
- `users.role`
- `openings.max_ctc_lpa`
- `openings.partner_recruitment_fee_pct`
- `rooms.room_name`

Do not assume these names exist live:

- `applications_id.opening_id`
- `applications_id.candidate_id`
- `users.type`
- `openings.ctc_lpa_limit_eg_14`
- `openings.partner_recruitment_fees_of_annual_ctc`
- `openings_exclusive_vendors`

## 3. Schema Change Recommendations

### 3.1 P0 changes to do before or alongside API migration

These are the most important schema fixes still pending.

#### 1. Add uniqueness only after dedupe

Current duplicate counts in live PG:

- duplicate `(openings_id, profiles_database_id, vendor_id)` in `applications_id`: `476`
- duplicate `slot_key` in `screenings`: `334`
- duplicate `event_id` in `screenings`: `2`
- duplicate `candidate_id` in `profiles_database`: `23`
- duplicate `username` in `users`: `3`

Recommended actions:

- dedupe `applications_id`, then add:
  - `UNIQUE (openings_id, profiles_database_id, vendor_id)`
- dedupe `screenings.slot_key`, then add:
  - `UNIQUE (slot_key) WHERE slot_key IS NOT NULL`
- dedupe `screenings.event_id`, then add:
  - `UNIQUE (event_id) WHERE event_id IS NOT NULL`
- dedupe `profiles_database.candidate_id`, then add:
  - `UNIQUE (candidate_id) WHERE candidate_id IS NOT NULL`
- dedupe `users.username`, then add:
  - `UNIQUE (username) WHERE username IS NOT NULL`

#### 2. Remove plaintext password dependency

Current live risk:

- `users` with non-empty password: `61`
- `vendor_master` with non-empty password: `67`

Recommended action:

- keep these columns only until login APIs are switched
- then move auth to Supabase Auth or at minimum hashed credentials
- do not build any new feature on these plaintext columns

#### 3. Add missing performance indexes for join-heavy routes

Recommended indexes:

- `applications_id(profiles_database_id)`
- `screenings(application_id)`
- `screenings(candidate_id)`
- `screenings(vendor_id)`
- `openings(opening_id)`
- `users(username)`
- `rooms(room_name)`
- `documents_master(name)`

Reason:

- foreign keys do not automatically get indexes in PostgreSQL
- the Day 1 and Day 2 APIs will join heavily on these columns

#### 4. Keep current table names, do not rename now

Recommended rule:

- keep `profiles_database`
- keep `applications_id`
- keep `screenings`

Reason:

- sync is already aligned to those names
- current app code and migration helpers can be switched faster if we preserve table names
- we can introduce helper functions or views later if we want cleaner names

### 3.2 P1 changes that are useful but not blockers

#### 1. Add compatibility view or typed query layer

Because the live schema still uses legacy-but-stable names, it would help to add a small query layer or SQL views that expose API-friendly aliases:

- `applications_id.openings_id AS opening_id`
- `applications_id.profiles_database_id AS candidate_profile_id`
- `rooms.room_name AS name`

This is optional, but it reduces repeated mapping logic inside API routes.

#### 2. Normalize opening/vendor exclusivity naming

Current situation:

- live PG has `vendor_openings`
- some migration helper code expects `openings_exclusive_vendors`

Recommendation:

- standardize code to use `vendor_openings`
- do not create a second junction table with the same meaning

#### 3. Consider `(room_id, scheduled_at)` uniqueness after dedupe

Recommended eventual booking guard:

- `UNIQUE (room_id, scheduled_at) WHERE room_id IS NOT NULL AND scheduled_at IS NOT NULL`

Reason:

- `slot_key` protects app identity
- `(room_id, scheduled_at)` protects real room double-booking

## 4. Migration Branch Status

The `migration` branch has already started some PG migration work, but it is not ready to ship as-is.

Files already started there:

- [app/api/fetchOpenings/route.ts](/Users/himanshup/Expo/XPO-ATS/app/api/fetchOpenings/route.ts)
- [app/api/extension/fetchOpenings/route.ts](/Users/himanshup/Expo/XPO-ATS/app/api/extension/fetchOpenings/route.ts)
- [app/api/screenersDetails/route.ts](/Users/himanshup/Expo/XPO-ATS/app/api/screenersDetails/route.ts)
- [app/api/auth/login/route.ts](/Users/himanshup/Expo/XPO-ATS/app/api/auth/login/route.ts)
- [app/api/admin/login/route.ts](/Users/himanshup/Expo/XPO-ATS/app/api/admin/login/route.ts)
- [lib/supabase/openings.ts](/Users/himanshup/Expo/XPO-ATS/lib/supabase/openings.ts)

Why it is “started but not ready”:

- helper expects `users.type`, but live PG has `users.role`
- helper expects `openings.ctc_lpa_limit_eg_14`, but live PG has `openings.max_ctc_lpa`
- helper expects `openings.partner_recruitment_fees_of_annual_ctc`, but live PG has `openings.partner_recruitment_fee_pct`
- helper expects `openings_exclusive_vendors`, but live PG uses `vendor_openings`

Conclusion:

- reuse the direction from the `migration` branch
- do not merge it directly without correcting the shared PG helper first

## 5. API Migration Inventory

### 5.1 Day 1 routes

These are the best first-wave routes because they are simple reads or straightforward joins.

| Route | Current | Target PG tables | Exact join path | Difficulty | Why Day 1 |
|---|---|---|---|---|---|
| `/api/screenersDetails` | Airtable | `screeners_profile` | none | Easy | Simple filtered select |
| `/api/locations` | Airtable | `locations` | none | Easy | Simple lookup route |
| `/api/fetchOpenings` | Airtable | `openings`, `vendor_master`, `client_department`, `openings_locations_openings`, `locations`, `vendor_openings` | vendor auth -> `vendor_master`; `openings.client_department_id -> client_department.id`; `openings.id -> openings_locations_openings.openings_id -> locations.id`; optional vendor visibility from `vendor_openings` | Medium | Migration branch already started |
| `/api/extension/fetchOpenings` | Airtable | `openings`, `client_department`, `openings_locations_openings`, `locations` | `openings.client_department_id -> client_department.id`; `openings.id -> openings_locations_openings.openings_id -> locations.id` | Easy-Medium | Read-only version of openings |
| `/api/screening-opening` | Airtable | `screenings`, `applications_id`, `openings` | `screenings.application_id -> applications_id.id -> applications_id.openings_id -> openings.id` | Easy | Very clean PG join |
| `/api/fetchProfile/[candidateId]` | Airtable | `profiles_database` | lookup by `candidate_id` | Easy | Single-table candidate fetch |
| `/api/pendingScreenings` | Airtable | `screenings`, `applications_id`, `profiles_database` | `screenings.application_id -> applications_id.id`; `screenings.candidate_id -> profiles_database.id` | Easy-Medium | Simple screening feed |
| `/api/screening-stats-by-day` | Airtable | `screenings` | none | Easy | Pure aggregate by date/status |
| `/api/applicationList` | Airtable | `applications_id`, `profiles_database`, `openings`, `locations` | `applications_id.profiles_database_id -> profiles_database.id`; `applications_id.openings_id -> openings.id`; `profiles_database.location_id -> locations.id` | Medium | Flattened read-only list |

### 5.2 Day 2 routes

These are still very achievable, but they need more joins or auth adjustment.

| Route | Current | Target PG tables | Exact join path | Difficulty | Why Day 2 |
|---|---|---|---|---|---|
| `/api/dashboard` | Airtable | `screenings`, `applications_id`, `openings`, `vendor_master`, `client_department` | `screenings.application_id -> applications_id.id -> applications_id.openings_id -> openings.id`; `applications_id.vendor_id -> vendor_master.id`; `openings.client_department_id -> client_department.id` | Medium-Hard | Needs PG aggregation rewrite |
| `/api/fetchCandidateByVendor` | Airtable | `profiles_database`, `applications_id`, `vendor_master`, `openings` | either `profiles_database.vendors_id -> vendor_master.id` or `applications_id.vendor_id -> vendor_master.id`, depending on business meaning | Medium | Needs one business-rule confirmation |
| `/api/admin/screeners` | Airtable | `screeners_profile`, `users` | `users.screener_profile_id -> screeners_profile.id` or `users.screener_link` equivalent | Medium | GET is easy, write path is transitional |
| `/api/meetings` | Airtable | `screenings`, `applications_id`, `profiles_database`, `openings`, `vendor_master` | `screenings.application_id -> applications_id.id`; then vendor/profile/opening joins | Medium | Vendor-filtered meeting feed |
| `/api/auth/login` | Airtable | `vendor_master` | lookup by vendor credentials | Medium | Small route, but depends on auth transition |
| `/api/admin/login` | Airtable | `users`, optional `vendor_master` | `users.vendor_id -> vendor_master.id` if vendor context is needed | Medium | Must use `users.role`, not `users.type` |

### 5.3 Later routes

These are not the best first-wave targets because they are workflow-heavy or still use Airtable behavior that must be redesigned, not merely translated.

| Route | Current | Target PG tables | Difficulty | Why later |
|---|---|---|---|---|
| `/api/screeningList` | Mixed, mostly Airtable | `screenings`, `applications_id`, `profiles_database`, `openings`, `vendor_master`, skill tables | Hard | Largest Airtable-dependent route |
| `/api/book-slot` | Mixed | `screenings`, `applications_id`, `profiles_database`, `rooms`, `room_vendors`, `vendor_master` | Hard | Booking rules + Google Calendar side effects |
| `/api/bookings` | Airtable | `rooms`, `screenings`, `room_vendors` | Hard | Room grid + status overlay logic |
| `/api/available-slots` | Airtable | `rooms`, `screenings`, `room_vendors` | Hard | Generated schedule math + room visibility |
| `/api/submit-recruitment` | Airtable | `profiles_database`, `applications_id`, `openings`, `vendor_master` | Hard | Multi-step write + duplicate handling |
| `/api/submit-c2c` | Airtable | `profiles_database`, `applications_id`, `openings`, `vendor_master` | Hard | Multi-step write + validation |
| `/api/cancelScreening` | Airtable | `screenings` | Hard | Workflow side effects |
| `/api/submitScreeningReport` | Airtable | `screenings`, `applications_id` | Hard | Write path and report ownership |
| `/api/generateScreenerAudit` | Airtable | `screenings`, `applications_id` | Hard | Still tied to Airtable workflow |
| `/api/generate_post_Screeningaudit_report` | Airtable | `screenings`, `applications_id`, `profiles_database` | Hard | Heavy workflow + writes |

## 6. Recommended Execution Order

### Today

Target: switch the first 8 to 9 PG-backed read APIs.

Recommended order:

1. `screenersDetails`
2. `locations`
3. fix shared openings/login helper on migration branch
4. `fetchOpenings`
5. `extension/fetchOpenings`
6. `screening-opening`
7. `fetchProfile/[candidateId]`
8. `pendingScreenings`
9. `screening-stats-by-day`
10. `applicationList`

### Tomorrow

Target: finish the next 5 to 6 moderate routes.

Recommended order:

1. `dashboard`
2. `fetchCandidateByVendor`
3. `admin/screeners`
4. `meetings`
5. `auth/login`
6. `admin/login`

This gets the practical ATS API migration to roughly the 60-70% mark.

## 7. Immediate Action Items

### Schema

- dedupe and constrain `applications_id`
- dedupe and constrain `screenings.slot_key`
- dedupe and constrain `screenings.event_id`
- dedupe and constrain `profiles_database.candidate_id`
- dedupe and constrain `users.username`
- add the missing join indexes listed above

### Code

- fix [lib/supabase/openings.ts](/Users/himanshup/Expo/XPO-ATS/lib/supabase/openings.ts) to match live PG column and table names
- then reuse that helper for:
  - `fetchOpenings`
  - `extension/fetchOpenings`
  - `auth/login`
  - `admin/login`

### Ground rule for new APIs

For all new PG routes:

- use live PG names, not idealized future names
- prefer explicit joins over Airtable-style lookup assumptions
- do not build new logic on plaintext passwords
- do not rename core tables during this API migration phase

