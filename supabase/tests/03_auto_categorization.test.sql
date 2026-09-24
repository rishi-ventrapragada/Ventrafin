-- (b) Auto-categorization: learned rules beat built-in keywords, missing
-- categories are created, unknown descriptions stay Uncategorized; plus
-- learning from corrections. Runs as a signed-in user, through RLS, exactly
-- as the apps will.
begin;
create extension if not exists pgtap with schema extensions;

select plan(41);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

-- Bob has a rule that would mis-file Swiggy; it must never affect Alice.
insert into public.category_rules (owner_id, keyword, category_id)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'swiggy', c.id
from public.categories c
where c.owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and c.name = 'Medical';

-- Test helpers (session-temporary; they run with the caller's rights, so RLS applies).
-- add(): insert an expense/income from Alice's Cash account, optionally with a chosen category.
create function pg_temp.add(p_id uuid, p_description text, p_type text default 'expense', p_category text default null)
returns void language sql as $$
  insert into public.transactions (id, amount_paise, description, account_id, type, category_id)
  select p_id, 10000, p_description,
         (select id from public.accounts where name = 'Cash'),
         p_type,
         (select id from public.categories where name = p_category and kind = p_type);
$$;
-- cat(): "<category name>" plus " [auto]" when the trigger chose it.
create function pg_temp.cat(p_id uuid)
returns text language sql stable as $$
  select coalesce(c.name, '(uncategorized)') || case when t.auto_categorized then ' [auto]' else '' end
  from public.transactions t left join public.categories c on c.id = t.category_id
  where t.id = p_id;
$$;
-- set_cat(): what the app does when the user picks a category in the grid/form.
create function pg_temp.set_cat(p_id uuid, p_category text)
returns void language sql as $$
  update public.transactions t
     set category_id = (select c.id from public.categories c where c.name = p_category and c.kind = t.type)
   where t.id = p_id;
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);


-- ===========================================================================
-- Built-in keyword list
-- ===========================================================================
select pg_temp.add('c0000000-0000-4000-8000-000000000001', 'Swiggy dinner');
select pg_temp.add('c0000000-0000-4000-8000-000000000002', 'UPI/ZOMATO/4471023@paytm');
select pg_temp.add('c0000000-0000-4000-8000-000000000003', 'Swiggy Instamart order');
select pg_temp.add('c0000000-0000-4000-8000-000000000004', 'Ola ride to station');
select pg_temp.add('c0000000-0000-4000-8000-000000000005', 'Coca cola crate');
select pg_temp.add('c0000000-0000-4000-8000-000000000006', 'MSEDCL electricity bill Sept');
select pg_temp.add('c0000000-0000-4000-8000-000000000007', 'D-Mart Andheri');

select is(pg_temp.cat('c0000000-0000-4000-8000-000000000001'), 'Food [auto]',        'built-in: "Swiggy dinner" -> Food (and Bob''s rule is not applied)');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000002'), 'Food [auto]',        'built-in: bank-style "UPI/ZOMATO/4471023@paytm" -> Food');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000003'), 'Groceries [auto]',   'built-in: longest keyword wins, "Swiggy Instamart" -> Groceries');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000004'), 'Transport [auto]',   'built-in: "Ola ride" -> Transport');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000005'), '(uncategorized)',    'built-in: whole-word keyword "ola" does not match inside "cola"');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000006'), 'Electricity [auto]', 'built-in: DISCOM name "MSEDCL" -> Electricity');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000007'), 'Groceries [auto]',   'built-in: punctuation-insensitive, "D-Mart" -> Groceries');


-- ===========================================================================
-- Missing category is created on first match
-- ===========================================================================
select is_empty($$ select 1 from public.categories where name = 'Fuel' $$, 'precondition: Alice has no Fuel category');

select pg_temp.add('c0000000-0000-4000-8000-000000000010', 'Indian Oil petrol pump');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000010'), 'Fuel [auto]', 'unknown-to-user built-in category: "Indian Oil" -> Fuel');

