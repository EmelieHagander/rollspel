-- ============================================================================
-- 0004_rpg_api_access.sql
--
-- Opens the `rpg` schema to the Supabase API roles for the browser frontend.
--
-- OWNER DECISION (explicit, recorded here): the browser client runs on the
-- PUBLIC ANON KEY and gets READ + WRITE on the character family; service_role
-- keeps full access. TRADE-OFF ACCEPTED: anyone holding the anon key can read
-- and write every row in these tables — there is no per-user ownership model.
-- This is a private hobby GM tool for one table of players; the open posture
-- is deliberate. REVISIT (add auth + ownership columns + scoped policies)
-- before this app is ever exposed publicly.
--
-- What this migration does:
--   1. GRANT USAGE on schema rpg to anon / authenticated / service_role.
--   2. Table privileges on all CURRENT rpg tables:
--        anon, authenticated  → SELECT / INSERT / UPDATE / DELETE
--        service_role         → ALL
--   3. ALTER DEFAULT PRIVILEGES so FUTURE rpg tables (the incoming GM family,
--      0003_gm_core.sql on its own branch) carry the same grants
--      automatically. Plain form (no FOR ROLE): default privileges attach to
--      the role running this statement, and every rollspel migration is
--      applied through the same MCP role, so the creator of future tables IS
--      the role these defaults bind to.
--   4. EXECUTE on rpg.ability_modifier to the three roles (clients derive
--      modifiers from scores). rpg.set_updated_at is EXCLUDED: it is
--      trigger-internal — Postgres checks EXECUTE on a trigger function at
--      CREATE TRIGGER time (against the trigger's creator), never against the
--      role whose DML fires it, so client roles need no grant and granting
--      one would only advertise an internal function through the API.
--   5. RLS policies (permissive, per command) on each of the five existing
--      tables for anon + authenticated. RLS stays ENABLED everywhere — the
--      policies are the door, not a removal of the wall. service_role
--      bypasses RLS natively (BYPASSRLS) and needs no policies.
--
-- NOTE FOR THE GM-FAMILY MIGRATION (0003 and beyond): default privileges
-- cover GRANTS only, never POLICIES. Every new rpg table must ship its own
-- `alter table ... enable row level security` plus its own per-table policy
-- block, or it will be granted-but-invisible (RLS enabled, zero policies =
-- deny-by-default) to the browser. Apply-order safety: if 0003 lands before
-- this file, its tables are caught by the ON ALL TABLES grants below; if
-- after, by the default privileges — grants hold either way, policies do not.
--
-- Policy naming: `<table>_api_<command>` — one policy per (table, command)
-- covering both client roles (anon, authenticated), rather than duplicating
-- every policy per role. "api" = the Supabase API client roles.
--
-- Scope fence: every object touched is schema-qualified `rpg.*`; nothing
-- outside schema rpg is read, written, or granted.
--
-- Forward-only: 0001/0002 are applied history; this lands as a new migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Schema usage
-- ---------------------------------------------------------------------------

grant usage on schema rpg to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Table privileges — current tables
-- ---------------------------------------------------------------------------

grant select, insert, update, delete
  on all tables in schema rpg
  to anon, authenticated;

grant all
  on all tables in schema rpg
  to service_role;

-- No sequences exist in rpg today (all keys are gen_random_uuid()), but the
-- grant is included with the default below so a future identity/serial column
-- never breaks INSERTs from the browser.
grant usage, select
  on all sequences in schema rpg
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Default privileges — future tables (the GM family and beyond)
--    Plain form: binds to the current role, which is the single MCP role all
--    rollspel migrations run through, i.e. the creator of every future table.
-- ---------------------------------------------------------------------------

alter default privileges in schema rpg
  grant select, insert, update, delete on tables to anon, authenticated;

alter default privileges in schema rpg
  grant all on tables to service_role;

alter default privileges in schema rpg
  grant usage, select on sequences to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Function EXECUTE
--    ability_modifier: client-useful (derive modifiers from stored scores).
--    set_updated_at:   deliberately excluded — trigger-internal; EXECUTE is
--    checked at CREATE TRIGGER time, not when client DML fires the trigger.
-- ---------------------------------------------------------------------------

grant execute
  on function rpg.ability_modifier(integer)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. RLS policies — permissive full CRUD for the API client roles.
--    RLS remains ENABLED on every table (0001); these policies are the door.
-- ---------------------------------------------------------------------------

-- rpg.characters -------------------------------------------------------------

create policy characters_api_select on rpg.characters
  for select to anon, authenticated
  using (true);

create policy characters_api_insert on rpg.characters
  for insert to anon, authenticated
  with check (true);

create policy characters_api_update on rpg.characters
  for update to anon, authenticated
  using (true) with check (true);

create policy characters_api_delete on rpg.characters
  for delete to anon, authenticated
  using (true);

-- rpg.character_skills --------------------------------------------------------

create policy character_skills_api_select on rpg.character_skills
  for select to anon, authenticated
  using (true);

create policy character_skills_api_insert on rpg.character_skills
  for insert to anon, authenticated
  with check (true);

create policy character_skills_api_update on rpg.character_skills
  for update to anon, authenticated
  using (true) with check (true);

create policy character_skills_api_delete on rpg.character_skills
  for delete to anon, authenticated
  using (true);

-- rpg.character_items ---------------------------------------------------------

create policy character_items_api_select on rpg.character_items
  for select to anon, authenticated
  using (true);

create policy character_items_api_insert on rpg.character_items
  for insert to anon, authenticated
  with check (true);

create policy character_items_api_update on rpg.character_items
  for update to anon, authenticated
  using (true) with check (true);

create policy character_items_api_delete on rpg.character_items
  for delete to anon, authenticated
  using (true);

-- rpg.character_spell_slots ---------------------------------------------------

create policy character_spell_slots_api_select on rpg.character_spell_slots
  for select to anon, authenticated
  using (true);

create policy character_spell_slots_api_insert on rpg.character_spell_slots
  for insert to anon, authenticated
  with check (true);

create policy character_spell_slots_api_update on rpg.character_spell_slots
  for update to anon, authenticated
  using (true) with check (true);

create policy character_spell_slots_api_delete on rpg.character_spell_slots
  for delete to anon, authenticated
  using (true);

-- rpg.character_spells --------------------------------------------------------

create policy character_spells_api_select on rpg.character_spells
  for select to anon, authenticated
  using (true);

create policy character_spells_api_insert on rpg.character_spells
  for insert to anon, authenticated
  with check (true);

create policy character_spells_api_update on rpg.character_spells
  for update to anon, authenticated
  using (true) with check (true);

create policy character_spells_api_delete on rpg.character_spells
  for delete to anon, authenticated
  using (true);

commit;
