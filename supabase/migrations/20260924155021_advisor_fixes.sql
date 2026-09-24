-- =============================================================================
-- Ventrafin — fixes for Supabase advisor findings after the initial deploy
--
-- 1. [security WARN 0028/0029] public.rls_auto_enable() is Supabase's own
--    "automatically enable RLS on new tables" event-trigger function (created
--    with the project, not by our migrations). Keep it — it is a useful safety
--    net — but it is SECURITY DEFINER in the API-exposed schema with EXECUTE
--    granted to anon/authenticated. Event triggers do not need those grants,
--    so revoke them. The postgres owner (which runs migrations) keeps EXECUTE.
--
-- 2. [security INFO 0008] private.builtin_* have RLS enabled with no policies.
--    That is intentional (deny-all; only SECURITY DEFINER functions read them).
--    Make the intent explicit with restrictive deny-all policies for the API
--    roles. These grant nothing; the table owner still bypasses RLS.
--
-- 3. [performance INFO 0001] cover the builtin_keywords -> builtin_categories
--    foreign key with an index.
--
-- Not changed: "unused_index" notices on the app tables. Those indexes back
-- the apps' main access paths and are only unused because no data exists yet.
-- =============================================================================

-- 1.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- 2.
create policy "no client access" on private.builtin_categories
  as restrictive for all to anon, authenticated
  using (false) with check (false);

create policy "no client access" on private.builtin_keywords
  as restrictive for all to anon, authenticated
  using (false) with check (false);

-- 3.
create index builtin_keywords_category_idx on private.builtin_keywords (category_name, category_kind);
