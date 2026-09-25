# Ventrafin — Full audit (25 September 2026)

Read-only audit of both apps, the Supabase schema and the repo configuration, done just after Dad started using the app with real data. Nothing was changed and no user rows were read; the hosted project was inspected only through the read-only MCP (schema, policies, advisors, migration hashes).

**Primary lens:** ease of use and design, judged as a 40-year-old non-technical Excel user. **Secondary:** PRD gaps, backend, security and privacy, code health.

**Severity:** critical = Dad is blocked or loses data · high = a daily annoyance or an unreadable/unsafe state · medium = friction he will notice · low = polish.

**Tracking.** This file is a living tracker. Every finding has an ID and a Status: `open`, `fixed (<commit>)`, `won't fix (<reason>)` or `deferred (<reason>)`. Check it before starting work and update the status when an item is fixed. The findings text is kept as audited (file:line pointers refer to the code on 25 September 2026). Backups are decided (D28) and are not to be raised again.

**Rounds.** Round 1 (branch `audit-round-1`): the Fix-first list except backups; NAV-1, NAV-2, TX-1; every web dialog (focus, Enter, focus rings); BILL-3; Categories and Accounts (PRD § 4.1, § 4.3); the security quick wins; housekeeping. Round 2 (branch `audit-round-2`): every open medium item. Everything still `open` is low severity or info, or was found later.

## Overall verdict

The backend is solid: RLS, grants, composite keys, function hardening, CSP, secrets handling and migration hashes all check out, and every test suite passes (Flutter 159/159; web 203/205 with two flaky timeouts; typecheck and analyzer clean).

For Dad the biggest problems are navigation and dead ends: the phone's back button exits the app from most tabs, neither app warns before throwing away half-typed entries, load errors have no Retry, the phone has no way to search transactions, and Categories/Accounts still say "coming in a later update". Below that sits a layer of polish: contrast slips in a few visible places, dialogs that ignore Enter, and wording that differs between phone and web.

## 1. Fix first

The ten items with the most relief per hour, in order. Where a later table repeats one of these, its row points back here.

| ID | Sev | App | Finding | Where | Fix | Status |
|---|---|---|---|---|---|---|
| FIX-1 | critical | phone | Android back exits the app from any tab except Dashboard, and from screens reached by cross-tab jumps. No `PopScope` exists anywhere | `mobile/lib/router.dart:50-116`, `mobile/lib/features/shell/app_shell.dart` | `PopScope` in the shell that returns to Dashboard first, then exits | fixed (2f02a91) |
| FIX-2 | high | both | No unsaved-changes warning. Web has no route-leave or `beforeunload` guard at all, so typed Add rows vanish on a sidebar click or F5. Phone Edit transaction, Bill form, Change pattern and the Category sheet discard silently on back | `web/src/pages/AddPage.vue:73` | Guard when dirty, "Discard changes?" | fixed (2f02a91 phone, 84f57ad web) |
| FIX-3 | high | both | Phone Transactions has no search or filter, and the amber "Uncategorized N" cell is not tappable. Web search covers only the shown month | `mobile/lib/features/transactions/transactions_screen.dart:19-67`, `web/src/pages/TransactionsPage.vue:131-149` | App-bar search on the phone, tap-to-filter on the count, "all months" search on the web (`fetchTransactionsBetween` already exists) | fixed (2f02a91 phone, 84f57ad web) |
| FIX-4 | high | both | Categories cannot be added or archived, Accounts cannot be added or renamed, and both screens say "coming in a later update". PRD § 4.3 promises add/archive | `categories_screen.dart:48-50`, `web/src/pages/CategoriesPage.vue:90-92`, `web/src/pages/AccountsPage.vue:41` | Build them (needs an `accounts.archived` column) or reword the note as a fact | fixed (2f02a91 phone, 84f57ad web; schema 1154d44, applied as migration 20260925181348) |
| FIX-5 | high | both | Load errors are dead ends on Dashboard, Reports, Categories and Accounts (no Retry; the phone Dashboard has no pull-to-refresh), and phone Accounts prints the raw exception string | `simple_screens.dart:180` | Reuse the Transactions `LoadError` + Retry pattern everywhere | fixed (2f02a91 phone, 84f57ad web) |
| FIX-6 | high | web | Save confirmations are hard to read. PrimeVue Aura's default toast puts green-600 on green-50 (3.1:1) and yellow-600 on yellow-50 (2.8:1); this is the only feedback after a save | `web/src/lib/theme.ts` | Override toast colours in the preset | fixed (84f57ad) |
| FIX-7 | high | web | A cell in Transactions can only be edited with the mouse. PrimeVue starts cell edit on click only and cells have no `tabindex` | `TransactionsPage.vue:433` | Focusable cells, Enter or F2 to edit | fixed (84f57ad) |
| FIX-8 | high, verify on device | phone | Status-bar clock and battery invisible on the lock and login screens in Ocean/Sunset/Forest/Garden. Nothing sets a status-bar style for screens without an AppBar, so white icons sit on the near-white page | `lock_gate.dart:71`, `android/app/src/main/res/values/styles.xml` | `AnnotatedRegion<SystemUiOverlayStyle>` with dark icons on Login, splash and the lock overlay, plus `windowLightStatusBar` in both Android styles | fixed (2f02a91); verify on device |
| FIX-9 | high | phone | "Uncategorized N" on the Transactions summary uses the pale amber (4.2:1, 3.8:1 on highlighted rows) where every other amber label uses the ink shade | `transactions_screen.dart:96` | One-token fix: `kUncategorizedInkColor` | fixed (2f02a91) |
| FIX-10 | medium | backend | Dad's real data has no backup at all (DECISIONS.md D28; the free plan keeps none) | `supabase/BACKUPS.md` | Run the one-time setup and restore the schedule | won't fix: decided against backups (D28) |

