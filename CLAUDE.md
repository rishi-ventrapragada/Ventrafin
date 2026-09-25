# CLAUDE.md — Working Guide for Claude Code

This file orients Claude Code (or any future contributor) working in this repository. Read `PRD.md` for what to build, `ARCHITECTURE.md` for how the system fits together, and `DECISIONS.md` for why it's built this way and what alternatives were rejected.

## What this repo is

Ventrafin is a home finance tracker built for one non-technical user ("Dad" throughout these docs), who splits his time between an Android phone and a Windows PC. There are two client apps sharing one Supabase backend:

- `/mobile` — Flutter app, Android target only
- `/web` — Vue 3 + TypeScript web app, deployed as a static site
- `/supabase` — SQL migrations, RLS policies, and trigger functions (the source of truth for the schema)

Both clients talk directly to Supabase. There is no custom backend server and no local database on either client — every read and write goes to Supabase, and Supabase Realtime pushes changes between the two apps.

## Repo layout (target state — create as needed)

```
/supabase
  /migrations       -- numbered SQL migration files (applied via Supabase MCP)
  /tests            -- pgTAP tests, run via MCP in rolled-back transactions
  seed.sql           -- local-only seed (empty; reference data lives in migrations)
/mobile               -- Flutter app
/web                  -- Vue 3 app
/shared
  theme-tokens.json   -- color themes, single source shared by both clients
/.github/workflows
  backup.yml          -- weekly encrypted data backup: schedule switched OFF for now (DECISIONS.md D28, /supabase/BACKUPS.md)
/scripts              -- repo tooling: optional pgTAP runner, backup credential generator
CLAUDE.md
PRD.md
ARCHITECTURE.md
DECISIONS.md
```

## Ground rules

- **Supabase schema is the source of truth.** Never hand-edit the schema through the dashboard for anything that should persist — write a migration file in `/supabase/migrations` instead, so the schema is reproducible and versioned. See "Database changes via Supabase MCP" below for the exact workflow.
- **RLS is mandatory on every table.** No table goes live without a Row Level Security policy restricting rows to `owner_id = auth.uid()`. There is no in-app admin bypass — admin access happens only through the Supabase dashboard, outside RLS, by the project owner. Never build an "admin view" into either client app.
- **No local database, no offline cache, no client-side encryption.** This is a deliberate scope decision — see `DECISIONS.md`. Don't introduce `drift`, `sqflite`, `Hive`, `IndexedDB`, or similar without checking with the human first.
- **Money is always integer paise**, never a float, in the database and in both apps' internal state. Convert to rupees only at display time.
- **Shared logic lives in Postgres, not duplicated per client.** Auto-categorization, category creation, and any computed totals that both apps need should be SQL functions/triggers/views, not reimplemented separately in Dart and TypeScript.
- **Both apps are multi-page/multi-route**, not single scrolling screens. Dad prefers navigating between distinct sections (Dashboard, Transactions, Add, Categories, Accounts, Bills, Reports, Settings) over one long page.
- **UI density: detailed, not oversimplified.** Dad is comfortable with dense views and tables (he's an Excel user) — don't default to large-button, minimal-information layouts.
- **Full build/design freedom otherwise.** Where `PRD.md` and `ARCHITECTURE.md` don't specify an exact implementation detail (component structure, exact file layout, specific package versions, naming), use your best judgment. The human will review and adjust after each phase.

## Database changes via Supabase MCP

The hosted project is managed through the **Supabase MCP server** (`.mcp.json`, scoped to the Ventrafin project). The Supabase CLI is not used.

- **Migration file first, then apply.** Every schema change starts as a new file `/supabase/migrations/<YYYYMMDDHHMMSS>_<name>.sql`. Only then apply it with the MCP `apply_migration` tool, using the file's exact contents and the same `<name>`. Never change the hosted schema without a matching file in the repo.
- **Don't apply a migration until the human has approved its branch.** Dad uses the app with real data, so the hosted project is production.
  - On the feature branch: write the migration file and its pgTAP tests, commit and push them, and say they are not applied yet.
  - Apply them with `apply_migration` only after the human approves the branch. Then do the version rename, hash check, tests and advisors (below) before merging.
  - Code that needs the new schema must not reach `main`, and so production, before the migration is applied.
- **Match the version after applying.** `apply_migration` stamps its own version (the apply time), so rename the file to `<version from list_migrations>_<name>.sql` and confirm the file's SHA-256 equals the stored statements (`supabase_migrations.schema_migrations`). Repo and hosted history must match exactly.
- **Never run DDL through `execute_sql`.** `execute_sql` is for read-only checks and for the rolled-back test runs below. Don't edit applied migration files; fix things with a new migration.
- **After applying, verify:** `list_migrations` must match `/supabase/migrations`, and `get_advisors` (security + performance) should be clean. Fix any findings with new migration files.
- **Tests** (`/supabase/tests/*.test.sql`, pgTAP) run via MCP inside a transaction that always rolls back, so no test data is left behind. `execute_sql` runs a script as one transaction and returns only the last result, so send the file's statements without `begin;`/`create extension`/`finish(); rollback;`, ending instead with a `do` block that raises the counts (recipe in `/supabase/README.md`). The raised error both reports the result and forces the rollback. pgTAP itself is installed by a migration.
- **No real data, no user data.** Never insert real data, and never read users' rows (transactions, accounts, categories, etc.), unless the human explicitly asks. Schema/metadata queries are fine.
- **Secrets stay out of the repo.** The MCP server authenticates via OAuth; `.mcp.json` holds only the project ref. Never write the service_role key, the database password, or OAuth client secrets into any file. If backups are turned on, their credentials (`BACKUP_DB_URL`, `BACKUP_PASSPHRASE`) live only in GitHub Actions secrets.
- **Read-only once Dad is using the app.** When Dad starts using the app for real, the MCP connection must be switched to read-only mode (add `&read_only=true` to the server URL in `.mcp.json`). After that, schema changes need the human to deliberately re-enable write access for that change.

## Build order

Follow the phase order in `PRD.md` § Build Phases. Each phase should leave the app in a working, demoable state before moving to the next. Don't jump ahead to later-phase features (e.g., don't build reminders while still in the schema phase).

