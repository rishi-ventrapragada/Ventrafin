-- =============================================================================
-- Ventrafin — Row Level Security (ARCHITECTURE.md § 4)
--
-- Every table: RLS on, owner-only policies, no admin role, no bypass.
-- Admin access exists only via the Supabase dashboard (project owner),
-- never through either client app.
--
-- Hardening beyond § 4:
--   * Policies target `authenticated` only; `anon` gets no table privileges
--     at all (Supabase grants ALL to anon/authenticated by default).
--   * authenticated gets only SELECT/INSERT/UPDATE/DELETE — not TRUNCATE,
--     REFERENCES or TRIGGER, which Supabase's default "ALL" would include.
--   * UPDATE policies carry an explicit WITH CHECK so a row can't be
--     re-assigned to another owner.
--   * auth.uid() is wrapped in (select ...) so Postgres evaluates it once per
--     statement instead of once per row (Supabase performance guidance).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Table privileges
-- -----------------------------------------------------------------------------
revoke all on table
  public.profiles, public.accounts, public.categories,
  public.category_rules, public.transactions, public.recurring_bills
from anon, authenticated;

grant select, insert, update, delete on table
  public.accounts, public.categories, public.category_rules,
  public.transactions, public.recurring_bills
to authenticated;

-- A profile's lifecycle follows auth.users (created by the signup trigger,
-- removed by ON DELETE CASCADE), so clients cannot delete it.
grant select, insert, update on table public.profiles to authenticated;


-- -----------------------------------------------------------------------------
-- profiles (keyed by id, which is the auth user id)
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;

create policy "owner can select own rows" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy "owner can insert own rows" on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

create policy "owner can update own rows" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));


-- -----------------------------------------------------------------------------
-- All owner_id tables share the same four policies.
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['accounts', 'categories', 'category_rules', 'transactions', 'recurring_bills']
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format($p$
      create policy "owner can select own rows" on public.%I
        for select to authenticated
        using (owner_id = (select auth.uid()))
    $p$, t);

    execute format($p$
      create policy "owner can insert own rows" on public.%I
        for insert to authenticated
        with check (owner_id = (select auth.uid()))
    $p$, t);

    execute format($p$
      create policy "owner can update own rows" on public.%I
        for update to authenticated
        using (owner_id = (select auth.uid()))
        with check (owner_id = (select auth.uid()))
    $p$, t);

    execute format($p$
      create policy "owner can delete own rows" on public.%I
        for delete to authenticated
        using (owner_id = (select auth.uid()))
    $p$, t);
  end loop;
end
$$;
