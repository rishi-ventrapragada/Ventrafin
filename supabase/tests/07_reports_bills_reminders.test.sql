-- Phase 5/6: monthly totals over a range, bill due dates and status, marking
-- a bill paid (idempotent, optionally logging the expense), reminder settings.
begin;
create extension if not exists pgtap with schema extensions;

select plan(30);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

create function pg_temp.add(p_owner uuid, p_date date, p_paise bigint, p_type text, p_category text,
                            p_to_account text default null)
returns void language sql as $$
  insert into public.transactions (owner_id, date, amount_paise, description, type, account_id, to_account_id, category_id)
  select p_owner, p_date, p_paise, 'x', p_type,
         (select id from public.accounts where owner_id = p_owner and name = 'Bank'),
         (select id from public.accounts where owner_id = p_owner and name = p_to_account),
         (select id from public.categories where owner_id = p_owner and name = p_category and kind = p_type);
$$;

-- Fixed months far from "today", so the test doesn't depend on the date.
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-05', 10000, 'expense', 'Food');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-31', 2500,  'expense', null);
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-10', 500000, 'income', 'Salary');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-12', 99900, 'transfer', null, 'Cash');
-- (February: nothing)
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-03-01', 7000,  'expense', 'Groceries');
select pg_temp.add('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2025-02-10', 55555, 'expense', 'Food');

-- Bills (inserted as the owner, before switching roles)
insert into public.recurring_bills (id, owner_id, name, kind, amount_paise, due_day, account_id, paid_through_month)
select 'b1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'BESCOM', 'utility', 145000, 31,
       (select id from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and name = 'Bank'),
       '2026-01-17';
insert into public.recurring_bills (id, owner_id, name, kind, amount_paise, due_day, account_id)
select 'b2222222-2222-4222-8222-222222222222', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Home loan', 'emi', 2500000,
       extract(day from private.local_today())::int,
       (select id from public.accounts where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and name = 'Bank');
insert into public.recurring_bills (id, owner_id, name, kind, amount_paise, due_day, account_id)
select 'b3333333-3333-4333-8333-333333333333', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Bob rent', 'utility', 100, 5,
       (select id from public.accounts where owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and name = 'Bank');

-- ---- reminder settings -------------------------------------------------------------
select results_eq(
  $$ select daily_reminder_time, bill_reminder_days_before from public.profiles
     where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  $$ values ('20:30'::time, 3::smallint) $$,
  'profiles: daily reminder at 20:30, bill reminders 3 days before, by default'
);
select throws_ok(
  $$ update public.profiles set bill_reminder_days_before = 11 where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '23514', null, 'bill_reminder_days_before is at most 10'
);
select throws_ok(
  $$ update public.profiles set daily_reminder_time = '20:30:15' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '23514', null, 'daily_reminder_time is whole minutes'
);

-- ---- due dates -------------------------------------------------------------------
select is(private.bill_due_date('2026-02-10', 31), '2026-02-28'::date, 'due day 31 in February 2026 is the 28th');
select is(private.bill_due_date('2028-02-01', 30), '2028-02-29'::date, 'leap year: the 29th');
select is(private.bill_due_date('2026-04-01', 31), '2026-04-30'::date, 'due day 31 in April is the 30th');
select is(private.bill_due_date('2026-04-01', 15), '2026-04-15'::date, 'a normal due day is kept');

-- ---- paid_through_month defaults ------------------------------------------------------
select is(
  (select paid_through_month from public.recurring_bills where id = 'b1111111-1111-4111-8111-111111111111'),
  '2026-01-01'::date, 'a given paid-through date moves to the first of its month'
);
select is(
  (select paid_through_month from public.recurring_bills where id = 'b2222222-2222-4222-8222-222222222222'),
  (date_trunc('month', private.local_today()::timestamp) - interval '1 month')::date,
  'a bill added on its due day starts owed this month'
);