## 2. Findings by screen

### Navigation and shell

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| NAV-1 | medium | phone | Cross-tab jumps (Dashboard → Reports, Bills bell → Settings, Settings → Bills) use `go`, so back lands on More or exits | `simple_screens.dart:99`, `bills_screen.dart:34`, `settings_screen.dart:251` | Push these as root-navigator routes | fixed (2f02a91) |
| NAV-2 | medium | phone | While locked, back is handled by the router first and can pop the hidden Edit/Bill screen underneath, losing edits | `lock_gate.dart:71-84`, `lock_screen.dart:46-50` | `PopScope(canPop: !locked)` around the Stack | fixed (2f02a91) |
| NAV-3 | medium | phone | First-run Set up lock has no way out if the wrong Google account was picked | `setup_lock_screen.dart:148-151`, `router.dart:41` | "Not you? Sign out" link | fixed (b0f700a) |
| NAV-4 | medium | web | Dashboard month and Reports month/span live in memory only; back or F5 resets them. Transactions already keeps them in the URL | `DashboardPage.vue:25`, `ReportsPage.vue:26,30` | Same query pattern as Transactions | fixed (e1e8700) |
| NAV-5 | medium | web | Layout does not fit a 1080p screen at 150 % Windows scaling (1280 CSS px): fixed 13 rem sidebar + Add grid `min-width: 67rem` + fixed table columns, so grids scroll sideways and toolbars wrap | `AppShell.vue:53`, `EntryGrid.vue:434`, `TransactionsPage.vue:472-619` | Collapse the sidebar under ~1400 px; let Description shrink | fixed (e1e8700); check the fit in a real 1280 px window |
| NAV-6 | medium | both | Section order differs: Bills is 4th on the phone, 6th on the web | `AppShell.vue:17-26` | Reorder the web sidebar to match | fixed (e1e8700) |
| NAV-7 | medium | web | Sidebar Sign out has no confirmation; Settings and the phone both ask | `AppShell.vue:41-47` | Same confirm | fixed (e1e8700) |
| NAV-8 | low | web | Session expiry sends to /login with no reason and no return path | `router.ts:73-75` | Pass `next` + "You were signed out" | open |
| NAV-9 | low | web | Page title shown twice (top bar and h1); Live tooltip not keyboard-reachable | `AppShell.vue:88-97` | Drop one title; make the status a button | open |
| NAV-10 | low | web | Logo and Login background hardcode Ocean blue on every theme | `AppLogo.vue:8`, `LoginPage.vue:71` | Use brand/page tokens | open |
| NAV-11 | low | web | Search text not in the URL (other filters are) | `TransactionsPage.vue:57` | Add `q` to the query | open |
| NAV-12 | low | phone | Fixed-height message boxes clip at 1.3x font on Lock and Set up lock; "one-way hash" jargon in the setup copy | `lock_screen.dart:169-180`, `setup_lock_screen.dart:159-181` | Min-height instead of fixed; plain words | open |
| NAV-13 | low | both | Technical sign-in errors shown verbatim ("Android OAuth client / SHA-1", raw `error_description`, `?error=`) | `login_screen.dart:36-42`, `AuthCallbackPage.vue:16-19`, `LoginPage.vue:20` | Lead with a plain sentence, detail second | open |
| NAV-14 | low | web | Setup-needed page shows developer instructions | `SetupNeededPage.vue:10-13` | Add a line for Dad | open |