## Git workflow

Claude handles git itself: commit and push after finishing each increment or fix, without waiting for the human to run the commands.

- **One feature branch per increment or fix**, not directly on `main` (as done for `increment-3-web-core`).
- **After finishing and testing a change, commit it and push the branch to `origin`.** Always scan the staged diff for secrets first (service_role key, database password, OAuth client secrets, `.env` files).
- **Only merge into `main` when the human explicitly says to merge.** Never merge automatically; the human may want to test first.
- **When told to merge**, do it yourself: `git checkout main`, `git pull`, `git merge --ff-only <branch>`, `git push`. If it's not a clean fast-forward, stop and tell the human rather than resolving conflicts yourself.
- **At the end of each turn, state clearly** what was committed, to which branch, and whether `main` was updated.

## Stack quick reference

| Layer | Choice |
|---|---|
| Mobile | Flutter (Dart), Android only |
| Web | Vue 3 (Composition API) + Vite + TypeScript |
| Web routing | Vue Router |
| Web UI kit | PrimeVue + Tailwind CSS |
| Backend | Supabase (Postgres, Auth, Realtime, RLS) |
| Auth | Google Sign-In (both apps) |
| Mobile lock | `local_auth` (fingerprint) + pattern-lock fallback |
| Web lock | Google session; Windows Hello via Supabase passkeys is a later addition |
| Charts | `fl_chart` (mobile), Chart.js or similar (web) |
| Notifications | `flutter_local_notifications` (Android only — web has no reminder push) |
| Hosting | Vercel (static site), project `ventrafin` under the `rishiventra` account. Deploys via Vercel CLI (one-time `vercel login`) plus GitHub auto-deploy on push to `main`. Root Directory is `web`, so run `vercel` from the repo root, not from `/web`; `.vercelignore` keeps uploads to `web/` + `shared/` |

## When something is ambiguous

If `PRD.md`, `ARCHITECTURE.md`, and `DECISIONS.md` don't resolve a question, make a reasonable choice, note the assumption in your output/commit message, and move on rather than blocking on it. The human will course-correct in review.
