-- ============================================================================
-- 0011_adventure_read_surface.sql
--
-- THE ADVENTURE PICKER'S READ SURFACE. The webapp gains an adventure picker:
-- a logged-in player chooses an adventure and watches its story stream. For
-- that, `authenticated` needs to READ the player-facing adventure surface —
-- and nothing more.
--
-- What this does (all inside schema rpg):
--   SELECT-only permissive policies, to `authenticated`, using (true), on:
--     * rpg.adventures            (adventures_api_select) — list adventures
--       (id, slug, title, system, status) and resolve the picked one.
--     * rpg.adventure_characters  (adventure_characters_api_select) — show
--       which characters are in the adventure.
--   Plus a belt-and-suspenders explicit SELECT grant (see GRANTS NOTE).
--
--   NO INSERT/UPDATE/DELETE policies for players on either table: the GM
--   (service_role, which bypasses RLS) writes; players read. rpg.story_beats
--   already carries select+insert for authenticated (0005, narrowed by 0010)
--   and is untouched here.
--
-- DELIBERATELY EXCLUDED — these stay service_role-only (RLS enabled, zero
-- policies = deny-by-default) until a deliberate migration says otherwise:
--   * rpg.npcs, rpg.areas, rpg.plot_points (0006_gm_prep_tables): GM prep.
--     Per the GM prompt, "secrets are treasure, not narration" — npc.secrets,
--     hidden plot points, and area GM-notes must never reach a player client.
--   * rpg.encounters / rpg.encounter_combatants: schema still in flux in the
--     parallel workstream; no read surface until it settles.
--   * rpg.session_events — WITHHELD PENDING OWNER CONFIRMATION. It was
--     requested as part of this read surface ("the session log surface"), but
--     it is documented in 0005 and 0006 as the GM-PRIVATE APPEND-ONLY LOG —
--     "rulings, threads, secrets-in-motion", deliberately browser-invisible,
--     written via rpg.log_event precisely so secrets never transit the public
--     stream. A using-(true) SELECT policy would put every logged secret on
--     every player's screen, contradicting that recorded design and the same
--     principle that excludes the prep tables above. The player-facing
--     session log ALREADY EXISTS: rpg.story_beats. If the owner explicitly
--     decides players should read session_events anyway, that is one added
--     statement in a follow-up migration:
--       create policy session_events_api_select on rpg.session_events
--         for select to authenticated using (true);
--     It is not created here on a guess.
--
-- GRANTS NOTE: privilege-layer SELECT almost certainly already exists —
-- 0007 granted DML on all tables present at its apply time, and 0004's
-- default privileges auto-grant authenticated on tables created after it —
-- but grants are idempotent, and the explicit statement below makes this
-- file the complete, greppable record of the read surface it opens rather
-- than leaning on two other migrations' side effects. (Policy + privilege
-- must both hold for access; this ensures the privilege half here.)
--
-- RLS is already ENABLED on both tables (0003) with zero policies = deny-all;
-- these policies open exactly the read half. anon remains fully locked out:
-- no schema usage, no grants, no policy names it (0009/0010).
--
-- Forward-only: lands as a new migration, never an edit to an applied one.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Read policies for logged-in players
-- ---------------------------------------------------------------------------

create policy adventures_api_select on rpg.adventures
  for select to authenticated
  using (true);

create policy adventure_characters_api_select on rpg.adventure_characters
  for select to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- 2. Belt-and-suspenders privilege grant (idempotent; see GRANTS NOTE)
-- ---------------------------------------------------------------------------

grant select
  on rpg.adventures, rpg.adventure_characters
  to authenticated;

commit;
