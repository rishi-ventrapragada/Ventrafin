# Ventrafin — Decision Log

This records what was decided, what was considered and rejected, and why — so future changes are made knowingly rather than accidentally reversing a deliberate tradeoff. Newer decisions supersede older ones where noted.

---

## D1. Local-first + client-side encryption → cloud-only, no encryption

**Original plan:** fully local `drift`/SQLCipher storage, client-side AES-256-GCM encryption before anything reached Supabase, a dedicated key-management scheme (secure storage + QR device pairing + recovery contact).

**Superseded by:** a cloud-only design with **no local database and no client-side encryption**. All data lives directly in Supabase; privacy is enforced entirely by Row Level Security.

**Why the change:** the encrypted/local-first design was solving for a threat model ("protected even if the backend is compromised") that turned out not to match what was actually wanted. The real requirement, confirmed directly, was simpler: *no one but Dad should be able to see the data inside the app* — plus the admin (project owner) being able to see it directly via the Supabase dashboard when needed for support. RLS satisfies exactly that. Encryption and a local database would have added real complexity (key management, offline conflict resolution, no server-side aggregation) to defend against a threat that isn't in scope.

**Accepted tradeoff:** the Supabase project owner *can* technically read all data via the dashboard, since RLS cannot restrict the project owner. This was made explicit and accepted, not overlooked. Two-factor auth on the Supabase account is the mitigation.

**If this changes:** if the threat model ever expands to "not even the admin should read this," client-side encryption would need to be reintroduced, and the schema/sync design in `ARCHITECTURE.md` would need to change substantially (encrypted blobs, key distribution, no server-side categorization triggers).

---

## D2. Desktop Flutter app → separate Vue 3 web app

**Original plan:** one Flutter codebase targeting both Android and Windows desktop.

**Superseded by:** two separate apps — Flutter for Android, a standalone Vue 3 web app (browser-based) for the Windows side.

**Why the change:** explicit preference to try a different web stack rather than reuse Flutter desktop, and a desire for the web app's entry experience to be spreadsheet-like (paste from Excel, in-cell editing) rather than a ported mobile UI. A dedicated web framework with a mature data-grid ecosystem (PrimeVue) fits that better than Flutter desktop widgets.

**Frameworks considered for the web app, in order:**
- **Astro / Next.js** — rejected as "not different enough" (already familiar tools).
- **SvelteKit** — considered and initially chosen, then dropped at explicit request for something other than Svelte.
- **Vue 3 + Vite** — chosen. New to the builder, strong ecosystem, PrimeVue's editable DataTable fits the Excel-paste requirement well.
- **React + Vite** — noted as an equally-safe fallback if Vue turns out to be a poor fit, but not the pick.

**Consequence:** logic that both apps need identically (categorization, aggregates) must live in Postgres, not in shared Dart/TypeScript, since the two clients no longer share a codebase. See `ARCHITECTURE.md` § 3.

---

## D3. In-app admin role → dashboard-only admin access

**Original plan:** an "admin" role inside the app itself, with its own elevated visibility into user data, enforced via RLS role checks.

**Superseded by:** no admin concept inside the app or the RLS policies at all. The admin (project owner) uses the **Supabase dashboard** directly — which bypasses RLS by nature of being the project owner — instead of a role built into the product.

**Why the change:** the builder's decision. It's simpler (no role column, no conditional policies, no "grant temporary access" UI to build and test) and matches how the admin intends to help: by looking directly at the database when needed, not through the app's UI. It also keeps the app itself private to Dad, who asked for his data to be "private to me for now." The app never shows his data to anyone else; dashboard access is an operational fact of owning the Supabase project, which the builder should make clear to Dad.

**Also rejected along the way:** a "let admin view my data for 24 hours" toggle (temporary RLS-enforced sharing). This was proposed as a middle ground and turned down by the builder in favor of dashboard-only access, which needs no extra UI.

---

## D4. Backend: Supabase vs. Firebase

**Considered:** Firebase (Firestore + Auth + Cloud Functions) as a full alternative backend.

