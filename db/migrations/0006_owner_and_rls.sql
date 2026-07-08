-- ============================================================================
-- 0006_owner_and_rls.sql
--
-- RENUMBERED from 0003 after merging origin/main, whose parallel GM-surface
-- workstream independently used 0003-0005 (0003_adventures_and_gm_surface,
-- 0004_rpg_api_access, 0005_story_beats). This file and its two successors
-- were shifted to 0006-0008 to resolve the collision and sit after main's
-- history. It was already applied live under its original short-name 0003;
-- the renumber is for repo ordering only, not a re-apply.
--
-- Turns on PER-USER access to the character family. The webapp now uses full
-- login (Supabase Auth); every row belongs to the signed-in user who owns it,
-- and RLS enforces that ownership. Logged-out clients (role `anon`) get
-- nothing — login is required to see or touch any character data.
--
-- What this migration does, all inside schema rpg:
--   1. Adds rpg.characters.owner_id (nullable uuid, NO cross-schema FK) + index.
--   2. Adds per-user RLS policies for the `authenticated` role on all five
--      character-family tables (RLS was already enabled in 0001 with zero
--      policies = deny-all; these policies open the deny-all to owners only).
--   3. Grants schema USAGE and table DML to `authenticated` (in-fence: this
--      alters the ACLs of OUR objects and grants to a pre-existing role — it
--      does NOT create or alter any role). Nothing is granted to `anon`.
--   4. Adds rpg.claim_demo_party(): a signed-in user adopts the unclaimed
--      demo characters seeded in db/seeds/0001_demo_party.sql.
--
-- Ownership-by-RLS, not by FK (deliberate):
--   owner_id has NO foreign key to auth.users. auth.* is another schema and
--   the Rollspel fence keeps our DDL out of it; ownership is enforced by RLS
--   comparing owner_id to auth.uid(), not by a cross-schema constraint. A
--   deleted auth user simply leaves rows no one can select — harmless, and
--   cleaned up out-of-band if ever needed.
--
-- auth.uid() is wrapped as (select auth.uid()) in every policy so the planner
-- evaluates it once per statement (initplan) instead of once per row.
--
-- SECURITY DEFINER hardening follows 0002: rpg.claim_demo_party() sets an
-- explicit empty search_path and schema-qualifies every reference, so nothing
-- unqualified — no tenant schema, no attacker-created object — can resolve
-- inside it. pg_catalog is always searched implicitly, so built-ins still work.
--
-- ----------------------------------------------------------------------------
-- REMAINING OWNER-ONLY STEP (NOT done here — out of fence, project config):
--   For the webapp to reach these tables through the Supabase API, the `rpg`
--   schema must be added under Settings -> API -> Exposed schemas (and the
--   PostgREST search path). That is shared-project configuration, not schema
--   DDL, so it is left to the human project owner. It is safe to expose once
--   this migration is applied: RLS denies everything to `anon` and restricts
--   `authenticated` to its own rows, so exposure grants no unowned access.
-- ----------------------------------------------------------------------------
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration, never an edit here.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Ownership column
-- ---------------------------------------------------------------------------

alter table rpg.characters
  add column owner_id uuid;

comment on column rpg.characters.owner_id is
  'The Supabase Auth user (auth.uid()) who owns this character. Nullable, and deliberately WITHOUT a foreign key to auth.users: ownership is enforced by RLS comparing this to auth.uid(), not by a cross-schema constraint, keeping the rpg fence clean. Null = unclaimed (e.g. the seeded demo party before rpg.claim_demo_party()).';

create index characters_owner_id_idx
  on rpg.characters (owner_id);

-- ---------------------------------------------------------------------------
-- 2. Per-user RLS policies (authenticated role only; anon stays denied)
-- ---------------------------------------------------------------------------

-- rpg.characters: keyed directly on owner_id.
create policy characters_select_own
  on rpg.characters
  for select
  to authenticated
  using (owner_id = (select auth.uid()));

create policy characters_insert_own
  on rpg.characters
  for insert
  to authenticated
  with check (owner_id = (select auth.uid()));

create policy characters_update_own
  on rpg.characters
  for update
  to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy characters_delete_own
  on rpg.characters
  for delete
  to authenticated
  using (owner_id = (select auth.uid()));

-- rpg.character_skills: gated by ownership of the parent character.
create policy character_skills_select_own
  on rpg.character_skills
  for select
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_skills.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_skills_insert_own
  on rpg.character_skills
  for insert
  to authenticated
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_skills.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_skills_update_own
  on rpg.character_skills
  for update
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_skills.character_id
      and c.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_skills.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_skills_delete_own
  on rpg.character_skills
  for delete
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_skills.character_id
      and c.owner_id = (select auth.uid())
  ));

-- rpg.character_items: gated by ownership of the parent character.
create policy character_items_select_own
  on rpg.character_items
  for select
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_items.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_items_insert_own
  on rpg.character_items
  for insert
  to authenticated
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_items.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_items_update_own
  on rpg.character_items
  for update
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_items.character_id
      and c.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_items.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_items_delete_own
  on rpg.character_items
  for delete
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_items.character_id
      and c.owner_id = (select auth.uid())
  ));

-- rpg.character_spell_slots: gated by ownership of the parent character.
create policy character_spell_slots_select_own
  on rpg.character_spell_slots
  for select
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_spell_slots.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_spell_slots_insert_own
  on rpg.character_spell_slots
  for insert
  to authenticated
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_spell_slots.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_spell_slots_update_own
  on rpg.character_spell_slots
  for update
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_spell_slots.character_id
      and c.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_spell_slots.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_spell_slots_delete_own
  on rpg.character_spell_slots
  for delete
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_spell_slots.character_id
      and c.owner_id = (select auth.uid())
  ));

-- rpg.character_spells: gated by ownership of the parent character.
create policy character_spells_select_own
  on rpg.character_spells
  for select
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_spells.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_spells_insert_own
  on rpg.character_spells
  for insert
  to authenticated
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_spells.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_spells_update_own
  on rpg.character_spells
  for update
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_spells.character_id
      and c.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from rpg.characters c
    where c.id = character_spells.character_id
      and c.owner_id = (select auth.uid())
  ));

create policy character_spells_delete_own
  on rpg.character_spells
  for delete
  to authenticated
  using (exists (
    select 1 from rpg.characters c
    where c.id = character_spells.character_id
      and c.owner_id = (select auth.uid())
  ));

-- ---------------------------------------------------------------------------
-- 3. Grants on OUR objects (in-fence: rpg object ACLs, pre-existing role)
--    RLS still governs row visibility; these grants only permit the role to
--    reach the tables at all. Nothing is granted to `anon`.
-- ---------------------------------------------------------------------------

grant usage on schema rpg to authenticated;

grant select, insert, update, delete
  on all tables in schema rpg
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Demo-party claim function
-- ---------------------------------------------------------------------------

create function rpg.claim_demo_party()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed integer;
begin
  update rpg.characters
     set owner_id = auth.uid()
   where id in (
     '11111111-1111-4111-8111-111111111111',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333'
   )
     and owner_id is null;
  get diagnostics claimed = row_count;
  return claimed;
end;
$$;

comment on function rpg.claim_demo_party() is
  'Lets the first signed-in user adopt the unclaimed demo party: sets owner_id = auth.uid() on the three seeded demo characters where owner_id is still null, and returns the count claimed. SECURITY DEFINER (with empty search_path per 0002) so the claim can bypass the owner-only RLS that would otherwise block writing rows the caller does not yet own.';

grant execute on function rpg.claim_demo_party() to authenticated;

commit;