Common tasks from the Dashboard: add an expense 1 tap/click; find a past transaction 2–4 plus scrolling (no search on the phone, one month on the web); mark a bill paid 3–4; this vs last month 0.

### Dashboard

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| DASH-1 | medium | both | The key number does not stand out: this month's Spent is small table text; the month name is bigger | `simple_screens.dart:29-33,54`, `DashboardPage.vue:126` | Promote Spent to a headline figure | fixed (b0f700a phone, e1e8700 web) |
| DASH-2 | medium | phone | "Add today's expenses" sits below the variable-height breakdown card, off-screen in a busy month | `simple_screens.dart:78-96` | Move above the card | fixed (b0f700a) |
| DASH-3 | medium | phone | Fixed 120/110 dp amount columns wrap "₹1,23,456.00" mid-number at large font; This month uses full format, Last month compact | `simple_screens.dart:29-38` | Compact for both, flexible widths | fixed (b0f700a) |
| DASH-4 | medium | web | Overdue and due-soon bills never appear on the Dashboard | `DashboardPage.vue` | Small bills tile linking to Bills | fixed (e1e8700) |
| DASH-5 | low | phone | Uncategorized card opens Transactions unfiltered | `simple_screens.dart:75` | Filter on arrival | fixed (2f02a91) |
| DASH-6 | low | web | "new" / "same" in the Change column reads oddly; empty state has no link to Add | `ChangeCell.vue:12-13`, `DashboardPage.vue:171` | "nothing last month"; add link | open |

### Transactions

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| TX-1 | medium | web | Delete confirm focuses Delete, so Enter deletes, and there is no undo | `TransactionsPage.vue:282-293` | `defaultFocus: 'reject'`, or a 5 s Undo toast | fixed (84f57ad): Cancel focused + 5 s Undo |
| TX-2 | medium | phone | Transfer rows with a payment method overflow on 360 dp phones | `transactions_screen.dart:257-285,343-364` | Drop the method for transfers | fixed (b0f700a) |
| TX-3 | medium | phone | Editing an Uncategorized entry shows "Auto" selected; the list calls the same state "Uncategorized" | `category_picker.dart:50-57`, `entry_form.dart:483-505` | Label the null tile "Uncategorized" in edit mode | fixed (b0f700a) |
| TX-4 | medium | phone | The 11 px "auto" marker uses the outline grey (4.0:1 on highlighted rows) | `transactions_screen.dart` (`_Label`) | Use `onSurfaceVariant` | fixed (b0f700a) |
| TX-5 | medium | web | Error toasts are sticky here but timed on Bills | `TransactionsPage.vue:223,247,300,314` vs `BillsPage.vue:69,86,107` | One rule | fixed (e1e8700) |
| TX-6 | low | web | Accepted date shortcuts (25/9, 25 Sep, t, y) are not discoverable | `TransactionsPage.vue:478`, `dates.ts:126-185` | Placeholder hint | open |
| TX-7 | low | web | Lowercase "expense"/"income" enum shown in the category filter | `TransactionsPage.vue:377` | Proper labels | open |
| TX-8 | low | web | Column "To" vs grid "To account" | `TransactionsPage.vue:586` | "To account" | open |
| TX-9 | low | web | Future-dated rows unreachable via the month switcher (max = current month) | `TransactionsPage.vue:331` | Allow forward when rows exist | open |
| TX-10 | low | web | Row delete icon has no tooltip; selection checkboxes unexplained until ticked | `TransactionsPage.vue:385-398,624` | Tooltip; hint | open |
| TX-11 | low | phone | Day header "3 · spent ₹1,250" needs a noun; swipe-delete has no Undo | `transactions_screen.dart:155,204-220` | "3 entries"; Undo | open |
| TX-12 | low | phone | Summary strip values wrap unevenly at 1.3x | `transactions_screen.dart:80-99` | `FittedBox` | open |

