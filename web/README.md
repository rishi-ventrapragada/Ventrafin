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
- Every page updates live when something changes on the phone (Supabase Realtime). The top bar shows **Live**, or **Reconnecting…** if the connection drops. When the browser goes offline a red banner says so, and saves are refused with a message; nothing fails silently.

## Layout

```
index.html, vite.config.ts, vercel.json      entry, build + test config, Vercel rewrite + security headers
demo.html, demo/                              dev-only demo on fake data
scripts/gen-icons.mjs                         Material Symbols -> src/lib/icons.generated.ts
src/
  main.ts, App.vue, router.ts, ui.ts          bootstrap, routes + sign-in guard, PrimeVue (Ocean preset)
  lib/        pure logic, no Vue: money (paise <-> ₹), dates (IST), entryRow (grid row parser),
              paste (Excel clipboard), cellEdit (table edits), models, categoryStyle + merchant
              (mirror /shared/category-style.json), options, errors, generated icons, DB types
  data/       repository interface + Supabase implementation, auth (Google, PKCE), app context
              (revisions per table, Realtime, online state, liveQuery), entry prefs
  components/ icons, category/merchant/account badges, ComboInput (pick-list cell), month switcher,
              donut, app shell, add/ (EntryGrid, PasteDialog, SavedPanel)
  pages/      Dashboard, Transactions, Add, Categories, Accounts, Bills*, Reports*, Settings, Login,
              AuthCallback, NotFound (* placeholders until phases 5-6)
tests/
  unit/       money, dates, paste, entryRow, cellEdit, visuals (icons/palette/badges = phone), deploy (CSP)
  components/ Add grid; Transactions, Categories, Dashboard, Realtime, sign-in guard
  support/    fake repository, mountApp helper
```
