-- (a) One user cannot read, insert, update or delete another user's rows in
-- any table — nor point their own rows at another user's accounts/categories,
-- nor move their rows into another user's ownership. Anonymous callers get
-- nothing at all.
begin;
create extension if not exists pgtap with schema extensions;

select plan(45);

-- ---------------------------------------------------------------------------
-- Fixture (as the migration owner, outside RLS)
--   Alice: aaaaaaaa-...   Bob: bbbbbbbb-...
--   Alice gets one row with a known id in every table.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

insert into public.accounts (id, owner_id, name, type) values
  ('a1000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Alice Savings', 'bank'),
  ('b1000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Bob Wallet',    'cash');

insert into public.categories (id, owner_id, name, kind, color) values
  ('a2000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Alice Hobbies', 'expense', '#123456');

insert into public.category_rules (id, owner_id, keyword, category_id) values
  ('a3000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pottery class',
   'a2000000-0000-4000-8000-000000000001');

insert into public.transactions (id, owner_id, date, amount_paise, description, account_id, type, payment_method, category_id) values
  ('a4000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', private.local_today(),
   123400, 'Alice private purchase', 'a1000000-0000-4000-8000-000000000001', 'expense', 'upi',
   'a2000000-0000-4000-8000-000000000001');

insert into public.recurring_bills (id, owner_id, name, kind, amount_paise, due_day, account_id, category_id) values
  ('a5000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Alice Home Loan', 'emi',
   2500000, 5, 'a1000000-0000-4000-8000-000000000001', null);


-- ===========================================================================
-- Act as Bob
-- ===========================================================================
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);

-- ---- SELECT: Bob sees only his own rows -------------------------------------
select isnt_empty($$ select 1 from public.accounts $$, 'sanity: Bob can see his own accounts');
select is_empty($$ select 1 from public.profiles        where id       <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, 'SELECT profiles: Bob sees no one else''s profile');
select is_empty($$ select 1 from public.accounts        where owner_id <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, 'SELECT accounts: Bob sees no one else''s rows');
select is_empty($$ select 1 from public.categories      where owner_id <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, 'SELECT categories: Bob sees no one else''s rows');
select is_empty($$ select 1 from public.category_rules  where owner_id <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, 'SELECT category_rules: Bob sees no one else''s rows');
select is_empty($$ select 1 from public.transactions    where owner_id <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, 'SELECT transactions: Bob sees no one else''s rows');
select is_empty($$ select 1 from public.recurring_bills where owner_id <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, 'SELECT recurring_bills: Bob sees no one else''s rows');