### Add

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| ADD-1 | medium | phone | "Paid by" for expenses but "Payment method (optional)" for income/transfer | `entry_form.dart:413` | "Paid by (optional)" | fixed (b0f700a) |
| ADD-2 | medium | phone | "Yest." chip | `entry_form.dart:459` | "Yesterday" | fixed (b0f700a) |
| ADD-3 | medium | web | Grid header does not actually stay visible after a long paste; the horizontal wrapper is the scroll container | `EntryGrid.vue:208,440-441` | Make the wrapper the vertical scroller | fixed (e1e8700); check in a real browser (jsdom does no layout) |
| ADD-4 | medium | web | Paste dialog opens with focus on the X, though the label says "click in the box" | `PasteDialog.vue:57-65` | `autofocus` the textarea | fixed (84f57ad) |
| ADD-5 | low | phone | Keypad keys are 46 dp; long-press-to-clear undiscoverable | `amount_keypad.dart:81-93` | 48 dp; visible clear | open |
| ADD-6 | low | phone | Validation scrolls to top and can hide the error | `entry_form.dart:152-156` | Scroll to the first error | open |
| ADD-7 | low | phone | Category picker names at 11 sp; Auto explained twice | `category_picker.dart:68-75,111-117`, `entry_form.dart:486-488` | `labelMedium`; keep one | open |
| ADD-8 | low | phone | Account dropdown `initialValue` may not re-sync on first install (verify on device) | `entry_form.dart:107-114,381-388` | Key the field on `_accountId` | fixed (2f02a91): fields keyed on their value; verify on device |
| ADD-9 | low | web | Escape does not revert plain cells; remove-row button skipped by Tab; Ctrl+Enter and F4 undocumented | `EntryGrid.vue:143-178,415`, `ComboInput.vue:143` | Revert on Esc; extend hints | open |
| ADD-10 | low | web | "saved this session" wording | `SavedPanel.vue:29,33` | "Saved just now" | open |

### Bills

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| BILL-1 | medium | web | Enter does nothing in the Add/Edit bill form (no submit button inside the form) or in "Amount paid" | `BillDialog.vue:111,174`, `MarkPaidDialog.vue:92-97` | Submit on Enter | fixed (84f57ad) |
| BILL-2 | medium | web | Both dialogs open with focus on the X | `BillDialog.vue:114`, `MarkPaidDialog.vue:92` | `autofocus` first field | fixed (84f57ad) |
| BILL-3 | medium | both | "undo" means two things: phone Undo reverts the month and deletes the logged expense; web "undo" link only marks unpaid and keeps it, and the web toast has no Undo | `bills_screen.dart:326-337`, `BillsPage.vue:213-220` | Rename the link "Mark unpaid" | fixed (84f57ad) |
| BILL-4 | medium | phone | Bell toggles a reminder on one tap, next to a fully tappable row, with no Undo | `bills_screen.dart:135-194,198-209` | Undo in the SnackBar | fixed (b0f700a) |
| BILL-5 | medium | phone | The "Add bill" FAB is pale in every theme (`primaryContainer` = `primarySoft`) | `theme.dart:15-19`, `bills_screen.dart:38-43` | FAB theme = primary/white | fixed (b0f700a) |
| BILL-6 | low | phone | Paid date is always today | `bills_screen.dart:311` | Date row with "Yesterday" | open |
| BILL-7 | low | phone | "Mark … unpaid" has no confirm; no remote-change banner on the bill form | `bill_form_screen.dart:49-64,312-332` | Confirm or Undo; banner | open |
| BILL-8 | low | web | Edit/Delete icons lack tooltips; bell has no busy state | `BillsPage.vue:63-71,241-246` | Tooltips; disable while pending | open |
| BILL-9 | low | web | Two date formats on one row ("Due 10 Oct" and "10/10/2026"); "Paid from" vs "Account"; native `<select>` differs from every other picker | `bills.ts:22`, `BillsPage.vue:175,203`, `BillDialog.vue:140-155` | One format; "Account"; PrimeVue Select | open |
| BILL-10 | low | both | "Every month" tile label is ambiguous | `bills_screen.dart:105-115`, `BillsPage.vue:145-151` | "All bills, per month" | open |

### Categories and Accounts

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| CAT-1 | medium | web | Accounts page is nearly empty: no per-account total, rows not clickable | `AccountsPage.vue:24-38` | Link rows to filtered Transactions; show this-month spend | fixed (e1e8700; get_account_totals in 4bd2755, applied after branch approval) |
| CAT-2 | medium | phone | Categories load error has no Retry | `categories_screen.dart:53` | `LoadError` | fixed (2f02a91) |
| CAT-3 | low | web | Hex codes shown as a column and read out for swatches | `CategoriesPage.vue:71-73`, `CategoryEditDialog.vue:129` | Named colours | open |
| CAT-4 | low | phone | Swatches 36 dp with no label; icon choices 44 dp | `categories_screen.dart:275-292,312-329` | 44/48 dp; `Semantics` | open |
| CAT-5 | low | web | Category dialog opens on the X | `CategoryEditDialog.vue:102-111` | `autofocus` | fixed (84f57ad) |

