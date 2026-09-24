-- =============================================================================
-- Ventrafin — Realtime (ARCHITECTURE.md § 1)
--
-- Add the tables both apps subscribe to for cross-device sync to Supabase's
-- `supabase_realtime` publication. Realtime evaluates the SELECT RLS policies
-- per subscriber, so each user only receives changes to their own rows.
--
-- Note for client code: with RLS enabled, DELETE events carry only the
-- primary key (`old_record.id`), not the full old row. Clients should remove
-- rows by id.
-- =============================================================================

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach t in array array['transactions', 'accounts', 'recurring_bills']
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
