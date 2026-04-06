-- Merge remaining referenced duplicate application rows.
-- Canonical row selection:
-- 1. Prefer a non-"Candidate Created" status when present
-- 2. More linked screenings
-- 3. More linked screener assignments
-- 4. Newer created_at
-- 5. Newer id
--
-- For each duplicate (profiles_database_id, openings_id, vendor_id) group:
-- - move screenings.application_id to the canonical row
-- - move screener_assignments.application_id to the canonical row
-- - delete the losing application row

with application_usage as (
  select
    a.id,
    a.profiles_database_id,
    a.openings_id,
    a.vendor_id,
    a.created_at,
    a.status,
    count(distinct s.id) as screening_refs,
    count(sa.application_id) as assignment_refs
  from public.applications_id a
  left join public.screenings s on s.application_id = a.id
  left join public.screener_assignments sa on sa.application_id = a.id
  where a.profiles_database_id is not null
    and a.openings_id is not null
    and a.vendor_id is not null
  group by
    a.id,
    a.profiles_database_id,
    a.openings_id,
    a.vendor_id,
    a.created_at,
    a.status
),
ranked as (
  select
    *,
    row_number() over (
      partition by profiles_database_id, openings_id, vendor_id
      order by
        case when coalesce(status, '') = 'Candidate Created' then 0 else 1 end desc,
        screening_refs desc,
        assignment_refs desc,
        created_at desc,
        id desc
    ) as canonical_rank,
    count(*) over (
      partition by profiles_database_id, openings_id, vendor_id
    ) as group_rows
  from application_usage
),
merge_map as (
  select
    loser.id as loser_id,
    winner.id as winner_id
  from ranked loser
  join ranked winner
    on winner.profiles_database_id = loser.profiles_database_id
   and winner.openings_id = loser.openings_id
   and winner.vendor_id = loser.vendor_id
   and winner.canonical_rank = 1
  where loser.group_rows > 1
    and loser.canonical_rank > 1
),
move_screenings as (
  update public.screenings s
  set application_id = m.winner_id
  from merge_map m
  where s.application_id = m.loser_id
  returning s.id
),
move_assignments as (
  update public.screener_assignments sa
  set application_id = m.winner_id
  from merge_map m
  where sa.application_id = m.loser_id
  returning sa.application_id
)
delete from public.applications_id a
using merge_map m
where a.id = m.loser_id;
