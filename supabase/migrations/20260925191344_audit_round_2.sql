-- =============================================================================
-- Ventrafin — audit round 2 (AUDIT.md: CODE-2, CAT-1)
--
-- 1. get_bill_schedule() also returns upcoming_due_dates: the due dates of
--    the next three bills still owed (the next unpaid month and the two
--    after it), with the due day clamped to short months. The phone used to
--    repeat the clamping rule in Dart to schedule reminders three months
--    ahead (CODE-2); now the rule exists only in private.bill_due_date.
--    A RETURNS TABLE can't gain a column in place, so the function is
--    dropped and created again in this one transaction. The new column is
--    last, so an app that doesn't know it yet reads the rest as before.
--
-- 2. get_account_totals(p_month): per account, that month's spending,
--    income, transfers out and in, and number of entries (CAT-1). Computed
--    here like every other total both apps may show. Archived accounts are
--    included (they can still have entries in an old month).
--
-- Both are SECURITY INVOKER with an owner filter: a caller only ever sees
-- their own bills and accounts. anon can't call them.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. get_bill_schedule(): + upcoming_due_dates
-- -----------------------------------------------------------------------------
drop function public.get_bill_schedule(date);

-- Bills with their next unpaid due date and status.
--   status:  'overdue'   next due date has passed
--            'due_today'
--            'due_soon'  within the next 7 days
--            'upcoming'
--   overdue_count: unpaid months whose due date has passed.
--   upcoming_due_dates: due dates of the next three unpaid months, oldest
--            first (the first is next_due_date). The phone schedules
--            reminders from these.
-- p_today is for tests; the apps leave it NULL (today in IST).
create function public.get_bill_schedule(p_today date default null)
returns table (
  id                 uuid,
  name               text,
  kind               text,
  amount_paise       bigint,
  due_day            integer,
  account_id         uuid,
  category_id        uuid,
  reminder_enabled   boolean,
  paid_through_month date,
  next_due_date      date,
  days_until         integer,
  status             text,
  overdue_count      integer,
  upcoming_due_dates date[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  with d as (
    select coalesce(p_today, private.local_today()) as today
  ),
  b as (
    select r.*,
           d.today,
           private.bill_due_date((r.paid_through_month + interval '1 month')::date, r.due_day) as next_due
    from public.recurring_bills r
    cross join d
    where r.owner_id = (select auth.uid())
  )
  select b.id, b.name, b.kind, b.amount_paise, b.due_day, b.account_id, b.category_id,
         b.reminder_enabled, b.paid_through_month,
         b.next_due,
         (b.next_due - b.today),
         case when b.next_due <  b.today      then 'overdue'
              when b.next_due =  b.today      then 'due_today'
              when b.next_due - b.today <= 7  then 'due_soon'
              else 'upcoming'
         end,
         (select count(*)::int
            from generate_series((b.paid_through_month + interval '1 month')::timestamp,
                                 date_trunc('month', b.today::timestamp),
                                 interval '1 month') g
           where private.bill_due_date(g::date, b.due_day) < b.today),
         array(select private.bill_due_date((b.paid_through_month + make_interval(months => k))::date, b.due_day)
                 from generate_series(1, 3) k
                order by k)
  from b
  order by b.next_due, lower(b.name), b.id;
$$;

revoke execute on function public.get_bill_schedule(date) from public, anon;
grant  execute on function public.get_bill_schedule(date) to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 2. get_account_totals(p_month)
--   p_month: any day in the month; NULL = the current month in IST.
--   One row per account the caller owns (archived included), by name.
--   expense/income: that month's entries booked to the account.
--   transfer_out: transfers from it; transfer_in: transfers to it.
--   entry_count: entries touching it (either side of a transfer counts).
-- -----------------------------------------------------------------------------
create function public.get_account_totals(p_month date default null)
returns table (
  account_id          uuid,
  month               date,
  expense_paise       bigint,
  income_paise        bigint,
  transfer_out_paise  bigint,
  transfer_in_paise   bigint,
  entry_count         bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with m as (
    select date_trunc('month', coalesce(p_month, private.local_today()))::date as start
  ),
  t as (
    select tx.*
    from public.transactions tx, m
    where tx.owner_id = (select auth.uid())
      and tx.date >= m.start
      and tx.date <  (m.start + interval '1 month')
  )
  select a.id,
         m.start,
         coalesce(sum(t.amount_paise) filter (where t.type = 'expense'  and t.account_id    = a.id), 0)::bigint,
         coalesce(sum(t.amount_paise) filter (where t.type = 'income'   and t.account_id    = a.id), 0)::bigint,
         coalesce(sum(t.amount_paise) filter (where t.type = 'transfer' and t.account_id    = a.id), 0)::bigint,
         coalesce(sum(t.amount_paise) filter (where t.type = 'transfer' and t.to_account_id = a.id), 0)::bigint,
         count(t.id)
  from public.accounts a
  cross join m
  left join t on t.account_id = a.id or t.to_account_id = a.id
  where a.owner_id = (select auth.uid())
  group by a.id, a.name, m.start
  order by lower(a.name), a.id;
$$;

revoke execute on function public.get_account_totals(date) from public, anon;
grant  execute on function public.get_account_totals(date) to authenticated, service_role;
