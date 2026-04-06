create or replace function public.create_screening_booking(
  p_candidate_id uuid,
  p_application_id uuid,
  p_vendor_id uuid,
  p_room_id uuid,
  p_scheduled_at timestamp with time zone,
  p_slot_key text
)
returns table (
  screening_id uuid,
  screening_airtable_id text,
  candidate_uuid uuid,
  candidate_unique_id text,
  room_uuid uuid,
  room_airtable_id text,
  scheduled_at timestamp with time zone,
  deduped boolean,
  created boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_candidate_unique_id text;
  v_room_airtable_id text;
  v_existing record;
begin
  if p_candidate_id is null
    or p_application_id is null
    or p_vendor_id is null
    or p_room_id is null
    or p_scheduled_at is null
    or p_slot_key is null
    or btrim(p_slot_key) = '' then
    raise exception 'MISSING_REQUIRED_BOOKING_REFS';
  end if;

  select candidate_id
  into v_candidate_unique_id
  from public.profiles_database
  where id = p_candidate_id
  limit 1;

  if v_candidate_unique_id is null then
    raise exception 'CANDIDATE_NOT_FOUND';
  end if;

  select airtable_id
  into v_room_airtable_id
  from public.rooms
  where id = p_room_id
  limit 1;

  if v_room_airtable_id is null then
    raise exception 'ROOM_NOT_FOUND';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      coalesce(p_application_id::text, '') || '|' ||
      coalesce(p_candidate_id::text, '') || '|' ||
      to_char(date_trunc('minute', p_scheduled_at at time zone 'utc'), 'YYYY-MM-DD"T"HH24:MI')
    )::bigint
  );

  perform pg_advisory_xact_lock(
    hashtext(
      coalesce(p_room_id::text, '') || '|' ||
      to_char(date_trunc('minute', p_scheduled_at at time zone 'utc'), 'YYYY-MM-DD"T"HH24:MI')
    )::bigint
  );

  select
    s.id,
    s.airtable_id,
    s.scheduled_at
  into v_existing
  from public.screenings s
  where s.application_id = p_application_id
    and s.candidate_id = p_candidate_id
    and date_trunc('minute', s.scheduled_at) = date_trunc('minute', p_scheduled_at)
  order by s.created_at asc nulls first, s.id asc
  limit 1;

  if found then
    return query
    select
      v_existing.id,
      v_existing.airtable_id,
      p_candidate_id,
      v_candidate_unique_id,
      p_room_id,
      v_room_airtable_id,
      v_existing.scheduled_at,
      true,
      false;
    return;
  end if;

  if exists (
    select 1
    from public.screenings s
    where s.slot_key = p_slot_key
       or (
         s.room_id = p_room_id
         and date_trunc('minute', s.scheduled_at) = date_trunc('minute', p_scheduled_at)
       )
  ) then
    raise exception 'SLOT_TAKEN';
  end if;

  insert into public.screenings (
    candidate_id,
    vendor_id,
    application_id,
    room_id,
    scheduled_at,
    slot_key
  )
  values (
    p_candidate_id,
    p_vendor_id,
    p_application_id,
    p_room_id,
    p_scheduled_at,
    p_slot_key
  )
  returning id, airtable_id, scheduled_at
  into v_existing;

  return query
  select
    v_existing.id,
    v_existing.airtable_id,
    p_candidate_id,
    v_candidate_unique_id,
    p_room_id,
    v_room_airtable_id,
    v_existing.scheduled_at,
    false,
    true;
end;
$$;

grant execute on function public.create_screening_booking(
  uuid,
  uuid,
  uuid,
  uuid,
  timestamp with time zone,
  text
) to anon, authenticated, service_role;
