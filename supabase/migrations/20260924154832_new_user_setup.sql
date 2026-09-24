-- =============================================================================
-- Ventrafin — new-user setup (ARCHITECTURE.md § 3 "New-user seeding")
--
--   auth.users INSERT  --trigger-->  public.profiles row
--   public.profiles INSERT --trigger--> starter categories + Cash/Bank/Credit Card
--
-- Both functions are SECURITY DEFINER: the auth.users insert is performed by
-- Supabase's `supabase_auth_admin` role, which has no rights on public tables.
-- They only ever write rows owned by the new user's own id.
-- Seeding is idempotent (ON CONFLICT DO NOTHING against the unique name
-- indexes), so re-running it can never duplicate rows.
-- =============================================================================

create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();


create function private.seed_new_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.categories (owner_id, name, kind, color)
  select new.id, c.name, c.kind, c.color
  from private.builtin_categories c
  where c.is_starter
  order by c.sort_order
  on conflict do nothing;

  insert into public.accounts (owner_id, name, type) values
    (new.id, 'Cash',        'cash'),
    (new.id, 'Bank',        'bank'),
    (new.id, 'Credit Card', 'credit')
  on conflict do nothing;

  return new;
end;
$$;

create trigger profiles_seed_defaults
  after insert on public.profiles
  for each row execute function private.seed_new_profile();


-- Backfill: anyone who signed in before this migration ran gets set up too.
insert into public.profiles (id)
select u.id from auth.users u
on conflict (id) do nothing;