select results_eq(
  $$ select owner_id, kind, color, archived from public.categories where name = 'Fuel' $$,
  $$ values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, 'expense'::text, '#6D4C41'::text, false) $$,
  'Fuel category was created for Alice with its built-in colour'
);

select pg_temp.add('c0000000-0000-4000-8000-000000000011', 'HPCL petrol');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000011'), 'Fuel [auto]', 'second fuel entry reuses the Fuel category');
select is((select count(*)::int from public.categories where name = 'Fuel'), 1, 'no duplicate Fuel category is created');


-- ===========================================================================
-- Nothing matches -> Uncategorized
-- ===========================================================================
select pg_temp.add('c0000000-0000-4000-8000-000000000020', 'Gift for Meena');
select pg_temp.add('c0000000-0000-4000-8000-000000000021', '');
select pg_temp.add('c0000000-0000-4000-8000-000000000022', '4471023');

select is(pg_temp.cat('c0000000-0000-4000-8000-000000000020'), '(uncategorized)', 'unknown description stays Uncategorized');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000021'), '(uncategorized)', 'empty description stays Uncategorized');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000022'), '(uncategorized)', 'numbers-only description stays Uncategorized');


-- ===========================================================================
-- User-chosen categories, transfers, income, archived categories
-- ===========================================================================
select pg_temp.add('c0000000-0000-4000-8000-000000000030', 'Swiggy', 'expense', 'Medical');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000030'), 'Medical', 'a category chosen at entry is kept and not flagged auto');

insert into public.transactions (id, amount_paise, description, account_id, category_id, type, auto_categorized)
values ('c0000000-0000-4000-8000-000000000031', 500, 'Bills',
        (select id from public.accounts where name = 'Cash'),
        (select id from public.categories where name = 'Bills'), 'expense', true);
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000031'), 'Bills', 'clients cannot forge auto_categorized = true');

insert into public.transactions (id, amount_paise, description, account_id, to_account_id, type)
values ('c0000000-0000-4000-8000-000000000032', 200000, 'ATM withdrawal near Swiggy office',
        (select id from public.accounts where name = 'Bank'),
        (select id from public.accounts where name = 'Cash'), 'transfer');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000032'), '(uncategorized)', 'transfers are never categorized');

select pg_temp.add('c0000000-0000-4000-8000-000000000033', 'Salary September', 'income');
select pg_temp.add('c0000000-0000-4000-8000-000000000034', 'Refund from Swiggy', 'income');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000033'), 'Salary [auto]', 'income: "Salary" -> Salary (income category)');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000034'), 'Refund [auto]', 'income: only income keywords apply ("Swiggy" ignored), Refund auto-created');
select is((select kind from public.categories where name = 'Refund'), 'income', 'auto-created Refund category is an income category');

update public.categories set archived = true where name = 'Entertainment';
select pg_temp.add('c0000000-0000-4000-8000-000000000035', 'Netflix subscription');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000035'), '(uncategorized)', 'archived category is not used; entry stays Uncategorized');
select is((select count(*)::int from public.categories where name = 'Entertainment'), 1, 'archived category is not re-created');


-- ===========================================================================
-- Learned rules take priority over built-in keywords
-- ===========================================================================
insert into public.category_rules (keyword, category_id)
values ('  Amazon ', (select id from public.categories where name = 'Groceries'));
select is((select keyword from public.category_rules where category_id = (select id from public.categories where name = 'Groceries')),
          'amazon', 'rule keywords are stored normalized');

select pg_temp.add('c0000000-0000-4000-8000-000000000040', 'Amazon Prime Video');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000040'), 'Groceries [auto]',
          'learned rule "amazon" beats even a longer built-in keyword ("prime video")');

select pg_temp.add('c0000000-0000-4000-8000-000000000041', 'AmazonFresh');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000041'), 'Shopping [auto]',
          'rules match whole words; "AmazonFresh" falls through to the built-in list');


-- ===========================================================================
-- Learning from a correction of an auto-assigned category
-- ===========================================================================
select pg_temp.add('c0000000-0000-4000-8000-000000000050', 'Apollo Tyres');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000050'), 'Medical [auto]', 'built-in guesses "Apollo" -> Medical (wrong here)');