### Reports

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| REP-1 | medium | phone | Numeric cells clip silently at large font or large amounts (fixed 80/50/62 dp) | `reports_screen.dart:126-129,189-199,342-369` | `FittedBox` per cell | fixed (b0f700a) |
| REP-2 | medium | phone | Pivot rows are a fixed 28 dp and overlap at 1.5x | `reports_screen.dart:805,817-833` | Scale `_rowH` with the text scaler | fixed (b0f700a) |
| REP-3 | medium | both | "Other" in the category trend is `#B0BEC5`, 1.9:1 against the card, so the top segment and legend swatch look empty | `report_data.dart:21`, `reports.ts:41` | Mid grey ≥ 3:1 or hairline outline | fixed (b0f700a phone, e1e8700 web) |
| REP-4 | medium | both | "Saved" and "Net" are never explained on the web; phone headers "#", "vs last", "Avg" need the subtitle | `reports_screen.dart:304,316,400,865`, `ReportsPage.vue` | One caption under both summaries | fixed (b0f700a phone, e1e8700 web) |
| REP-5 | low | both | Section errors have no Retry (phone has unsignposted pull-to-refresh) | `reports_screen.dart:120-121`, `ReportsPage.vue:126-345` | Retry button | fixed (2f02a91 phone, 84f57ad web) |
| REP-6 | low | web | Top half duplicates the Dashboard; charts cause a ~220 px jump while loading | `ReportsPage.vue:122-261,295-364` | Reserve chart height | open |

### Settings, export, import, Windows Hello

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| SET-1 | medium | web | "passkey" wording on Login, Settings and errors where the feature is called Windows Hello | `LoginPage.vue:100`, `PasskeySection.vue:74,124,146`, `passkeys.ts:121,140` | "Windows Hello sign-in" | fixed (e1e8700) |
| SET-2 | medium | phone | With the daily reminder off, "Reminder time 8:30 pm" renders at 38 % opacity (2.4:1) | `settings_screen.dart:180-239` | Grey only the control | fixed (b0f700a) |
| SET-3 | low | both | "Your session has expired" offers no action; "(23514)" server code leaks in the fallback | `errors.dart:32-36`, `errors.ts` | Sign out automatically; drop the code | open |
| SET-4 | low | web | "Sync with the phone" heading; initial state says "Reconnecting"; theme picker disabled forever on profile error; radio group without arrow keys | `SettingsPage.vue:20-22,71,76,168` | Plain words; Connecting; Retry | open |
| SET-5 | low | web | Two import errors with no next step | `ImportDialog.vue:101,236` | "Save as CSV UTF-8 and try again" | open |
| SET-6 | low | both | Export is called four things across the two apps | `settings_screen.dart`, `export_sheet.dart`, `SettingsPage.vue`, `ExportDialog.vue` | "Export for Excel (CSV)" on both | open |
| SET-7 | low | phone | Auto-lock row looks tappable; "India time" subtitle; theme radios silently disabled while loading; three variants of the offline sentence | `settings_screen.dart:107-113,195,330,342` | Plain text; "Every day"; one sentence | open |
| SET-8 | low | phone | At ×1.5 text on a 360 dp phone the "When to remind" dropdown in Settings overflows by 42 px (found in round 2; the ×1.5 screen tests skip Settings until fixed) | `settings_screen.dart` | Let the row wrap or move the dropdown under its label | open |

### Themes, contrast and keyboard access (cross-cutting)

