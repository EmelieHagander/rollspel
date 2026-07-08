-- ============================================================================
-- 0014_encounter_read_and_player_notes.sql
--
-- Two webapp features, one migration, all inside schema rpg:
--
--   PART 1 — players read the combat board. 0013 built rpg.encounters,
--   rpg.encounter_combatants, and the render-ready rpg.encounter_board view
--   (security_invoker = on), all RLS-enabled with zero policies (deny-all).
--   Logged-in players get SELECT — and only SELECT: the GM (service_role,
--   which bypasses RLS) runs the 13 encounter verbs; players render.
--
--   PART 2 — rpg.player_notes: per-user private margin notes. The one
--   deliberately PER-USER surface in the vault — characters are shared table
--   property, but a player's own scribbles are theirs alone, enforced by RLS
--   keyed on auth.uid().
--
-- PART 1 NOTES:
--   * View plumbing: rpg.encounter_board is security_invoker, so the CALLER
--     must hold SELECT privilege and pass RLS on every underlying table. It
--     reads rpg.encounters + rpg.encounter_combatants (opened below), and
--     reads through to rpg.adventures (readable by authenticated since 0011)
--     and rpg.characters (characters_api_select, authenticated since 0009),
--     plus rpg.health_label(integer, integer), evaluated as the caller —
--     hence the EXECUTE grant. With those five pieces the view works
--     end-to-end for players.
--   * FOE-HP SECRECY IS PRESENTATION-LEVEL. The view exposes exact HP numbers
--     AND the derived health label; 0013's view comment says: show foes the
--     label, the party the numbers. The webapp honors that at render time. A
--     player opening devtools can see foe numbers in the response — a
--     stricter column-level fence would be a future change to the view (e.g.
--     nulling foe HP for non-service callers), deliberately NOT done here.
--   * Idempotent explicit grants as belt-and-suspenders: 0004's default
--     privileges likely auto-granted authenticated on the 0013 tables
--     already, but this file states its own read surface rather than leaning
--     on another migration's side effects (policy + privilege must both
--     hold; this pins the privilege half).
--
-- PART 2 NOTES:
--   * owner_id has NO foreign key to auth.users — same rationale as 0007:
--     auth.* is another schema and the rpg fence keeps our DDL out of it;
--     ownership is enforced by RLS comparing owner_id to auth.uid(), wrapped
--     as (select auth.uid()) so the planner evaluates it once per statement.
--   * HONESTY LINE: service_role bypasses RLS, so the GM's trusted tooling
--     CAN technically read player notes. The "GM never sees them" promise is
--     table etiquette, not cryptography — recorded here and in the table
--     comment so nobody mistakes the guarantee's strength.
--   * anon gets nothing, as everywhere since 0009/0010: no schema usage, no
--     grants, and no policy below names it.
--
-- Forward-only: lands as a new migration, never an edit to an applied one.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- PART 1: read policies for the combat board
-- ---------------------------------------------------------------------------

create policy encounters_api_select on rpg.encounters
  for select to authenticated
  using (true);

create policy encounter_combatants_api_select on rpg.encounter_combatants
  for select to authenticated
  using (true);

-- No INSERT/UPDATE/DELETE policies: the GM (service_role) runs the verbs.

-- Belt-and-suspenders privilege grants (idempotent; see PART 1 NOTES).
grant select
  on rpg.encounters, rpg.encounter_combatants, rpg.encounter_board
  to authenticated;

-- The security_invoker view calls this as the caller.
grant execute
  on function rpg.health_label(integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- PART 2: rpg.player_notes — per-user private margin notes
-- ---------------------------------------------------------------------------

create table rpg.player_notes (
  id            uuid         primary key default gen_random_uuid(),
  -- auth.uid() of the author. No FK to auth.users (see header): RLS-enforced
  -- ownership, not constraint-enforced.
  owner_id      uuid         not null,
  -- A note may attach to an adventure; if the adventure goes, the note stays
  -- as a free-floating scribble.
  adventure_id  uuid         references rpg.adventures (id) on delete set null,
  title         text         not null default '',
  body          text         not null default '',
  pinned        boolean      not null default false,
  created_at    timestamptz  not null default now(),
  updated_at    timestamptz  not null default now(),
  constraint player_notes_not_all_blank
    check (btrim(title) <> '' or btrim(body) <> '')
);

comment on table rpg.player_notes is
  'A player''s private margin notes — the one deliberately per-user surface in the vault: characters are shared table property, but what a player scribbles about the session is theirs alone, visible only to them (RLS on owner_id = auth.uid()). Optionally pinned, optionally attached to an adventure. Honesty line: service_role bypasses RLS, so the GM''s trusted tooling CAN technically read these — the privacy promise is table etiquette, not cryptography.';

comment on column rpg.player_notes.owner_id is
  'The Supabase Auth user (auth.uid()) who wrote the note. Deliberately WITHOUT a foreign key to auth.users (same rationale as 0007): ownership is enforced by RLS comparing this to auth.uid(), keeping the rpg fence out of cross-schema DDL.';

-- The owner's notebook read: my notes, newest first.
create index player_notes_owner_id_created_at_idx
  on rpg.player_notes (owner_id, created_at desc);

-- FK index (house rule: every foreign key column gets one).
create index player_notes_adventure_id_idx
  on rpg.player_notes (adventure_id);

create trigger player_notes_set_updated_at
  before update on rpg.player_notes
  for each row execute function rpg.set_updated_at();

alter table rpg.player_notes enable row level security;

-- Per-user policies: each verb sees/touches only the caller's own rows.
create policy player_notes_select_own
  on rpg.player_notes
  for select
  to authenticated
  using (owner_id = (select auth.uid()));

create policy player_notes_insert_own
  on rpg.player_notes
  for insert
  to authenticated
  with check (owner_id = (select auth.uid()));

create policy player_notes_update_own
  on rpg.player_notes
  for update
  to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy player_notes_delete_own
  on rpg.player_notes
  for delete
  to authenticated
  using (owner_id = (select auth.uid()));

grant select, insert, update, delete
  on rpg.player_notes
  to authenticated;

commit;