**Decision:** stayed with Supabase.

**Why:** Ventrafin's data is inherently relational (transactions reference accounts and categories; reporting needs grouped aggregates; categorization rules reference categories). Supabase's Postgres + SQL triggers implement the shared categorization/aggregation logic once, for free, in a place both independent clients can rely on identically. Firestore's document model has no real joins or `GROUP BY`-style aggregation, and its equivalent of a shared trigger (Cloud Functions) requires the paid Blaze plan — Spark's free tier doesn't include it. Firebase's advantages (first-class Flutter SDK, no project-pausing on free tier) didn't outweigh fighting a document database's shape for relational data.

**Known limitation accepted either way:** neither platform's free tier includes real backups. A periodic manual/automated export was flagged as a follow-up regardless of backend choice.

---

## D5. Budgets → dropped in favor of month-over-month comparison

**Decision:** no spending limits, caps, or overspend alerts anywhere in the product.

**Why:** direct answer from the primary user ("track spending without limits") overrode the earlier draft, which had proposed per-category budget progress bars. Month-vs-last-month comparison was requested instead and is the actual reporting anchor. Do not reintroduce budget caps without re-confirming — this was a considered removal, not an oversight.

---

## D6. Recovery flow: dropped

**Decision:** no separate reset system (no reset emails, no recovery codes). Instead, the mobile lock screen has a visible **"Forgot pattern?"** option that signs Dad out; he signs back in with Google and sets a new pattern.

**Why:** Dad explicitly asked for a "Forgot password" option to recover access. Because sign-in is through Google, Google's own account recovery is the real safety net, so the "Forgot pattern?" option routes through Google sign-in instead of a bespoke reset mechanism. The option must be visible on the lock screen; don't drop it as redundant. (An earlier draft proposed a "Rishi holds a recovery copy of the key" scheme; that belonged entirely to the abandoned encryption design in D1 and no longer applies.)

---

## D7. UI density: dense/detailed, not simplified

**Decision:** both apps use detailed, information-dense layouts (tables, multiple fields visible at once), not a large-button minimal-friction design.

**Why:** an earlier draft assumed a non-technical older user needs maximal simplicity. Direct feedback corrected this — the primary user is an experienced Excel user and prefers detailed, dense views over simplified ones. Don't over-simplify the UI on the assumption of low technical comfort; the actual constraint is "easy to enter data quickly," not "as few elements on screen as possible."

---

## D8. Navigation: multi-route, not single-scroll

**Decision:** both apps are structured as distinct pages/routes (Dashboard, Transactions, Add, Categories, Accounts, Bills, Reports, Settings), not single long scrolling screens.

**Why:** explicit preference — the primary user prefers clicking between clearly divided sections. This applies to both the Vue web app (Vue Router, real routes) and the Flutter app (bottom nav + distinct screens), even though the web app is technically built and deployed as a single-page application (SPA) — "SPA" here refers to the build/deploy mechanism only, not the navigation experience.

---

## D9. Infra: one new Supabase organization for Ventrafin

**Decision:** Ventrafin lives in its own new Supabase organization/project, separate from any pre-existing Supabase projects on the builder's account or on a collaborator's account.

**Why:** the free-tier 2-active-project cap is per organization. Creating a fresh organization avoided having to pause or delete existing unrelated projects, and keeps Ventrafin's data fully isolated from anything else.

---

## D10. Android package name: `com.ventrafin.app`

**Decision:** the Flutter app's Android application id / package name is **`com.ventrafin.app`**.

