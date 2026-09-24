# Ventrafin — Product Requirements

## 1. Summary

Ventrafin is a home finance tracker built for one primary user — a non-technical, Excel-literate person referred to throughout as **Dad**. He splits usage between an **Android phone** and a **Windows PC** (used via a web browser), logs transactions mostly in a batch at the end of the day, and wants a private, simple-to-enter, detail-rich view of his spending. A second person (the builder/admin) manages the system but does not need in-app visibility into the data.

## 2. Users

- **Primary user ("Dad").** Uses both apps. Logs transactions, views spending, manages categories and bills, sets his own reminders and theme.
- **Admin (the builder).** Not a role inside the app. Manages the Supabase project directly via the Supabase dashboard for support, fixes, and backups. Cannot see data through either client app.

There is no multi-tenant concept beyond standard Supabase Auth users — the schema supports more than one signed-in user (each fully isolated by RLS), but the product is designed around Dad as the only real user for now.

## 3. Priorities (in order)

1. **Ease of use** for a non-technical, Excel-comfortable user
2. **Privacy** — no one but Dad can see his data inside the app
3. **Reliability of sync** between phone and PC

Note: this product does **not** use client-side encryption or a local on-device database (see `DECISIONS.md` for why). Privacy is enforced entirely through Supabase Row Level Security. The admin retains dashboard-level access to the raw data by design.

## 4. Core features

### 4.1 Accounts
Three account types: **Cash, Bank, Credit Card**. Each transaction is tied to one account (or two, for transfers).

### 4.2 Transactions
- Fields: date, amount, description, account, category, payment method (Cash / UPI / Debit / Card), type (Expense / Income / Transfer), destination account (transfers only).
- Amounts are stored as integer paise everywhere.
- **Entry must be fast and forgiving of batch entry**, since Dad logs at the end of the day, not in real time:
  - **Mobile:** number-keypad-first entry flow, with a "Save & add another" action that keeps the user on the entry screen for successive entries.
  - **Web:** an editable, spreadsheet-style grid (tab/enter to move between cells) that supports **pasting rows directly from Excel**, plus CSV/Excel file import.
- Editing and deleting past transactions is supported on both apps.

### 4.3 Categories
- Dad starts with a **preset set of common Indian household categories** (Groceries, Bills, Medical, Transport, Food, Electricity, Entertainment, Other) which he can rename, recolor, add to, or archive.
- Categories are split into **expense categories** and **income categories**.
- An **Uncategorized** bucket collects anything auto-categorization couldn't resolve, surfaced somewhere Dad will notice it (e.g., a dashboard callout or filter).

### 4.4 Auto-categorization
- On transaction entry, if no category is chosen:
  1. Check the user's own learned rules (`category_rules`: keyword → category), built from corrections Dad has made in the past.
  2. Fall back to a built-in keyword list for common Indian merchants/services (e.g. Swiggy/Zomato → Food, Apollo/Medplus → Medical, DISCOM/electricity board names → Electricity, DMart/supermarket chains → Groceries).
  3. If a matched category doesn't exist yet for this user, create it automatically.
  4. If nothing matches, leave it in Uncategorized.
- Every time Dad manually corrects an auto-assigned category, that correction should strengthen or create a rule in `category_rules` so the same description is categorized correctly next time.
- This logic must behave identically regardless of which app the transaction was entered from — implement it once, in the database (see `ARCHITECTURE.md`).

### 4.5 Budgets — explicitly out of scope
Dad does not want spending limits. **Do not build budget caps or overspend alerts.** In their place:

### 4.6 Reporting
- **This month vs. last month** comparison, both overall and broken down by category.
- Totals by category for the current and past months.
- Charts (bar/line, category breakdown) on both apps.
- A dense, table-first reports view — not a simplified summary-only screen.

### 4.7 Recurring bills & reminders
- Bill types: **Utility bills** (electricity, water, gas, phone/internet) and **Loan EMIs**.
- Each recurring bill has: name, kind, amount, due day, linked account, category, and its own reminder on/off toggle.
- A separate **daily evening reminder** ("log today's expenses") with its own toggle.
- A **master reminders switch** that can turn all reminders off/on at once, in addition to the per-bill and daily-nudge toggles.
- Reminders fire on the **mobile app only** (via local notifications). The web app can show a "due soon" panel but does not push notifications.

### 4.8 Themes
- **Light mode only** — no dark mode.
- Multiple color theme options, each pairing a primary and accent color, shared between both apps from one token source:
  - Ocean (blue / teal)
  - Sunset (blue / coral)
  - Forest (green / amber)
  - Garden (green / rose)
  - Sunflower (yellow / orange)
  - Marigold (yellow / plum)
- Theme choice is stored per-user (`profiles.theme`) so switching on one device updates the other.

### 4.9 Import / export
- CSV/Excel **export** of transactions.
- CSV/Excel **import**, feeding into the same entry/auto-categorization pipeline.

### 4.10 Security & access
- **Google Sign-In** on both apps — no separate password to manage or reset.
- **Mobile:** app lock via fingerprint, with an in-app pattern (Android-style dot pattern) as fallback. The lock screen shows a visible **"Forgot pattern?"** option (Dad asked for a forgot-password option): it signs him out, he signs back in with Google, and sets a new pattern. No separate reset emails or recovery codes.
- **Web:** Google session is the login. Windows Hello (via Supabase passkeys) is a **later-phase nice-to-have**, not required for launch.
- **RLS on every table** — a signed-in user can only ever see and modify rows they own. No exceptions and no in-app admin role. The admin manages data exclusively through the Supabase dashboard, outside the app.

## 5. Non-functional requirements

- **No offline mode.** Both apps require an internet connection; show a clear "no connection" state rather than failing silently. (Accepted tradeoff — see `DECISIONS.md`.)
- **Realtime sync**: a change made on one app should appear on the other within a few seconds, using Supabase Realtime — no manual refresh needed.
- **UI density**: detailed/dense views, not oversized simplified UI — Dad is an experienced Excel user, not someone who needs hand-holding.
- **Navigation**: multi-page/multi-route on both apps (sidebar or bottom nav + distinct routes), not single long scrolling screens.
- **Backups**: since the Supabase free tier has no automatic backups, a periodic (e.g. weekly) export mechanism should exist so data isn't reliant on Supabase alone. Exact mechanism is open — flag as a follow-up if not solved during initial build.

## 6. Out of scope (initial build)

- Budgets / spending limits / overspend alerts
- Client-side encryption
- Local/offline database
- In-app admin/shared-viewer role of any kind
- Dark mode
- iOS, macOS, or Linux targets
- Bank sync / Plaid-style automatic transaction import

## 7. Build phases

1. **Supabase foundation** — schema, RLS policies, auto-categorization trigger, seed categories, Google auth configured.
2. **Mobile core** — Google login, lock screen (fingerprint + pattern), quick/batch entry, transaction list, realtime updates.
3. **Web core** — Google login, editable grid with Excel paste, realtime updates. Verify cross-app sync end-to-end here.
4. **Categorization** — auto-categorization wired into both entry flows, correction-learning into `category_rules`, Uncategorized surfacing.
5. **Reporting** — month-vs-month comparisons, category totals, charts, dense summary views.
6. **Reminders** — daily nudge, bill/EMI reminders, master + per-item toggles (mobile only).
7. **Polish** — themes, CSV/Excel import/export, Windows Hello on web, backup mechanism.

Each phase should be independently usable/demoable before moving to the next.
