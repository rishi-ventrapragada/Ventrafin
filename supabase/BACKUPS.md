# Backups: setup, checking, restoring

> **Switched off for now** (`DECISIONS.md` D28). The workflow has no schedule, the secrets and the role's password
> were never set up, and the `ventrafin_backup` role is NOLOGIN (migration `…_audit_round_1`), so no backups are being made. To turn it on, do the one-time setup below, then put back the
> commented `schedule:` lines in `.github/workflows/backup.yml` and run it once by hand.

Supabase's free plan keeps no backups, and Ventrafin has no server of its own. A GitHub Actions workflow
(`.github/workflows/backup.yml`) makes one every week instead. Why it works this way: `DECISIONS.md` D27.

| | |
|---|---|
| **What** | Every row of the app tables: `profiles`, `accounts`, `categories`, `category_rules`, `transactions`, `recurring_bills`. The schema isn't included: it's in `supabase/migrations`. Sign-in data (`auth.*`) isn't included either (see "Restore into a new project") |
| **When** | Mondays 03:00 India time (Sunday 21:30 UTC), and whenever it is run by hand |
| **How** | `pg_dump` as the read-only `ventrafin_backup` role → `tar.gz` → encrypted with AES-256 (`gpg`, passphrase) |
| **Where** | A workflow artifact of this private GitHub repo, kept **90 days** (about 13 weekly copies) |
| **Who can open it** | Only someone with access to this repo *and* the passphrase |

Everything the workflow needs lives in two **GitHub Actions secrets**. Nothing is in the repo, and nothing is in either app.

## One-time setup (after merging to `main`)

1. **Get the Session pooler connection string.** Open the Supabase dashboard for the Ventrafin project and click **Connect**
   (top bar). Under *Connection string*, set **Method: Session pooler** and copy the URI. It looks like
   `postgresql://postgres.dmcmxozgihdnsvoohxcg:[YOUR-PASSWORD]@aws-1-<region>.pooler.supabase.com:5432/postgres`.
   Leave `[YOUR-PASSWORD]` as it is: the backup doesn't use the database password.

   Why the pooler: GitHub's runners only have IPv4, and the direct `db.<ref>.supabase.co` host is IPv6-only on the
   free plan. It has to be the *Session* pooler (port 5432), because `pg_dump` needs a session.
2. **Make the credentials** (on your PC, from the repo root):
   ```powershell
   node scripts/backup-credentials.mjs "<the string you copied>"
   ```
   The script prints three things. It saves nothing and sends nothing anywhere.
   - an `alter role ventrafin_backup with login password 'SCRAM-SHA-256$…';` statement. It lets the role log in again
     (it is NOLOGIN while backups are off) and sets a hash of the password, so the password itself never shows up in
     the SQL editor's history or the database logs;
   - the `BACKUP_DB_URL` value, with a new random password for the read-only role;
   - a new random `BACKUP_PASSPHRASE`.
3. **Set the role's password.** In the dashboard open **SQL Editor**, paste the `alter role …` line and click **Run**.
4. **Create the two secrets.** In GitHub go to the repo, then **Settings → Secrets and variables → Actions → New
   repository secret**:
   | Name | Value |
   |---|---|
   | `BACKUP_DB_URL` | the `postgresql://ventrafin_backup.<ref>:…@…pooler.supabase.com:5432/postgres?sslmode=require` line |
   | `BACKUP_PASSPHRASE` | the passphrase line |
5. **Save `BACKUP_PASSPHRASE` in your password manager too.** GitHub never shows a secret again, and without the
   passphrase no backup can be opened. Then clear the terminal (`cls`).
6. **Run it once now.** In GitHub go to **Actions → Weekly database backup → Run workflow** (branch `main`).
   Alternatively run `gh workflow run backup.yml`.

The `ventrafin_backup` role (migration `…142724_backup_reader_role`) can log in and read the app tables, and that's
all. It can't write, can't read `auth`, and every transaction it starts is read-only. If its password ever leaks,
repeat steps 2–5; the new password replaces the old one.

## Checking that it runs

- **Every run:** open **Actions → Weekly database backup**. A green tick means the dump worked, the file was
  encrypted, and it was **decrypted again inside the job** to prove the passphrase opens it. The run's summary shows
  the file size and a row count per table. The counts should grow over time and never drop to 0.
- **Artifacts:** at the bottom of each run's page, `ventrafin-backup-YYYY-MM-DD.tar.gz.gpg` with its expiry date.
- **From a terminal:** `gh run list --workflow backup.yml --limit 5`.
- **Failures:** GitHub emails whoever last changed the workflow's schedule when a scheduled run fails. Check that
  Actions notifications are on: GitHub → Settings → Notifications → Actions.
