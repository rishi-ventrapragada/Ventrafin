-- Phase 7: the read-only role the weekly GitHub Actions backup logs in as.
-- It can read every app table (bypassing RLS) and nothing else.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

select has_role('ventrafin_backup', 'the backup role exists');

select results_eq(
  $$ select rolcanlogin, rolbypassrls, rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolinherit, rolconnlimit
     from pg_roles where rolname = 'ventrafin_backup' $$,
  $$ values (false, true, false, false, false, false, false, 2) $$,
  'bypassrls only, and NOLOGIN while backups are off (D28): not superuser, cannot create roles or databases, no replication, 2 connections at most'
);

select is(
  (select count(*)::int from pg_auth_members where member = 'ventrafin_backup'::regrole),
  0,
  'is not a member of any other role (inherits nothing)'
);

select ok(
  (select setconfig from pg_db_role_setting where setrole = 'ventrafin_backup'::regrole and setdatabase = 0)
    @> array['default_transaction_read_only=on'],
  'every transaction is read-only by default'
);

select is(
  (select count(*)::int from pg_tables
   where schemaname = 'public' and not has_table_privilege('ventrafin_backup', format('%I.%I', schemaname, tablename), 'SELECT')),
  0,
  'can SELECT every public table'
);

select is(
  (select count(*)::int from pg_tables
   where schemaname = 'public'
     and has_table_privilege('ventrafin_backup', format('%I.%I', schemaname, tablename),
                             'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')),
  0,
  'cannot write, truncate, reference or add triggers to any public table'
);

select ok(
  not has_schema_privilege('ventrafin_backup', 'public', 'CREATE'),
  'cannot create objects in public'
);

select ok(
  not has_schema_privilege('ventrafin_backup', 'auth', 'USAGE')
  and not has_table_privilege('ventrafin_backup', 'auth.users', 'SELECT'),
  'cannot read auth (users, identities, sessions)'
);

select ok(
  not has_schema_privilege('ventrafin_backup', 'private', 'USAGE'),
  'cannot use the private schema'
);

select ok(
  has_table_privilege('ventrafin_backup', 'supabase_migrations.schema_migrations', 'SELECT'),
  'can read the migration history (recorded in each backup)'
);

select ok(
  not has_function_privilege('ventrafin_backup', 'public.mark_bill_paid(uuid, date, uuid, bigint, date, text)', 'execute'),
  'cannot call the app''s write functions'
);

-- A table added by a later migration (run as postgres) is readable too.
create table public.zz_backup_probe (id int);
select ok(
  has_table_privilege('ventrafin_backup', 'public.zz_backup_probe', 'SELECT')
  and not has_table_privilege('ventrafin_backup', 'public.zz_backup_probe', 'INSERT'),
  'tables created by later migrations are readable (and only readable) automatically'
);

select * from finish();
rollback;
