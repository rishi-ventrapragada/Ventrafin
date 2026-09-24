-- Structural guarantees: RLS everywhere, owner-only policies, no anon access,
-- no privileged functions in the exposed schema, realtime tables published.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

select is_empty(
  $$ select c.relname from pg_class c
     where c.relnamespace in ('public'::regnamespace, 'private'::regnamespace)
       and c.relkind in ('r', 'p') and not c.relrowsecurity $$,
  'every table in public and private has RLS enabled'
);

select set_eq(
  $$ select tablename::text from pg_tables where schemaname = 'public' $$,
  array['profiles', 'accounts', 'categories', 'category_rules', 'transactions', 'recurring_bills'],
  'public contains exactly the six app tables'
);

select set_eq(
  $$ select tablename::text || ':' || cmd from pg_policies where schemaname = 'public' $$,
  array[
    'profiles:SELECT', 'profiles:INSERT', 'profiles:UPDATE',
    'accounts:SELECT', 'accounts:INSERT', 'accounts:UPDATE', 'accounts:DELETE',
    'categories:SELECT', 'categories:INSERT', 'categories:UPDATE', 'categories:DELETE',
    'category_rules:SELECT', 'category_rules:INSERT', 'category_rules:UPDATE', 'category_rules:DELETE',
    'transactions:SELECT', 'transactions:INSERT', 'transactions:UPDATE', 'transactions:DELETE',
    'recurring_bills:SELECT', 'recurring_bills:INSERT', 'recurring_bills:UPDATE', 'recurring_bills:DELETE'
  ],
  'each table has exactly the expected owner policies (profiles: no client delete)'
);

-- Every USING / WITH CHECK expression must be exactly "owner = auth.uid()".
select is_empty(
  $$ with allowed(expr) as (values
       ('(owner_id = ( SELECT auth.uid() AS uid))'),
       ('(id = ( SELECT auth.uid() AS uid))'))
     select tablename, policyname from pg_policies
     where schemaname = 'public'
       and (   coalesce(qual, with_check) is null
            or (qual       is not null and qual       not in (select expr from allowed))
            or (with_check is not null and with_check not in (select expr from allowed))) $$,
  'every policy condition is exactly owner_id/id = auth.uid() (no other access paths)'
);

select is_empty(
  $$ select tablename, policyname from pg_policies
     where schemaname = 'public' and roles <> array['authenticated']::name[] $$,
  'policies apply to the authenticated role only'
);

select is_empty(
  $$ select policyname from pg_policies where schemaname = 'public' and permissive <> 'PERMISSIVE' $$,
  'no restrictive/unusual policies'
);

select is_empty(
  $$ select c.relname from pg_class c
     where c.relnamespace in ('public'::regnamespace, 'private'::regnamespace) and c.relkind = 'r'
       and has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') $$,
  'anon has no privileges on any table'
);

select is_empty(
  $$ select c.relname from pg_class c
     where (c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
            and has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER'))
        or (c.relnamespace = 'private'::regnamespace and c.relkind = 'r'
            and has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')) $$,
  'authenticated: no TRUNCATE/REFERENCES/TRIGGER on app tables, nothing on private tables'
);

-- (Supabase's own rls_auto_enable() event-trigger function is SECURITY DEFINER
-- in public; what matters is that no such function is callable via the API.)
select is_empty(
  $$ select p.oid::regprocedure from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prosecdef
       and (has_function_privilege('anon', p.oid, 'execute')
            or has_function_privilege('authenticated', p.oid, 'execute')) $$,
  'no SECURITY DEFINER function in the API-exposed public schema is callable by anon/authenticated'
);

select ok(
  not has_function_privilege('anon', 'public.get_month_totals(date)', 'execute')
  and not has_function_privilege('anon', 'public.get_month_comparison(date)', 'execute')
  and not has_function_privilege('anon', 'public.get_monthly_category_totals(date, date)', 'execute')
  and has_function_privilege('authenticated', 'public.get_month_totals(date)', 'execute')
  and has_function_privilege('authenticated', 'public.get_month_comparison(date)', 'execute')
  and has_function_privilege('authenticated', 'public.get_monthly_category_totals(date, date)', 'execute'),
  'report functions: executable by authenticated, not by anon'
);

select set_eq(
  $$ select tablename::text from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' $$,
  array['transactions', 'accounts', 'recurring_bills'],
  'realtime publishes transactions, accounts, recurring_bills'
);

set local role authenticated;
select throws_ok(
  $$ select * from private.builtin_keywords $$,
  '42501', null,
  'authenticated cannot read the private keyword table directly'
);
reset role;

select * from finish();
rollback;