-- ---- INSERT rows owned by Alice: rejected by RLS ----------------------------
select throws_ok(
  $$ insert into public.profiles (id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', null, 'INSERT profiles: Bob cannot create a profile for Alice');
select throws_ok(
  $$ insert into public.accounts (owner_id, name, type) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Sneaky', 'cash') $$,
  '42501', null, 'INSERT accounts: Bob cannot insert a row owned by Alice');
select throws_ok(
  $$ insert into public.categories (owner_id, name, kind) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Sneaky', 'expense') $$,
  '42501', null, 'INSERT categories: Bob cannot insert a row owned by Alice');
select throws_ok(
  $$ insert into public.category_rules (owner_id, keyword, category_id)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sneaky', 'a2000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'INSERT category_rules: Bob cannot insert a row owned by Alice');
select throws_ok(
  $$ insert into public.transactions (owner_id, amount_paise, description, account_id, type)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 100, 'sneaky', 'a1000000-0000-4000-8000-000000000001', 'expense') $$,
  '42501', null, 'INSERT transactions: Bob cannot insert a row owned by Alice');
select throws_ok(
  $$ insert into public.recurring_bills (owner_id, name, kind, amount_paise, due_day, account_id)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Sneaky', 'utility', 100, 1, 'a1000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'INSERT recurring_bills: Bob cannot insert a row owned by Alice');

-- ---- UPDATE Alice's rows: silently matches nothing ---------------------------
select is_empty($$ update public.profiles set theme = 'forest' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' returning 1 $$,
  'UPDATE profiles: Bob cannot change Alice''s profile');
select is_empty($$ update public.accounts set name = 'hacked' where id = 'a1000000-0000-4000-8000-000000000001' returning 1 $$,
  'UPDATE accounts: Bob cannot change Alice''s rows');
select is_empty($$ update public.categories set name = 'hacked' where id = 'a2000000-0000-4000-8000-000000000001' returning 1 $$,
  'UPDATE categories: Bob cannot change Alice''s rows');
select is_empty($$ update public.category_rules set keyword = 'hacked' where id = 'a3000000-0000-4000-8000-000000000001' returning 1 $$,
  'UPDATE category_rules: Bob cannot change Alice''s rows');
select is_empty($$ update public.transactions set amount_paise = 1 where id = 'a4000000-0000-4000-8000-000000000001' returning 1 $$,
  'UPDATE transactions: Bob cannot change Alice''s rows');
select is_empty($$ update public.recurring_bills set amount_paise = 1 where id = 'a5000000-0000-4000-8000-000000000001' returning 1 $$,
  'UPDATE recurring_bills: Bob cannot change Alice''s rows');

-- ---- UPDATE own rows into Alice's ownership: rejected ------------------------
select throws_ok(
  $$ update public.accounts set owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' where id = 'b1000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'UPDATE accounts: Bob cannot hand his row over to Alice');
select throws_ok(
  $$ update public.profiles set id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '42501', null, 'UPDATE profiles: Bob cannot re-key his profile to Alice');

-- ---- DELETE Alice's rows: silently matches nothing ---------------------------
select throws_ok(
  $$ delete from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', null, 'DELETE profiles: not permitted from the client at all');
select is_empty($$ delete from public.accounts        where id = 'a1000000-0000-4000-8000-000000000001' returning 1 $$, 'DELETE accounts: Bob cannot delete Alice''s rows');
select is_empty($$ delete from public.categories      where id = 'a2000000-0000-4000-8000-000000000001' returning 1 $$, 'DELETE categories: Bob cannot delete Alice''s rows');
select is_empty($$ delete from public.category_rules  where id = 'a3000000-0000-4000-8000-000000000001' returning 1 $$, 'DELETE category_rules: Bob cannot delete Alice''s rows');
select is_empty($$ delete from public.transactions    where id = 'a4000000-0000-4000-8000-000000000001' returning 1 $$, 'DELETE transactions: Bob cannot delete Alice''s rows');
select is_empty($$ delete from public.recurring_bills where id = 'a5000000-0000-4000-8000-000000000001' returning 1 $$, 'DELETE recurring_bills: Bob cannot delete Alice''s rows');

-- ---- Own rows pointing at Alice's accounts/categories: rejected by FK -------
select throws_ok(
  $$ insert into public.transactions (amount_paise, description, account_id, type)
     values (100, 'x', 'a1000000-0000-4000-8000-000000000001', 'expense') $$,
  '23503', null, 'Bob cannot book a transaction against Alice''s account');
select throws_ok(
  $$ insert into public.transactions (amount_paise, description, account_id, type, category_id)
     values (100, 'x', 'b1000000-0000-4000-8000-000000000001', 'expense', 'a2000000-0000-4000-8000-000000000001') $$,
  '23503', null, 'Bob cannot file a transaction under Alice''s category');
select throws_ok(
  $$ insert into public.category_rules (keyword, category_id) values ('x y', 'a2000000-0000-4000-8000-000000000001') $$,
  '23503', null, 'Bob cannot create a rule pointing at Alice''s category');
select throws_ok(
  $$ insert into public.recurring_bills (name, kind, amount_paise, due_day, account_id)
     values ('x', 'utility', 100, 1, 'a1000000-0000-4000-8000-000000000001') $$,
  '23503', null, 'Bob cannot create a bill against Alice''s account');

-- ---- Bob's own CRUD still works ------------------------------------------------
select lives_ok(
  $$ insert into public.transactions (id, amount_paise, description, account_id, type)
     values ('b4000000-0000-4000-8000-000000000001', 5000, 'Bob chai', 'b1000000-0000-4000-8000-000000000001', 'expense') $$,
  'Bob can insert his own transaction (owner_id defaults to auth.uid())');
select isnt_empty(
  $$ update public.transactions set amount_paise = 6000 where id = 'b4000000-0000-4000-8000-000000000001' returning 1 $$,
  'Bob can update his own transaction');
select is(
  (select owner_id from public.transactions where id = 'b4000000-0000-4000-8000-000000000001'),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
  'owner_id was filled in from the session');

-- ---- Reports only aggregate the caller's rows --------------------------------
select is((select expense_paise from public.get_month_totals()), 6000::bigint,
  'get_month_totals as Bob includes only Bob''s spending');
select is((select sum(total_paise)::bigint from public.get_monthly_category_totals()), 6000::bigint,
  'get_monthly_category_totals as Bob includes only Bob''s rows');

select isnt_empty(
  $$ delete from public.transactions where id = 'b4000000-0000-4000-8000-000000000001' returning 1 $$,
  'Bob can delete his own transaction');

-- ===========================================================================
-- Anonymous (not signed in): no access to anything
-- ===========================================================================
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok($$ select * from public.profiles $$,        '42501', null, 'anon cannot read profiles');
select throws_ok($$ select * from public.accounts $$,        '42501', null, 'anon cannot read accounts');
select throws_ok($$ select * from public.categories $$,      '42501', null, 'anon cannot read categories');
select throws_ok($$ select * from public.category_rules $$,  '42501', null, 'anon cannot read category_rules');
select throws_ok($$ select * from public.transactions $$,    '42501', null, 'anon cannot read transactions');
select throws_ok($$ select * from public.recurring_bills $$, '42501', null, 'anon cannot read recurring_bills');
select throws_ok($$ select * from public.get_month_totals() $$, '42501', null, 'anon cannot call report functions');

-- ===========================================================================
-- Back as owner: Alice's data is exactly as it was
-- ===========================================================================
reset role;

select results_eq(
  $$ select (select theme from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
            (select name from public.accounts where id = 'a1000000-0000-4000-8000-000000000001'),
            (select name from public.categories where id = 'a2000000-0000-4000-8000-000000000001'),
            (select keyword from public.category_rules where id = 'a3000000-0000-4000-8000-000000000001'),
            (select amount_paise from public.transactions where id = 'a4000000-0000-4000-8000-000000000001'),
            (select amount_paise from public.recurring_bills where id = 'a5000000-0000-4000-8000-000000000001'),
            (select count(*) from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  $$ values ('ocean'::text, 'Alice Savings'::text, 'Alice Hobbies'::text, 'pottery class'::text,
             123400::bigint, 2500000::bigint, 4::bigint) $$,
  'all of Alice''s rows are untouched after Bob''s attempts'
);

select * from finish();
rollback;