| ID | Sev | App | Problem for Dad | Where | Fix | Status |
|---|---|---|---|---|---|---|
| UI-1 | medium | web | Garden sidebar is the weakest brand surface: inactive links 4.3:1 at /90, active row 3.6:1 because the highlight lightens the row | `AppShell.vue:67`, `shared/theme-tokens.json` | Darken the active row (`bg-black/15`) instead; drop the /90 | fixed (e1e8700) |
| UI-2 | medium | web | Text inputs have `outline-none` with only a 1 px border change on focus | `TransactionsPage.vue:339`, `BillDialog.vue:106`, `CategoryEditDialog.vue:106`, `MarkPaidDialog.vue:94`, `PasteDialog.vue:61` | Focus ring | fixed (84f57ad) |
| UI-3 | medium | web | Every dialog opens with focus on the X button (only the Add "Not saved" dialog sets `autofocus`) | all dialogs | `autofocus` first field | fixed (84f57ad) |
| UI-4 | medium | web | slate-500 used for informative text ("(no description)", skipped import rows, zero cells) drops to 4.2:1 off-white; disabled cells fade to 50 % opacity yet still carry meaning; a row being saved fades to 60 % | `TransactionsPage.vue`, `SavedPanel.vue`, `RowsPreview.vue`, `ComboInput.vue` | slate-600; colour, not opacity | fixed (e1e8700) |
| UI-5 | low | both | Reject buttons alternate Keep/Cancel on the web; the phone always says Cancel | web confirms | Cancel everywhere | fixed (84f57ad): Cancel everywhere |
| UI-6 | low | both | Yellow themes have no edge between bar and white cards (1.7–2.0:1); pale category circles (`#FFAB91`, `#C0CA33`, `#AED581`) pass the 1.5:1 outline rule only just | tokens; `kCircleEdgeMinContrast` | Optional 1 px border; raise threshold to 2.0 | open |
| UI-7 | low | phone | Disabled › month chevron at 30 % alpha looks like a smudge on yellow themes; Forest/Ocean nav-indicator pill is invisible (1.1:1, cosmetic) | `month_bar.dart`, tokens | Hide the chevron | open |
| UI-8 | low | both | Same icon, different action: `playlist_add` is "Save & add another" on the phone and "Add 5 rows" on the web | `entry_form.dart`, `AddPage.vue` | Different icon on one | open |
| UI-9 | low | both | Minor wording drift: "Due in 7 days" vs "Due in the next 7 days"; "Add one" vs "Add some"; "Deleted ₹1,250.00" vs "Deleted 1 transaction"; "No internet connection. Connect…" vs "There's no internet connection…" | various | Align | open |
| UI-10 | low | web | Sunflower: the current-section marker bar is 2.4:1 against the darkened active sidebar row (3.4:1 against the sidebar; the row is also bold with a filled icon). Found in round 2 (UI-1) | `AppShell.vue`, `shared/theme-tokens.json` | Lighter highlight for the yellow themes or another marker colour | open |

**Verified comfortable in all six themes:** brand text, primary, buttons and the four semantic colours ≥ 4.5:1 on every surface; all 24 category glyph/circle pairs ≥ 4.2:1; category names via `readableTextColor` 4.6–6.1:1; bill chips 5.7–6.8:1; offline banners 6.5:1; error text 5.6–6.5:1; phone body text 17:1, detail text 9.3:1; web body 14.7:1, secondary 7.6:1. Money, dates, error tables, bill wording, export presets and category-name rules are literal mirrors on both apps. Every curated icon key exists on both apps and in the database constraint. The full ratio tables (WCAG and APCA, per theme) were produced by a script during the audit and can be regenerated from `shared/theme-tokens.json`.

## 3. Secondary: PRD gaps, backend, security, code health

### PRD gaps

The bullet findings in this section have an ID and a Status too, like the table rows.

- **PRD-1** · **[high] § 4.1 Accounts:** create / rename / archive missing on both apps; neither repository has an account write method. — **Status:** fixed (2f02a91 phone, 84f57ad web; schema 1154d44, applied as migration 20260925181348)
- **PRD-2** · **[high] § 4.3 Categories:** add a category by hand missing on both; **[medium]** archive/unarchive missing on both (the `archived` label renders, nothing writes it). — **Status:** fixed (2f02a91 phone, 84f57ad web)
- **PRD-3** · **[medium] § 4.2 Transactions:** phone list has only a month switcher (no filter, search or sort); web has no Expense-vs-Income filter. **[low]** web has no calendar picker (typed dd/mm/yyyy only); `.xlsx` import is refused by design (D25). — **Status:** open (low part only): phone search and filter in FIX-3 (2f02a91); phone sort (b0f700a) and web type filter (e1e8700) fixed in round 2; the web calendar picker (low) remains
- Implemented and verified: entry/edit/delete/paste (4.2), auto-categorization in Postgres only (4.4), reporting (4.6), bills and reminders (4.7), themes (4.8), CSV export both / import web (4.9), Google + lock + Windows Hello + RLS (4.10) including "Forgot pattern?" exactly as D6 describes (`lock_screen.dart:195-198`, `lock_controller.dart:172-179`).

