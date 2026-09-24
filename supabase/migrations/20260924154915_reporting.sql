-- =============================================================================
-- Ventrafin — reporting aggregates (PRD § 4.6, ARCHITECTURE.md § 3)
--
-- Called identically from both apps:
--   supabase-js:       supabase.rpc('get_month_comparison', { p_month: '2026-09-01' })
--   supabase_flutter:  supabase.rpc('get_month_comparison', params: {'p_month': '2026-09-01'})
--
-- Rules shared by all three functions
--   * SECURITY INVOKER + explicit owner filter: a caller only ever aggregates
--     their own rows (RLS applies as well). No owner_id parameter exists, so
--     there is nothing to spoof.
--   * Months are identified by any date inside them; NULL = current month (IST).
--   * Transfers are excluded: they move money between your own accounts and
--     are neither spending nor income. (A credit-card purchase is an expense
--     when it happens; paying the card bill is a transfer.)
--   * Uncategorized rows come back with category_id NULL and name
--     'Uncategorized'.
--   * Amounts are bigint paise.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Totals per month x category over a range of months (for tables and charts).
-- Defaults: the 12 months ending with the current month.
-- -----------------------------------------------------------------------------
create function public.get_monthly_category_totals(
  p_from_month date default null,
  p_to_month   date default null
)
returns table (
  month             date,
  kind              text,
  category_id       uuid,
  category_name     text,
  category_color    text,
  transaction_count bigint,
  total_paise       bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select b.to_month,
           coalesce(date_trunc('month', p_from_month)::date,
                    (b.to_month - interval '11 months')::date) as from_month
    from (select date_trunc('month', coalesce(p_to_month, private.local_today()))::date as to_month) b
  )
  select date_trunc('month', t.date)::date            as month,
         t.type                                       as kind,
         t.category_id,
         coalesce(c.name, 'Uncategorized')            as category_name,
         coalesce(c.color, '#9E9E9E')                 as category_color,
         count(*)                                     as transaction_count,
         sum(t.amount_paise)::bigint                  as total_paise
  from public.transactions t
  cross join bounds b
  left join public.categories c
    on c.owner_id = t.owner_id and c.id = t.category_id
  where t.owner_id = (select auth.uid())
    and t.type in ('expense', 'income')
    and t.date >= b.from_month
    and t.date <  (b.to_month + interval '1 month')
  group by 1, 2, 3, 4, 5
  order by 1 desc, 2, 7 desc, 4;
$$;


-- -----------------------------------------------------------------------------
-- This month vs last month, per category.
-- change_pct is NULL when last month was 0 (no meaningful percentage).
-- -----------------------------------------------------------------------------
create function public.get_month_comparison(p_month date default null)
returns table (
  kind              text,
  category_id       uuid,
  category_name     text,
  category_color    text,
  this_month_paise  bigint,
  last_month_paise  bigint,
  change_paise      bigint,
  change_pct        numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  with m as (
    select date_trunc('month', coalesce(p_month, private.local_today()))::date as this_start
  ),
  agg as (
    select t.type        as kind,
           t.category_id as category_id,
           coalesce(sum(t.amount_paise) filter (where t.date >= m.this_start), 0)::bigint as this_month,
           coalesce(sum(t.amount_paise) filter (where t.date <  m.this_start), 0)::bigint as last_month
    from public.transactions t
    cross join m
    where t.owner_id = (select auth.uid())
      and t.type in ('expense', 'income')
      and t.date >= (m.this_start - interval '1 month')
      and t.date <  (m.this_start + interval '1 month')
    group by 1, 2
  )
  select a.kind,
         a.category_id,
         coalesce(c.name, 'Uncategorized'),
         coalesce(c.color, '#9E9E9E'),
         a.this_month,
         a.last_month,
         a.this_month - a.last_month,
         case when a.last_month = 0 then null
              else round((a.this_month - a.last_month) * 100.0 / a.last_month, 1)
         end
  from agg a
  left join public.categories c
    on c.owner_id = (select auth.uid()) and c.id = a.category_id
  order by a.kind, a.this_month desc, a.last_month desc, 3;
$$;


-- -----------------------------------------------------------------------------
-- This month vs last month, overall (one row) — dashboard headline numbers.
-- -----------------------------------------------------------------------------
create function public.get_month_totals(p_month date default null)
returns table (
  month                date,
  last_month           date,
  expense_paise        bigint,
  last_expense_paise   bigint,
  income_paise         bigint,
  last_income_paise    bigint,
  net_paise            bigint,
  last_net_paise       bigint,
  uncategorized_count  bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with m as (
    select date_trunc('month', coalesce(p_month, private.local_today()))::date as this_start
  ),
  s as (
    select
      coalesce(sum(t.amount_paise) filter (where t.type = 'expense' and t.date >= m.this_start), 0)::bigint as exp_this,
      coalesce(sum(t.amount_paise) filter (where t.type = 'expense' and t.date <  m.this_start), 0)::bigint as exp_last,
      coalesce(sum(t.amount_paise) filter (where t.type = 'income'  and t.date >= m.this_start), 0)::bigint as inc_this,
      coalesce(sum(t.amount_paise) filter (where t.type = 'income'  and t.date <  m.this_start), 0)::bigint as inc_last,
      count(*) filter (where t.date >= m.this_start and t.category_id is null)                              as uncat_this
    from m
    left join public.transactions t
      on  t.owner_id = (select auth.uid())
      and t.type in ('expense', 'income')
      and t.date >= (m.this_start - interval '1 month')
      and t.date <  (m.this_start + interval '1 month')
  )
  select m.this_start,
         (m.this_start - interval '1 month')::date,
         s.exp_this, s.exp_last,
         s.inc_this, s.inc_last,
         s.inc_this - s.exp_this,
         s.inc_last - s.exp_last,
         s.uncat_this
  from m cross join s;
$$;


-- Callable by signed-in users only.
revoke execute on function public.get_monthly_category_totals(date, date) from public, anon;
revoke execute on function public.get_month_comparison(date)              from public, anon;
revoke execute on function public.get_month_totals(date)                  from public, anon;
grant  execute on function public.get_monthly_category_totals(date, date) to authenticated, service_role;
grant  execute on function public.get_month_comparison(date)              to authenticated, service_role;
grant  execute on function public.get_month_totals(date)                  to authenticated, service_role;
