SELECT 'openings' as table_name, count(*) FROM openings
UNION ALL
SELECT 'profiles_database', count(*) FROM profiles_database
UNION ALL
SELECT 'applications_id', count(*) FROM applications_id
UNION ALL
SELECT 'screenings', count(*) FROM screenings
UNION ALL
SELECT 'selected_candidates', count(*) FROM selected_candidates
UNION ALL
SELECT 'screener_assignments', count(*) FROM screener_assignments
UNION ALL
SELECT 'onboarding_events', count(*) FROM onboarding_events;
