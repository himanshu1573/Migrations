-- Safe duplicate cleanup for applications_id.
-- Keeps the strongest row per (profiles_database_id, openings_id, vendor_id)
-- and removes only duplicate rows with zero linked screenings.

with application_usage as (
  select
    a.id,
    a.airtable_id,
    a.profiles_database_id,
    a.openings_id,
    a.vendor_id,
    a.created_at,
    count(distinct s.id) as screening_refs
  from public.applications_id a
  left join public.screenings s on s.application_id = a.id
  where a.profiles_database_id is not null
    and a.openings_id is not null
    and a.vendor_id is not null
  group by
    a.id,
    a.airtable_id,
    a.profiles_database_id,
    a.openings_id,
    a.vendor_id,
    a.created_at
),
ranked as (
  select
    *,
    row_number() over (
      partition by profiles_database_id, openings_id, vendor_id
      order by screening_refs desc, created_at desc, id desc
    ) as keep_rank,
    count(*) over (
      partition by profiles_database_id, openings_id, vendor_id
    ) as group_rows
  from application_usage
),
delete_candidates as (
  select id
  from ranked
  where group_rows > 1
    and keep_rank > 1
    and screening_refs = 0
)
delete from public.applications_id a
using delete_candidates d
where a.id = d.id;
