-- ============================================================================
-- 0005_require_login_revoke_anon.sql
--
-- Locks the character family to LOGGED-IN users only.
--
-- Background: when the human owner exposed the `rpg` schema in the Supabase
-- dashboard, Supabase automatically granted the `anon` role `usage` on schema
-- rpg plus DML on its tables. Combined with the pre-existing
-- `<table>_api_{select,insert,update,delete}` permissive policies — which
-- target roles {anon, authenticated} with USING (true) / WITH CHECK (true) —
-- that opened the tables to the public/anon key embedded in the webapp: anon
-- could read AND write every character with no login. Verified: role `anon`
-- saw all three demo characters.
--
-- The owner chose LOGIN REQUIRED. This migration produces that end state,
-- entirely within schema rpg, with defence in depth:
--   1. Revoke every rpg privilege from `anon` (tables, sequences, functions)
--      and `usage` on schema rpg — undoing what schema-exposure granted.
--   2. Narrow all 20 pre-existing `_api_*` policies to the `authenticated`
--      role only, via ALTER POLICY (names and USING/WITH CHECK expressions are
--      preserved). So even if the schema is ever re-exposed and anon is
--      re-granted, no permissive policy applies to anon and it still gets
--      nothing.
--
-- UNCHANGED:
--   * `authenticated` keeps its 0003 grants (usage on schema rpg + table DML)
--     and full read/write through those now-authenticated-only `_api_*`
--     policies.
--   * `service_role` (the AI GM's key) is untouched — it bypasses RLS
--     regardless, so GM writes are unaffected.
--
-- Note on ownership of the `_api_*` policies: they are PRE-EXISTING and were
-- not created by any migration in this repo (0001 created zero policies). This
-- migration only narrows their role list from {anon, authenticated} to
-- {authenticated}; it does not change their intent (permissive, USING true).
--
-- Forward-only: lands as a new migration, never an edit to an applied one.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Revoke everything the schema-exposure handed `anon`, defensively across
--    tables, sequences, and functions, then usage on the schema itself.
-- ---------------------------------------------------------------------------

revoke all privileges on all tables    in schema rpg from anon;
revoke all privileges on all sequences in schema rpg from anon;
revoke all privileges on all functions in schema rpg from anon;
revoke usage on schema rpg from anon;

-- ---------------------------------------------------------------------------
-- 2. Narrow the 20 pre-existing `_api_*` permissive policies to
--    `authenticated` only (defence in depth against future re-exposure).
--    ALTER POLICY preserves each policy's name and USING / WITH CHECK.
-- ---------------------------------------------------------------------------

alter policy characters_api_select on rpg.characters to authenticated;
alter policy characters_api_insert on rpg.characters to authenticated;
alter policy characters_api_update on rpg.characters to authenticated;
alter policy characters_api_delete on rpg.characters to authenticated;

alter policy character_skills_api_select on rpg.character_skills to authenticated;
alter policy character_skills_api_insert on rpg.character_skills to authenticated;
alter policy character_skills_api_update on rpg.character_skills to authenticated;
alter policy character_skills_api_delete on rpg.character_skills to authenticated;

alter policy character_items_api_select on rpg.character_items to authenticated;
alter policy character_items_api_insert on rpg.character_items to authenticated;
alter policy character_items_api_update on rpg.character_items to authenticated;
alter policy character_items_api_delete on rpg.character_items to authenticated;

alter policy character_spell_slots_api_select on rpg.character_spell_slots to authenticated;
alter policy character_spell_slots_api_insert on rpg.character_spell_slots to authenticated;
alter policy character_spell_slots_api_update on rpg.character_spell_slots to authenticated;
alter policy character_spell_slots_api_delete on rpg.character_spell_slots to authenticated;

alter policy character_spells_api_select on rpg.character_spells to authenticated;
alter policy character_spells_api_insert on rpg.character_spells to authenticated;
alter policy character_spells_api_update on rpg.character_spells to authenticated;
alter policy character_spells_api_delete on rpg.character_spells to authenticated;

commit;
