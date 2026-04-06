# XPO ATS PostgreSQL Migration Status

Date: 2026-03-31

## What Is Going On

The ATS PostgreSQL migration is now in a mixed-mode stage:

- PostgreSQL is already the live source for core ATS data such as `openings`, `profiles_database`, `applications_id`, `screenings`, `vendor_master`, and `users`.
- Some API routes were still reading Airtable even though the equivalent data already exists in PostgreSQL.
- A compatibility bridge is still in place for some Airtable-style IDs like `airtable_id` so existing cookies, request params, and UI assumptions do not break during the migration.
- The immediate goal is to move read-heavy APIs first, prove them in production, and leave workflow-heavy write routes for later.

## What Was Completed In This Pass

### Shared PG helper fixes

File: `/Users/himanshup/Expo/XPO-ATS/lib/supabase/openings.ts`

Completed:

- Replaced non-live table `openings_exclusive_vendors` with live PG table `vendor_openings`.
- Fixed exclusivity logic to use boolean `is_exclusive` instead of Airtable-style `'Yes'`.
- Switched opening field mapping to live PG columns:
  - `max_ctc_lpa`
  - `partner_recruitment_fee_pct`
- Fixed admin login to use `users.role` and preserve the existing `type` payload contract for the app.
- Fixed vendor login to return `vendorType`, so `vendor_type` cookie creation works correctly.

### API migrations completed

#### 1. `/api/locations`

File: `/Users/himanshup/Expo/XPO-ATS/app/api/locations/route.ts`

Status: Migrated to PostgreSQL

Notes:

- Reads from PG `locations`.
- Still returns Airtable-style record IDs from `locations.airtable_id` for UI compatibility.

#### 2. `/api/fetchProfile/[candidateId]`

Files:

- `/Users/himanshup/Expo/XPO-ATS/app/api/fetchProfile/[candidateId]/route.ts`
- `/Users/himanshup/Expo/XPO-ATS/lib/supabase/profiles.ts`

Status: Migrated to PostgreSQL

Notes:

- Reads candidate, application, opening, vendor, location, and document context from PG.
- Preserves the existing 27-slot array response shape so current UI and downstream APIs continue to work.
- Resolves preferred location display name from PG while still preserving compatibility IDs where needed.
- Returns opening labels in the historical `openingId-jobTitle` style for compatibility.

#### 3. `/api/screening-opening`

File: `/Users/himanshup/Expo/XPO-ATS/app/api/screening-opening/route.ts`

Status: Migrated to PostgreSQL

Notes:

- Input remains the Airtable screening record ID, but the lookup is now PG-native:
  - `screenings.airtable_id`
  - `screenings.application_id`
  - `applications_id.openings_id`
  - `openings.opening_id`, `openings.job_title`

## Testing And Validation

Validation date: 2026-03-31

### Route checks

Verified successfully:

- `/api/locations` returned HTTP 200 and a PG-backed location list.
- `/api/fetchProfile/10069` returned HTTP 200 from the PG-backed route.
- `/api/screening-opening` returned exact Airtable-matching results for:
  - `recbSk7FoNfwv6uC4` -> `{ openingId: "199", opening: "CME Java Developer Lead" }`
  - `rec0GjrZOUiyKsXj9` -> `{ openingId: "375", opening: "XP QA" }`

### Payload comparison checks

Compared Airtable vs PostgreSQL-backed `fetchProfile` payloads for:

- `10069`
- `10070`
- `10071`

Confirmed matched or intentionally compatible:

- candidate id
- candidate name
- skill/opening label
- notice period
- preferred location display value
- CV link
- bench type
- candidate cost
- vendor id number
- profile Airtable record id
- vendor Airtable id
- vendor PoC email array

Known differences still present:

- PG returns vendor PoC email directly at slot `13`, while Airtable often returned `null` there.
- PG currently returns only the opening ids that exist in the migrated `applications_id` rows. For sample candidates `10069` and `10070`, Airtable still exposes `[26, 174]` while PG currently resolves `[26]`.
- PG currently resolves document types from live `documents_master`, which produced `["Aadhar"]` in the tested samples, while Airtable's older rollup returned a longer repeated list.

Interpretation:

- `/api/locations` is production-safe.
- `/api/screening-opening` is production-safe and route-matched against Airtable.
- `/api/fetchProfile/[candidateId]` is functionally migrated and working, but it still carries a few compatibility differences caused by historical Airtable rollups vs current PG truth.

## APIs Already On PG

Confirmed PG-backed before or during this pass:

- `/api/fetchOpenings`
- `/api/extension/fetchOpenings`
- `/api/auth/login`
- `/api/admin/login`
- `/api/screenersDetails`
- `/api/locations`
- `/api/fetchProfile/[candidateId]`
- `/api/screening-opening`

## Good Next APIs To Migrate

Recommended next order:

1. `/api/pendingScreenings`
2. `/api/screening-stats-by-day`
3. `/api/applicationList`

Why these next:

- read-heavy
- manager-visible
- lower risk than booking/cancellation/report submission workflows

## APIs To Avoid For Now

Postpone until later:

- `/api/available-slots`
- `/api/bookings`
- `/api/book-slot`
- `/api/cancelScreening`
- `/api/submitScreeningReport`
- admin write flows like create/update application and screener management

Reason:

- these involve side effects, scheduling logic, workflow state transitions, and tighter coupling to historical Airtable behavior

## Current Blockers Still Open

- Historical Airtable rollup behavior does not always match current PG truth for multi-opening candidate history.
- Duplicate data still exists in live PG, especially around applications and screenings.
- Important join indexes are still missing on several hot lookup paths.
- Plaintext password storage still exists in `users` and `vendor_master`.
- Some runtime flows still depend on Airtable-style IDs as compatibility keys.

## Manager Summary

As of 2026-03-31, three additional ATS read APIs are now PostgreSQL-backed:

- `/api/locations`
- `/api/fetchProfile/[candidateId]`
- `/api/screening-opening`

The strongest proof point is `/api/screening-opening`, which was tested against Airtable on live sample records and matched exactly. `/api/locations` is clean and low-risk. `/api/fetchProfile/[candidateId]` is now PG-backed and working, with a few remaining compatibility differences caused by older Airtable rollups not yet fully represented in PG.
