-- Safe duplicate cleanup for candidate_id CC10229.
-- Keeps the strongest referenced profile row and removes only zero-reference duplicates.

with profile_usage as (
  select
    p.id,
    p.airtable_id,
    p.candidate_id,
    p.created_at,
    count(distinct a.id) as application_refs,
    count(distinct s.id) as screening_refs
  from public.profiles_database p
  left join public.applications_id a on a.profiles_database_id = p.id
  left join public.screenings s on s.candidate_id = p.id
  where p.candidate_id = 'CC10229'
  group by p.id, p.airtable_id, p.candidate_id, p.created_at
),
ranked as (
  select
    *,
    row_number() over (
      partition by candidate_id
      order by application_refs desc, screening_refs desc, created_at desc, id desc
    ) as keep_rank
  from profile_usage
),
delete_candidates as (
  select id
  from ranked
  where keep_rank > 1
    and application_refs = 0
    and screening_refs = 0
)
delete from public.profiles_database p
using delete_candidates d
where p.id = d.id;