**Why:** the package name is effectively permanent. The Android OAuth client in Google Cloud is bound to it (together with the signing key's SHA-1). The Play Store and Android identify the app by it, and on-device data (the session, the lock pattern hash) lives under it. It needed to be short, product-named and conventional reverse-DNS.

**Rejected:**
- `com.ventrafin.ventrafin`: Flutter's generated default; redundant.
- `io.github.<username>.ventrafin`: a guaranteed-owned namespace, but long, and it ties the app's permanent identity to a personal GitHub account.
- Anything under `in.` (the India TLD): `in` is a Kotlin keyword, which makes the Kotlin sources awkward.

We don't own `ventrafin.com`. That doesn't matter for sideloading or the Play Store, where package names are simply first-come.

**If this changes:** a new package name is a new app. It means reinstalling, creating a new Android OAuth client (with SHA-1s), and setting the lock pattern again.

---

## D11. Mobile state management: Riverpod 3 (no code generation), with go_router

**Decision:** `flutter_riverpod` 3 for state and dependency wiring, without `riverpod_generator`; `go_router` for navigation.

**Why:**
- **Async-first.** Supabase reads are futures and Realtime is a stream. `FutureProvider`/`StreamProvider` model loading/error/data directly, and a per-table "revision" counter bumped by Realtime makes every screen that shows that table re-fetch automatically, with no manual refresh anywhere.
- **Testable without a DI framework.** Provider overrides swap in a fake repository, a fixed clock and fake connectivity. That's how the Add-flow widget tests run with no network.
- **No BuildContext needed** for services (auth, lock, repository), and no codegen step to run or forget on Windows.
- **go_router** gives real routes per section (D8), declarative redirects (signed out → Login, no pattern yet → Set up lock), and `StatefulShellRoute` so each bottom-nav tab keeps its own stack.

**Rejected:**
- `provider` + `ChangeNotifier`: older, with a weaker async story and more boilerplate.
- **Bloc**: a lot of ceremony per feature for a one-user app.
- **GetX**: global mutable state and poor testability.
- Plain `setState`: no sane way to share Realtime-driven data across tabs.

---

## D12. Mobile auth & lock details

**Decisions**, within the constraints already set by D6 and ARCHITECTURE § 5:
- **Native Google Sign-In → `signInWithIdToken`.** There's no browser redirect, so the mobile app needs no redirect URL or deep link.
- **The Supabase session lives in Keystore-backed secure storage** (`flutter_secure_storage`), replacing supabase_flutter's default plain SharedPreferences. App backup and device-to-device transfer are disabled for the same reason.
- **The pattern is stored only as salted PBKDF2-HMAC-SHA256** (50,000 iterations, 16-byte random salt), per user, in secure storage.
  - A 3×3 pattern has fewer than 400k possibilities, so the hash only slows an attacker who already has root access to the phone. The iteration count is stored with each hash and can be raised later.
  - Wrong attempts are persisted, so killing the app doesn't reset them. After every 5 misses there's a cooldown: 30 s, doubling each time, capped at 15 min.
- **Re-lock after 60 s in the background** (`kRelockAfterBackground`). That's long enough to check a UPI/bank app mid-entry without unlocking again, and short enough that a phone left on a table is locked.
- **The lock is an overlay above the navigator**, not a route, so a half-typed entry survives a re-lock.
- **An ordinary sign-out keeps the pattern; "Forgot pattern?" deletes it** before signing out (D6).

---

## D13. Category icons: curated Material Symbols keys stored in the database

**Decision:** each category stores an icon **key** (`categories.icon`), not an image. Keys are names from Google's **Material Symbols** set (Apache-2.0), for example `restaurant`, `shopping_cart`, `local_hospital`, `local_gas_station`, `bolt` or `account_balance_wallet`. Only a curated subset of about 60 icons is allowed, enforced by the `categories_icon_check` constraint. Colours come from a curated 24-colour palette (`private.category_palette()`).

**Why:**
- **Same icons in both apps from one open font.** Flutter already bundles these glyphs as `Icons.<key>`, with no new dependency. The web app can use the Material Symbols font (Google Fonts or the `material-symbols` npm package) with the same key as the ligature name. Storing the key in Postgres means both apps show the same icon without sharing any code.
- **Curated, not free-form.** A CHECK list guarantees that every stored key renders on both clients, and it keeps the picker small enough to scan. Adding an icon means a migration plus both clients, which is rare.
- **Defaults live in Postgres** (a `BEFORE INSERT` trigger), like the rest of the shared logic:
  - A built-in name ("Fuel") gets its built-in icon and colour.
  - A name that the keyword list recognises ("Petrol", "Swiggy") gets that category's icon.
  - Anything else gets a tag icon.
  - The colour is the first palette colour none of the user's active categories uses yet.
  - Seeding and auto-categorization pick all this up without changes.
- **Built-in colours were re-picked to be distinct.** Every pair of built-in expense colours is at least CIEDE2000 15 apart. The migration moved existing users' colours only where they were still the old default.
- **Readable glyphs** on pale colours: the apps draw a white glyph when it reaches 3:1 contrast, otherwise a dark one. *(Superseded by D20: whichever of white/dark contrasts more.)*
- **Uncategorized has no row**, so it has a fixed look in the clients instead: an amber `?` in an *outlined* circle. Every real category is a *filled* circle.

**The mirror:** `/shared/category-style.json` mirrors the icon list (with labels and groups) and the palette for the clients. `mobile/test/category_style_test.dart` fails if the Dart list, the JSON and the latest migration drift apart.

**Rejected:**
- **Image files or URLs per category:** storage, sizing and licensing per image, and nothing guarantees they render.
- **Emoji:** they look different on every device and Windows version, and several have no good equivalent (LPG cylinder, EMI).
- **Font Awesome / other icon packs:** a new dependency on mobile, and a more restrictive licence for some icons.

---

## D14. Merchant badges: letters, never logos

**Decision:** where a transaction's description names a merchant, the list shows a small **letter badge**, coloured consistently per merchant. There are **no brand logos and no logo service** (Clearbit, Brandfetch, favicon fetchers and the like).

**Why:** brand logos are trademarks, and any logo service would receive Dad's merchant names, which is a privacy leak to a third party (PRD priority 2). The badge is computed on the phone from text it already has:
- the merchant is the first word of the description that isn't a payment filler word (`upi`, `paid`, `to`, …) or a number;
- the letter is that word's first letter;
- the colour is `palette[FNV-1a-32(word) % 24]`.

The exact rule, the filler words and test vectors are in `/shared/category-style.json`, so the web app can draw identical badges. It is display-only, so it is not stored.

---

## D15. Mobile screens are not capturable (FLAG_SECURE)

**Decision:** the Android activity sets `FLAG_SECURE`, and on Android 13+ also `setRecentsScreenshotEnabled(false)`. The app shows as a blank card in the recent-apps screen, and screenshots, screen recording and casting capture a black screen.

**Why:** finance data shouldn't sit in the recents thumbnail, where it's visible even while the app lock is up, or end up in the gallery or cloud photo backups by accident.

**Accepted tradeoff:** Dad can't screenshot a screen to share it. Developers can't use `adb screencap` or screen mirroring on a real device either, so use widget tests or an emulator build for screenshots. If sharing becomes a need, add an in-app export instead of lifting the flag.

---

## D16. Web entry: an always-editable grid for Add, PrimeVue cell editing for Transactions, one row parser

**Decision:**
- **Add** is a custom grid where every cell is an input all the time, like a blank spreadsheet. Excel keys work:
  - Tab / Enter / arrows move between cells;
  - Ctrl+D fills down;
  - Ctrl+; enters today's date;
  - Ctrl+S saves.
- **Transactions** uses PrimeVue's DataTable in cell-edit mode: the rows read like the phone's list (icons, badges, colours), and a click turns one cell into an editor.
- Category, account, type and "paid by" cells in both are a small **type-to-filter pick list** (`ComboInput`). Typing "gro" offers Groceries, and "gpay" means UPI.
- Every Add row is **text**, like a spreadsheet cell. Typed rows and rows pasted from Excel go through the same parser (`web/src/lib/entryRow.ts`), which applies the phone's rules:
  - amount > 0;
  - day/month/year dates;
  - a payment method for expenses;
  - a different "To" account for transfers.
- Pasting several cells opens a **preview**:
  - it detects columns from headings or from the values, including bank-statement Withdrawal/Deposit pairs, and each detected column can be changed;
  - it marks invalid rows with the reason;
  - it saves only after confirmation. Rows with problems go into the grid to be fixed.
- An unknown category name is a **warning, not an error**: the row saves on Auto. This keeps a pasted "Kirana" from blocking a whole sheet.
- A save inserts all ready rows in **one statement** (all or nothing) with client-generated ids, so a retry after a lost response can't duplicate anything.

**Why:**
- PrimeVue's editors open on click and lean on Enter to finish editing, and their dropdowns take Enter too. That's right for correcting one cell, and wrong for typing twenty rows in a row, where Enter must mean "next row" as in Excel.
- One parser for typed and pasted rows means they can't drift apart.
- A preview with visible column mapping is safer than guessing silently, and Dad reads tables fluently.

**Rejected:** PrimeVue's DataTable for batch entry as well (Enter conflicts, and the cells are invisible until clicked); the Clipboard API "Paste" button (browser permission prompts; a paste box works everywhere); auto-creating categories from pasted names (adding categories comes in phase 4).

---

## D17. Web icons: Material Symbols as generated SVG paths, no icon font, no third-party requests

**Decision:** the web app draws the same Material Symbols glyphs as the phone (D13), but as SVG paths.
- `web/scripts/gen-icons.mjs` reads the icon keys from `/shared/category-style.json` plus a short list of UI icons. It writes `src/lib/icons.generated.ts` from the `@material-symbols/svg-400` package (Apache-2.0), using the filled variant for category glyphs, as Flutter's `Icons.*` are filled.
- Four Material Icons names that Symbols renamed are mapped (smartphone → mobile, card_giftcard → redeem, auto_awesome → star_shine, expand_more → keyboard_arrow_down). The stored keys stay the Flutter names.
- The page text uses the system font (Segoe UI on Windows). The CSP therefore needs no font or CDN host at all: only the app's origin and the Supabase URL.

**Why:**
- An icon font from Google Fonts would be a third-party request on every visit (privacy, PRD priority 2), plus a CSP exception.
- Before the font loads, the icon names would flash as text ("restaurant").
- The full self-hosted font is several megabytes for roughly 120 glyphs. The generated file is about 40 kB before compression.
- A test checks that every curated key has a glyph.

---

## D18. Renaming a category keeps its built-in keywords (`categories.builtin_name`)

**Decision:** Increment 3 lets both apps rename categories. Auto-categorization used to find a built-in keyword's category **by name** ("Swiggy" → the category called "Food"), so renaming Food to "Khana" would have made the next Swiggy entry quietly re-create a "Food" category. Migration `…044748_category_builtin_link` changes this:
- It adds `categories.builtin_name`, the built-in category a row stands for. A trigger fills it on insert when the name is a built-in one and keeps it on update, so clients can't set or move it.
- The categorizer looks the category up through that link first and by name second. An active category is preferred over an archived one.
- Tests are in `supabase/tests/06_category_rename.test.sql`.

**Consequences:**
- A new category that takes the old name ("Food" again, while "Khana" exists) is a plain category. The keywords stay with the renamed original until it is archived.
- A user category renamed *to* a built-in name ("Car costs" → "Fuel") is found by name, as before.
- Changing a category's kind drops its link.

**Rejected:** leaving rename naive (confusing duplicates); asking the client to re-point rules on rename (logic duplicated in two apps, and the built-in list isn't readable by clients).

---

## D19. Web library choices

- **PrimeVue 4.5** (MIT), not 5.x: 5.x adds a `@primeui/license-manager` dependency, and 4.5 has everything this app uses. Upgrading is a later, deliberate step.
- **TypeScript 5.9**, not 7: `vue-tsc` needs the TypeScript language-service API, which the native TypeScript 7 compiler doesn't expose yet.
- **No Pinia**: a small app context (provide/inject) with per-table revision counters mirrors the phone's design and is easy to fake in tests.
- **Vitest + @vue/test-utils + jsdom** for unit and component tests. jsdom 29 is used because 30 needs a newer Node 24 minor than the dev PC has.

---

## D20. Category glyph colour: whichever contrasts more (supersedes the 3:1 rule in D13), plus outlines for pale circles

**Decision:** both apps draw a category's glyph in white or near-black (87 % black over the circle), **whichever has more contrast** with the circle, with white keeping near-ties (within 10 %). The web app changed to this in its readability pass; the phone now does the same, so every built-in category's icon is the same colour on both apps.
- D13's rule was "white whenever it reaches 3:1". That left mid-tones such as green `#43A047` (Groceries) at 3.3:1. Now every palette colour gets 4.2:1 or better.
- On the phone this turns six palette colours' glyphs from white to dark: `#43A047` Groceries, `#0097A7` Travel, `#1E88E5` Transport, `#EC407A` Shopping, `#78909C` Other Income, and `#A1887F`.
- `/shared/category-style.json` (`glyph.onPalette`) lists the result for all 24 palette colours, which cover every built-in category. Both apps' tests check against it.

Two related rules, also on both apps:
- **Outlined looks** (Uncategorized `?`, Transfer arrow, Auto sparkle) draw their glyph and ring in a darker shade of their colour that reaches 4.5:1 on their own tint over every surface of the current theme.
- **Pale circles get an outline.** A filled circle whose colour is below 1.5:1 against any surface it can sit on in the current theme (white cards, the page, highlighted rows) gets a 1px ring in a darker shade (3:1 against those surfaces). In practice: yellow `#FDD835` (Electricity) everywhere, and light green `#AED581` on highlighted rows.

**Rejected:** recolouring categories per theme. A category is recognised by its colour, and the user picked it; changing it with the theme would break that. The outline fixes the only real clash without touching the colour.

---

## D21. Reports: existing functions plus one zero-filled monthly total

**Decision:** the Reports screens reuse `get_month_totals`, `get_month_comparison` and `get_monthly_category_totals`, and add one function, `get_monthly_totals(from, to)`, for the income-against-spending trend.

**Why a new function:** a trend needs every month in the range, including months with nothing in them, and per-month income, spending, net and entry counts. Summing category rows and filling gaps in each client would be the kind of duplicated computation `CLAUDE.md` keeps in Postgres. It is capped at 120 months per call.

**Shape of the screens** (both apps): a month picker drives everything; the trends cover 6 or 12 months **ending with the chosen month**, so looking at an old month shows the months before it. The category trend chart shows the five largest categories over the range plus "Other" (grey `#B0BEC5`, not a palette colour); the table under it lists every category. Charts always sit next to a table with the same numbers (D7). The web draws its charts as SVG itself (no chart library: nothing extra to load, same CSP, testable in jsdom).

---

## D22. Themes: brand colour vs. primary colour, from one shared file

**Decision:** `/shared/theme-tokens.json` holds the six themes. Each theme separates:
- **brand**: the big coloured surfaces (phone app bar, web sidebar), with its own text colour. For Sunflower and Marigold this is yellow with dark text.
- **primary**: buttons, links, switches, selected states. Always dark enough to be text on white and to carry white text (4.5:1), so for the yellow themes it is a dark gold/brown, not yellow.

**Why:** PRD § 4.8 pairs two themes with yellow. Yellow can't carry white text or be link text on white. Keeping "brand" and "primary" apart lets the yellow themes look yellow without any unreadable button or link.

**Other choices:**
- The web imports the JSON; the phone has a generated Dart file with a staleness test (Flutter can't bundle assets from outside its package, and a generated constant keeps icons/colours tree-shaken and typed).
- Semantic colours (expense red, income green, Uncategorized amber) don't change with the theme, so Forest's green brand never gets confused with "income" in the numbers themselves.
- Cards and sheets stay white on every theme; only the page behind them is tinted. That keeps category colours on the same surfaces everywhere (D20) and matches the web.
- Two Ocean values moved slightly so everything passes 4.5:1 (checked by tests on all six themes): the teal accent `#00897B` → `#00796B`, and the highlight tint `#E3F2FD` → `#E8F3FD` (green income amounts on a highlighted row were 4.49:1). Sunset's highlight is `#F0F1FA` for the same reason.
- The theme applies immediately when picked and rolls back if saving fails. Each browser/phone remembers the last theme locally only so it opens in it before the profile loads.

---

## D23. Bills: a paid-through month, not payment matching

**Decision:** "overdue" needs to know whether a bill was paid. Each bill stores `paid_through_month`; the next bill due is in the month after it. **Mark paid** moves it forward one month (or to any later month), optionally logging the payment as an expense in the same database call (`mark_bill_paid`).
- When a bill is added, the database decides the first month owed: this month if its due date hasn't passed yet, otherwise next month. (Adding a bill on 25 Sep with due day 10 doesn't make it instantly overdue.)
- Due dates clamp to short months (due day 31 is 30 April, 28/29 February), computed in SQL (`private.bill_due_date`); the phone repeats the same rule only to schedule reminders for later months, and tests pin both to the same examples.
- Status: overdue / due today / due within 7 days / upcoming, computed in `get_bill_schedule`.
- `mark_bill_paid` is idempotent per month: marking an already-paid month changes nothing and logs no second expense, so a retry after a lost response, or marking the same bill paid on both apps, can't double-count. The logged expense uses a client-generated id.
- Undo moves the month back. The phone's Undo, right after marking, also deletes the expense it just logged. "Mark unpaid" later (either app) leaves Transactions alone and says so.
- The web Bills page can add, edit, delete and mark bills paid as well, not only list them: Dad may be at the PC when he pays.

**Rejected:**
- Matching transactions to bills by category or amount: utility amounts change every month and a guess that's wrong shows a paid bill as overdue.
- A separate payments table: more than this needs; the expense itself is already in Transactions.

---

## D24. Reminders: local notifications, exact when allowed, inexact otherwise

**Decision:** reminders are scheduled on the phone with `flutter_local_notifications`, in **Asia/Kolkata** whatever the phone is set to (the app's single time zone). The web shows due and overdue bills but sends nothing.
- **Defaults:** daily "log today's expenses" at **8:30 pm**, changeable. Bill reminders at **9:00 am**, **3 days before** the due date (configurable 0–10; 0 = only on the day) **and on the due date**. Both settings live in `profiles`, so they survive a reinstall and show on the web.
- **Switches:** the daily reminder has its own switch; the bill master switch turns off every bill reminder but not the daily one; each bill has its own switch too.
- **Scheduling:** a pure planner builds the full list; the phone cancels everything and schedules the list again whenever the profile, the bills or the permissions change, and on returning to the app. Bill reminders are scheduled three months ahead, so they keep coming if the app isn't opened for a while. A month that is already overdue gets no more reminders; the Bills screen shows it in red.
- **Permissions:**
  - Notifications (Android 13+): asked once, in context, after a short explanation, the first time the signed-in app opens with a reminder on. If refused, Settings shows a banner with **Allow**, which asks again or, once Android stops asking, opens the app's notification settings.
  - Exact alarms: `SCHEDULE_EXACT_ALARM`, which Android 14+ doesn't grant by default. Without it reminders are scheduled as **inexact** alarms (they still come, possibly some minutes late) and Settings offers to allow exact timing. If the permission is withdrawn while alarms are pending, scheduling falls back to inexact instead of failing. `USE_EXACT_ALARM` was not used: Play reserves it for alarm-clock and calendar apps.
- **Privacy:** notifications name the bill and date but never the amount, and are marked private (hidden on a secure lock screen that hides sensitive content). Signing out cancels them all.
- **Known limit:** a change made on the web (a new bill, a bill marked paid) reaches the phone's schedule the next time the phone app is opened. Until then an old reminder can still fire. A server-side push would fix this, but the product has no server by design (ARCHITECTURE.md § 9).

---

## Open items not yet decided

- Exact backup/export mechanism for guarding against Supabase's lack of free-tier backups (flagged in `PRD.md` § 5, not yet solved).
- Whether Rishi (or another second party) gets any visibility into the data beyond dashboard-level admin access — currently: no, private to the primary user only.
- Windows Hello / passkey rollout timing — deferred to a later polish phase, contingent on the web app's deployed domain being finalized first (passkeys are origin-bound).
