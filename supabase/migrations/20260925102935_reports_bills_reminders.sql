-- =============================================================================
-- Ventrafin — phase 5 (reports) and phase 6 (bills and reminders)
--
-- Reports
--   get_monthly_totals(from, to): one row per month in the range, months with
--   nothing in them included as zeros, for the multi-month trend (spent,
--   income, net). The per-category trend reuses get_monthly_category_totals.
--
-- Bills
--   recurring_bills.paid_through_month: the latest month whose bill is
--   settled. Every month has one instance of a bill, due on due_day (clamped
--   to the month's last day: due day 31 is 30 April, 28 or 29 February).
--   The first unpaid instance is the month after paid_through_month.
--     * On insert the database fills it in: a bill added on 25 Sep with due
--       day 10 starts with October (September's is taken as already paid);
--       with due day 28 it starts with September.
--   get_bill_schedule(): every bill with its next unpaid due date, days until
--   it (negative = overdue), a status and the number of overdue months. Both
--   apps show this; the phone schedules its reminders from it.
--   mark_bill_paid(): settles a month's bill and, if asked, logs the payment
--   as an expense in one transaction. Safe to retry (see the function).
--
-- Reminders (phone only; the settings live here so they sync and survive a
-- reinstall)
--   profiles.daily_reminder_time        "log today's expenses", IST, default 20:30
--   profiles.bill_reminder_days_before  bill reminders fire this many days
--                                       before the due date (and on the day),
--                                       0-10, default 3
--   profiles.daily_reminder_enabled / bill_reminders_enabled already exist.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Reminder settings
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column daily_reminder_time time not null default '20:30'
    constraint profiles_daily_reminder_time_check check (extract(second from daily_reminder_time) = 0),
  add column bill_reminder_days_before smallint not null default 3
    constraint profiles_bill_reminder_days_before_check check (bill_reminder_days_before between 0 and 10);

comment on column public.profiles.daily_reminder_time is
  'Time of the daily "log today''s expenses" reminder, India time (whole minutes).';
comment on column public.profiles.bill_reminder_days_before is
  'Bill reminders fire this many days before the due date, and again on the due date (0 = only on the due date).';


-- -----------------------------------------------------------------------------
-- Due date of a bill in a month: due_day clamped to the month's last day.
-- -----------------------------------------------------------------------------
create function private.bill_due_date(p_month date, p_due_day integer)
returns date
language sql
immutable
strict
set search_path = ''
as $$
  select make_date(
    extract(year from p_month)::int,
    extract(month from p_month)::int,
    least(p_due_day,
          extract(day from date_trunc('month', p_month::timestamp) + interval '1 month - 1 day')::int)
  );
$$;

grant execute on function private.bill_due_date(date, integer) to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- recurring_bills.paid_through_month
-- -----------------------------------------------------------------------------
alter table public.recurring_bills add column paid_through_month date;

comment on column public.recurring_bills.paid_through_month is
  'First day of the latest month whose bill is paid. The next unpaid bill is due in the month after. Filled in on insert when omitted.';

-- The month before the first bill that is still owed, counted from today:
-- if this month's due date hasn't passed, this month is owed.
create function private.bill_start_paid_through(p_due_day integer)
returns date
language sql
stable
set search_path = ''
as $$
  select case
           when private.bill_due_date(private.local_today(), p_due_day) >= private.local_today()
             then (date_trunc('month', private.local_today()::timestamp) - interval '1 month')::date
           else date_trunc('month', private.local_today()::timestamp)::date
         end;
$$;

grant execute on function private.bill_start_paid_through(integer) to authenticated, service_role;

-- Existing rows start the same way as a bill added today.
update public.recurring_bills set paid_through_month = private.bill_start_paid_through(due_day);

alter table public.recurring_bills
  alter column paid_through_month set not null,
  add constraint recurring_bills_paid_through_month_check
    check (paid_through_month = date_trunc('month', paid_through_month::timestamp)::date);

-- Fills paid_through_month on insert when omitted, and moves any date to the
-- first of its month, so clients may send any day of the month.
create function private.recurring_bills_paid_through()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.paid_through_month is null then
    new.paid_through_month := private.bill_start_paid_through(new.due_day);
  else
    new.paid_through_month := date_trunc('month', new.paid_through_month::timestamp)::date;
  end if;
  return new;
end;
$$;

create trigger recurring_bills_paid_through
  before insert or update of paid_through_month on public.recurring_bills
  for each row execute function private.recurring_bills_paid_through();


-- -----------------------------------------------------------------------------
-- Monthly totals over a range (the Reports trend)
-- One row per month, oldest first, zero-filled. Defaults: the 12 months
-- ending with the current month (IST). At most 120 months per call.
-- Transfers are excluded, as in the other reports.
-- -----------------------------------------------------------------------------
create function public.get_monthly_totals(
  p_from_month date default null,
  p_to_month   date default null
)
returns table (
  month               date,
  expense_paise       bigint,
  income_paise        bigint,
  net_paise           bigint,
  expense_count       bigint,
  income_count        bigint,
  uncategorized_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_to   date := date_trunc('month', coalesce(p_to_month, private.local_today())::timestamp)::date;
  v_from date := coalesce(date_trunc('month', p_from_month::timestamp)::date,
                          (date_trunc('month', coalesce(p_to_month, private.local_today())::timestamp) - interval '11 months')::date);
begin
  if v_from > v_to then
    return;
  end if;
  if v_from < (v_to - interval '119 months')::date then
    raise exception 'get_monthly_totals: at most 120 months per call' using errcode = '22023';
  end if;

  return query
  with months as (
    select g::date as m
    from generate_series(v_from::timestamp, v_to::timestamp, interval '1 month') g
  ),
  agg as (
    select date_trunc('month', t.date::timestamp)::date                        as m,
           coalesce(sum(t.amount_paise) filter (where t.type = 'expense'), 0) as exp,
           coalesce(sum(t.amount_paise) filter (where t.type = 'income'), 0)  as inc,
           count(*) filter (where t.type = 'expense')                          as exp_n,
           count(*) filter (where t.type = 'income')                           as inc_n,
           count(*) filter (where t.category_id is null)                       as uncat_n
    from public.transactions t
    where t.owner_id = (select auth.uid())
      and t.type in ('expense', 'income')
      and t.date >= v_from
      and t.date <  (v_to + interval '1 month')
    group by 1
  )
  select months.m,
         coalesce(a.exp, 0)::bigint,
         coalesce(a.inc, 0)::bigint,
         (coalesce(a.inc, 0) - coalesce(a.exp, 0))::bigint,
         coalesce(a.exp_n, 0)::bigint,
         coalesce(a.inc_n, 0)::bigint,
         coalesce(a.uncat_n, 0)::bigint
  from months
  left join agg a on a.m = months.m
  order by months.m;
end;
$$;


-- -----------------------------------------------------------------------------
-- Bills with their next unpaid due date and status.
--   status:  'overdue'   next due date has passed
--            'due_today'
--            'due_soon'  within the next 7 days
--            'upcoming'
--   overdue_count: unpaid months whose due date has passed.
-- p_today is for tests; the apps leave it NULL (today in IST).
-- -----------------------------------------------------------------------------
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
  overdue_count      integer
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
           where private.bill_due_date(g::date, b.due_day) < b.today)
  from b
  order by b.next_due, lower(b.name), b.id;
$$;


-- -----------------------------------------------------------------------------
-- Mark one month's bill as paid, optionally logging the payment.
--   p_month          any day in the month being paid (normally the month of
--                    next_due_date). Paying a later month settles the ones
--                    before it too.
--   p_txn_id         when given, the payment is also logged as an expense
--                    (the bill's name, account and category; amount and date
--                    overridable) with this client-generated id.
-- Safe to retry: when the month is already paid nothing changes and no
-- second expense is logged, so a retry after a lost response, or the same
-- bill marked paid on the phone and the PC, can't double-count.
-- Returns the paid-through month, the logged transaction's id (NULL if none
-- exists with p_txn_id) and whether the month was already paid.
-- -----------------------------------------------------------------------------
create function public.mark_bill_paid(
  p_bill_id        uuid,
  p_month          date,
  p_txn_id         uuid   default null,
  p_amount_paise   bigint default null,
  p_paid_on        date   default null,
  p_payment_method text   default null
)
returns table (
  paid_through_month date,
  transaction_id     uuid,
  already_paid       boolean
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_bill  public.recurring_bills;
  v_month date := date_trunc('month', p_month::timestamp)::date;
begin
  if p_bill_id is null or p_month is null then
    raise exception 'mark_bill_paid: bill and month are required' using errcode = '22004';
  end if;

  select * into v_bill
  from public.recurring_bills r
  where r.id = p_bill_id and r.owner_id = (select auth.uid())
  for update;
  if not found then
    raise exception 'Bill not found' using errcode = 'P0002';
  end if;

  if v_bill.paid_through_month >= v_month then
    return query
      select v_bill.paid_through_month,
             (select t.id from public.transactions t where t.id = p_txn_id),
             true;
    return;
  end if;

  update public.recurring_bills r
     set paid_through_month = v_month
   where r.id = p_bill_id;

  if p_txn_id is not null then
    insert into public.transactions (id, date, amount_paise, description, type, account_id, category_id, payment_method)
    values (p_txn_id,
            coalesce(p_paid_on, private.local_today()),
            coalesce(p_amount_paise, v_bill.amount_paise),
            v_bill.name,
            'expense',
            v_bill.account_id,
            v_bill.category_id,
            p_payment_method);
  end if;

  return query select v_month, p_txn_id, false;
end;
$$;


-- Callable by signed-in users only.
revoke execute on function public.get_monthly_totals(date, date)                         from public, anon;
revoke execute on function public.get_bill_schedule(date)                                from public, anon;
revoke execute on function public.mark_bill_paid(uuid, date, uuid, bigint, date, text)   from public, anon;
grant  execute on function public.get_monthly_totals(date, date)                         to authenticated, service_role;
grant  execute on function public.get_bill_schedule(date)                                to authenticated, service_role;
grant  execute on function public.mark_bill_paid(uuid, date, uuid, bigint, date, text)   to authenticated, service_role;
