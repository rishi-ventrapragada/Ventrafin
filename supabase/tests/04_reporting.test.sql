-- Reporting rpc functions: month-vs-month (overall and per category) and
-- monthly category totals. Transfers excluded, Uncategorized included,
-- other users' data never included.
begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

-- add(owner, date, paise, description, type, category name | null, to_account name | null)
create function pg_temp.add(p_owner uuid, p_date date, p_paise bigint, p_description text,
                            p_type text, p_category text, p_to_account text default null)
returns void language sql as $$
  insert into public.transactions (owner_id, date, amount_paise, description, type, account_id, to_account_id, category_id)
  select p_owner, p_date, p_paise, p_description, p_type,
         (select id from public.accounts where owner_id = p_owner and name = 'Bank'),
         (select id from public.accounts where owner_id = p_owner and name = p_to_account),
         (select id from public.categories where owner_id = p_owner and name = p_category and kind = p_type);
$$;

-- Month anchors, relative to "today" in IST so the test is date-independent.
create function pg_temp.this_start() returns date language sql stable as
  $$ select date_trunc('month', private.local_today())::date $$;

-- Alice, this month
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', pg_temp.this_start(),  30000,   'Dinner',        'expense', 'Food');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', private.local_today(), 5000,    'Snacks',        'expense', 'Food');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', pg_temp.this_start(),  20000,   'Weekly shop',   'expense', 'Groceries');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', pg_temp.this_start(),  7000,    'mystery item',  'expense', null);
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', pg_temp.this_start(),  5000000, 'Pay',           'income',  'Salary');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', pg_temp.this_start(),  100000,  'ATM',           'transfer', null, 'Cash');
-- Alice, last month (both edges of the month)
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', pg_temp.this_start() - 1,                     10000,   'Dinner', 'expense', 'Food');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (pg_temp.this_start() - interval '1 month')::date, 15000, 'Pills', 'expense', 'Medical');
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (pg_temp.this_start() - interval '1 month')::date, 4500000, 'Pay', 'income', 'Salary');
-- Alice, two months ago
select pg_temp.add('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (pg_temp.this_start() - interval '2 months')::date, 99999, 'Party', 'expense', 'Food');
-- Bob, this month
select pg_temp.add('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', pg_temp.this_start(), 77777, 'Bob dinner', 'expense', 'Food');


set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

-- ---- get_month_totals ----------------------------------------------------------
select results_eq(
  $$ select month, last_month, expense_paise, last_expense_paise, income_paise, last_income_paise,
            net_paise, last_net_paise, uncategorized_count
     from public.get_month_totals() $$,
  $$ select pg_temp.this_start(), (pg_temp.this_start() - interval '1 month')::date,
            62000::bigint, 25000::bigint, 5000000::bigint, 4500000::bigint,
            4938000::bigint, 4475000::bigint, 1::bigint $$,
  'get_month_totals: this vs last month; transfers excluded; Bob excluded'
);

-- ---- get_month_comparison --------------------------------------------------------
select results_eq(
  $$ select kind, category_name, this_month_paise, last_month_paise, change_paise, change_pct
     from public.get_month_comparison() $$,
  $$ values
       ('expense'::text, 'Food'::text,          35000::bigint, 10000::bigint,  25000::bigint, 250.0::numeric),
       ('expense',       'Groceries',           20000,         0,              20000,         null),
       ('expense',       'Uncategorized',       7000,          0,              7000,          null),
       ('expense',       'Medical',             0,             15000,          -15000,        -100.0),
       ('income',        'Salary',              5000000,       4500000,        500000,        11.1) $$,
  'get_month_comparison: per-category this vs last month, ordered by kind then size'
);

select is(
  (select category_id from public.get_month_comparison() where category_name = 'Uncategorized'),
  null::uuid,
  'Uncategorized row has a NULL category_id'
);

select results_eq(
  $$ select category_name, this_month_paise, last_month_paise, change_pct
     from public.get_month_comparison((pg_temp.this_start() - interval '1 month')::date)
     where category_name = 'Food' $$,
  $$ values ('Food'::text, 10000::bigint, 99999::bigint, -90.0::numeric) $$,
  'get_month_comparison(p_month) compares any chosen month with the one before'
);

-- ---- get_monthly_category_totals -----------------------------------------------
select results_eq(
  $$ select kind, category_name, transaction_count, total_paise
     from public.get_monthly_category_totals(pg_temp.this_start(), pg_temp.this_start()) $$,
  $$ values ('expense'::text, 'Food'::text,          2::bigint, 35000::bigint),
            ('expense',       'Groceries',           1,         20000),
            ('expense',       'Uncategorized',       1,         7000),
            ('income',        'Salary',              1,         5000000) $$,
  'get_monthly_category_totals for a single month'
);

select is(
  (select sum(total_paise)::bigint from public.get_monthly_category_totals() where kind = 'expense'),
  186999::bigint,
  'default range (last 12 months) includes older months'
);

select is(
  (select count(distinct month)::int from public.get_monthly_category_totals()),
  3,
  'one group per month that has data'
);

select is(
  (select sum(total_paise)::bigint from public.get_monthly_category_totals(
     (pg_temp.this_start() - interval '1 month')::date, (pg_temp.this_start() - interval '1 month')::date)
   where kind = 'expense'),
  25000::bigint,
  'custom range selects exactly the requested month(s)'
);

-- ---- Bob gets only his own numbers ---------------------------------------------
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
select results_eq(
  $$ select expense_paise, income_paise from public.get_month_totals() $$,
  $$ values (77777::bigint, 0::bigint) $$,
  'the same function called by Bob returns only Bob''s totals'
);

reset role;

select * from finish();
rollback;
