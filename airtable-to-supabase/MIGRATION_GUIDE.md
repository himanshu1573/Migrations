# Airtable → Supabase Migration Guide

> Update note: this guide describes the older broader migration model.
> Current project direction now removes `prompts`, `interview_feedback`,
> `interview_rounds`, and `profiles_database.vendor_id` from the target PG schema.
> Use the latest live schema snapshot and current app migrations for planning.

## 📁 Project Structure

```
airtable-to-supabase/
├── .env                    # Environment variables (ADD YOUR DB PASSWORD!)
├── generate_schema.js      # Generates supabase_schema.sql from schema4.json
├── migrate_data.js         # Fetches Airtable data → imports to Supabase
├── supabase_schema.sql     # Generated DDL SQL (run this FIRST in Supabase)
└── migration_log.txt       # Generated after migration run
```

---

## 🚀 Step-by-Step Migration Process

### Step 1: Configure Your Environment

Edit `.env` and replace `[YOUR-PASSWORD]` with your Supabase database password:

```
DATABASE_URL=postgresql://postgres.qurjkxotolzqmwjjaekp:YOUR_ACTUAL_PASSWORD@db.qurjkxotolzqmwjjaekp.supabase.co:5432/postgres
```

> Your Supabase database password was set when you created the project. You can reset it in **Supabase Dashboard → Settings → Database → Database Password**.

### Step 2: Create the Schema in Supabase

**Option A – Supabase SQL Editor (recommended):**
1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Navigate to **SQL Editor**
3. Paste the contents of `supabase_schema.sql`
4. Click **Run**

**Option B – Via CLI:**
```bash
psql "$DATABASE_URL" -f supabase_schema.sql
```

### Step 3: Run the Data Migration

```bash
cd ~/migrations/airtable-to-supabase
node migrate_data.js
```

This will:
- Fetch ALL records from each Airtable table (paginated, rate-limited)
- Upsert them into Supabase
- Resolve foreign keys using the `airtable_id` bridge column
- Log results to `migration_log.txt`

### Step 4: Verify the Migration

```sql
-- Check record counts in Supabase SQL Editor:
SELECT 'client_master' as tbl, count(*) FROM client_master
UNION ALL SELECT 'client_department', count(*) FROM client_department
UNION ALL SELECT 'locations', count(*) FROM locations
UNION ALL SELECT 'vendor_master', count(*) FROM vendor_master
UNION ALL SELECT 'openings', count(*) FROM openings
UNION ALL SELECT 'profiles_database', count(*) FROM profiles_database
UNION ALL SELECT 'applications_id', count(*) FROM applications_id
UNION ALL SELECT 'screenings', count(*) FROM screenings
UNION ALL SELECT 'screeners_profile', count(*) FROM screeners_profile
UNION ALL SELECT 'users', count(*) FROM users
UNION ALL SELECT 'interview_feedback', count(*) FROM interview_feedback
UNION ALL SELECT 'selected_candidates', count(*) FROM selected_candidates;
```

### Step 5: Clean Up Temp Columns

Once migration is verified, remove the temporary bridging columns:

```sql
-- Drop all temp_ columns (run after verification)
ALTER TABLE client_master DROP COLUMN IF EXISTS temp_client_department;
ALTER TABLE client_master DROP COLUMN IF EXISTS temp_openings;
ALTER TABLE client_department DROP COLUMN IF EXISTS temp_openings;
ALTER TABLE client_department DROP COLUMN IF EXISTS temp_client_name;
ALTER TABLE locations DROP COLUMN IF EXISTS temp_openings;
ALTER TABLE locations DROP COLUMN IF EXISTS temp_profiles_database;
ALTER TABLE vendor_master DROP COLUMN IF EXISTS temp_candidates_profile;
ALTER TABLE vendor_master DROP COLUMN IF EXISTS temp_openings;
ALTER TABLE vendor_master DROP COLUMN IF EXISTS temp_screenings;
ALTER TABLE vendor_master DROP COLUMN IF EXISTS temp_profiles_database;
ALTER TABLE vendor_master DROP COLUMN IF EXISTS temp_selected_candidates;
ALTER TABLE openings DROP COLUMN IF EXISTS temp_client_department;
ALTER TABLE openings DROP COLUMN IF EXISTS temp_client;
ALTER TABLE openings DROP COLUMN IF EXISTS temp_applications_id;
ALTER TABLE openings DROP COLUMN IF EXISTS temp_profiles_database;
ALTER TABLE openings DROP COLUMN IF EXISTS temp_cv_sent_to_client;
ALTER TABLE openings DROP COLUMN IF EXISTS temp_cv_sent_to_client_pipeline;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_vendor_id;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_openings_id;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_screener;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_selected_candidates;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_candidate_idprofile_database;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_pid_taken_by;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_profiles_database;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_screenings_2;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_tech_screener;
ALTER TABLE applications_id DROP COLUMN IF EXISTS temp_openings_3;
ALTER TABLE profiles_database DROP COLUMN IF EXISTS temp_location_id;
ALTER TABLE profiles_database DROP COLUMN IF EXISTS temp_applications_id;
ALTER TABLE profiles_database DROP COLUMN IF EXISTS temp_vendors_id;
ALTER TABLE profiles_database DROP COLUMN IF EXISTS temp_screenings;
ALTER TABLE profiles_database DROP COLUMN IF EXISTS temp_openings;
ALTER TABLE profiles_database DROP COLUMN IF EXISTS temp_applications_id_2;
ALTER TABLE screenings DROP COLUMN IF EXISTS temp_candidate_id;
ALTER TABLE screenings DROP COLUMN IF EXISTS temp_vendor_id;
ALTER TABLE screenings DROP COLUMN IF EXISTS temp_application_id;
ALTER TABLE screeners_profile DROP COLUMN IF EXISTS temp_applications_id;
ALTER TABLE screeners_profile DROP COLUMN IF EXISTS temp_applications_id_3;
ALTER TABLE users DROP COLUMN IF EXISTS temp_applications_id;
ALTER TABLE selected_candidates DROP COLUMN IF EXISTS temp_candidate_from_applications;
ALTER TABLE selected_candidates DROP COLUMN IF EXISTS temp_whose_bench;
```

