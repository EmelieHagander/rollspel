-- ============================================================================
-- 0014_encounter_board_api_access.sql
--
-- EXPOSE THE COMBAT BOARD TO THE BROWSER — READ-ONLY AND LIVE. The webapp
-- already renders the public story stream (rpg.story_beats) and updates it in
-- realtime; this file does the same for the combat board, so every player
-- watches the fight change as the GM runs it.
--
-- The bug this fixes: rpg.encounters and rpg.encounter_combatants (0013) ship
-- with RLS ENABLED and ZERO policies — deny-by-default — while carrying the
-- authenticated DML grants that 0004's default privileges hand every new rpg
-- table. So the privilege layer says "you may read" but the policy layer says
-- "no rows", and the webapp sees an empty board. rpg.encounter_board is a
-- security_invoker view: it resolves through the CALLER's policies, so until
-- its two base tables carry SELECT policies for authenticated, the view is
-- empty too. The view's OTHER joined tables (rpg.adventures,
-- rpg.adventure_characters, rpg.characters) already have authenticated
-- `_api_select` policies (0009/0011), so once these two open, the view
-- resolves fully.
--
-- What this does, all inside schema rpg (except the one publication statement
-- flagged in the FENCE NOTE):
--   1. READ POLICIES — `encounters_api_select` and
--      `encounter_combatants_api_select`, `for select to authenticated
--      using (true)`, matching the exact form of every other `<table>_api_select`
--      policy in the schema (0009/0011). RLS stays ENABLED; these are the door.
--   2. READ-ONLY FOR THE WEBAPP — revoke INSERT/UPDATE/DELETE on both tables
--      from `authenticated` (0004's default privileges granted them), leaving
--      SELECT. The board is GM-managed exclusively through the 0013 verbs, run
--      by service_role (the GM connector), which BYPASSES RLS. The browser
--      only renders. Revoking the write privileges makes the privilege layer
--      agree with the policy layer — SELECT only — so no accidental or future
--      permissive policy can let a browser write to the board. service_role
--      keeps ALL (untouched); anon keeps nothing (the require-login posture of
--      0009/0010 — anon has no schema usage and is named by no policy).
--   3. THE VIEW GRANT — `grant select on rpg.encounter_board to authenticated`,
--      explicit and idempotent, so this file is the complete greppable record
--      of the read surface it opens (matching 0011's belt-and-suspenders
--      posture). The view is security_invoker, so the base-table policies in
--      step 1 are what actually gate the rows; this grant is the privilege
--      half that must also hold.
--   4. LIVE UPDATES — add both tables to the supabase_realtime publication,
--      idempotent and guarded exactly like 0005 did for story_beats. The
--      webapp subscribes to these two tables' changes (round + turn pointer on
--      rpg.encounters; HP, conditions, initiative, roster on
--      rpg.encounter_combatants) and re-reads rpg.encounter_board once per
--      change. Realtime postgres_changes respects RLS, so the SELECT policies
--      in step 1 are also what let the authenticated subscription receive rows.
--
-- REPLICA IDENTITY — a considered choice (story_beats did NOT need it; this
-- board does). story_beats is insert-only, and an INSERT payload carries the
-- full new row under the default replica identity (primary key), so its
-- render trigger had everything. The combat board is UPDATE-heavy and
-- DELETE-capable (remove_combatant, and cascade cleanup). Under the default
-- (PK-only) replica identity:
--   * UPDATE payloads carry the full NEW row but the OLD row is only the PK —
--     fine for "re-read the view", but a client cannot filter its subscription
--     on the OLD value of a changed column, nor diff.
--   * DELETE payloads carry ONLY the PK — so a combatant leaving the board
--     yields an event that names neither its encounter nor its adventure, and
--     the client cannot route the re-render (or server-side-filter the
--     subscription by encounter_id) because encounter_id is absent from the
--     old tuple.
-- So this file sets `REPLICA IDENTITY FULL` on BOTH tables: every INSERT,
-- UPDATE and DELETE payload then carries the full row — encounter_id and
-- adventure linkage included, and the changed columns on UPDATE — which is
-- what lets the webapp filter its subscription per encounter and always know
-- which board to re-read, including when a combatant is removed mid-fight. The
-- cost is a larger old-tuple in WAL on UPDATE/DELETE; on these small,
-- low-frequency combat tables that is negligible, and the correctness of live
-- removals is worth it. (If WAL volume ever mattered here it would be trivial
-- to narrow in a later migration — this is forward-only either way.)
--
-- FENCE NOTE: the two `alter publication supabase_realtime add table rpg.*`
-- statements (in the guarded DO block) are the only statements in this file
-- that name an object outside schema rpg — the publication itself, which is
-- Supabase's single sanctioned realtime switchboard and cannot live inside
-- rpg. They are within the fence's spirit, exactly as 0005's was: each alters
-- replication OF OUR TABLES ONLY (adds two rpg-schema tables to the member
-- list) and reads or writes nothing belonging to any other tenant. No other
-- statement leaves schema rpg.
--
-- NOT EXPOSED HERE (deliberately, per 0011's exclusions): the GM-private
-- tables rpg.session_events, rpg.plot_points, rpg.npcs, rpg.areas stay
-- service_role-only (RLS enabled, zero policies). This migration is the combat
-- board only. rpg.story_beats is already exposed (0005/0010) and untouched.
--
-- Forward-only: lands as a new migration, never an edit to an applied one.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Read policies for logged-in players. RLS stays ENABLED; these are the
--    door. Same form as every other rpg `<table>_api_select` (0009/0011):
--    for select to authenticated, using (true).
-- ---------------------------------------------------------------------------

create policy encounters_api_select on rpg.encounters
  for select to authenticated
  using (true);

create policy encounter_combatants_api_select on rpg.encounter_combatants
  for select to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- 2. Read-only for the webapp. 0004's default privileges auto-granted
--    authenticated INSERT/UPDATE/DELETE at table creation; take those back so
--    the privilege layer agrees with the SELECT-only policy layer and no
--    browser write can reach the GM-managed board. SELECT stays. service_role
--    (RLS-bypassing GM connector) keeps ALL and is untouched; anon has
--    nothing (require-login posture).
-- ---------------------------------------------------------------------------

revoke insert, update, delete on rpg.encounters            from authenticated;
revoke insert, update, delete on rpg.encounter_combatants  from authenticated;

-- Belt-and-suspenders explicit SELECT grant (idempotent; already present via
-- 0004's default privileges) so this file is the complete, greppable record
-- of the read surface it opens — the privilege half that must hold alongside
-- the policies above.
grant select
  on rpg.encounters, rpg.encounter_combatants
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The view grant. rpg.encounter_board is security_invoker, so the
--    base-table policies in step 1 gate the rows; this is the privilege half.
--    Explicit and idempotent.
-- ---------------------------------------------------------------------------

grant select on rpg.encounter_board to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Live updates. Set REPLICA IDENTITY FULL (see the REPLICA IDENTITY note in
--    the header) so UPDATE and DELETE payloads carry the full row, then add
--    both tables to the supabase_realtime publication.
--    (See FENCE NOTE: the publication statements are the only ones naming an
--    object outside schema rpg; they alter replication of our tables only.)
--    Idempotent: guarded on the publication existing and on per-table
--    membership, so the migration survives environments where it is absent.
-- ---------------------------------------------------------------------------

alter table rpg.encounters           replica identity full;
alter table rpg.encounter_combatants replica identity full;

do $$
declare
  v_tbl text;
begin
  if exists (select 1 from pg_catalog.pg_publication
             where pubname = 'supabase_realtime') then
    foreach v_tbl in array array['encounters', 'encounter_combatants'] loop
      if not exists (select 1 from pg_catalog.pg_publication_tables
                     where pubname = 'supabase_realtime'
                       and schemaname = 'rpg'
                       and tablename = v_tbl) then
        execute format(
          'alter publication supabase_realtime add table rpg.%I', v_tbl);
      end if;
    end loop;
  else
    raise warning 'Publication supabase_realtime not found: rpg.encounters and rpg.encounter_combatants were NOT added. Add them manually once the publication exists: alter publication supabase_realtime add table rpg.encounters, rpg.encounter_combatants;';
  end if;
end
$$;

commit;
