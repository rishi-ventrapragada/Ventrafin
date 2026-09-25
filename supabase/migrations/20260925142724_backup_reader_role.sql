-- =============================================================================
-- Ventrafin — phase 7: read-only role for the weekly backup
--
-- The GitHub Actions backup (.github/workflows/backup.yml, DECISIONS.md D27)
-- dumps the app's data with this role instead of the `postgres` superuser-like
-- account, so the credential stored in GitHub can read the app tables and
-- nothing else: it cannot write, delete, change the schema, or read auth.
--
-- * LOGIN, but no password is set here (a password is a secret and never
--   goes in the repo). Until the project owner sets one in the SQL editor
--   (see supabase/BACKUPS.md) nobody can log in as this role.
-- * BYPASSRLS: a backup must see every user's rows. Reading only; there are
--   no INSERT/UPDATE/DELETE grants, and every transaction defaults to
--   read-only as a second guard.
-- * SELECT on the public tables (and on tables added by later migrations),
--   plus the migration history so a backup records which schema it matches.
-- * No access to auth.*: the backup holds app data only. A restore into a new
--   project maps the old user id to the new one (supabase/BACKUPS.md).
-- =============================================================================

create role ventrafin_backup
  with login bypassrls noinherit nosuperuser nocreatedb nocreaterole noreplication
  connection limit 2;

comment on role ventrafin_backup is
  'Read-only login for the weekly GitHub Actions backup (pg_dump of public data). Password set by the project owner, stored only in GitHub Actions secrets.';

alter role ventrafin_backup set default_transaction_read_only = on;
alter role ventrafin_backup set statement_timeout = '5min';
alter role ventrafin_backup set idle_in_transaction_session_timeout = '1min';

grant usage on schema public to ventrafin_backup;
grant select on all tables in schema public to ventrafin_backup;
-- Tables created by later migrations (they run as postgres) are covered too.
alter default privileges for role postgres in schema public grant select on tables to ventrafin_backup;

grant usage on schema supabase_migrations to ventrafin_backup;
grant select on supabase_migrations.schema_migrations to ventrafin_backup;
