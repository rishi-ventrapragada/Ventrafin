-- (c) Signup seeding: a new auth user gets a profile, the starter categories
-- and the default Cash / Bank / Credit Card accounts — and nothing else.
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

-- Simulate Google sign-up for two users (this is what Supabase Auth does).
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

-- ---- profile -----------------------------------------------------------------
select results_eq(
  $$ select theme, daily_reminder_enabled, bill_reminders_enabled
     from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  $$ values ('ocean'::text, true, true) $$,
  'signup creates one profile with default theme and reminders on'
);

-- ---- categories ----------------------------------------------------------------
select set_eq(
  $$ select name from public.categories
     where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and kind = 'expense' $$,
  array['Groceries', 'Bills', 'Medical', 'Transport', 'Food', 'Electricity', 'Entertainment', 'Other'],
  'starter expense categories are seeded (PRD 4.3)'
);

select set_eq(
  $$ select name from public.categories
     where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and kind = 'income' $$,
  array['Salary', 'Interest', 'Other Income'],
  'starter income categories are seeded'
);

select is_empty(
  $$ select 1 from public.categories
     where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
       and (archived or color !~ '^#[0-9A-Fa-f]{6}$') $$,
  'seeded categories are active and have a colour'
);

select is_empty(
  $$ select 1 from public.categories
     where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and name in ('Fuel', 'Shopping', 'Refund') $$,
  'non-starter built-in categories are NOT seeded (they are created on first match)'
);

-- ---- accounts ------------------------------------------------------------------
select set_eq(
  $$ select name, type from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  $$ values ('Cash'::text, 'cash'::text), ('Bank', 'bank'), ('Credit Card', 'credit') $$,
  'default Cash, Bank and Credit Card accounts are seeded'
);

-- ---- nothing else --------------------------------------------------------------
select is_empty(
  $$ select 1 from public.transactions    where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     union all
     select 1 from public.category_rules  where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     union all
     select 1 from public.recurring_bills where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'no transactions, rules or bills are created at signup'
);

-- ---- per-user isolation of seeded data ----------------------------------------
select is(
  (select count(*)::int from public.categories where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  11,
  'second user gets their own 11 categories'
);

select is(
  (select count(*)::int from public.categories where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  11,
  'first user still has exactly 11 categories after another signup'
);

select is(
  (select count(*)::int from public.accounts where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  3,
  'second user gets their own 3 accounts'
);

-- ---- idempotency -----------------------------------------------------------------
-- Re-running the seed (e.g. profile recreated) must not duplicate anything.
delete from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
insert into public.profiles (id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

select is(
  (select count(*)::int from public.categories where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  + (select count(*)::int from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  14,
  're-seeding a profile does not duplicate categories or accounts'
);

-- ---- the app can read its own seed as that user --------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.categories) + (select count(*)::int from public.accounts)
  + (select count(*)::int from public.profiles),
  15,
  'signed-in user sees exactly their own 11 categories, 3 accounts and 1 profile'
);

reset role;

-- ---- account deletion cascades ------------------------------------------------------
delete from auth.users where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select is_empty(
  $$ select 1 from public.profiles   where id       = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
     union all
     select 1 from public.categories where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
     union all
     select 1 from public.accounts   where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  'deleting an auth user removes all of their data'
);

select is(
  (select count(*)::int from public.categories where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  11,
  'deleting one user does not touch another user''s data'
);

select * from finish();
rollback;