-- Schedule of BESCOM (due day 31, paid through January 2026: February's bill, the 28th, is next).
create function pg_temp.bescom(p_today date) returns table (next_due date, days int, status text, overdue int)
language sql as $$
  select next_due_date, days_until, status, overdue_count from public.get_bill_schedule(p_today)
  where id = 'b1111111-1111-4111-8111-111111111111'
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

-- ---- get_monthly_totals ------------------------------------------------------------
select results_eq(
  $$ select month, expense_paise, income_paise, net_paise, expense_count, income_count, uncategorized_count
     from public.get_monthly_totals('2024-12-15', '2025-03-20') $$,
  $$ values ('2024-12-01'::date, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint),
            ('2025-01-01'::date, 12500::bigint, 500000::bigint, 487500::bigint, 2::bigint, 1::bigint, 1::bigint),
            ('2025-02-01'::date, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint),
            ('2025-03-01'::date, 7000::bigint, 0::bigint, -7000::bigint, 1::bigint, 0::bigint, 0::bigint) $$,
  'get_monthly_totals: oldest first, empty months as zeros, transfers and other users excluded'
);
select is((select count(*) from public.get_monthly_totals()), 12::bigint, 'get_monthly_totals: 12 months by default');
select is(
  (select max(month) from public.get_monthly_totals()),
  date_trunc('month', private.local_today()::timestamp)::date,
  'get_monthly_totals: the default range ends with the current month'
);
select is_empty($$ select * from public.get_monthly_totals('2025-05-01', '2025-01-01') $$, 'get_monthly_totals: from after to is empty');
select throws_ok(
  $$ select * from public.get_monthly_totals('2010-01-01', '2025-01-01') $$,
  '22023', null, 'get_monthly_totals: more than 120 months is refused'
);

-- ---- get_bill_schedule ---------------------------------------------------------------
select results_eq($$ select * from pg_temp.bescom('2026-02-20') $$,
  $$ values ('2026-02-28'::date, 8, 'upcoming', 0) $$, 'schedule: 8 days out is upcoming');
select results_eq($$ select * from pg_temp.bescom('2026-02-21') $$,
  $$ values ('2026-02-28'::date, 7, 'due_soon', 0) $$, 'schedule: 7 days out is due soon');
select results_eq($$ select * from pg_temp.bescom('2026-02-28') $$,
  $$ values ('2026-02-28'::date, 0, 'due_today', 0) $$, 'schedule: due today');
select results_eq($$ select * from pg_temp.bescom('2026-04-02') $$,
  $$ values ('2026-02-28'::date, -33, 'overdue', 2) $$,
  'schedule: February and March unpaid on 2 April: overdue by 33 days, 2 months overdue');
select is(
  (select array_agg(name order by name) from public.get_bill_schedule('2026-02-20')),
  array['BESCOM', 'Home loan'], 'schedule: only my own bills'
);

-- ---- mark_bill_paid --------------------------------------------------------------------
select results_eq(
  $$ select paid_through_month, transaction_id, already_paid
     from public.mark_bill_paid('b1111111-1111-4111-8111-111111111111', '2026-02-28',
                                'c1111111-1111-4111-8111-111111111111', null, '2026-02-26', 'upi') $$,
  $$ values ('2026-02-01'::date, 'c1111111-1111-4111-8111-111111111111'::uuid, false) $$,
  'mark_bill_paid: February settled and the payment logged'
);
select results_eq(
  $$ select date, amount_paise, description, type, payment_method,
            account_id = (select id from public.accounts where name = 'Bank')
     from public.transactions where id = 'c1111111-1111-4111-8111-111111111111' $$,
  $$ values ('2026-02-26'::date, 145000::bigint, 'BESCOM', 'expense', 'upi', true) $$,
  'mark_bill_paid: the expense has the bill''s name, amount and account'
);
select results_eq($$ select next_due, status from pg_temp.bescom('2026-03-01') $$,
  $$ values ('2026-03-31'::date, 'upcoming') $$, 'schedule: after paying February, March is next');
select results_eq(
  $$ select paid_through_month, transaction_id, already_paid
     from public.mark_bill_paid('b1111111-1111-4111-8111-111111111111', '2026-02-01',
                                'c1111111-1111-4111-8111-111111111111') $$,
  $$ values ('2026-02-01'::date, 'c1111111-1111-4111-8111-111111111111'::uuid, true) $$,
  'mark_bill_paid: a retry changes nothing'
);
select results_eq(
  $$ select transaction_id, already_paid
     from public.mark_bill_paid('b1111111-1111-4111-8111-111111111111', '2026-02-10',
                                'c2222222-2222-4222-8222-222222222222') $$,
  $$ values (null::uuid, true) $$,
  'mark_bill_paid: an already-paid month logs no second expense'
);
select is(
  (select count(*) from public.transactions where description = 'BESCOM'), 1::bigint,
  'mark_bill_paid: exactly one expense logged'
);
select results_eq(
  $$ select paid_through_month, transaction_id, already_paid
     from public.mark_bill_paid('b1111111-1111-4111-8111-111111111111', '2026-05-15') $$,
  $$ values ('2026-05-01'::date, null::uuid, false) $$,
  'mark_bill_paid: paying a later month settles the ones before it, without logging'
);
select throws_ok(
  $$ select * from public.mark_bill_paid('b3333333-3333-4333-8333-333333333333', '2026-05-01') $$,
  'P0002', 'Bill not found', 'mark_bill_paid: another user''s bill is not found'
);
select throws_ok(
  $$ select * from public.mark_bill_paid('b1111111-1111-4111-8111-111111111111', null) $$,
  '22004', null, 'mark_bill_paid: the month is required'
);

-- Undo is a plain update (RLS applies), normalised to the first of the month.
update public.recurring_bills set paid_through_month = '2026-04-20' where id = 'b1111111-1111-4111-8111-111111111111';
select is(
  (select paid_through_month from public.recurring_bills where id = 'b1111111-1111-4111-8111-111111111111'),
  '2026-04-01'::date, 'undo: paid_through_month can be moved back'
);

-- ---- anon ----------------------------------------------------------------------------
reset role;
select ok(
  not has_function_privilege('anon', 'public.get_bill_schedule(date)', 'execute')
  and not has_function_privilege('anon', 'public.mark_bill_paid(uuid, date, uuid, bigint, date, text)', 'execute')
  and not has_function_privilege('anon', 'public.get_monthly_totals(date, date)', 'execute'),
  'anon cannot call the new functions'
);

select * from finish();
rollback;
