-- =============================================================================
-- Ventrafin — enable pgTAP for the database tests in /supabase/tests
--
-- Installed into the `extensions` schema, which is not exposed through the
-- Data API. The tests themselves always run inside a transaction that is
-- rolled back, so they never leave data behind.
-- =============================================================================

create extension if not exists pgtap with schema extensions;