### Backend

Verified fine: RLS on all 8 tables (6 public, 2 private) with 23 exact-owner policies for `authenticated` only; `anon` has no table or function privileges; composite FKs everywhere; the 5 SECURITY DEFINER functions live in `private` with empty `search_path`; the 7 public RPCs are SECURITY INVOKER with owner filters; `auto_categorized` and `builtin_name` cannot be forged; `mark_bill_paid` and `export_transactions_csv` touch own rows only; CSV formula guard; realtime publication = exactly the five tables; `list_migrations` matches the 16 repo files and every SHA-256 matches; indexes cover every access path. Advisors: security has one low WARN (leaked-password protection off, irrelevant with Google-only sign-in); performance is clean.

- **DB-1** · **[medium] pgTAP can no longer run through the MCP** (`read_only=true`; every test inserts into `auth.users`), and `supabase/README.md:49-62` still describes that path. The suite was not run in this audit. Fix: document `npm run db:test` with the session-pooler string and run it once. — **Status:** fixed (1154d44): `npm run db:test` documented; all 11 suites (229 assertions) passed against the hosted project on 25 Sep 2026, run through the MCP while write access was on
- **DB-2** · **[low] `private` functions are EXECUTE-granted to PUBLIC.** The `alter default privileges … revoke` in `20260924154708_private_schema_and_helpers.sql:17` had no effect (no `pg_default_acl` entry for the schema). Only the missing schema USAGE stops `anon`; `authenticated` can call them. Harmless today (reference data only). Fix: a migration revoking execute on all private functions from public, plus a pgTAP assertion. — **Status:** fixed (1154d44), applied as migration 20260925181348
- **DB-3** · **[low] `ventrafin_backup` is LOGIN + BYPASSRLS with no password** while backups are off (D28). Fix: `alter role ventrafin_backup nologin` until backups are turned on. — **Status:** fixed (1154d44), applied as migration 20260925181348
- **DB-4** · **[low] Default ACLs still grant `anon`/`authenticated` ALL on future public tables and functions.** Every migration must keep the explicit revoke pattern. Fix: `alter default privileges for role postgres in schema public revoke all on tables from anon` once. — **Status:** fixed (1154d44), applied as migration 20260925181348
- **DB-5** · **[low] `accounts` has no `archived` flag** and its FKs are `NO ACTION`, so the coming Accounts feature cannot delete a used account. Add the column with that feature. — **Status:** fixed (1154d44), applied as migration 20260925181348
- **DB-6** · **[low] Keep `on_auth_user_created` minimal:** if it ever raises, Google sign-in fails for everyone. — **Status:** open
- **DB-7** · pgTAP gaps: private function privileges; `updated_at` triggers; the transfer CHECKs directly; `categories_default_style` on `color = null` UPDATE; explicit `p_month` far from today; anon calling `get_bill_schedule`. — **Status:** open

### Security and privacy

