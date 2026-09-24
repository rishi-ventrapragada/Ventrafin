# Ventrafin — Architecture

See `PRD.md` for what's being built and `DECISIONS.md` for why this shape was chosen over the alternatives considered.

## 1. System shape

Two independent client apps, one shared backend, no custom server:

```
 ┌────────────────┐        ┌────────────────┐
 │  Flutter app    │        │   Vue 3 app     │
 │  (Android)      │        │  (web/Vercel)   │
 └───────┬─────────┘        └───────┬─────────┘
         │  supabase_flutter        │  supabase-js
         │  (anon key)              │  (anon key)
         └────────────┬─────────────┘
                       │
              ┌────────▼─────────┐
              │     Supabase      │
              │  Postgres + RLS   │
              │  Auth (Google)    │
              │  Realtime         │
              └───────────────────┘
```

Both clients hold only the Supabase **anon/public key**. All access control is enforced server-side by RLS — the anon key alone grants nothing without a valid authenticated session tied to matching `owner_id` rows. The `service_role` key is never present in either client; it stays in the Supabase dashboard only.

There is no local database (no `drift`/`sqflite`/`Hive`/`IndexedDB`) and no client-side encryption layer. All reads and writes go straight to Supabase. Cross-app sync happens via Supabase Realtime subscriptions on `transactions`, `accounts`, and `recurring_bills` — both apps subscribe and update their local UI state when a change arrives.

## 2. Data model

All tables include `owner_id uuid references auth.users`, and every table has RLS enabled with an owner-only policy (see § 4). Money is always `integer` paise.

### `profiles`
| column | type | notes |
|---|---|---|
| id | uuid, PK, references auth.users | |
| theme | text | one of the theme tokens, default `'ocean'` |
| daily_reminder_enabled | boolean | default true |
| bill_reminders_enabled | boolean | master switch, default true |

### `accounts`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| name | text | |
| type | text | `cash` / `bank` / `credit` |

### `categories`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| name | text | |
| kind | text | `expense` / `income` |
| color | text | hex, for chart/UI display |
| archived | boolean | default false |

### `category_rules`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| keyword | text | matched case-insensitively as a substring of `transactions.description` |
| category_id | uuid, references categories | |

### `transactions`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| date | date | |
| amount_paise | integer | always positive; sign/direction implied by `type` |
| description | text | |
| account_id | uuid, references accounts | |
| to_account_id | uuid, references accounts, nullable | set only when `type = 'transfer'` |
| category_id | uuid, references categories, nullable | null until categorized |
| payment_method | text | `cash` / `upi` / `debit` / `card` |
| type | text | `expense` / `income` / `transfer` |
| auto_categorized | boolean | default false |

### `recurring_bills`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| name | text | |
| kind | text | `utility` / `emi` |
| amount_paise | integer | |
| due_day | integer | day of month, 1–31 |
| account_id | uuid, references accounts | |
| category_id | uuid, references categories | |
| reminder_enabled | boolean | default true |

## 3. Shared logic lives in Postgres

Because two independently-built clients write to the same data, any logic that must behave identically on both — categorization, category auto-creation, computed totals — is implemented once as SQL, not duplicated in Dart and TypeScript:

- **Auto-categorization**: a trigger function on `transactions` (before insert/update, when `category_id is null`) that:
  1. Looks for a matching `category_rules` row for that `owner_id` (case-insensitive substring match on `description`).
  2. Falls back to a built-in keyword list (maintained in SQL, e.g. as a `case` expression or a small seed table) covering common Indian merchant/biller names.
  3. Creates the matched category for that `owner_id` if it doesn't already exist.
  4. Sets `auto_categorized = true` when it fires.
- **Learning from corrections**: when Dad manually changes a transaction's category after auto-categorization assigned one, the client should upsert a `category_rules` row (keyword derived from the description, or a meaningful token from it) so the same merchant categorizes correctly next time. This can be a trigger on update, or an explicit client call — pick whichever is cleaner during implementation, but keep it in one place conceptually.
- **Reporting aggregates** (month totals, month-over-month comparison by category): implement as SQL views or functions (`get_monthly_summary(owner_id, month)`), callable identically from both `supabase-js` and `supabase_flutter` via `rpc()` or view selects, rather than pulling all rows and summing client-side twice.
- **New-user seeding**: a trigger on new `profiles` row creation that inserts the starter category set (Groceries, Bills, Medical, Transport, Food, Electricity, Entertainment, Other).