---

## 📊 Schema Summary

| Airtable Table       | Supabase Table        | Fields Kept | Fields Skipped             |
|---------------------|-----------------------|-------------|---------------------------|
| Client Master       | `client_master`       | 11          | 0 (formulas/lookups)       |
| Client Department   | `client_department`   | 12          | 0                          |
| Locations           | `locations`           | 5           | 0                          |
| Vendor Master       | `vendor_master`       | 19          | 8                          |
| Openings            | `openings`            | 27          | 16                         |
| **Candidates Profile** | **SKIPPED**        | —           | *Deprecated table*         |
| Applications_ID     | `applications_id`     | ~45         | 69                         |
| Profiles Database   | `profiles_database`   | ~30         | 32                         |
| Screenings          | `screenings`          | ~20         | 40                         |
| Screeners Profile   | `screeners_profile`   | 3           | 1                          |
| Users               | `users`               | 6           | 3                          |
| Interview Feedback  | `interview_feedback`  | 4           | 2                          |
| Selected Candidates | `selected_candidates` | ~22         | 29                         |

**Total: ~58% of fields removed** (formulas, lookups, rollups, duplicates)

---

## 🔗 Relationship Strategy

### Foreign Keys (One-to-Many)
All `multipleRecordLinks` fields are treated as foreign keys by default:
- Stored as `UUID` columns referencing the parent table's `id`
- Resolved via the `airtable_id` bridge during migration

### Junction Tables (Many-to-Many)
Created for known M:M relationships:
- **`openings_locations_openings`** — Openings ↔ Locations
- **`openings_exclusive_vendors`** — Openings ↔ Vendor Master

### Fields That Were Removed
| Type | Count | Reason |
|------|-------|--------|
| `formula` | ~80 | Compute in app layer or SQL views |
| `multipleLookupValues` | ~150 | Available via JOINs |
| `rollup` | ~10 | Aggregate via SQL queries |
| Duplicates/copies | ~100 | "copy", "copy 2", etc. |
| `aiText` | 1 | Recompute if needed |

---

## ⚠️ Important Considerations

### 1. Airtable Rate Limits
- Airtable API allows **5 requests/second**
- The script adds 250ms delays between pagination requests
- Total migration time depends on data volume (~10-20 minutes)

### 2. Formulas Not Migrated
Airtable formulas like `Ageing`, `Margin`, `Salary Jump` are **NOT** migrated. Options:
- **SQL Views**: Create PostgreSQL views for computed fields
- **Application Layer**: Calculate in your Next.js app
- **Generated Columns**: Use `GENERATED ALWAYS AS` for simple computations

Example SQL view for `Ageing`:
```sql
CREATE VIEW applications_with_ageing AS
SELECT *,
  EXTRACT(DAY FROM NOW() - created_time) AS ageing_days
FROM applications_id;
```

### 3. Supabase Auth
The `users` table contains raw passwords from Airtable. You should:
1. Migrate users to **Supabase Auth** (`auth.users`)
2. Hash passwords properly
3. Set up RLS policies per role

### 4. RLS Policies
The schema enables RLS but doesn't create policies. Add policies like:
```sql
-- Allow service role full access
CREATE POLICY "Service role access" ON openings
  FOR ALL TO service_role USING (true);

-- Allow authenticated users to read
CREATE POLICY "Authenticated read" ON openings
  FOR SELECT TO authenticated USING (true);
```

### 5. Attachments
Airtable attachments (JSONB columns) store metadata only. To fully migrate:
1. Download files from Airtable URLs
2. Upload to **Supabase Storage**
3. Update JSONB with new URLs

---

## 🔧 Regenerating the Schema

If you modify the Airtable schema or want to adjust field mappings:

```bash
node generate_schema.js  # Re-generates supabase_schema.sql
```

The generator will re-read `schema4.json` and produce a fresh SQL file.