Verified fine: `vercel.json` CSP (`default-src 'self'`, Supabase https/wss only, `object-src 'none'`, `frame-ancestors 'none'`; `style-src 'unsafe-inline'` is genuinely required by PrimeVue 4's runtime styles), X-Frame-Options, nosniff, referrer and permissions policies, COOP/CORP, HSTS; `supabaseClient.ts` refuses secret keys and uses PKCE with a 15 s timeout; `safeNextPath` blocks open redirects; Android manifest requests only the six needed permissions, `allowBackup=false`, only the launcher activity exported, FLAG_SECURE + recents screenshot off; session and lock data in Keystore-backed storage; PBKDF2-HMAC-SHA256 50 000 iterations with persisted cooldown; reminders carry no amounts and are `private`; no secrets in the working tree or in any git revision; `.env.local` and `mobile/config/dev.json` are ignored and untracked; `backup.yml` least-privilege with a SHA-pinned action.

- **SEC-1** · **[low] Lock cooldown trusts the wall clock** (`lock_controller.dart:94,101`); moving the phone's clock forward ends it. Keystore + FLAG_SECURE are the real controls. — **Status:** open
- **SEC-2** · **[low] A release build silently falls back to the debug signing key** when `key.properties` is absent (`mobile/android/app/build.gradle.kts`). A debug-signed APK on Dad's phone cannot be upgraded by a properly signed one without an uninstall (which loses the lock pattern). Fix: fail the release build without `key.properties`. — **Status:** fixed (1154d44)
- **SEC-3** · **[low] Web session in `localStorage` on a shared PC.** Acceptable with the strict CSP; consider a Supabase inactivity timeout if the PC is shared. — **Status:** open
- **SEC-4** · **[low] Web `localStorage` prefs (passkey hint, theme, entry prefs) are per-browser, not per-user.** Cosmetic. Prefix keys with the user id as the phone's `LockStore` does. — **Status:** open
- **SEC-5** · **[info]** The CSP hardcodes the project ref; a project move needs both the env var and the header changed. — **Status:** open

### Code health

- **CODE-1** · **Results:** `npm run typecheck` clean; `flutter analyze` clean; `flutter test` 159/159; `vitest run` 203/205 with two "timed out in 5000 ms" failures (`tests/components/pages.test.ts:45`, `tests/components/phase7.test.ts:64`) that pass alone (34/34). **[medium]** Fix: raise `testTimeout` for component tests (or `pool: 'vmThreads'`) so a normal `npm test` is green. — **Status:** fixed (84f57ad): testTimeout 20 s; 262/262 on two full runs
- **CODE-2** · **[medium] Bill due-date rule duplicated** in SQL (`private.bill_due_date`) and Dart (`models.dart:582-585`, needed to schedule reminders three months ahead), pinned only by parallel fixtures. Fix: have `get_bill_schedule` return the next due dates, or cross-reference the two tests. — **Status:** fixed (4bd2755 upcoming_due_dates in get_bill_schedule, applied after branch approval; b0f700a phone schedules from it, Dart copy deleted)
- **CODE-3** · **[low] Dead code:** `web/src/components/ComingSoon.vue`; `ComingSoonScreen` in `simple_screens.dart:109-133`; `friendlyDate` (`dates.ts:85`), `percentChange` (`reports.ts:117`), `UNCATEGORIZED_COLOR` (`theme.ts:42`); `createMemoryEntryPrefs` ships but is test-only; `EntryForm._pendingId` unused in edit mode; `_reconcileAccounts` mutates state inside `build`. — **Status:** fixed (2f02a91 phone, 84f57ad web)
- **CODE-4** · **[low] "Today in India" is implemented three times** (SQL, `dates.ts`, `india_time.dart`), each tested; acceptable. The CSV formula-guard contract (server adds `'`, web import strips it) has no shared fixture. — **Status:** open
- **CODE-5** · **[low] Outdated:** PrimeVue 4.5.5 → 5.0.1 and `@primeuix/themes` 2 → 3 (major, deliberately deferred per D19), TypeScript 5.9 → 7 (deliberate), `@types/node` 24 → 26, `@supabase/supabase-js` 2.117.1 → 2.117.2, `vitest` 5.0.1 → 5.0.2. Flutter direct dependencies are current. The mobile SDK constraint `^3.13.3` is the very latest Dart minor. — **Status:** open
- **CODE-6** · **[info]** Mobile realtime ignores `CHANNEL_ERROR`/`TIMED_OUT` (`supabase_repository.dart:271-275`); the web shows "Reconnecting…". Data is still refreshed on resume and re-subscribe. — **Status:** open
- **CODE-7** · **Test gaps.** Web: browser back / query restoration, unsaved changes, keyboard start of cell editing, Enter/Escape/initial focus in every dialog, the transfer-target dialog, multi-row delete, Bills delete, MonthSwitcher, AuthCallback error path, NotFound/SetupNeeded, OfflineBanner and Live label, `fetchWithTimeout`, `watchChanges`/resync. Mobile: Login, LockScreen/LockGate/SetupLockScreen (only the hasher is tested), `LockController.tryPattern`/cooldown/`forgotPattern`, router redirects and back handling, Transactions month navigation / swipe-delete / empty / error, Edit banners, Accounts/Categories/Dashboard error states, realtime stream; large-font tests run only at 1.3x on six screens. — **Status:** open
- No TODO/FIXME/HACK comments anywhere.

## Method

Four parallel read-only passes: every Dart file under `mobile/lib` and every file under `web/src` read in full and walked screen by screen; all migrations and pgTAP tests read, with the hosted project inspected via the read-only Supabase MCP (advisors, `pg_policies`, grants, `pg_proc`, publication, roles, migration hashes); a contrast script over `shared/theme-tokens.json` and `shared/category-style.json` (WCAG 2.1 and APCA) for every theme and surface; and a string-by-string wording comparison between the two apps. The three highest new claims (status-bar icons, the amber count, Aura toast colours) were re-checked by hand against the source.