select pg_temp.set_cat('c0000000-0000-4000-8000-000000000050', 'Transport');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000050'), 'Transport', 'user correction is saved and no longer flagged auto');

select results_eq(
  $$ select r.keyword, c.name, r.hit_count
     from public.category_rules r join public.categories c on c.id = r.category_id
     where r.keyword = 'apollo tyres' $$,
  $$ values ('apollo tyres'::text, 'Transport'::text, 1) $$,
  'correction created rule "apollo tyres" -> Transport'
);

select pg_temp.add('c0000000-0000-4000-8000-000000000051', 'APOLLO TYRES wheel alignment');
select pg_temp.add('c0000000-0000-4000-8000-000000000052', 'Apollo Pharmacy');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000051'), 'Transport [auto]', 'next Apollo Tyres entry follows the learned rule');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000052'), 'Medical [auto]',   'Apollo Pharmacy still uses the built-in keyword');


-- ===========================================================================
-- Learning from categorizing an Uncategorized entry; strengthening; re-pointing
-- ===========================================================================
select pg_temp.set_cat('c0000000-0000-4000-8000-000000000020', 'Other');   -- 'Gift for Meena'
select results_eq(
  $$ select c.name, r.hit_count from public.category_rules r join public.categories c on c.id = r.category_id
     where r.keyword = 'gift for meena' $$,
  $$ values ('Other'::text, 1) $$,
  'categorizing an Uncategorized entry learns "gift for meena" -> Other'
);

select pg_temp.add('c0000000-0000-4000-8000-000000000053', 'Gift for Meena - birthday');
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000053'), 'Other [auto]', 'the same description is categorized automatically next time');

select pg_temp.add('c0000000-0000-4000-8000-000000000054', 'Gift for Meena', 'expense', 'Bills');
select pg_temp.set_cat('c0000000-0000-4000-8000-000000000054', 'Other');
select is((select hit_count from public.category_rules where keyword = 'gift for meena'), 2,
          'repeating the same correction strengthens the rule (hit_count 2)');

select pg_temp.set_cat('c0000000-0000-4000-8000-000000000020', 'Food');
select results_eq(
  $$ select c.name, r.hit_count from public.category_rules r join public.categories c on c.id = r.category_id
     where r.keyword = 'gift for meena' $$,
  $$ values ('Food'::text, 1) $$,
  'a different correction re-points the rule and resets hit_count'
);


-- ===========================================================================
-- Updates
-- ===========================================================================
select pg_temp.add('c0000000-0000-4000-8000-000000000060', 'Swigy');   -- typo
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000060'), '(uncategorized)', 'typo "Swigy" is Uncategorized');
update public.transactions set description = 'Swiggy' where id = 'c0000000-0000-4000-8000-000000000060';
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000060'), 'Food [auto]', 'fixing the description of an Uncategorized entry re-runs categorization');
select is_empty($$ select 1 from public.category_rules where keyword = 'swiggy' $$,
                'an automatic assignment never creates a rule');

update public.transactions set amount_paise = 99900 where id = 'c0000000-0000-4000-8000-000000000001';
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000001'), 'Food [auto]', 'editing other fields keeps the category and its auto flag');

update public.transactions
   set type = 'transfer', to_account_id = (select id from public.accounts where name = 'Bank')
 where id = 'c0000000-0000-4000-8000-000000000002';
select is(pg_temp.cat('c0000000-0000-4000-8000-000000000002'), '(uncategorized)', 'changing an entry to a transfer clears its category');

update public.transactions set type = 'expense' where id = 'c0000000-0000-4000-8000-000000000002';
select results_eq(
  $$ select to_account_id, category_id is not null from public.transactions where id = 'c0000000-0000-4000-8000-000000000002' $$,
  $$ values (null::uuid, true) $$,
  'changing it back to an expense drops to_account_id and re-categorizes'
);

reset role;

select * from finish();
rollback;
