-- ============================================================================
-- 0007_drop_per_user_layer.sql
--
-- RENUMBERED from 0004 after merging origin/main, whose parallel GM-surface
-- workstream independently used 0003-0005 (adventures_and_gm_surface /
-- rpg_api_access / story_beats). Shifted 0004 -> 0007 to resolve the collision
-- and follow main's history. Already applied live under its short-name 0004;
-- the renumber is repo ordering only, not a re-apply.
--
-- Reverses the per-user scaffolding added in 0006. The project owner has
-- chosen a SHARED-ACCESS model over per-row isolation for the character
-- family: login exists only to view; the AI GM writes as `service_role`
-- (which bypasses RLS); and general read/write for any logged-in user is
-- desired. The data is not sensitive, so per-character ownership is not wanted.
--
-- This migration therefore drops everything 0006 added to enforce ownership:
--   * the 20 per-user `_own` RLS policies (4 verbs x 5 tables),
--   * rpg.claim_demo_party() (its EXECUTE grant drops with the function),
--   * the characters_owner_id_idx index,
--   * the rpg.characters.owner_id column.
--
-- KEPT (deliberately not touched):
--   * The two grants from 0006 —
--       grant usage on schema rpg to authenticated;
--       grant select, insert, update, delete on all tables in schema rpg
--         to authenticated;
--     — these are what let logged-in users actually reach the tables.
--   * The pre-existing `<table>_api_{select,insert,update,delete}` permissive
--     policies (roles {anon, authenticated}, USING (true) / WITH CHECK (true))
--     on all five tables. With permissive policies OR-ed together, these now
--     provide the intended general access on their own. `anon` still has no
--     schema/table GRANTs, so it stays blocked regardless of its policy
--     membership; only `authenticated` (granted above) can use them.
--
-- OBSERVATION: when this file was authored the `<table>_api_*` policies were
-- of unknown origin (0001 created zero policies). The later merge of
-- origin/main revealed their source: main's 0004_rpg_api_access.sql created
-- them as a DELIBERATE open-anon posture. They are left in place here because
-- they deliver the shared-authenticated access the owner then wanted; a
-- subsequent migration (0008) narrows them to `authenticated` only.
--
-- Net effect: the schema honestly reflects "shared authenticated access, no
-- per-row ownership." Forward-only: this reversal lands as a new migration,
-- never as an edit to 0006.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Drop the 20 per-user `_own` policies from 0006.
--    (Must precede dropping owner_id: the characters policies reference it.)
-- ---------------------------------------------------------------------------

drop policy if exists characters_select_own on rpg.characters;
drop policy if exists characters_insert_own on rpg.characters;
drop policy if exists characters_update_own on rpg.characters;
drop policy if exists characters_delete_own on rpg.characters;

drop policy if exists character_skills_select_own on rpg.character_skills;
drop policy if exists character_skills_insert_own on rpg.character_skills;
drop policy if exists character_skills_update_own on rpg.character_skills;
drop policy if exists character_skills_delete_own on rpg.character_skills;

drop policy if exists character_items_select_own on rpg.character_items;
drop policy if exists character_items_insert_own on rpg.character_items;
drop policy if exists character_items_update_own on rpg.character_items;
drop policy if exists character_items_delete_own on rpg.character_items;

drop policy if exists character_spell_slots_select_own on rpg.character_spell_slots;
drop policy if exists character_spell_slots_insert_own on rpg.character_spell_slots;
drop policy if exists character_spell_slots_update_own on rpg.character_spell_slots;
drop policy if exists character_spell_slots_delete_own on rpg.character_spell_slots;

drop policy if exists character_spells_select_own on rpg.character_spells;
drop policy if exists character_spells_insert_own on rpg.character_spells;
drop policy if exists character_spells_update_own on rpg.character_spells;
drop policy if exists character_spells_delete_own on rpg.character_spells;

-- ---------------------------------------------------------------------------
-- 2. Drop the demo-party claim function (its EXECUTE grant drops with it).
-- ---------------------------------------------------------------------------

drop function if exists rpg.claim_demo_party();

-- ---------------------------------------------------------------------------
-- 3. Drop the ownership index, then the ownership column.
--    (Dropping the column would drop the index too; done explicitly and in
--    order for clarity.)
-- ---------------------------------------------------------------------------

drop index if exists rpg.characters_owner_id_idx;

alter table rpg.characters
  drop column if exists owner_id;

commit;
