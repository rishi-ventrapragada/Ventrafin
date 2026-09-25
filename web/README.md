# /web: Ventrafin web app (Vue 3)

The PC side of Ventrafin: a static single-page app that talks only to Supabase (no server code). Vue 3 (Composition API) + Vite + TypeScript, Vue Router, PrimeVue 4 + Tailwind CSS 4, `supabase-js`. See `ARCHITECTURE.md` § 7 and `DECISIONS.md` D16–D18.

## Run it locally

Needs Node 22 or 24.

```powershell
cd web
Copy-Item .env.example .env.local   # then fill in the two values (see below)
npm install
npm run dev                         # http://localhost:5173
```

| `.env.local` key | Where to find it |
|---|---|
| `VITE_SUPABASE_URL` | Supabase dashboard → Project Settings → API (`https://<ref>.supabase.co`) |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Same page. The **publishable** key (`sb_publishable_…`). The app refuses to start with a secret key |

`.env.local` is gitignored. Both values are safe in a browser: access is enforced by Row Level Security.

Sign-in is Google through Supabase (PKCE). It comes back to `http://localhost:5173/auth/callback`, so the Supabase project's Redirect URLs must allow `http://localhost:5173/**`. Port 5173 is fixed (`strictPort`) for that reason.

Other scripts:

```powershell
npm test               # unit + component tests (Vitest, jsdom)
npm run typecheck      # vue-tsc over the app and the tests
npm run build          # type-check + production build into dist/
npm run preview        # serve dist/ on :5173
node scripts/gen-icons.mjs   # regenerate src/lib/icons.generated.ts after changing the icon list
```

**Demo page (dev only):** `http://localhost:5173/demo.html` runs the real app on an in-memory fake repository with made-up sample data. There's no sign-in and nothing is saved. It's for looking at the UI and taking screenshots. `npm run build` only builds `index.html`, so the demo never ships.

## Using it

- **Add** is a spreadsheet. Tab/Shift+Tab move between cells. Enter/↓ go to the same column in the next row, and Enter on the last row adds one. Shift+Enter/↑ go up. Other keys:
  - Ctrl+D copies the cell above.
  - Ctrl+; puts today's date in a date cell.
  - Alt+↓ opens a pick list.
  - Ctrl+S saves.

  New rows start with today's date (India time), Expense, category **Auto**, and the last-used account and payment method. A row's problems show once you leave it. Saving stores every ready row in one request. Rows with problems stay in the grid, highlighted. Saved rows appear below the grid with the category the database gave them.
- **Paste from Excel**: paste several cells anywhere in the grid (or use the button).
  - A preview shows how Ventrafin read each column. Change any column it got wrong.
  - It marks rows that can't be saved and says why.
  - Nothing is saved until you press **Save N rows**. Rows with problems go into the grid to fix.
  - It understands:
    - heading rows in any order;
    - bank statements (Withdrawal/Deposit columns; Balance and reference columns are ignored);
    - Indian dates (`dd/mm/yyyy`, `25-Sep-26`, `25/09`, Excel day numbers);
    - amounts with `₹`, `Rs`, commas, `-500`, `(500)`, `Dr`/`Cr`;
    - payment words like GPay, PhonePe, "credit card".
- **Transactions**: click a cell to edit it in place. Enter or Tab saves, Esc cancels. Changing a category teaches the database's learning trigger, as on the phone. Filter by month (kept in the URL), account, category (including *Uncategorized* and *Transfers*) and text. Delete one row or several; both ask first.
- **Reports**: pick any month for its totals and categories against the month before, then 6- or 12-month trends: income against spending, and spending by category (top five in the chart, every category in the table below it). Hover a month in a chart to see its numbers.
- **Bills**: what's due, soonest first; overdue in red, due within a week in amber. **Mark paid** can add the payment to Transactions in the same step. Add, edit, delete, and switch a bill's reminder on or off here; the reminders themselves pop up on the phone.
- **Export (CSV for Excel)**: on Transactions (first choice: exactly what's on screen, filters included) and in Settings (this or last month, this or last financial year, all time, or any dates). The file is built by the database, so the phone's export is identical. It opens in Excel with a double-click.
- **Settings › Import transactions from a CSV file**: a bank statement or spreadsheet saved as CSV ("CSV UTF-8" in Excel), or a Ventrafin export.
  - The same preview as Paste from Excel: the columns it recognised, and every row checked before anything is saved.
  - Pick the account and "paid by" for rows that don't say.
  - Rows already in Transactions (same date, amount, account and description) are skipped unless you tick "Save them anyway".
  - Rows with problems go to the Add grid to fix.
- **Settings › Sign in with Windows Hello**: set up a passkey on this PC, then use "Sign in with Windows Hello" on the sign-in page. Google keeps working. It only works on `https://ventrafin.vercel.app`, not on localhost or preview URLs, and only once passkeys are switched on in the Supabase dashboard (DECISIONS.md D26).
- **Settings › Theme**: six colour themes; the phone follows.
- Every page updates live when something changes on the phone (Supabase Realtime). The top bar shows **Live**, or **Reconnecting…** if the connection drops. When the browser goes offline a red banner says so, and saves are refused with a message; nothing fails silently.

## Layout

```
index.html, vite.config.ts, vercel.json      entry, build + test config, Vercel rewrite + security headers
demo.html, demo/                              dev-only demo on fake data (demo.html?theme=marigold for another theme)
scripts/gen-icons.mjs                         Material Symbols -> src/lib/icons.generated.ts
src/
  main.ts, App.vue, router.ts, ui.ts          bootstrap, routes + sign-in guard, PrimeVue (theme preset)
  lib/        pure logic, no Vue: money (paise <-> ₹), dates (IST), entryRow (grid row parser),
              paste (Excel clipboard), cellEdit (table edits), models, categoryStyle + merchant
              (mirror /shared/category-style.json), theme (/shared/theme-tokens.json: CSS variables +
              PrimeVue preset), reports (trend shaping, axis labels), bills (status wording),
              options, errors, generated icons, DB types, csvImport (reading CSV files), exportRange
              (presets, financial year, file names), duplicates (rows already saved), download
  data/       repository interface + Supabase implementation, auth (Google, PKCE), app context
              (revisions per table, Realtime, online state, liveQuery), entry prefs, passkeys
              (Windows Hello: support checks, Supabase calls, plain-language errors), gridHandoff
  components/ icons, category/merchant/account badges, ComboInput (pick-list cell), month switcher,
              donut, bar chart (SVG), bill + mark-paid dialogs, app shell,
              add/ (EntryGrid, PasteDialog, SavedPanel), import/ (RowsPreview + previewRows shared by
              paste and CSV import, ImportDialog), ExportDialog, PasskeySection
  pages/      Dashboard, Transactions, Add, Categories, Accounts, Bills, Reports, Settings, Login,
              AuthCallback, NotFound
tests/
  unit/       money, dates, paste, entryRow, cellEdit, visuals (icons/palette/badges = phone), deploy (CSP),
              themes (all six: contrast, category colours, glyphs = phone), reportsBills,
              importExport (CSV round trip of the SQL export, ranges, duplicates, passkey errors)
  components/ Add grid; Transactions, Categories, Dashboard, Realtime, sign-in guard; Reports, Bills,
              Settings theme (phase567); export, import, Windows Hello (phase7)
  support/    fake repository, mountApp helper
```
