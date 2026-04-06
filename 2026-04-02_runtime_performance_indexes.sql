CREATE INDEX IF NOT EXISTS idx_screenings_application_id
  ON public.screenings (application_id);

CREATE INDEX IF NOT EXISTS idx_screenings_candidate_id
  ON public.screenings (candidate_id);

CREATE INDEX IF NOT EXISTS idx_screenings_vendor_id
  ON public.screenings (vendor_id);

CREATE INDEX IF NOT EXISTS idx_applications_id_profiles_database_id
  ON public.applications_id (profiles_database_id);

CREATE INDEX IF NOT EXISTS idx_openings_opening_id
  ON public.openings (opening_id);

CREATE INDEX IF NOT EXISTS idx_users_username
  ON public.users (username);

CREATE INDEX IF NOT EXISTS idx_rooms_room_name
  ON public.rooms (room_name);
