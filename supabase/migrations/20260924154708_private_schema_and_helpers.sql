-- =============================================================================
-- Ventrafin — private schema + shared helper functions
--
-- `private` holds internal functions and reference data. It is NOT listed in
-- the Data API's exposed schemas (config.toml [api].schemas), so nothing in it
-- is reachable through PostgREST/rpc. Clients only ever touch `public`.
-- =============================================================================

create schema if not exists private;

revoke all on schema private from public;
-- authenticated/service_role need USAGE so that triggers and column defaults
-- running with their privileges can call the helper functions granted below.
grant usage on schema private to authenticated, service_role;

-- Functions created in `private` must not be executable by everyone by default.
alter default privileges in schema private revoke execute on functions from public;


-- -----------------------------------------------------------------------------
-- Today's date in India. Supabase servers run in UTC; between 00:00 and 05:30
-- IST a plain current_date would still be "yesterday".
-- ASSUMPTION: the app is India-only, so the timezone is fixed rather than
-- stored per user.
-- -----------------------------------------------------------------------------
create function private.local_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Kolkata')::date;
$$;


-- -----------------------------------------------------------------------------
-- Canonical form of free text used for keyword matching:
--   lower-case, punctuation/whitespace runs -> single space, pure-number tokens
--   (UPI refs, order ids, amounts) dropped, trimmed.
--   'UPI/SWIGGY/4471023@icici' -> 'upi swiggy icici'
--   'Domino''s Pizza #123'     -> 'domino s pizza'
-- Both the keyword side and the description side go through this, so matching
-- is consistent whatever punctuation or reference numbers the bank adds.
-- Non-Latin text (e.g. Devanagari) passes through unchanged.
-- -----------------------------------------------------------------------------
create function private.normalize_text(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select btrim(
           regexp_replace(
             regexp_replace(
               ' ' || regexp_replace(lower(coalesce(p_text, '')), '[[:space:][:punct:]]+', ' ', 'g') || ' ',
               ' [0-9]+(?= )', '', 'g'),
             ' {2,}', ' ', 'g'));
$$;


-- -----------------------------------------------------------------------------
-- Generic updated_at maintenance.
-- -----------------------------------------------------------------------------
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


grant execute on function private.local_today()        to authenticated, service_role;
grant execute on function private.normalize_text(text) to authenticated, service_role;
