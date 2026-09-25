-- =============================================================================
-- Ventrafin — audit round 1 (AUDIT.md: FIX-4 / PRD-1 / DB-5, DB-3, DB-2, DB-4)
--
-- 1. accounts.archived (PRD § 4.1): an account can be archived instead of
--    deleted, since its transactions and bills still reference it (the FKs are
--    NO ACTION). Archived accounts disappear from the apps' pickers but keep
--    their name on old entries. A trigger refuses to archive the last active
--    account, so there is always one to enter transactions against.
--
-- 2. ventrafin_backup becomes NOLOGIN while backups are switched off
--    (DECISIONS.md D28). It had LOGIN + BYPASSRLS and no password; with
--    NOLOGIN nobody can log in as it even if a password were set by mistake.
--    Turning backups on means `alter role ventrafin_backup login` together
--    with setting the password (supabase/BACKUPS.md).
--
-- 3. Functions in `private` lose the EXECUTE that PostgreSQL grants PUBLIC by
--    default. The `alter default privileges in schema private revoke … from
--    public` in …154708 had no effect: per-schema default privileges can only
--    add to the global defaults, never remove from them. The explicit grants
--    to authenticated / service_role that the triggers and column defaults
--    need are kept. New private functions must repeat this revoke.
--
-- 4. `anon` loses its default privileges on future tables, sequences and
--    functions that migrations (run as postgres) create in public. Every
--    migration already revokes them explicitly; this removes the default so a
--    forgotten revoke can't expose a new table to signed-out callers. (PUBLIC
--    still gets EXECUTE on new functions by PostgreSQL's built-in default, so
--    new public functions keep their explicit `revoke … from public, anon`.)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. accounts.archived
-- -----------------------------------------------------------------------------
alter table public.accounts add column archived boolean not null default false;

comment on column public.accounts.archived is
  'Hidden from pickers; old transactions and bills keep it. At least one account stays active (trigger).';

create function private.accounts_keep_one_active()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.archived and not old.archived and not exists (
    select 1 from public.accounts a
    where a.owner_id = new.owner_id and a.id <> new.id and not a.archived
  ) then
    raise exception 'Keep at least one active account.'
      using errcode = 'check_violation', constraint = 'accounts_one_active';
  end if;
  return new;
end;
$$;

create trigger accounts_keep_one_active
  before update of archived on public.accounts
  for each row execute function private.accounts_keep_one_active();


-- -----------------------------------------------------------------------------
-- 2. The backup role cannot log in while backups are off
-- -----------------------------------------------------------------------------
alter role ventrafin_backup nologin;

comment on role ventrafin_backup is
  'Read-only role for the weekly GitHub Actions backup (pg_dump of public data). NOLOGIN while backups are off (DECISIONS.md D28); turning them on sets LOGIN and a password (supabase/BACKUPS.md).';


-- -----------------------------------------------------------------------------
-- 3. No PUBLIC execute on private functions (the trigger above included)
-- -----------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;


-- -----------------------------------------------------------------------------
-- 4. No default privileges for anon on future public objects
-- -----------------------------------------------------------------------------
alter default privileges for role postgres in schema public revoke all on tables    from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