- **Every few months:** download the latest backup and open it ("Opening a backup" below). That's the only real proof
  the passphrase in your password manager is the right one.

Things that would make it fail, and what to do:

| Error in the log | Fix |
|---|---|
| `Secret BACKUP_DB_URL is not set` | Setup step 4 |
| `password authentication failed for user "ventrafin_backup"` | The role's password and the secret don't match. Redo setup steps 2–5 |
| `connection to server … failed` / timeout | The Supabase project is paused (free plan, after a week without use) or down. Restore it in the dashboard, then run the workflow again |
| `server version mismatch` | Supabase moved to a new Postgres major version. Change `postgresql-client-17` and `PG_BIN` in the workflow to match |

## Opening a backup

1. Download it. In GitHub go to **Actions**, open a run, and under **Artifacts** click `ventrafin-backup-….tar.gz.gpg`.
2. Decrypt it in **Git Bash**, which ships with `gpg` on Windows:
   ```bash
   gpg --pinentry-mode loopback --output backup.tar.gz --decrypt ventrafin-backup-2026-09-28.tar.gz.gpg   # asks for the passphrase
   tar -xzf backup.tar.gz
   ```
3. Inside `ventrafin-backup-2026-09-28/`:
   - `data.sql`: `INSERT` statements with column names, 500 rows each. It's readable in any text editor.
   - `manifest.txt`: when the backup was made, the latest migration it matches, the rows per table, and each user's id
     with their number of transactions.
   - `migrations.txt`: every migration that was applied at the time.

Delete the decrypted files when you're done. They hold Dad's data in plain text.

## Restoring

**First, make a backup of the present state.** Run the workflow by hand, or export a CSV from the app. That way a
restore can itself be undone. Ask Dad to close both apps while you restore, and to reopen them afterwards.

You need `psql` version 17. Install either:
- *PostgreSQL 17 → Command Line Tools* from the EDB Windows installer (untick the server), or
- Docker: `docker run --rm -it -v "${PWD}:/work" -w /work postgres:17 bash`.

Connect as **`postgres`**, not the read-only role: use the Session pooler string with the database password. If you
don't know that password, reset it under Project Settings → Database.

### A. Put the data back as it was (same project)

For example after a bulk delete by mistake. This replaces **all** app data with the backup's contents, so anything
entered since the backup is lost unless you re-enter it.

```bash
psql "postgresql://postgres.<ref>:<db-password>@<pooler-host>:5432/postgres" \
  --single-transaction -v ON_ERROR_STOP=1 \
  -c "set session_replication_role = replica" \
  -c "truncate public.transactions, public.category_rules, public.recurring_bills, public.categories, public.accounts, public.profiles" \
  -f ventrafin-backup-2026-09-28/data.sql
```

`session_replication_role = replica` switches the tables' triggers off while loading, so the rows come back exactly as
they were. Categorization isn't re-run, and nothing new is seeded. `--single-transaction` means that if anything fails,
nothing changes.

For a small backup (a few thousand rows) the dashboard's **SQL Editor** works too. Paste the `set …;` and `truncate …;`
lines, then the contents of `data.sql`, and run it.

**Only a few rows lost?** Find them in `data.sql` (search by description or date). Then copy just those rows into an
`insert into public.transactions (…) values (…);` in the SQL Editor, with `set session_replication_role = replica;`
first.

### B. Restore into a new project (the old one is gone)

1. Create a Supabase project. Apply every file in `supabase/migrations`, in order: via the Supabase MCP
   `apply_migration`, or paste each file into the SQL Editor. Then set up Auth as before: the Google provider, the
   redirect URLs and, if used, passkeys.
2. Point the apps at the new project: the web app's Vercel env vars, the phone's `config/dev.json`, and a new release.
3. Dad signs in once with Google. That makes his new user id; old passkeys won't carry over. Look it up in the SQL
   Editor with `select id, email from auth.users;`.
4. His **old** id is in the backup's `manifest.txt` under "Owners".
5. Swap old for new in the dump, then clear what sign-up just created and load the backup:
   ```bash
   sed "s/OLD-USER-ID/NEW-USER-ID/g" ventrafin-backup-2026-09-28/data.sql > data-new.sql
   psql "postgresql://postgres.<new-ref>:<db-password>@<pooler-host>:5432/postgres" \
     --single-transaction -v ON_ERROR_STOP=1 \
     -c "set session_replication_role = replica" \
     -c "delete from public.transactions; delete from public.category_rules; delete from public.recurring_bills; delete from public.categories; delete from public.accounts; delete from public.profiles;" \
     -f data-new.sql
   ```
6. Set up backups again for the new project (the one-time setup above).

Sign-in data (`auth.users`) isn't in the backup on purpose. The read-only role can't read it, and it would add
session and identity details to every copy. Step 3 recreates it.
