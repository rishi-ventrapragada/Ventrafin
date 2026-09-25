-- (f) Renaming categories: a category keeps its link to the built-in category
-- it stands for, so built-in keywords keep going to it after a rename (and
-- no duplicate "Food" appears). Clients cannot forge or move the link.
-- Rename validation (reserved name, duplicates) is enforced by the table.
-- Runs as a signed-in user, through RLS, exactly as the apps will.
begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

-- add(): an expense from Alice's Cash account, left for auto-categorization.
create function pg_temp.add(p_id uuid, p_description text)
returns void language sql as $$
  insert into public.transactions (id, amount_paise, description, account_id, type)
  select p_id, 10000, p_description, (select id from public.accounts where name = 'Cash'), 'expense';
$$;
-- cat(): "<category name>" plus " [auto]" when the trigger chose it.
create function pg_temp.cat(p_id uuid)
returns text language sql stable as $$
  select coalesce(c.name, '(uncategorized)') || case when t.auto_categorized then ' [auto]' else '' end
  from public.transactions t left join public.categories c on c.id = t.category_id
  where t.id = p_id;
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);


-- ===========================================================================
-- The link
-- ===========================================================================
select is_empty(
  $$ select name from public.categories where builtin_name is distinct from name $$,
  'seeded starter categories stand for the built-in category of the same name'
);

-- ===========================================================================
-- Rename keeps built-in keywords pointed at the category
-- ===========================================================================
update public.categories set name = 'Khana' where name = 'Food' and kind = 'expense';
select pg_temp.add('d0000000-0000-4000-8000-000000000001', 'Swiggy dinner');
select is(pg_temp.cat('d0000000-0000-4000-8000-000000000001'), 'Khana [auto]', 'renamed Food -> Khana: Swiggy still goes to Khana');
select is_empty($$ select 1 from public.categories where name = 'Food' $$, 'no new Food category is created');
select is((select builtin_name from public.categories where name = 'Khana'), 'Food', 'the rename kept the link');

update public.categories set builtin_name = 'Medical' where name = 'Khana';
select is((select builtin_name from public.categories where name = 'Khana'), 'Food', 'clients cannot change the link');

insert into public.categories (name, kind, builtin_name) values ('Kirana', 'expense', 'Groceries');
select is((select builtin_name from public.categories where name = 'Kirana'), null, 'clients cannot set a link on insert');

update public.categories set kind = 'income' where name = 'Other' and kind = 'expense';
select is((select builtin_name from public.categories where name = 'Other'), null, 'changing a category''s kind drops its link');

-- ===========================================================================
-- Auto-created categories are linked too
-- ===========================================================================
select pg_temp.add('d0000000-0000-4000-8000-000000000002', 'Indian Oil petrol pump');
select is((select builtin_name from public.categories where name = 'Fuel'), 'Fuel', 'a category auto-created for a keyword is linked');
update public.categories set name = 'Petrol' where name = 'Fuel';
select pg_temp.add('d0000000-0000-4000-8000-000000000003', 'HPCL petrol');
select is(pg_temp.cat('d0000000-0000-4000-8000-000000000003'), 'Petrol [auto]', 'renamed auto-created category keeps getting its keywords');

-- ===========================================================================
-- A user category renamed TO a built-in name is found by name
-- ===========================================================================
insert into public.categories (name, kind) values ('Phone', 'expense');
update public.categories set name = 'Mobile & Internet' where name = 'Phone';
select pg_temp.add('d0000000-0000-4000-8000-000000000004', 'Jio recharge');
select is(pg_temp.cat('d0000000-0000-4000-8000-000000000004'), 'Mobile & Internet [auto]', 'a category renamed to a built-in name is used by name');
select is((select count(*)::int from public.categories where name = 'Mobile & Internet'), 1, 'no duplicate Mobile & Internet category');

-- ===========================================================================
-- A new category taking the old name, and archived categories
-- ===========================================================================
insert into public.categories (name, kind) values ('Food', 'expense');
select is((select builtin_name from public.categories where name = 'Food'), null, 'a new "Food" is plain: Khana keeps the link');
select pg_temp.add('d0000000-0000-4000-8000-000000000005', 'Zomato lunch');
select is(pg_temp.cat('d0000000-0000-4000-8000-000000000005'), 'Khana [auto]', 'while Khana is active it keeps getting food keywords');

update public.categories set archived = true where name = 'Khana';
select pg_temp.add('d0000000-0000-4000-8000-000000000006', 'Zomato dinner');
select is(pg_temp.cat('d0000000-0000-4000-8000-000000000006'), 'Food [auto]', 'once Khana is archived, the active "Food" gets them');

-- ===========================================================================
-- Rename validation
-- ===========================================================================
select throws_ok(
  $$ update public.categories set name = ' uncategorized ' where name = 'Groceries' $$,
  '23514', null,
  'a category cannot be renamed to the reserved name Uncategorized'
);
select throws_ok(
  $$ update public.categories set name = 'medical' where name = 'Groceries' $$,
  '23505', null,
  'a category cannot be renamed to another expense category''s name (case-insensitive)'
);

reset role;

select * from finish();
rollback;
