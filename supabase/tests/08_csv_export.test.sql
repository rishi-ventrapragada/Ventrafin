-- Phase 7: export_transactions_csv(). The exact file both apps save:
-- columns, labels, amounts, quoting, the formula guard, date range and id
-- filters, and never another user's rows.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice@test.local', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob@test.local',   'authenticated', 'authenticated');

-- add(id, owner, date, paise, description, type, category name | null, method | null, to_account | null)
create function pg_temp.add(p_id uuid, p_owner uuid, p_date date, p_paise bigint, p_description text,
                            p_type text, p_category text, p_method text, p_to_account text default null)
returns void language sql as $$
  insert into public.transactions (id, owner_id, date, amount_paise, description, type, account_id, to_account_id,
                                   category_id, payment_method)
  select p_id, p_owner, p_date, p_paise, p_description, p_type,
         (select id from public.accounts where owner_id = p_owner and name = 'Bank'),
         (select id from public.accounts where owner_id = p_owner and name = p_to_account),
         (select id from public.categories where owner_id = p_owner and name = p_category and kind = p_type),
         p_method;
$$;

-- Same-date rows are inserted in one transaction (equal created_at), so their
-- ids decide the order: ...01 before ...02.
select pg_temp.add('00000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-05', 45000,
                   'Swiggy dinner', 'expense', 'Food', 'upi');
select pg_temp.add('00000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-05', 5,
                   'Zqx "odd", item', 'expense', null, 'cash');
select pg_temp.add('00000000-0000-4000-8000-000000000003', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-06', 123456,
                   '=HYPERLINK("x")', 'expense', 'Groceries', 'card');
select pg_temp.add('00000000-0000-4000-8000-000000000004', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-07', 500000,
                   'Pay', 'income', 'Salary', null);
select pg_temp.add('00000000-0000-4000-8000-000000000005', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-08', 100000,
                   'ATM', 'transfer', null, null, 'Cash');
select pg_temp.add('00000000-0000-4000-8000-000000000006', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2025-01-09', 100,
                   E'Line1\nLine2', 'expense', 'Food', 'cash');
-- Inserted last but dated first: the file is in date order, not entry order.
select pg_temp.add('00000000-0000-4000-8000-000000000007', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2024-12-31', 20000,
                   '-5 discount', 'expense', 'Food', 'debit');
select pg_temp.add('00000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2025-01-05', 77700,
                   'Bob dinner', 'expense', 'Food', 'upi');

-- ---- grants ----------------------------------------------------------------------
select ok(
  not has_function_privilege('anon', 'public.export_transactions_csv(date, date, uuid[])', 'execute'),
  'anon cannot call export_transactions_csv'
);
select ok(
  has_function_privilege('authenticated', 'public.export_transactions_csv(date, date, uuid[])', 'execute'),
  'authenticated can call export_transactions_csv'
);

-- ---- the cell encoder ------------------------------------------------------------
select results_eq(
  $$ values (private.csv_cell('plain')), (private.csv_cell('a,b')), (private.csv_cell('say "hi"')),
            (private.csv_cell(E'two\nlines')), (private.csv_cell('+91 98')), (private.csv_cell('@home')),
            (private.csv_cell('-')), (private.csv_cell(null)), (private.csv_cell(' pad ')) $$,
  $$ values ('plain'), ('"a,b"'), ('"say ""hi"""'), (E'"two\nlines"'), ('''+91 98'), ('''@home'),
            ('''-'), (''), ('" pad "') $$,
  'csv_cell: quotes commas, quotes and line breaks; guards formula starts; NULL is empty'
);

set local role anon;
select throws_ok(
  $$ select public.export_transactions_csv() $$,
  '42501', null, 'anon is refused'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

-- ---- the whole file ------------------------------------------------------------
select is(
  public.export_transactions_csv(),
  E'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n'
  || E'2024-12-31,''-5 discount,200.00,Expense,Food,Bank,,Debit\r\n'
  || E'2025-01-05,Swiggy dinner,450.00,Expense,Food,Bank,,UPI\r\n'
  || E'2025-01-05,"Zqx ""odd"", item",0.05,Expense,Uncategorized,Bank,,Cash\r\n'
  || E'2025-01-06,"''=HYPERLINK(""x"")",1234.56,Expense,Groceries,Bank,,Card\r\n'
  || E'2025-01-07,Pay,5000.00,Income,Salary,Bank,,\r\n'
  || E'2025-01-08,ATM,1000.00,Transfer,,Bank,Cash,\r\n'
  || E'2025-01-09,"Line1\nLine2",1.00,Expense,Food,Bank,,Cash\r\n',
  'all time: every column, oldest first, quoting, formula guard, Uncategorized, transfer with its To account'
);

select is(
  public.export_transactions_csv('2025-01-06', '2025-01-07'),
  E'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n'
  || E'2025-01-06,"''=HYPERLINK(""x"")",1234.56,Expense,Groceries,Bank,,Card\r\n'
  || E'2025-01-07,Pay,5000.00,Income,Salary,Bank,,\r\n',
  'date range: both ends inclusive'
);

select is(
  public.export_transactions_csv(p_from => '2025-01-09'),
  E'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n'
  || E'2025-01-09,"Line1\nLine2",1.00,Expense,Food,Bank,,Cash\r\n',
  'open-ended range: from a date onwards'
);

select is(
  public.export_transactions_csv(p_to => '2024-12-31'),
  E'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n'
  || E'2024-12-31,''-5 discount,200.00,Expense,Food,Bank,,Debit\r\n',
  'open-ended range: up to a date'
);

select is(
  public.export_transactions_csv('2030-01-01', '2030-12-31'),
  E'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n',
  'nothing in range: just the heading row'
);

select is(
  public.export_transactions_csv(p_ids => array['00000000-0000-4000-8000-000000000004',
                                                '00000000-0000-4000-8000-000000000001']::uuid[]),
  E'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n'
  || E'2025-01-05,Swiggy dinner,450.00,Expense,Food,Bank,,UPI\r\n'
  || E'2025-01-07,Pay,5000.00,Income,Salary,Bank,,\r\n',
  'p_ids keeps only those rows, still oldest first'
);

select ok(
  position('Bob dinner' in public.export_transactions_csv()) = 0
  and position('Bob dinner' in public.export_transactions_csv(p_ids => array['00000000-0000-4000-8000-0000000000b1']::uuid[])) = 0,
  'another user''s rows are never exported, even by id'
);

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
select is(
  public.export_transactions_csv(),
  E'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n'
  || E'2025-01-05,Bob dinner,777.00,Expense,Food,Bank,,UPI\r\n',
  'Bob gets only his own row'
);

select * from finish();
rollback;
