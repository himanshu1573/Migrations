# XPO ATS Final Live Schema

Date: 2026-03-28

This note is based on the live PostgreSQL catalog, queried directly from the current `DATABASE_URL`.

Artifacts extracted from the live DB:

- `migrations/live_pg_columns_2026-03-28.tsv`
- `migrations/live_pg_constraints_2026-03-28.tsv`
- `migrations/live_pg_indexes_2026-03-28.tsv`
- `migrations/live_pg_row_estimates_2026-03-28.tsv`

Note:

- The local `pg_dump` client is PostgreSQL 14 while the server is PostgreSQL 17.6, so a raw schema-only dump was not produced from `pg_dump`.
- The inventory above comes from `information_schema`, `pg_constraint`, `pg_indexes`, and `pg_stat_user_tables`, so it is still live-source-of-truth.

## Final Keep Set

These are the tables that should be treated as the live working schema.

### Core ATS tables

| Table | Approx rows | Keep? | Why |
| --- | ---: | --- | --- |
| `vendor_master` | 104 | KEEP | Canonical vendor table |
| `client_master` | 21 | KEEP | Canonical client table |
| `client_department` | 39 | KEEP | Canonical department table |
| `documents_master` | 5 | KEEP | Live synced document master |
| `documents_master_client_departments` | 143 | KEEP | Live M:N mapping |
| `locations` | 14 | KEEP | Lookup table |
| `openings` | 358 | KEEP | Canonical opening table |
| `openings_locations_openings` | 544 | KEEP | Opening-location junction |
| `vendor_openings` | 325 | KEEP | Opening visibility/exclusivity junction |
| `profiles_database` | 11457 | KEEP | Canonical candidate table |
| `applications_id` | 10168 | KEEP | Canonical application table |
| `screenings` | 11462 | KEEP | Canonical screening table |
| `rooms` | 7 | KEEP | Booking room table |
| `room_vendors` | 1 | KEEP | Room visibility junction |
| `screeners_profile` | 83 | KEEP | Screener directory |
| `users` | 62 | KEEP | Live app user table for now |
| `screener_assignments` | 8745 | KEEP | Normalized screener mapping |
| `status_config` | 47 | KEEP | Planned shared status dictionary |

### Product / feature tables

| Table | Approx rows | Keep? | Why |
| --- | ---: | --- | --- |
| `candidate_skill_map` | 15250 | KEEP | Used by app now |
| `skill_master` | 634 | KEEP | Used by app now |
| `skill_level_master` | 4 | KEEP | Used by app now |
| `skill_map` | 584 | KEEP | Used by app now |
| `skill_question` | 47 | KEEP | Used by app now |
| `opening_skill_question` | 40 | KEEP | Used by app now |
| `naukri_folders` | 166 | KEEP | Used by app now |
| `naukri_candidates` | 3692 | KEEP | Used by app now |
| `ranking_jobs` | 2 | KEEP | Used by app now |
| `campaign_trigger` | 4 | KEEP | Used by app now |
| `campaign_subscription` | 3451 | KEEP | Used by app now |
| `openai_call_logs` | 2834 | KEEP | Used by app now |
| `jd_generator_history` | 2 | KEEP | Used by app now |
| `app_tokens` | 1 | KEEP | Used by app now |

## Keep, But Needs Decision

### `onboarding_events`

- Approx rows: `200`
- Status: keep for now
- Reason:
  - it is part of the intended normalized ATS model
  - but live `public` does not currently have a `selected_candidates` table
  - the table also does not have a live FK to `selected_candidates`

Conclusion:

- do not delete it yet
- first decide whether onboarding will stay in PG
- if yes, add/restore the owning `selected_candidates` model and FK path

### `questions` and `difficulties`

- `questions`: `0` rows
- `difficulties`: `4` rows
- Status: likely old question-bank model
- Current app usage appears to be on:
  - `skill_question`
  - `skill_master`
  - `skill_level_master`
  - `opening_skill_question`

Conclusion:

- these are strong delete candidates
- but because `questions` still has FKs to `difficulties` and `skill_master`, treat them as "delete after one last business confirmation"

