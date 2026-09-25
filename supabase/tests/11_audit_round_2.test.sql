-- Audit round 2: get_bill_schedule() returns the next three due dates (the
-- phone no longer repeats the clamping rule), and get_account_totals()
-- gives each account's month. Runs as a signed-in user, through RLS.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

-- Alice: a bill due on the 31st, paid through January 2026.
insert into public.recurring_bills (id, owner_id, name, kind, amount_paise, due_day, account_id, paid_through_month)
select 'b1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'BESCOM', 'utility', 145000, 31,
       (select id from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and name = 'Bank'),
       '2026-01-01';
-- Bob: a bill of his own.
insert into public.recurring_bills (id, owner_id, name, kind, amount_paise, due_day, account_id)
select 'b3333333-3333-4333-8333-333333333333', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Bob rent', 'utility', 100, 5,
       (select id from public.accounts where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and name = 'Bank');

-- Alice's September 2026 (and one August entry that must not count).
create function pg_temp.add(p_date date, p_paise bigint, p_type text, p_from text, p_to text default null)
returns void language sql as $$
  insert into public.transactions (owner_id, date, amount_paise, description, type, account_id, to_account_id, payment_method)
  select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_date, p_paise, 'x', p_type,
         (select id from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and name = p_from),
         (select id from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and name = p_to),
         case when p_type = 'expense' then 'cash' end;
$$;
select pg_temp.add('2026-09-02', 20000,   'expense',  'Cash');
select pg_temp.add('2026-09-03', 5000,    'expense',  'Cash');
select pg_temp.add('2026-09-05', 7000000, 'income',   'Bank');
select pg_temp.add('2026-09-06', 300000,  'transfer', 'Bank', 'Cash');
select pg_temp.add('2026-09-30', 150000,  'expense',  'Credit Card');
select pg_temp.add('2026-08-31', 99900,   'expense',  'Cash');
insert into public.transactions (owner_id, date, amount_paise, description, type, account_id)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2026-09-10', 55500, 'Bob', 'expense',
       (select id from public.accounts where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and name = 'Cash');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

-- ===========================================================================
-- get_bill_schedule(): upcoming_due_dates
-- ===========================================================================
select is(
  (select upcoming_due_dates from public.get_bill_schedule('2026-02-20') where name = 'BESCOM'),
  array['2026-02-28', '2026-03-31', '2026-04-30']::date[],
  'the next three due dates, clamped to short months (31st -> 28 Feb, 30 Apr)'
);

select is(
  (select upcoming_due_dates[1] = next_due_date from public.get_bill_schedule('2026-02-20') where name = 'BESCOM'),
  true,
  'the first upcoming date is next_due_date'
);

update public.recurring_bills set paid_through_month = '2027-12-01' where name = 'BESCOM';
select is(
  (select upcoming_due_dates from public.get_bill_schedule('2027-12-15') where name = 'BESCOM'),
  array['2028-01-31', '2028-02-29', '2028-03-31']::date[],
  'across a year end and a leap February'
);

select is(
  (select array_agg(name) from public.get_bill_schedule()),
  array['BESCOM'],
  'the schedule still holds only the caller''s own bills'
);

select results_eq(
  $$ select status, overdue_count from public.get_bill_schedule('2028-01-31') $$,
  $$ values ('due_today'::text, 0) $$,
  'the other columns are unchanged (status, overdue count)'
);

-- ===========================================================================
-- get_account_totals()
-- ===========================================================================
select results_eq(
  $$ select a.name, t.month, t.expense_paise, t.income_paise, t.transfer_out_paise, t.transfer_in_paise, t.entry_count
     from public.get_account_totals('2026-09-15') t join public.accounts a on a.id = t.account_id
     order by a.name $$,
  $$ values ('Bank'::text,        '2026-09-01'::date, 0::bigint,      7000000::bigint, 300000::bigint, 0::bigint,      2::bigint),
            ('Cash'::text,        '2026-09-01'::date, 25000::bigint,  0::bigint,       0::bigint,      300000::bigint, 3::bigint),
            ('Credit Card'::text, '2026-09-01'::date, 150000::bigint, 0::bigint,       0::bigint,      0::bigint,      1::bigint) $$,
  'per account: spending, income, transfers out and in, and entries, for the month only'
);

select is(
  (select expense_paise from public.get_account_totals('2026-08-01') t join public.accounts a on a.id = t.account_id where a.name = 'Cash'),
  99900::bigint,
  'another month gives that month''s totals'
);

select is(
  (select count(*)::int from public.get_account_totals('2030-01-01') where entry_count = 0 and expense_paise = 0),
  3,
  'a month with no entries: every account, all zeros'
);

update public.accounts set archived = true where name = 'Credit Card';
select is(
  (select expense_paise from public.get_account_totals('2026-09-01') t join public.accounts a on a.id = t.account_id where a.name = 'Credit Card'),
  150000::bigint,
  'archived accounts are still listed with their totals'
);

select is(
  (select month from public.get_account_totals() limit 1),
  date_trunc('month', private.local_today()::timestamp)::date,
  'no month given: the current month in India'
);

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
select is(
  (select sum(expense_paise)::bigint from public.get_account_totals('2026-09-01')),
  55500::bigint,
  'Bob gets only his own accounts'' totals'
);

reset role;
select ok(
  not has_function_privilege('anon', 'public.get_account_totals(date)', 'execute')
  and not has_function_privilege('anon', 'public.get_bill_schedule(date)', 'execute')
  and has_function_privilege('authenticated', 'public.get_account_totals(date)', 'execute')
  and has_function_privilege('authenticated', 'public.get_bill_schedule(date)', 'execute'),
  'authenticated can call both functions; anon can''t'
);

select * from finish();
rollback;
