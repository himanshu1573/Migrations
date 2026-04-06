create table if not exists public.screening_slot_overrides (
  id uuid not null default extensions.uuid_generate_v4(),
  airtable_id text not null,
  room_id uuid null,
  date_time timestamp with time zone null,
  status text null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint screening_slot_overrides_pkey primary key (id),
  constraint screening_slot_overrides_airtable_id_key unique (airtable_id),
  constraint screening_slot_overrides_room_id_fkey
    foreign key (room_id) references public.rooms(id) on delete set null,
  constraint screening_slot_overrides_status_check
    check (status in ('cancelled', 'reopened'))
) tablespace pg_default;

create index if not exists idx_screening_slot_overrides_date_time
  on public.screening_slot_overrides using btree (date_time);

create index if not exists idx_screening_slot_overrides_room_id_date_time
  on public.screening_slot_overrides using btree (room_id, date_time);

drop trigger if exists trg_screening_slot_overrides_updated_at on public.screening_slot_overrides;

create trigger trg_screening_slot_overrides_updated_at
before update on public.screening_slot_overrides
for each row
execute function update_updated_at_column();
