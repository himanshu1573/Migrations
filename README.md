# Migrations

This folder now keeps only the current migration and schema artifacts that still matter.

## Keep

- `xpo-ats-sync-service/`
  - current Airtable -> Postgres sync service
- `2026-03-22_core_ats_safe_normalization.sql`
  - core normalization migration
- `2026-03-24_user_decisions_sync_schema.sql`
  - sync/schema changes aligned to current decisions
- `2026-03-24_phase2_legacy_column_cleanup.sql`
  - legacy-column archive/drop migration
- `2026-03-28_live_pg_cleanup_candidates.sql`
  - conservative cleanup candidates from live DB audit
- `XPO_ATS_FINAL_LIVE_SCHEMA_2026-03-28.md`
  - final live-schema note
- `live_pg_columns_2026-03-28.tsv`
  - extracted live columns
- `live_pg_constraints_2026-03-28.tsv`
  - extracted live constraints
- `live_pg_indexes_2026-03-28.tsv`
  - extracted live indexes
- `live_pg_row_estimates_2026-03-28.tsv`
  - extracted live row counts

## Removed

The older migration stacks and superseded schema-analysis docs were removed so this folder reflects the current path only.
