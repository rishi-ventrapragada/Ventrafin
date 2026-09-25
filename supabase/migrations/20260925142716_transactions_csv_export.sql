-- =============================================================================
-- Ventrafin — phase 7: CSV export of transactions
--
-- export_transactions_csv(p_from, p_to, p_ids) returns the whole CSV file as
-- one text value, so both apps download/share exactly the same file and the
-- column list, labels, quoting and number format live in one place
-- (CLAUDE.md: shared logic lives in Postgres). A single value also avoids the
-- API's row limit on large exports.
--
--   Date,Description,Amount (₹),Type,Category,Account,To account,Paid by
--   2026-09-25,Swiggy dinner,450.00,Expense,Food,Cash,,UPI
--
-- * Oldest first (date, then entry order), CRLF line endings (RFC 4180).
-- * Date is ISO yyyy-mm-dd: Excel reads it as a date in any regional setting
--   and shows it in the PC's own format.
-- * Amount is rupees with two decimals, always positive; Type says which way
--   the money went. No grouping commas, so Excel treats it as a number.
-- * Category is "Uncategorized" when none, empty for transfers.
-- * Cells starting with = + - @ (or tab / CR) get a leading apostrophe so a
--   spreadsheet never runs a description as a formula (CSV injection); the
--   web import strips it again.
-- * p_from / p_to are inclusive; NULL means unbounded. p_ids, when given,
--   keeps only those transactions (the web's "export what's shown").
-- * The byte-order mark Excel needs to read UTF-8 (₹, Hindi text) is added
--   by the apps when they write the file.
-- SECURITY INVOKER: RLS applies and only the caller's rows are read.
-- =============================================================================

-- One CSV cell: formula guard, then quotes when needed.
create function private.csv_cell(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
           when v ~ '[",\r\n]' or v <> btrim(v) then '"' || replace(v, '"', '""') || '"'
           else v
         end
  from (select case when coalesce(p_value, '') ~ '^[=+@\t\r-]' then '''' || p_value
                    else coalesce(p_value, '') end as v) s;
$$;

grant execute on function private.csv_cell(text) to authenticated, service_role;


create function public.export_transactions_csv(
  p_from date   default null,
  p_to   date   default null,
  p_ids  uuid[] default null
)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select string_agg(line, E'\r\n' order by ord) || E'\r\n'
  from (
    select 0::bigint as ord,
           'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by' as line
    union all
    select row_number() over (order by t.date, t.created_at, t.id),
           concat_ws(',',
             to_char(t.date, 'YYYY-MM-DD'),
             private.csv_cell(t.description),
             (t.amount_paise / 100)::text || '.' || lpad((t.amount_paise % 100)::text, 2, '0'),
             case t.type when 'expense' then 'Expense' when 'income' then 'Income' else 'Transfer' end,
             private.csv_cell(case when t.type = 'transfer' then '' else coalesce(c.name, 'Uncategorized') end),
             private.csv_cell(a.name),
             private.csv_cell(coalesce(ta.name, '')),
             case t.payment_method
               when 'cash' then 'Cash' when 'upi' then 'UPI' when 'debit' then 'Debit' when 'card' then 'Card'
               else ''
             end)
    from public.transactions t
    join public.accounts a
      on a.owner_id = t.owner_id and a.id = t.account_id
    left join public.accounts ta
      on ta.owner_id = t.owner_id and ta.id = t.to_account_id
    left join public.categories c
      on c.owner_id = t.owner_id and c.id = t.category_id
    where t.owner_id = (select auth.uid())
      and (p_from is null or t.date >= p_from)
      and (p_to   is null or t.date <= p_to)
      and (p_ids  is null or t.id = any (p_ids))
  ) lines;
$$;

comment on function public.export_transactions_csv(date, date, uuid[]) is
  'The caller''s transactions as a CSV file (text): Date, Description, Amount (₹), Type, Category, Account, To account, Paid by. Oldest first. p_from/p_to inclusive, NULL = unbounded; p_ids keeps only those rows.';

revoke execute on function public.export_transactions_csv(date, date, uuid[]) from public, anon;
grant  execute on function public.export_transactions_csv(date, date, uuid[]) to authenticated, service_role;
