# /supabase — backend (source of truth for the schema)

Everything the database needs is in `migrations/`, applied in filename order.
Never change the schema through the dashboard. Add a new migration instead.

| Migration | What it does |
|---|---|
| `…154708_private_schema_and_helpers` | `private` schema (not exposed to the API), `normalize_text()`, `local_today()` (IST), `updated_at` trigger |
| `…154739_core_schema` | `profiles`, `accounts`, `categories`, `category_rules`, `transactions`, `recurring_bills`, with constraints and indexes |
| `…154753_rls_policies` | RLS on every table, owner-only policies, tightened grants |
| `…154822_builtin_categories_and_keywords` | Built-in category list and the Indian merchant/biller keyword list (`private.*`) |
| `…154832_new_user_setup` | Signup → profile → starter categories + Cash/Bank/Credit Card |
| `…154856_auto_categorization` | Categorization trigger and learning from corrections |
| `…154915_reporting` | `get_month_totals`, `get_month_comparison`, `get_monthly_category_totals` (rpc) |
| `…154918_realtime` | Publishes `transactions`, `accounts`, `recurring_bills` |
| `…155021_advisor_fixes` | Revokes API execute on Supabase's `rls_auto_enable()`, adds explicit deny-all policies on `private.*`, indexes a reference-data FK |
| `…155214_enable_pgtap` | Installs pgTAP (in `extensions`) for the tests |
| `…162343_realtime_categories_profiles` | Publishes `categories` and `profiles` too |
| `…040030_category_icons` | `categories.icon` (curated Material Symbols keys), a curated palette, distinct built-in colours, and a trigger that fills in the default icon and colour. Backfills existing rows |
| `…044748_category_builtin_link` | `categories.builtin_name`: a category keeps its built-in keywords when renamed ("Food" → "Khana" still gets Swiggy). Trigger-maintained; the categorizer uses it before the name (DECISIONS.md D18) |
| `…102935_reports_bills_reminders` | Phases 5–6: `get_monthly_totals` (zero-filled month range), `recurring_bills.paid_through_month` (filled in on insert), `get_bill_schedule` (next due date, status, overdue months), `mark_bill_paid` (settle a month and optionally log the expense, retry-safe), `profiles.daily_reminder_time` and `profiles.bill_reminder_days_before` (DECISIONS.md D21, D23, D24) |
| `…142716_transactions_csv_export` | Phase 7: `export_transactions_csv(from, to, ids)` returns the CSV file both apps save (one text value; formula-guarded cells) (DECISIONS.md D25) |
| `…142724_backup_reader_role` | Phase 7: `ventrafin_backup`, the read-only login for the weekly backup (SELECT on public tables, BYPASSRLS, read-only transactions, no password in the repo) (DECISIONS.md D27) |

`seed.sql` is intentionally empty. Reference data lives in migrations so the hosted project gets it too.

**Backups** (weekly, encrypted, via GitHub Actions): setup, checking and restoring are in [`BACKUPS.md`](BACKUPS.md).

## Applying changes (Supabase MCP, not the CLI)

1. Write a new file `migrations/<YYYYMMDDHHMMSS>_<name>.sql`.
2. Apply it with the MCP `apply_migration` tool, using the file's exact contents and the same `<name>`.
3. The MCP stamps its own version at apply time, so rename the file to `<that version>_<name>.sql` and check the hashes match:
   ```sql
   select version, name, encode(sha256(convert_to(array_to_string(statements, E'\n'), 'UTF8')), 'hex')
   from supabase_migrations.schema_migrations order by version;
   ```
   Compare with `sha256sum supabase/migrations/*.sql`.
4. Check that `list_migrations` matches this folder and that `get_advisors` (security + performance) is clean.
   Expect "unused index" INFO notices while the tables are empty.

The full rules are in the root `CLAUDE.md` ("Database changes via Supabase MCP").
`config.toml` is left over from `supabase init`. It only matters for a local Docker stack, and the hosted project ignores it.

## Tests (pgTAP, `tests/*.test.sql`)

Every file runs inside `BEGIN … ROLLBACK`, so it leaves nothing behind. `00`–`09`: structure, signup seeding, RLS isolation, auto-categorization, reporting, category style, category rename, reports/bills/reminders, CSV export, backup role.

- **Normally, via the Supabase MCP (`execute_sql`).** `execute_sql` runs the whole script as one transaction and returns only the last statement's result. So send the file's statements with three changes:
  1. drop `begin;`
  2. drop the `create extension … pgtap` line (a migration already installed it)
  3. replace `select * from finish(); rollback;` with the block below.

  ```sql
  do $tap$
  begin
    raise exception 'TAP <file>: planned=% ran=% failed=% (transaction rolled back)',
      extensions._get('plan'), currval('__tresults___numb_seq'), extensions.num_failed();
  end
  $tap$;
  ```
  The call always "fails" with that message. The error carries the result and guarantees the rollback. A pass reads `planned=N ran=N failed=0`. If a file shows failures, run it from a terminal (below) to see which assertions failed.
- **Optional, from a terminal:** set the connection string for this terminal only, then run `npm run db:test`:
  ```powershell
  $env:SUPABASE_DB_URL = "postgresql://postgres.<project-ref>:<db-password>@<pooler-host>:5432/postgres"
  npm run db:test
  Remove-Item Env:SUPABASE_DB_URL
  ```
  Get the string from Dashboard → **Connect** → *Session pooler*. Percent-encode any special characters in the password.

## Calling the reports from the apps

```ts
supabase.rpc('get_month_totals')                                   // current month (IST) vs last
supabase.rpc('get_month_comparison', { p_month: '2026-08-01' })    // per category, any month
supabase.rpc('get_monthly_category_totals', { p_from_month: '2026-01-01', p_to_month: '2026-09-01' })
supabase.rpc('get_monthly_totals', { p_from_month: '2026-04-01', p_to_month: '2026-09-01' })   // one row per month, zeros included
supabase.rpc('get_bill_schedule')                                   // bills with next due date + status
supabase.rpc('mark_bill_paid', { p_bill_id, p_month: '2026-09-01', p_txn_id })   // p_txn_id: also log the expense
supabase.rpc('export_transactions_csv', { p_from: '2026-04-01', p_to: '2027-03-31' })   // the CSV file as text; omit both for all time
```
```dart
supabase.rpc('get_month_comparison', params: {'p_month': '2026-08-01'});
```