## 4. Row Level Security

Every table's policy shape is the same:

```sql
alter table <table> enable row level security;

create policy "owner can select own rows"
  on <table> for select
  using (owner_id = auth.uid());

create policy "owner can insert own rows"
  on <table> for insert
  with check (owner_id = auth.uid());

create policy "owner can update own rows"
  on <table> for update
  using (owner_id = auth.uid());

create policy "owner can delete own rows"
  on <table> for delete
  using (owner_id = auth.uid());
```

No policy grants any cross-user access. There is no role/claim for "admin" or "viewer" anywhere in the schema or policies — admin access to raw data happens exclusively via the Supabase dashboard (which authenticates as the project owner, outside of RLS), never through either client app.

## 5. Auth

- **Google Sign-In** is the only auth method on both apps, via Supabase Auth's Google OAuth provider.
- Redirect URLs must be registered in both the Google OAuth client config and Supabase Auth settings for: the deployed web app URL, `localhost` during web dev, and the Flutter app's redirect scheme.
- **Mobile app lock** (fingerprint / pattern) is a **client-side gate on top of** an already-valid Supabase session — it is not a second authentication factor recognized by the backend. It controls whether the app *shows* data it already has a valid session for, not whether Supabase will serve that data.
- **No password reset system** (no reset emails or codes), since there's no app-specific password. The lock screen's **"Forgot pattern?"** option signs the user out; they re-authenticate with Google and set a new pattern.
- **Windows Hello (later phase)**: via Supabase's passkey/WebAuthn support. Treat as additive to Google Sign-In, not a replacement, and note that passkeys are origin-bound — the web app's final deployed domain should be settled before wiring this up.

## 6. Mobile app (Flutter)

- Target: Android only.
- `supabase_flutter` for auth, data access, and Realtime subscriptions.
- `local_auth` for fingerprint; a pattern-lock package (or a small custom widget) for the fallback.
- `flutter_local_notifications` for the daily nudge and bill/EMI reminders, scheduled locally from `recurring_bills`/`profiles` reminder settings — no server-side push needed since reminders are local-time-based.
- `fl_chart` for reporting charts.
- Navigation: bottom nav bar (Dashboard / Transactions / Add / Bills) plus a "More" section (Categories / Accounts / Reports / Settings) — multiple distinct routes, not a single scrolling page.
- Entry flow: numeric-keypad-first, with "Save & add another" to support end-of-day batch logging.

## 7. Web app (Vue 3)

- Vue 3 (Composition API) + Vite + TypeScript.
- **Vue Router** with one route per section: `/dashboard`, `/transactions`, `/add`, `/categories`, `/accounts`, `/bills`, `/reports`, `/settings` — a genuine multi-page app, not a single scrollable view. A route guard redirects unauthenticated users to `/login`.
- **PrimeVue** for the DataTable (in-cell editable grid, supports paste-from-Excel) plus forms/dialogs; **Tailwind CSS** for layout/utility styling.
- `supabase-js` for auth, data access, and Realtime subscriptions.
- Deployed as a **static site** (SPA build) — no server-side rendering, no API routes, no serverless functions of its own. All logic is either in the browser or in Supabase.
- Hosted on **Vercel**. Needs a `vercel.json` rewrite rule sending all paths to `index.html` (required for direct loads/refreshes on routes like `/bills` to work), plus basic security headers (CSP scoped to the app's own origin and the Supabase URL).

## 8. Shared theming

A single `theme-tokens.json` (or equivalent) defines each theme's primary/accent colors and chart palette. Both apps consume this file (copied in or symlinked at build time — implementation detail left open) so a theme looks identical on both, and both derive their color scheme from it rather than hardcoding values independently. The user's selected theme is persisted in `profiles.theme` and applied on load in both apps.

## 9. What's deliberately absent

- No custom backend server, API layer, or serverless functions — Postgres (via RLS + SQL functions) is the only "backend logic" layer.
- No local database or offline cache on either client.
- No client-side encryption/key management.
- No in-app admin or shared-viewer role, and no RLS bypass reachable from either client.
