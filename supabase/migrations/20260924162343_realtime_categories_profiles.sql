-- =============================================================================
-- Ventrafin — Realtime on categories and profiles
--
-- categories: auto-categorization can create a category from either device;
--             pickers and lists on the other device should see it immediately.
-- profiles:   settings (theme, reminder toggles) changed on one device should
--             reach the other without a refresh (PRD § 4.8).
--
-- Same rules as the first realtime migration: Realtime applies the SELECT RLS
-- policies per subscriber, so each user only receives their own rows.
-- =============================================================================

do $$
declare
  t text;
begin
  foreach t in array array['categories', 'profiles']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end
$$;
