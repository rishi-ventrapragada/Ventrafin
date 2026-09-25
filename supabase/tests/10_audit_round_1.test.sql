-- Audit round 1: archiving accounts and categories, adding them by hand, and
-- the privilege clean-up (private functions, anon default privileges).
-- Runs as a signed-in user, through RLS, exactly as the apps will.
begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

-- ===========================================================================
-- Privileges (as postgres)
-- ===========================================================================
select is(
  (select count(*)::int
   from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.pronamespace = 'private'::regnamespace
     and a.privilege_type = 'EXECUTE'
     and a.grantee in (0, 'anon'::regrole)),
  0,
  'no function in private is executable by PUBLIC or anon'
);

select ok(
  has_function_privilege('authenticated', 'private.local_today()', 'execute')
  and has_function_privilege('authenticated', 'private.normalize_text(text)', 'execute'),
  'authenticated keeps the helpers its column defaults and triggers call'
);

select is(
  (select count(*)::int
   from pg_default_acl d, aclexplode(d.defaclacl) a
   where d.defaclrole = 'postgres'::regrole
     and d.defaclnamespace = 'public'::regnamespace
     and a.grantee = 'anon'::regrole),
  0,
  'postgres has no default privileges for anon on new public tables, sequences or functions'
);

-- A table and function created later (as postgres) are not reachable by anon.
create table public.zz_anon_probe (id int);
create function public.zz_anon_probe_fn() returns int language sql as $$ select 1 $$;
select ok(
  not has_table_privilege('anon', 'public.zz_anon_probe', 'SELECT, INSERT, UPDATE, DELETE'),
  'a table created by a later migration gives anon nothing'
);
-- (PUBLIC still gets EXECUTE on new functions by PostgreSQL's own default, which
-- is why every public function keeps its explicit `revoke … from public, anon`.)
select is(
  (select count(*)::int
   from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.oid = 'public.zz_anon_probe_fn()'::regprocedure and a.grantee = 'anon'::regrole),
  0,
  'a function created by a later migration has no grant to anon'
);

select ok(
  not (select rolcanlogin from pg_roles where rolname = 'ventrafin_backup'),
  'the backup role cannot log in while backups are off (D28)'
);

select col_not_null('public', 'accounts', 'archived', 'accounts.archived is not null');
select col_default_is('public', 'accounts', 'archived', 'false', 'accounts.archived defaults to false');

-- ===========================================================================
-- As a signed-in user
-- ===========================================================================
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

-- Accounts: add, rename, archive
insert into public.accounts (name, type) values ('SBI Savings', 'bank');
select is(
  (select archived from public.accounts where name = 'SBI Savings'),
  false,
  'a new account starts active'
);

update public.accounts set name = 'SBI Salary' where name = 'SBI Savings';
select is((select count(*)::int from public.accounts where name = 'SBI Salary'), 1, 'an account can be renamed');

select throws_ok(
  $$ update public.accounts set name = 'cash' where name = 'SBI Salary' $$,
  '23505', null,
  'an account cannot take another account''s name (case-insensitive)'
);

update public.accounts set archived = true where name in ('Bank', 'Credit Card', 'SBI Salary');
select is(
  (select array_agg(name order by name) from public.accounts where not archived),
  array['Cash'],
  'accounts can be archived while another stays active'
);

select throws_ok(
  $$ update public.accounts set archived = true where name = 'Cash' $$,
  '23514', 'Keep at least one active account.',
  'the last active account cannot be archived'
);

insert into public.transactions (amount_paise, description, account_id, type)
select 5000, 'old entry', id, 'expense' from public.accounts where name = 'Bank';
select is(
  (select count(*)::int from public.transactions t join public.accounts a on a.id = t.account_id where a.name = 'Bank'),
  1,
  'an archived account still resolves on transactions that use it'
);

update public.accounts set archived = false where name = 'Bank';
update public.accounts set archived = true where name = 'Cash';
select is(
  (select array_agg(name order by name) from public.accounts where not archived),
  array['Bank'],
  'restoring one account lets the other be archived'
);

-- Categories: add by hand, archive, restore
insert into public.categories (name, kind) values ('Kirana', 'expense');
select isnt(
  (select icon from public.categories where name = 'Kirana'),
  null,
  'a category added by hand gets a default icon and colour'
);

update public.categories set archived = true where name = 'Food' and kind = 'expense';
insert into public.transactions (amount_paise, description, account_id, type)
select 20000, 'Swiggy dinner', id, 'expense' from public.accounts where name = 'Bank';
select is(
  (select c.name from public.transactions t left join public.categories c on c.id = t.category_id
   where t.description = 'Swiggy dinner'),
  null,
  'an archived category is not chosen by auto-categorization'
);

-- Bob cannot archive Alice's accounts.
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
update public.accounts set archived = false
where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
select is(
  (select count(*)::int from public.accounts where archived),
  3,
  'another user cannot restore (or archive) someone else''s accounts'
);

select * from finish();
rollback;