## Safe Delete Candidates

These are the objects I am comfortable calling out as cleanup candidates from the live DB plus code search.

### 1. Legacy archive tables created by the 2026-03-24 cleanup

These are archive copies, not live working tables:

| Table | Approx rows | Why safe candidate |
| --- | ---: | --- |
| `_legacy_profiles_database_cleanup_20260324` | 11084 | Archive of dropped legacy columns from `profiles_database` |
| `_legacy_applications_id_cleanup_20260324` | 9547 | Archive of dropped legacy columns from `applications_id` |
| `_legacy_screenings_cleanup_20260324` | 11030 | Archive of dropped legacy columns from `screenings` |

These were created by:

- `migrations/2026-03-24_phase2_legacy_column_cleanup.sql`

That file already documents them as archive tables for dropped legacy columns.

Recommendation:

- if you no longer need rollback/archive access inside the live DB, drop these three tables first
- if you want a belt-and-suspenders approach, export them once before dropping

### 2. `skill_master_duplicate`

- Approx rows: `633`
- DB comment: `This is a duplicate of skill_master`
- No app code references were found

Recommendation:

- drop it if the duplicate-skill cleanup exercise is complete

### 3. Likely delete after confirmation

| Table | Approx rows | Why |
| --- | ---: | --- |
| `questions` | 0 | Appears unused; old model |
| `difficulties` | 4 | Appears to exist only for `questions` |

Recommendation:

- drop `questions` first
- then drop `difficulties`

## Not Safe To Delete Yet

Do not delete these yet even if current app usage is partial:

- `vendor_openings`
- `room_vendors`
- `screener_assignments`
- `status_config`
- `onboarding_events`
- `users`
- `screeners_profile`
- `rooms`
- `openings`
- `profiles_database`
- `applications_id`
- `screenings`

Reason:

- they are part of the live sync target schema or the intended final ATS schema
- some are already populated by sync even if app cutover is incomplete

## Important Live Reality

### The app is not yet PG-authoritative for ATS core flows

Current ATS app code still largely reads/writes Airtable for:

- openings
- profiles
- applications
- screenings
- booking
- screener management
- login

So this cleanup should be interpreted as:

- safe DB archival cleanup
- not full ATS PG cutover completion

### Plaintext passwords still exist

These columns still exist and should not be treated as final-state design:

- `vendor_master.password`
- `users.password`

Do not delete them until auth migration is complete, but do not build anything new on them either.

## Final Cleanup Order I Recommend

### Delete now if you are done with archive copies

1. `_legacy_profiles_database_cleanup_20260324`
2. `_legacy_applications_id_cleanup_20260324`
3. `_legacy_screenings_cleanup_20260324`

### Delete next if duplicate-skill cleanup is done

4. `skill_master_duplicate`

### Delete only after final confirmation

5. `questions`
6. `difficulties`

## Final Schema Summary

If you want the final live working schema to be the one we keep going forward, it is:

- ATS core:
  - `vendor_master`
  - `client_master`
  - `client_department`
  - `documents_master`
  - `documents_master_client_departments`
  - `locations`
  - `openings`
  - `openings_locations_openings`
  - `vendor_openings`
  - `profiles_database`
  - `applications_id`
  - `screenings`
  - `rooms`
  - `room_vendors`
  - `screeners_profile`
  - `users`
  - `screener_assignments`
  - `status_config`

- Product/supporting:
  - `candidate_skill_map`
  - `skill_master`
  - `skill_level_master`
  - `skill_map`
  - `skill_question`
  - `opening_skill_question`
  - `naukri_folders`
  - `naukri_candidates`
  - `ranking_jobs`
  - `campaign_trigger`
  - `campaign_subscription`
  - `openai_call_logs`
  - `jd_generator_history`
  - `app_tokens`

- Needs separate decision:
  - `onboarding_events`
  - `questions`
  - `difficulties`

- Cleanup leftovers:
  - `_legacy_profiles_database_cleanup_20260324`
  - `_legacy_applications_id_cleanup_20260324`
  - `_legacy_screenings_cleanup_20260324`
  - `skill_master_duplicate`
