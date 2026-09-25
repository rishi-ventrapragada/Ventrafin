# Ventrafin — Architecture

See `PRD.md` for what's being built and `DECISIONS.md` for why this shape was chosen over the alternatives considered. The SQL in `/supabase/migrations` is the source of truth. This document describes it; where they disagree, the migrations win and this file should be fixed.

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

Both clients hold only the Supabase **anon/publishable key**. All access control is enforced server-side by RLS. The anon key alone grants nothing without a valid authenticated session tied to matching `owner_id` rows. The `service_role` key is never present in either client; it stays in the Supabase dashboard only.

There is no local database (no `drift`/`sqflite`/`Hive`/`IndexedDB`) and no client-side encryption layer. All reads and writes go straight to Supabase. Cross-app sync happens via Supabase Realtime subscriptions on `transactions`, `accounts`, `recurring_bills`, `categories` and `profiles`. Both apps subscribe and update their UI state when a change arrives. Realtime applies each table's SELECT policy per subscriber, so a user only ever receives their own rows. With RLS on, DELETE events carry only the primary key, so clients remove rows by id.

**Timezone.** The app is India-only and uses **Asia/Kolkata** as its single timezone. The database's `private.local_today()` defines "today" (the default transaction date) and "current month" for reports. The mobile app computes today the same way, so a transaction entered at 00:30 IST lands on the right day even though servers run in UTC.

## 2. Data model

Conventions that apply to every table:

- **Owner.** Every user-owned table has `owner_id uuid not null default auth.uid() references auth.users on delete cascade`. Clients may omit it; RLS still verifies it. `profiles` uses its `id` (= the auth user id) as the owner.
- **Money** is integer paise stored as **`bigint`**. `integer` would cap amounts at about ₹2.1 crore. Amounts must be `> 0` and `< 10^15`, which keeps every value inside JavaScript's safe-integer range, since PostgREST sends bigint as a JSON number.
- **Composite foreign keys.** Child rows reference parents through `(owner_id, x_id) → parent (owner_id, id)`. Foreign-key checks bypass RLS, so a plain FK would let a user attach a row to someone else's account or category by guessing its UUID. The composite FK makes cross-user references impossible at the database level.
- **Deleting in-use parents.** An account or category that is still referenced cannot be deleted. Categories are archived instead. (The FKs are `NO ACTION`, so deleting an auth user still cascades cleanly.)
- Every table has `created_at` and `updated_at` (maintained by trigger).
- Enum-like text columns have `CHECK` constraints listing the allowed values.

### `profiles`
| column | type | notes |
|---|---|---|
| id | uuid, PK, references auth.users | acts as owner_id |
| theme | text | `ocean` / `sunset` / `forest` / `garden` / `sunflower` / `marigold`, default `'ocean'` |
| daily_reminder_enabled | boolean | default true |
| daily_reminder_time | time | India time, whole minutes, default `20:30` |
| bill_reminders_enabled | boolean | master switch for bill reminders (not the daily one), default true |
| bill_reminder_days_before | smallint | 0–10, default 3: bill reminders fire this many days before the due date and again on it |

Clients can select, insert and update their own profile but not delete it; its lifecycle follows `auth.users`.

### `accounts`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| name | text | 1–60 chars, unique per user (case-insensitive) |
| type | text | `cash` / `bank` / `credit` |

### `categories`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| name | text | 1–40 chars; unique per user and kind (case-insensitive); `Uncategorized` is reserved |
| kind | text | `expense` / `income` |
| color | text | `#RRGGBB`, for chart/UI display. If omitted on insert: the built-in colour, else the first unused palette colour |
| icon | text | key from the curated icon set (Material Symbols name, `categories_icon_check`). If omitted on insert: the built-in icon, else a keyword-based guess, else `label`. See `DECISIONS.md` D13 |
| archived | boolean | default false |
| builtin_name | text, nullable | the built-in category this row stands for. Set by trigger on insert when the name is a built-in one; kept when the category is renamed; clients cannot set or change it. See `DECISIONS.md` D18 |

