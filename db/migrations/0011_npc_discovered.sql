-- ============================================================================
-- 0011_npc_discovered.sql
--
-- One column, to finish a mechanic. The GM's prep layer (0006) tracks what the
-- party has learned as the story emerges at the table, and it did so on two of
-- its three tables but not the third:
--
--   rpg.areas        — visited  (has the party been here yet?)
--   rpg.plot_points  — status   (hidden → revealed → resolved)
--   rpg.npcs         — <nothing> ← the gap this migration closes
--
-- This adds rpg.npcs.discovered, the NPC's discovery flag: false until the
-- party has met or learned of this NPC, flipped true live at the table as the
-- cast emerges. It mirrors rpg.areas.visited exactly — a boolean, not null,
-- default false — so that seeding a prepped adventure starts every NPC
-- undiscovered, the same way every area starts unvisited and every plot point
-- starts hidden, and the whole cast is revealed only by play.
--
-- default false means the (currently zero) existing rows and every future seed
-- start undiscovered; no backfill is needed and none is done.
--
-- Nothing else changes: no new enum, no other column, no data, and the
-- GM-private access posture of rpg.npcs (0006: RLS on, no policies, anon
-- revoked) is untouched.
--
-- Fence: schema rpg only, as always — nothing outside it is read or written.
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration.
-- ============================================================================

begin;

alter table rpg.npcs
  add column discovered boolean not null default false;

comment on column rpg.npcs.discovered is
  'Live discovery state, mirroring rpg.areas.visited: false until the party has met or learned of this NPC, flipped true at the table as the cast emerges. Seeds start every NPC undiscovered.';

commit;
