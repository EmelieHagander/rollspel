-- ============================================================================
-- 0009_require_login_revoke_anon.sql
--
-- RENUMBERED from 0005 after merging origin/main, whose parallel GM-surface
-- workstream independently used 0003-0005 (adventures_and_gm_surface /
-- rpg_api_access / story_beats). Shifted 0005 -> 0008 to resolve the collision
-- and follow main's history. Already applied live under its short-name 0005;
-- the renumber is repo ordering only, not a re-apply. The merge also revealed
-- the `_api_*` policies this file narrows were created by main's
-- 0004_rpg_api_access.sql. A follow-up (0010_complete_login_lockdown) extends
-- this same login-required lockdown to the merged GM-surface objects
-- (story_beats policies, anon default privileges).
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
--   * `authenticated` keeps its 0007 grants (usage on schema rpg + table DML)
--     and full read/write through those now-authenticated-only `_api_*`
--     policies.
--   * `service_role` (the AI GM's key) is untouched — it bypasses RLS
--     regardless, so GM writes are unaffected.
--
-- Note on ownership of the `_api_*` policies: authored when their origin was
-- unknown (0001 created zero policies); the origin/main merge later showed them
-- to be main's 0004_rpg_api_access.sql. This migration only narrows their role
-- list from {anon, authenticated} to {authenticated}; it does not change their
-- intent (permissive, USING true).
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