**Uncategorized** is not a row: it is `transactions.category_id IS NULL`.

### `category_rules`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| keyword | text | stored **normalized** (see § 3); unique per user |
| category_id | uuid | composite FK to categories, cascades on category delete |
| hit_count | integer | how often the user confirmed this mapping; tie-breaker |

### `transactions`
| column | type | notes |
|---|---|---|
| id | uuid, PK | clients may supply it (the mobile app does, so a retried save can't duplicate) |
| owner_id | uuid | |
| date | date | default = today in Asia/Kolkata; 1990–2099 |
| amount_paise | bigint | always positive; direction comes from `type` |
| description | text | ≤ 500 chars, trimmed |
| account_id | uuid | composite FK to accounts |
| to_account_id | uuid, nullable | required when `type = 'transfer'`, must differ from `account_id`, forbidden otherwise |
| category_id | uuid, nullable | NULL = Uncategorized; always NULL for transfers |
| payment_method | text, nullable | `cash` / `upi` / `debit` / `card`. Nullable in the database; the mobile app requires it for expenses |
| type | text | `expense` / `income` / `transfer` |
| auto_categorized | boolean | set only by the categorization trigger; clients cannot forge it |

### `recurring_bills`
| column | type | notes |
|---|---|---|
| id | uuid, PK | |
| owner_id | uuid | |
| name | text | 1–60 chars |
| kind | text | `utility` / `emi` |
| amount_paise | bigint | > 0 |
| due_day | integer | day of month, 1–31 (clients clamp for short months) |
| account_id | uuid | composite FK to accounts |
| category_id | uuid, nullable | composite FK to categories |
| reminder_enabled | boolean | default true |
| paid_through_month | date | first day of the latest month whose bill is paid; the next unpaid bill is due the month after. Filled in on insert when omitted: the first month whose due date is today or later is owed. Any date is moved to the first of its month. See `DECISIONS.md` D23 |

### Internal (`private` schema, not exposed through the API)
- `private.builtin_categories`: every category the system can create: name, kind, colour, icon, and whether it's a starter.
- `private.category_palette()`: the curated 24-colour palette, in picker order.
- `private.builtin_keywords`: the built-in Indian merchant/biller keyword list (about 230 keywords) mapping to those categories, each with a match mode (`word` or `substring`).
- Both have RLS on with explicit deny-all policies and no grants to `anon`/`authenticated`. They are read only through SECURITY DEFINER functions.

## 3. Shared logic lives in Postgres

Because two independently-built clients write to the same data, any logic that must behave identically on both is implemented once as SQL, not duplicated in Dart and TypeScript. That covers categorization, category auto-creation and computed totals.

- **Text normalization** (`private.normalize_text`): lower-case, punctuation/whitespace runs collapsed to single spaces, pure-number tokens (UPI refs, order ids) dropped. For example `'UPI/SWIGGY/4471023@icici'` becomes `'upi swiggy icici'`. Keywords and descriptions are both normalized before matching.
- **Auto-categorization**: a `BEFORE INSERT OR UPDATE` trigger on `transactions`, running as the calling user (SECURITY INVOKER, so RLS applies to everything it reads or creates):
  1. **Transfers** are never categorized. The trigger also clears whichever of `category_id` / `to_account_id` doesn't fit the row's `type`, so grid edits that change `type` don't fail.
  2. A category the user chose is kept and `auto_categorized = false`. An update that leaves the category untouched keeps it and its flag.
  3. If `category_id` is NULL, it tries, in order:
     1. the user's **learned rules** (`category_rules`), matched as **whole words** in the normalized description. The longest keyword wins, then the highest `hit_count`, then the newest.
     2. the **built-in keyword list**. `word` keywords must match whole words (so `ola` doesn't match "coca cola"); `substring` keywords (distinctive brands) may match anywhere. The longest keyword wins, so "Swiggy Instamart" goes to Groceries rather than Food.
     3. otherwise the transaction stays NULL (**Uncategorized**).
  4. Only categories of the matching kind are considered (expense → expense categories, income → income).
     - A built-in match finds the user's category through `categories.builtin_name` first, so a renamed category keeps its keywords ("Food" renamed "Khana" still gets Swiggy). If no category holds the link, it looks the category up by name. An active category is preferred over an archived one.
     - A built-in match whose category the user doesn't have yet **creates it** with its built-in colour.
     - A match pointing at an **archived** category is skipped, not resurrected.
  5. `auto_categorized = true` only when step 3 assigned the category.
- **Learning from corrections** is a trigger, not a client call. An `AFTER UPDATE OF category_id` trigger fires whenever the *user* changes a transaction's category (`auto_categorized` is false on the new row). That covers fixing a wrong auto category and categorizing an Uncategorized one. It upserts a rule `keyword → new category`:
  - The keyword is the normalized description with leading/trailing filler words (`upi`, `paid`, `to`, `bill`, `order`, …) removed, capped at 4 words. For example `'Paid to Ramesh Kirana Store for veg'` gives `'ramesh kirana store'`.
  - Repeating the same correction increments `hit_count`. A different correction re-points the rule and resets it to 1.
  - Learned rules beat built-in keywords, so the correction wins from the next entry onward, on both apps.
- **Reporting aggregates** are SQL functions called via `rpc()` from both apps. They are SECURITY INVOKER with no owner parameter, so a caller can only ever aggregate their own rows:
  - `get_month_totals(p_month date default null)`: one row with this month vs last month for expense, income and net, plus this month's Uncategorized count.
  - `get_month_comparison(p_month date default null)`: per category (Uncategorized included as `category_id NULL`), this month vs last month, change in paise and %.
  - `get_monthly_category_totals(p_from_month, p_to_month)`: per month × category totals; defaults to the last 12 months.
  - `get_monthly_totals(p_from_month, p_to_month)`: one row per month (oldest first, empty months as zeros) with spent, income, net, entry counts and the Uncategorized count; defaults to the last 12 months, at most 120. The Reports trends use it.
  - `p_month` is any date in the month; NULL means the current month in Asia/Kolkata. **Transfers are excluded** from all totals: a credit-card purchase is an expense when it happens, and paying the card bill is a transfer.
- **Bills** (`DECISIONS.md` D23): every month has one instance of a bill, due on `due_day` clamped to the month's last day (`private.bill_due_date`).
  - `get_bill_schedule(p_today default null)`: each bill with `next_due_date` (the month after `paid_through_month`), `days_until` (negative = overdue), `status` (`overdue` / `due_today` / `due_soon` within 7 days / `upcoming`) and `overdue_count`. Both apps show it; the phone schedules reminders from it.
  - `mark_bill_paid(p_bill_id, p_month, p_txn_id, p_amount_paise, p_paid_on, p_payment_method)`: sets `paid_through_month` to `p_month` and, with `p_txn_id`, inserts the payment as an expense (the bill's name, account and category) in the same transaction. When the month is already paid it changes nothing and logs nothing, so a retry or the same tap on the other app can't double-count. Undo is a plain update of `paid_through_month`.
- **CSV export** (`DECISIONS.md` D25): `export_transactions_csv(p_from, p_to, p_ids)` returns the whole file as one text value (SECURITY INVOKER, own rows only), so both apps save the same file:
  - columns `Date, Description, Amount (₹), Type, Category, Account, To account, Paid by`;
  - ISO dates, rupees with two decimals, oldest first, CRLF line endings;
  - "Uncategorized" for no category, an empty category for transfers;
  - an apostrophe before cells starting with `= + - @` (formula guard);
  - `p_from`/`p_to` are inclusive (NULL = open), and `p_ids` limits it to given rows. The apps add the UTF-8 byte-order mark.
- **Category icon and colour defaults**: a `BEFORE INSERT` trigger on `categories` fills in whichever of `icon` / `color` the client left out:
  - a built-in name gets its built-in icon and colour;
  - a name that the built-in keyword list recognises ("Petrol") gets that category's icon;
  - otherwise the icon is `label`, and the colour is the first palette colour none of the user's active categories uses yet.

  Auto-categorization and seeding rely on this too. `/shared/category-style.json` mirrors the icon list and palette for the clients.
- **New-user seeding**: a trigger on `auth.users` creates the `profiles` row. A trigger on `profiles` then inserts the starter categories and the default accounts **Cash**, **Bank** and **Credit Card**.
  - Starter expense categories: Groceries, Bills, Medical, Transport, Food, Electricity, Entertainment, Other.
  - Starter **income** categories: Salary, Interest, Other Income.
  - Seeding is idempotent.
  - Non-starter built-in categories (Fuel, Shopping, Mobile & Internet, Refund, …) are only created when a keyword first needs them.

## 4. Row Level Security

Every table's policy shape is the same, owner-only and for the `authenticated` role only:

```sql
alter table <table> enable row level security;

create policy "owner can select own rows" on <table>
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "owner can insert own rows" on <table>
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "owner can update own rows" on <table>
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));   -- a row can't be handed to another owner

create policy "owner can delete own rows" on <table>
  for delete to authenticated using (owner_id = (select auth.uid()));
```

(`profiles` uses `id` in place of `owner_id` and has no delete policy.) Hardening on top of the policies:
- `anon` has **no** table privileges at all.
- `authenticated` has only SELECT/INSERT/UPDATE/DELETE, not the TRUNCATE/REFERENCES/TRIGGER that Supabase's default grants would include.
- No SECURITY DEFINER function in the API-exposed `public` schema is callable by `anon`/`authenticated`.
- `auth.uid()` is wrapped in `(select …)` so Postgres evaluates it once per statement.
- The composite FKs in § 2 close the cross-user-reference gap that RLS alone leaves open.

**One role outside the app bypasses RLS: `ventrafin_backup`** (`DECISIONS.md` D27), the login the weekly backup uses.
- It has BYPASSRLS and SELECT on the `public` tables, plus tables created later via default privileges.
- It has no write privileges, `default_transaction_read_only = on`, no access to `auth` or `private`, and at most 2 connections.
- Its password is set once by the owner (as a SCRAM verifier) and exists only in a GitHub Actions secret. Neither app, nor the API, can use it.

No policy grants any cross-user access. There is no role/claim for "admin" or "viewer" anywhere in the schema or policies. Admin access to raw data happens exclusively via the Supabase dashboard (which authenticates as the project owner, outside of RLS), never through either client app. The pgTAP suite in `/supabase/tests` checks all of this against the hosted project.

## 5. Auth

- **Google Sign-In** is the account on both apps, via Supabase Auth's Google provider. The Email provider is off. The web can add Windows Hello passkeys on top (below).
- **Web**: OAuth redirect flow. The deployed web URL and `localhost` (dev) must be in Supabase's Redirect URLs, and the Web OAuth client's JavaScript origins must include them. Google's redirect URI is only the Supabase callback.
- **Mobile**: **native** Google Sign-In (Android Credential Manager via `google_sign_in`), with **no browser redirect**:
  - The app requests an ID token for the **Web** client ID (`serverClientId`) and passes it to `supabase.auth.signInWithIdToken(provider: google)`.
  - Google only issues that token to an app whose package name and signing-certificate SHA-1 match an **Android** OAuth client in the same Google Cloud project.
  - Supabase's Google provider lists the Web and Android client IDs as authorized client IDs.
  - No redirect scheme is needed for mobile.
- **Mobile app lock** (fingerprint / pattern) is a **client-side gate on top of** an already-valid Supabase session. It is not a second authentication factor recognized by the backend. It controls whether the app *shows* data it already has a valid session for, not whether Supabase will serve that data.
- **No password reset system** (no reset emails or codes), since there's no app-specific password. The lock screen's **"Forgot pattern?"** option signs the user out and deletes the stored pattern. They re-authenticate with Google and set a new pattern.
- **Windows Hello (web)**: Supabase Auth passkeys (beta), in addition to Google, never instead of it (`DECISIONS.md` D26).
  - Relying party: ID `ventrafin.vercel.app`, origin `https://ventrafin.vercel.app`. Passkeys therefore don't work on localhost or Vercel preview URLs.
  - A signed-in user registers, lists and removes passkeys in Settings (`supabase.auth.registerPasskey()`, `auth.passkey.list/delete`).
  - The sign-in page offers `signInWithPasskey()` only when:
    - the browser has WebAuthn;
    - the project's public `/auth/v1/settings` says `passkeys_enabled`;
    - this browser has seen the account use a passkey (a `localStorage` hint).
  - A passkey sign-in produces an ordinary Supabase session, so everything after it is the same as with Google.

## 6. Mobile app (Flutter)

- Target: **Android only**. Package name `com.ventrafin.app` (see `DECISIONS.md`).
- **Config** at build time via `--dart-define-from-file` (`mobile/config/*.json`, gitignored): Supabase URL, anon/publishable key, Google Web client ID. Nothing is hardcoded or committed.
- `supabase_flutter` for auth, data access and Realtime. **Riverpod** for state (see `DECISIONS.md`) and **go_router** for routes.
- **App lock**:
  - The pattern is stored only as a salted PBKDF2-HMAC-SHA256 hash, in Android-Keystore-backed secure storage, per user.
  - Fingerprint comes first (via `local_auth`), with the pattern as fallback.
  - The app locks on cold start, and on resume after a background timeout (a constant in code).
  - The lock is an overlay above the navigator, so an in-progress entry survives a re-lock.
- **Reminders** (`DECISIONS.md` D24): `flutter_local_notifications`, scheduled on the phone from `profiles` and `get_bill_schedule()`, with no server push.
  - A pure planner (`features/reminders/reminder_plan.dart`) turns the profile and bills into a list of notifications; a provider replaces everything scheduled with that list whenever a setting or a bill changes (here or on the web, via Realtime) and on returning to the app.
  - Daily reminder: repeats every day at `daily_reminder_time` in Asia/Kolkata. Bill reminders: 9:00 am IST `bill_reminder_days_before` days before the due date and on the due date, for the next three months of each bill with both its own switch and the master switch on. Nothing is scheduled for an already-overdue month.
  - Exact alarms when Android allows them (`SCHEDULE_EXACT_ALARM`), inexact otherwise. A boot receiver restores them after a restart. Signing out cancels them.
  - Tapping a reminder opens Add (daily) or Bills.
- `fl_chart` for the Dashboard donut and the Reports charts.
- **Navigation**: bottom nav bar (Dashboard / Transactions / Add / Bills / More). **More** leads to Categories, Accounts, Reports and Settings. Each is a distinct route, not a single scrolling page.
- **Reports** (`/more/reports`): a month picker; that month's totals (spent, income, net, saved %) against the month before; spending and income by category with entry counts and shares; then 6- or 12-month trends ending with the chosen month: income against spending (grouped bars + table) and spending by category (stacked bars of the top five plus Other + a category × month table that scrolls sideways).
- **Bills** (`/bills`): bills soonest due first with a status chip, a bell per bill for its reminder, and a sheet to mark a month paid (optionally logging the payment) or edit/delete. `/bills/new` and `/bills/:id` are the form.
- **Settings**:
  - reminders: daily switch and time, bill master switch and how many days before, notification and exact-alarm permission states, a test notification;
  - the theme picker;
  - **Your data**: export a CSV (this/last month, this/last financial year, all time, chosen dates) through Android's share sheet (`share_plus`), and a note on backups;
  - app lock and sign-out.
- **Themes** (`DECISIONS.md` D22): `buildAppTheme` builds the `ThemeData` from the generated tokens; the app bar uses the theme's brand colour, cards and sheets stay white on the theme's page colour.
- **Entry flow**:
  - An on-screen number keypad comes first, then the other fields.
  - "Save & add another" supports end-of-day batch logging and keeps the date, type, account and payment method between entries.
  - The last-used account and payment method are remembered on the device (UI preference only, not data).
- **Realtime**: the app subscribes to all five published tables and re-fetches the affected view on change, on reconnect and on resume.
- **No offline mode**: a visible "no internet" state, and every failed save is reported with the form kept intact.
- **Visual recognition** (D13, D14):
  - Every category shows as its icon in a filled circle of its colour, in the transaction list, pickers, the Categories screen and the Dashboard. Uncategorized is an outlined amber `?` and transfers an outlined grey arrow.
  - Descriptions get a merchant letter badge.
  - Accounts and payment methods have fixed icons.
  - The icons sit inside the existing two-line rows, so the list is no taller (a widget test checks this).
- **Dashboard** adds a this-month spending-by-category donut and a this-vs-last-month table per category, from `get_month_comparison`.
- **Categories screen**: rename a category (name checked against the same rules as the database: 1–40 characters, not "Uncategorized", unique per kind) and change its icon and colour.
- **FLAG_SECURE** (D15): blank in recent apps, no screenshots or screen recording.

## 7. Web app (Vue 3)

- Vue 3 (Composition API) + Vite + TypeScript, **PrimeVue 4** + **Tailwind CSS 4**, `supabase-js`. It is a static site (SPA build) with no server-side rendering, API routes or serverless functions of its own. All logic is either in the browser or in Supabase.
- **Routes** (Vue Router, one per section): `/dashboard`, `/transactions`, `/add`, `/categories`, `/accounts`, `/bills`, `/reports`, `/settings`, plus `/login` and `/auth/callback`. It's a genuine multi-page app, not a single scrollable view.
  - A route guard waits for the stored session to load, then sends signed-out users to `/login?next=<path>`. After sign-in they come back to that path (same-app paths only).
  - Signing out anywhere returns to `/login`.
- **Auth**: Google through Supabase's browser OAuth flow with **PKCE** (`flowType: 'pkce'`).
  - Sign-in leaves for Google and returns to `/auth/callback?code=…`. supabase-js exchanges the code while it starts up.
  - The session is kept by supabase-js in `localStorage`. Signing out on the web signs out this browser only.
- **Config** at build time from Vite env vars: `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` (`web/.env.local` locally, gitignored; project settings on Vercel). The app refuses a secret key.
- **Data layer** (`src/data`):
  - Pages go through a `FinanceRepository` interface, which component tests replace with an in-memory fake.
  - An app context holds a revision counter per Realtime table. `liveQuery(tables, fetch)` re-fetches whenever a table it reads changes, keeping the old data on screen meanwhile. This is the same design as the phone's Riverpod revisions (D11).
  - Accounts and categories are shared live queries.
  - Every request has a 15 s timeout, so a dead connection surfaces as an error instead of a spinner.
- **Realtime**: one channel per signed-in user for all five published tables.
  - Events are debounced by 300 ms into revision bumps.
  - (Re)subscribing re-fetches everything, as does coming back online or returning to a tab that was hidden for more than 30 s.
  - The top bar shows *Live* / *Reconnecting…*.
- **Add** is a custom always-editable grid (D16) with the same validation as the phone.
  - Rows are text, like spreadsheet cells, and pass through one parser (`src/lib/entryRow.ts`) whether typed or pasted.
  - Saving inserts all ready rows in one statement, with client-generated ids so a retry can't duplicate.
  - Rows pasted from Excel go through a preview (`src/lib/paste.ts`) that detects columns, marks invalid rows and saves only after confirmation.
- **CSV** (`DECISIONS.md` D25):
  - **Export** on Transactions ("what the page shows", filters included, or a date range) and in Settings. The file comes from `export_transactions_csv` and is downloaded with a UTF-8 byte-order mark.
  - **Import** in Settings: a `.csv` file becomes the same table as a paste (`src/lib/csvImport.ts`), and the shared preview (`components/import/`) checks it with the same parser. Beyond the paste flow, it:
    - skips rows already in Transactions unless asked;
    - saves in 500-row batches with fixed ids;
    - sends rows with problems to the Add grid.
- **Windows Hello**: `src/data/passkeys.ts` (Supabase implementation, support checks, plain-language errors), Settings › Sign in with Windows Hello, and the extra button on `/login`.
- **Transactions** uses PrimeVue's DataTable in cell-edit mode. A finished cell edit becomes a one-column update (`src/lib/cellEdit.ts`); a category change is what feeds the learning trigger. Saves are shown straight away and rolled back with a message if they fail.
- **Money** stays integer paise in state (the database's `< 10^15` bound keeps every value a safe JavaScript integer). Rupees appear only in formatted strings with Indian grouping (`₹1,23,456.00`).
- **Dates** are ISO strings; "today" is Asia/Kolkata whatever the PC's timezone.
- **Visuals** match the phone:
  - Material Symbols glyphs for the same icon keys, bundled as SVG paths generated from the icon package (D17);
  - category circles and colours from `/shared/category-style.json`;
  - the same merchant letter badges (FNV-1a, checked against vectors printed by the Dart code);
  - account and payment-method icons;
  - the same six themes (below).
- **Reports** and **Bills** match the phone's (same SQL functions, same wording). Charts are SVG drawn by the app (no chart library): one rupee axis, the same numbers in a table beside each chart, and a tooltip per month. Bills has no notifications of its own (they are on the phone); it shows due-soon and overdue in colour and lets Dad mark bills paid, add, edit and delete them.
- **Themes**: applied from `profiles.theme` (the phone's change arrives via Realtime) by setting CSS variables for the brand colours and swapping PrimeVue's preset; the last theme is kept in `localStorage` so the page opens in it.
- **No offline mode**: an offline banner, and saves are refused with a message while offline. Every failed save says why and keeps what was typed.
- Hosted on **Vercel**. `web/vercel.json` rewrites every path to `index.html` (so deep links and refreshes work) and sets security headers:
  - a CSP allowing only the app's own origin and the Supabase project's `https://`/`wss://` URL. Styles also allow `'unsafe-inline'`, because PrimeVue injects its theme at runtime. There are no third-party fonts or scripts;
  - `X-Frame-Options: DENY`, `nosniff`, a referrer policy, a permissions policy, COOP/CORP and HSTS.

## 8. Shared theming

`/shared/theme-tokens.json` defines the six themes and the semantic colours (`DECISIONS.md` D22). Each theme has:
- `brand` / `onBrand` / `brandIndicator`: the phone's app bar and the web sidebar, the text on them, and the current-section marker;
- `primary` / `primaryHover` / `primarySoft`: buttons, links, switches and selections, readable as text on white and under white text, and the highlight behind selected rows;
- `accent` / `onAccent` / `accentSoft`: secondary highlights (the phone's navigation indicator);
- `page`: the background behind the white cards;
- `primaryScale`: shades of `primary` for PrimeVue.

The web app imports the JSON; the phone's `theme_tokens.g.dart` is generated from it by `mobile/tool/gen_theme_tokens.dart`, and a test fails if it is stale. The semantic colours (expense red, income green, transfer grey, Uncategorized amber) and the category colours are the same in every theme. The theme is stored in `profiles.theme`: picking one on either app applies it at once, and the other follows through Realtime.

## 9. What's deliberately absent

- No custom backend server, API layer, or serverless functions — Postgres (via RLS + SQL functions) is the only "backend logic" layer. The one scheduled job, the weekly backup, runs on GitHub Actions against the read-only `ventrafin_backup` role and serves no app traffic (`supabase/BACKUPS.md`).
- No local database or offline cache on either client.
- No client-side encryption/key management.
- No in-app admin or shared-viewer role, and no RLS bypass reachable from either client.
