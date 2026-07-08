-- ============================================================================
-- 0005_encounters_and_combat_board.sql
--
-- The ENCOUNTER FAMILY: a combat board the table-side GM builds fast, shows
-- to players as a rendered table, and manages through pure numbers.
--
-- New objects:
--   rpg.encounter_status      — enum: building | active | ended
--   rpg.combatant_side        — enum: party | foe | ally
--   rpg.condition             — enum: the 15 standard 5e SRD conditions
--   rpg.encounters            — one fight per row, with round + turn pointer
--   rpg.encounter_combatants  — one row per creature on the board
--   rpg.find_encounter        — slug -> the one open encounter (helper)
--   rpg.find_combatant        — display name -> combatant row (helper)
--   rpg.health_label          — hp -> fresh|wounded|bloodied|down (helper)
--   13 verbs                  — create_encounter, add_party, add_combatant,
--                               add_monster, remove_combatant, set_initiative,
--                               start_encounter, next_turn, damage_combatant,
--                               heal_combatant, add_condition,
--                               remove_condition, end_encounter
--   rpg.encounter_board       — the render-ready read view
--
-- Design decisions (agreed with the owner):
--   * PCs ARE NEVER COPIED. A combatant row either references a character
--     (character_id set — HP/AC/death saves are READ from rpg.characters,
--     never stored on the row; rpg.apply_damage remains how PCs take damage,
--     updating sheet and board in one write) or is a monster (character_id
--     null, own hp_current/hp_max/armor_class). Check constraints enforce
--     exactly these two shapes. Monster prose stays in the campaign binder;
--     the board holds only fighting numbers.
--   * ONE FIGHT AT A TIME. create_encounter refuses while a non-ended
--     encounter exists for the adventure, so every verb can resolve by
--     adventure slug alone — unambiguous mid-session. Enforcement is
--     verb-level (not a partial unique index) so that if the state ever
--     arises anyway, rpg.find_encounter can teach the way out (end the
--     extras by name via end_encounter's optional third parameter) instead
--     of the vault hard-failing.
--   * TINY RETURNS, SCOPED READS. Every verb returns only what changed;
--     next_turn returns only {round, up, side}. The board is one compact
--     view row per combatant, re-read once per render.
--   * FOE HP SECRECY IS A DERIVED LABEL. The view exposes exact numbers AND
--     a health label — fresh (full), wounded (below max), bloodied (<= half,
--     the 5e-familiar signal), down (0). The GM prompt shows party HP as
--     numbers and foe HP as the label; the vault only derives it (for
--     character-linked rows too — harmless and consistent).
--   * INITIATIVE TIEBREAK: initiative desc, then display name alphabetically
--     (case-insensitive) — deterministic, and names are unique per encounter
--     so the order is total. A table that wants a different tie order nudges
--     the initiative numbers.
--   * damage_combatant / heal_combatant are ONE VERB, BOTH SHAPES: monster
--     rows adjust their own HP (floor 0 / cap max); character-linked rows
--     delegate to rpg.apply_damage / rpg.heal and return their return.
--   * end_encounter AUTO-LOGS one summary sentence to the session notebook
--     via rpg.log_event (0004) and returns exactly what it logged.
--   * Exhaustion is a condition flag only; its level (1-6) is tracked in the
--     combatant's notes.
--
-- Security posture (shared project, advisor-clean, per 0001-0004):
--   * New tables: RLS ENABLED, NO policies (deny-by-default).
--   * rpg.encounter_board: security_invoker = on.
--   * Every function: SECURITY INVOKER (default), SET search_path = '' with
--     fully qualified body references.
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Enums (fixed value sets)
-- ---------------------------------------------------------------------------

create type rpg.encounter_status as enum ('building', 'active', 'ended');

comment on type rpg.encounter_status is
  'Encounter lifecycle: building (roster assembling, initiative being recorded), active (turns running), ended (over — the board view no longer shows it).';

create type rpg.combatant_side as enum ('party', 'foe', 'ally');

comment on type rpg.combatant_side is
  'Which side a combatant fights on: party (player characters), foe (opposition), ally (friendly NPCs fighting alongside the party).';

create type rpg.condition as enum (
  'blinded', 'charmed', 'deafened', 'frightened', 'grappled', 'incapacitated',
  'invisible', 'paralyzed', 'petrified', 'poisoned', 'prone', 'restrained',
  'stunned', 'unconscious', 'exhaustion'
);

comment on type rpg.condition is
  'The standard 5e SRD conditions. exhaustion is a flag only — its level (1-6) is tracked in the combatant''s notes; the enum just marks that it applies.';

-- ---------------------------------------------------------------------------
-- rpg.encounters — one fight per row
-- ---------------------------------------------------------------------------

create table rpg.encounters (
  id                    uuid                  primary key default gen_random_uuid(),
  adventure_id          uuid                  not null
                                              references rpg.adventures (id)
                                              on delete cascade,
  name                  text                  not null,
  status                rpg.encounter_status  not null default 'building',
  round                 smallint              not null default 0
                                              check (round >= 0),
  -- Turn pointer: FK to rpg.encounter_combatants added AFTER that table
  -- exists (circular reference between the two tables).
  active_combatant_id   uuid,
  notes                 text,
  created_at            timestamptz           not null default now(),
  updated_at            timestamptz           not null default now(),
  constraint encounters_name_not_blank
    check (btrim(name) <> '')
);

comment on table rpg.encounters is
  'Combat encounters per adventure: name (e.g. ''Ambush at the ford''), lifecycle status, current round, and a pointer to whose turn it is; at most one non-ended encounter per adventure, enforced by rpg.create_encounter.';

comment on column rpg.encounters.round is
  '0 while building; combat rounds count from 1 once rpg.start_encounter runs.';

comment on column rpg.encounters.active_combatant_id is
  'Whose turn it is (FK to rpg.encounter_combatants, added post-creation due to the circular reference); null while building and after the encounter ends.';

create index encounters_adventure_id_idx
  on rpg.encounters (adventure_id);

create trigger encounters_set_updated_at
  before update on rpg.encounters
  for each row execute function rpg.set_updated_at();

alter table rpg.encounters enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.encounter_combatants — one row per creature on the board
-- ---------------------------------------------------------------------------

create table rpg.encounter_combatants (
  id            uuid                not null primary key default gen_random_uuid(),
  encounter_id  uuid                not null
                                    references rpg.encounters (id)
                                    on delete cascade,
  -- Character-linked rows READ their HP/AC/death saves from rpg.characters;
  -- nothing is copied. Monster rows carry their own numbers below.
  character_id  uuid                references rpg.characters (id)
                                    on delete cascade,
  display_name  text                not null,
  side          rpg.combatant_side  not null,
  -- Rolled at the table, recorded via rpg.set_initiative; null until then —
  -- a combatant without initiative is not yet in the turn order.
  initiative    smallint,
  -- Monster-only fighting numbers (null on character-linked rows).
  hp_current    integer,
  hp_max        integer,
  armor_class   smallint,
  conditions    rpg.condition[]     not null default '{}',
  notes         text,
  created_at    timestamptz         not null default now(),
  updated_at    timestamptz         not null default now(),

  constraint encounter_combatants_display_name_not_blank
    check (btrim(display_name) <> ''),

  -- Exactly two shapes: character-linked rows carry NO monster numbers;
  -- monster rows MUST carry all three.
  constraint encounter_combatants_two_shapes
    check (
      (character_id is not null
         and hp_current is null and hp_max is null and armor_class is null)
      or
      (character_id is null
         and hp_current is not null and hp_max is not null
         and armor_class is not null)
    ),
  constraint encounter_combatants_hp_bounds
    check (hp_max is null or (hp_max > 0 and hp_current between 0 and hp_max)),
  constraint encounter_combatants_ac_bounds
    check (armor_class is null or armor_class between 1 and 30)
);

comment on table rpg.encounter_combatants is
  'Everyone on a combat board: either a reference to a character (HP/AC read live from rpg.characters, never copied) or a monster with its own fighting numbers — prose for both stays in the campaign binder.';

comment on column rpg.encounter_combatants.character_id is
  'Set for party members and allied NPCs with sheets: their HP/AC/death saves are read from rpg.characters, and rpg.apply_damage / rpg.heal (via damage_combatant / heal_combatant) update sheet and board in one write. Null for monsters.';

comment on column rpg.encounter_combatants.display_name is
  'How the board and the verbs name this combatant — unique per encounter, case-insensitive; add_monster numbers duplicates (''Goblin 1'' … ''Goblin N'').';

comment on column rpg.encounter_combatants.initiative is
  'Initiative total as rolled at the table; null until recorded via rpg.set_initiative — start_encounter refuses while anyone is missing one.';

comment on column rpg.encounter_combatants.conditions is
  'Active 5e conditions on this combatant; exhaustion''s level (1-6) is tracked in notes, the array entry just flags it.';

-- Display names resolve the verbs, so they must be unique per encounter
-- (case-insensitive); leading column also covers the encounter_id FK.
create unique index encounter_combatants_encounter_id_name_key
  on rpg.encounter_combatants (encounter_id, lower(display_name));

-- The board read: one encounter's roster in initiative order.
create index encounter_combatants_board_idx
  on rpg.encounter_combatants
     (encounter_id, initiative desc nulls last, lower(display_name));

create index encounter_combatants_character_id_idx
  on rpg.encounter_combatants (character_id);

create trigger encounter_combatants_set_updated_at
  before update on rpg.encounter_combatants
  for each row execute function rpg.set_updated_at();

alter table rpg.encounter_combatants enable row level security;

-- The turn pointer, now that both tables exist (circular reference).
alter table rpg.encounters
  add constraint encounters_active_combatant_id_fkey
  foreign key (active_combatant_id)
  references rpg.encounter_combatants (id)
  on delete set null;

create index encounters_active_combatant_id_idx
  on rpg.encounters (active_combatant_id);

-- ---------------------------------------------------------------------------
-- Lookup helpers (resolution with model-readable errors)
-- ---------------------------------------------------------------------------

create function rpg.find_encounter(
  p_adventure_slug  text,
  p_encounter_name  text default null)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_aid uuid := rpg.find_adventure(p_adventure_slug);
  v_id  uuid;
begin
  if p_encounter_name is not null then
    select e.id into strict v_id
    from rpg.encounters e
    where e.adventure_id = v_aid
      and e.status <> 'ended'
      and lower(e.name) = lower(p_encounter_name);
  else
    select e.id into strict v_id
    from rpg.encounters e
    where e.adventure_id = v_aid
      and e.status <> 'ended';
  end if;
  return v_id;
exception
  when no_data_found then
    if p_encounter_name is not null then
      raise exception 'No open encounter named "%" for "%". Open encounters: %.',
        p_encounter_name, lower(p_adventure_slug),
        coalesce((select string_agg(e.name, '; ' order by e.created_at)
                  from rpg.encounters e
                  where e.adventure_id = v_aid and e.status <> 'ended'),
                 '(none)');
    else
      raise exception 'No open encounter for "%". Build one: select rpg.create_encounter(''%'', ''<encounter name>'');',
        lower(p_adventure_slug), lower(p_adventure_slug);
    end if;
  when too_many_rows then
    raise exception 'Several open encounters for "%": %. There should be one fight at a time — end the extras by name: select rpg.end_encounter(''%'', null, ''<encounter name>'');',
      lower(p_adventure_slug),
      (select string_agg(e.name, '; ' order by e.created_at)
       from rpg.encounters e
       where e.adventure_id = v_aid and e.status <> 'ended'),
      lower(p_adventure_slug);
end;
$$;

comment on function rpg.find_encounter(text, text) is
  'Resolves an adventure slug to its single open (non-ended) encounter, or — with the optional name — to a specific open encounter; raises clear errors when none exist or several do. Internal helper for the encounter verbs.';

create function rpg.find_combatant(p_encounter_id uuid, p_name text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select cb.id into strict v_id
  from rpg.encounter_combatants cb
  where cb.encounter_id = p_encounter_id
    and lower(cb.display_name) = lower(p_name);
  return v_id;
exception
  when no_data_found then
    raise exception 'No combatant named "%" on this board. Roster: %.',
      p_name,
      coalesce((select string_agg(cb.display_name, ', '
                                  order by lower(cb.display_name))
                from rpg.encounter_combatants cb
                where cb.encounter_id = p_encounter_id),
               '(empty)');
end;
$$;

comment on function rpg.find_combatant(uuid, text) is
  'Resolves a display name (case-insensitive) to a combatant row within one encounter; the not-found error lists the roster. Names are unique per encounter, so no ambiguity branch is needed. Internal helper for the encounter verbs.';

create function rpg.health_label(p_current integer, p_max integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
           when p_current is null or p_max is null then null
           when p_current <= 0                     then 'down'
           when p_current >= p_max                 then 'fresh'
           when p_current * 2 <= p_max             then 'bloodied'
           else                                         'wounded'
         end
$$;

comment on function rpg.health_label(integer, integer) is
  'Derives the coarse health label the GM shows for foes instead of numbers: fresh (full HP), wounded (below max), bloodied (at or below half, the 5e-familiar signal), down (0). Derived, never stored.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — building the board
-- ---------------------------------------------------------------------------

create function rpg.create_encounter(p_adventure_slug text, p_name text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_aid  uuid := rpg.find_adventure(p_adventure_slug);
  v_open text;
begin
  if p_name is null or btrim(p_name) = '' then
    raise exception 'An encounter needs a name, e.g. ''Ambush at the ford''.';
  end if;
  select e.name into v_open
  from rpg.encounters e
  where e.adventure_id = v_aid and e.status <> 'ended'
  limit 1;
  if v_open is not null then
    -- One fight at a time: every verb resolves by adventure slug alone, so a
    -- second open encounter would make that resolution ambiguous.
    raise exception 'An open encounter "%" already exists for "%" — one fight at a time keeps resolution unambiguous. End it first: select rpg.end_encounter(''%'');',
      v_open, lower(p_adventure_slug), lower(p_adventure_slug);
  end if;
  insert into rpg.encounters (adventure_id, name)
  values (v_aid, btrim(p_name));
  return jsonb_build_object(
    'adventure_slug', lower(p_adventure_slug),
    'encounter',      btrim(p_name),
    'status',         'building');
end;
$$;

comment on function rpg.create_encounter(text, text) is
  'Opens a new encounter (status ''building'') for an adventure. Refuses while a non-ended encounter exists — one fight at a time, so every encounter verb can resolve by adventure slug alone. Returns the encounter and its status.';

create function rpg.add_party(p_adventure_slug text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid   uuid := rpg.find_encounter(p_adventure_slug);
  v_aid   uuid;
  v_enc   text;
  v_added jsonb;
begin
  select e.adventure_id, e.name into v_aid, v_enc
  from rpg.encounters e where e.id = v_eid;
  if not exists (select 1 from rpg.adventure_characters ac
                 where ac.adventure_id = v_aid) then
    raise exception 'Adventure "%" has an empty party roster. Add characters first: select rpg.add_to_party(''%'', ''<character name>'');',
      lower(p_adventure_slug), lower(p_adventure_slug);
  end if;
  with ins as (
    insert into rpg.encounter_combatants
      (encounter_id, character_id, display_name, side)
    select v_eid, c.id, c.name, 'party'
    from rpg.adventure_characters ac
    join rpg.characters c on c.id = ac.character_id
    where ac.adventure_id = v_aid
      and not exists (select 1 from rpg.encounter_combatants cb
                      where cb.encounter_id = v_eid
                        and cb.character_id = c.id)
    returning display_name
  )
  select coalesce(jsonb_agg(i.display_name order by lower(i.display_name)),
                  '[]'::jsonb)
    into v_added
  from ins i;
  return jsonb_build_object('encounter', v_enc, 'added', v_added);
exception
  when unique_violation then
    raise exception 'A combatant on this board already uses a party member''s name (names are unique per encounter, case-insensitive). Remove or rename it — select rpg.remove_combatant(''%'', ''<name>''); — then retry.',
      lower(p_adventure_slug);
end;
$$;

comment on function rpg.add_party(text) is
  'Puts the adventure''s whole roster on the board in one call: every character not already on it, side ''party'', display name = character name (HP/AC stay on the sheet — never copied). Idempotent: re-running adds only the missing. Returns the names added.';

create function rpg.add_combatant(
  p_adventure_slug  text,
  p_character_name  text,
  p_side            rpg.combatant_side default 'party')
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid  uuid := rpg.find_encounter(p_adventure_slug);
  v_cid  uuid := rpg.find_character(p_character_name);
  v_name text;
  v_side rpg.combatant_side := coalesce(p_side, 'party');
begin
  select c.name into v_name from rpg.characters c where c.id = v_cid;
  if exists (select 1 from rpg.encounter_combatants cb
             where cb.encounter_id = v_eid and cb.character_id = v_cid) then
    raise exception '"%" is already on the board.', v_name;
  end if;
  insert into rpg.encounter_combatants
    (encounter_id, character_id, display_name, side)
  values (v_eid, v_cid, v_name, v_side);
  return jsonb_build_object('name', v_name, 'side', v_side);
exception
  when unique_violation then
    raise exception 'A combatant named "%" is already on the board (names are unique per encounter, case-insensitive).', v_name;
end;
$$;

comment on function rpg.add_combatant(text, text, rpg.combatant_side) is
  'Puts one character on the board by name (side ''party'' by default; ''ally'' for friendly NPCs with sheets). HP/AC stay on the character sheet — never copied. Returns the name and side.';

create function rpg.add_monster(
  p_adventure_slug  text,
  p_name            text,
  p_armor_class     integer,
  p_hp              integer,
  p_count           integer            default 1,
  p_side            rpg.combatant_side default 'foe')
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid   uuid := rpg.find_encounter(p_adventure_slug);
  v_count integer := coalesce(p_count, 1);
  v_side  rpg.combatant_side := coalesce(p_side, 'foe');
  v_names jsonb;
begin
  if p_name is null or btrim(p_name) = '' then
    raise exception 'A monster needs a name.';
  end if;
  if coalesce(p_hp, 0) <= 0 then
    raise exception 'Monster HP must be a positive integer (got %).', p_hp;
  end if;
  if coalesce(p_armor_class, 0) not between 1 and 30 then
    raise exception 'Monster AC must be between 1 and 30 (got %).', p_armor_class;
  end if;
  if v_count not between 1 and 30 then
    raise exception 'Count must be between 1 and 30 (got %); add larger hordes in batches with distinct names.', p_count;
  end if;
  with ins as (
    insert into rpg.encounter_combatants
      (encounter_id, display_name, side, hp_current, hp_max, armor_class)
    select v_eid,
           case when v_count = 1 then btrim(p_name)
                else btrim(p_name) || ' ' || g.n end,
           v_side, p_hp, p_hp, p_armor_class
    from generate_series(1, v_count) as g(n)
    returning display_name
  )
  select jsonb_agg(i.display_name
                   order by length(i.display_name), i.display_name)
    into v_names
  from ins i;
  return jsonb_build_object(
    'added', v_names, 'ac', p_armor_class, 'hp', p_hp, 'side', v_side);
exception
  when unique_violation then
    raise exception 'A combatant named "%" (or one of its numbered copies) is already on the board — names are unique per encounter, case-insensitive. A second wave needs fresh names, e.g. ''% 4''.',
      btrim(p_name), btrim(p_name);
end;
$$;

comment on function rpg.add_monster(text, text, integer, integer, integer, rpg.combatant_side) is
  'Puts monsters on the board with their own fighting numbers (AC, HP; prose stays in the binder). count > 1 numbers them ''Name 1'' … ''Name N''. Side defaults to ''foe''. Returns the names added with their shared AC and HP.';

create function rpg.remove_combatant(p_adventure_slug text, p_name text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid     uuid := rpg.find_encounter(p_adventure_slug);
  v_cbid    uuid := rpg.find_combatant(v_eid, p_name);
  v_name    text;
  v_pointer uuid;
  v_status  rpg.encounter_status;
begin
  select e.active_combatant_id, e.status into v_pointer, v_status
  from rpg.encounters e where e.id = v_eid;
  if v_status = 'active' and v_pointer = v_cbid then
    raise exception 'It is "%"''s turn; advance first — select rpg.next_turn(''%''); — then remove.',
      p_name, lower(p_adventure_slug);
  end if;
  delete from rpg.encounter_combatants
  where id = v_cbid
  returning display_name into v_name;
  return jsonb_build_object('removed', v_name);
end;
$$;

comment on function rpg.remove_combatant(text, text) is
  'Takes a combatant off the board — for building mistakes; dead monsters stay (next_turn skips them). Errors — listing the roster — when the name is not found, and refuses to remove whoever''s turn it currently is. Returns the removed name.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — initiative and turns
-- ---------------------------------------------------------------------------

create function rpg.set_initiative(
  p_adventure_slug text,
  p_name           text,
  p_value          integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid  uuid := rpg.find_encounter(p_adventure_slug);
  v_cbid uuid := rpg.find_combatant(v_eid, p_name);
  v_name text;
begin
  if p_value is null then
    raise exception 'Initiative must be a number — the total rolled at the table (d20 + DEX modifier).';
  end if;
  update rpg.encounter_combatants
  set initiative = p_value
  where id = v_cbid
  returning display_name into v_name;
  return jsonb_build_object('name', v_name, 'initiative', p_value);
end;
$$;

comment on function rpg.set_initiative(text, text, integer) is
  'Records a combatant''s initiative total — the dice are rolled at the table, this just writes the number down. Returns the name and value.';

create function rpg.start_encounter(p_adventure_slug text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid     uuid := rpg.find_encounter(p_adventure_slug);
  v_enc     record;
  v_missing text;
  v_first   record;
begin
  select e.name, e.status, e.round into v_enc
  from rpg.encounters e where e.id = v_eid;
  if v_enc.status = 'active' then
    raise exception 'Encounter "%" is already active (round %). Advance: select rpg.next_turn(''%'');',
      v_enc.name, v_enc.round, lower(p_adventure_slug);
  end if;
  if not exists (select 1 from rpg.encounter_combatants cb
                 where cb.encounter_id = v_eid) then
    raise exception 'Encounter "%" has no combatants. Board the party — select rpg.add_party(''%''); — and the opposition — select rpg.add_monster(''%'', ''<name>'', <ac>, <hp>, <count>);',
      v_enc.name, lower(p_adventure_slug), lower(p_adventure_slug);
  end if;
  select string_agg(cb.display_name, ', ' order by lower(cb.display_name))
    into v_missing
  from rpg.encounter_combatants cb
  where cb.encounter_id = v_eid and cb.initiative is null;
  if v_missing is not null then
    raise exception 'Missing initiative for: %. Record each — select rpg.set_initiative(''%'', ''<name>'', <total>); — then start again.',
      v_missing, lower(p_adventure_slug);
  end if;
  -- Turn order: initiative desc; ties break alphabetically by display name
  -- (case-insensitive) — deterministic, since names are unique per encounter.
  select cb.id, cb.display_name, cb.side into v_first
  from rpg.encounter_combatants cb
  where cb.encounter_id = v_eid
  order by cb.initiative desc nulls last, lower(cb.display_name)
  limit 1;
  update rpg.encounters
  set status = 'active', round = 1, active_combatant_id = v_first.id
  where id = v_eid;
  return jsonb_build_object(
    'encounter', v_enc.name,
    'round',     1,
    'up',        v_first.display_name,
    'side',      v_first.side);
end;
$$;

comment on function rpg.start_encounter(text) is
  'Starts the fight: errors — naming them — while anyone lacks initiative; otherwise status ''active'', round 1, turn pointer to the highest initiative (ties break alphabetically by display name — deterministic; nudge initiative values for a different order). Returns {encounter, round, up, side}.';

create function rpg.next_turn(p_adventure_slug text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid     uuid := rpg.find_encounter(p_adventure_slug);
  v_status  rpg.encounter_status;
  v_round   smallint;
  v_pointer uuid;
  v_ids     uuid[];
  v_names   text[];
  v_sides   rpg.combatant_side[];
  v_can_act boolean[];
  v_n       integer;
  v_pos     integer := 0;
  v_i       integer;
  v_steps   integer := 0;
begin
  select e.status, e.round, e.active_combatant_id
    into v_status, v_round, v_pointer
  from rpg.encounters e where e.id = v_eid;
  if v_status <> 'active' then
    raise exception 'The encounter is still building. Start it: select rpg.start_encounter(''%'');',
      lower(p_adventure_slug);
  end if;
  -- The full order, plus who may act: character-linked combatants always
  -- take their turn (death saves happen on turns); monsters at 0 HP are
  -- skipped; combatants without initiative are not in the order yet.
  select array_agg(t.id       order by t.ord),
         array_agg(t.display_name order by t.ord),
         array_agg(t.side     order by t.ord),
         array_agg(t.can_act  order by t.ord)
    into v_ids, v_names, v_sides, v_can_act
  from (
    select cb.id, cb.display_name, cb.side,
           (cb.initiative is not null
              and (cb.character_id is not null or cb.hp_current > 0)) as can_act,
           row_number() over (order by cb.initiative desc nulls last,
                                       lower(cb.display_name)) as ord
    from rpg.encounter_combatants cb
    where cb.encounter_id = v_eid
  ) t;
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n = 0 then
    raise exception 'The board is empty. End the encounter: select rpg.end_encounter(''%'');',
      lower(p_adventure_slug);
  end if;
  for i in 1 .. v_n loop
    if v_ids[i] = v_pointer then
      v_pos := i;
    end if;
  end loop;
  v_i := v_pos;
  loop
    v_steps := v_steps + 1;
    if v_steps > v_n then
      raise exception 'No combatant can act: every foe is down (monsters at 0 HP are skipped; combatants without initiative are not in the order). End it: select rpg.end_encounter(''%'');',
        lower(p_adventure_slug);
    end if;
    v_i := v_i + 1;
    if v_i > v_n then
      v_i := 1;
      v_round := v_round + 1;
    end if;
    exit when v_can_act[v_i];
  end loop;
  update rpg.encounters
  set round = v_round, active_combatant_id = v_ids[v_i]
  where id = v_eid;
  return jsonb_build_object(
    'round', v_round, 'up', v_names[v_i], 'side', v_sides[v_i]);
end;
$$;

comment on function rpg.next_turn(text) is
  'Advances the turn pointer in initiative order: monsters at 0 HP are skipped, character-linked combatants at 0 HP still get their turn (death saves happen on turns), and passing the top of the order bumps the round. Returns only {round, up, side}.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — damage, healing, conditions (one verb, both shapes)
-- ---------------------------------------------------------------------------

create function rpg.damage_combatant(
  p_adventure_slug text,
  p_name           text,
  p_amount         integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid uuid := rpg.find_encounter(p_adventure_slug);
  v_cb  record;
  v_hp  integer;
begin
  select cb.id, cb.character_id, cb.display_name, cb.hp_max into v_cb
  from rpg.encounter_combatants cb
  where cb.id = rpg.find_combatant(v_eid, p_name);
  if v_cb.character_id is not null then
    -- Character-linked: the sheet is the truth — delegate, one write updates
    -- sheet and board alike, and hand back apply_damage's own return.
    return rpg.apply_damage(
      (select c.name from rpg.characters c where c.id = v_cb.character_id),
      p_amount);
  end if;
  if coalesce(p_amount, -1) < 0 then
    raise exception 'Damage amount must be a non-negative integer (got %).', p_amount;
  end if;
  update rpg.encounter_combatants
  set hp_current = greatest(hp_current - p_amount, 0)
  where id = v_cb.id
  returning hp_current into v_hp;
  return jsonb_build_object(
    'name',       v_cb.display_name,
    'hp_current', v_hp,
    'hp_max',     v_cb.hp_max,
    'health',     rpg.health_label(v_hp, v_cb.hp_max));
end;
$$;

comment on function rpg.damage_combatant(text, text, integer) is
  'Deals damage on the board — one verb, both shapes: monster rows lose their own HP (floored at 0) and return {name, hp_current, hp_max, health}; character-linked rows delegate to rpg.apply_damage (temp-HP-first, sheet updated) and return its return.';

create function rpg.heal_combatant(
  p_adventure_slug text,
  p_name           text,
  p_amount         integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid uuid := rpg.find_encounter(p_adventure_slug);
  v_cb  record;
  v_hp  integer;
begin
  select cb.id, cb.character_id, cb.display_name, cb.hp_max into v_cb
  from rpg.encounter_combatants cb
  where cb.id = rpg.find_combatant(v_eid, p_name);
  if v_cb.character_id is not null then
    return rpg.heal(
      (select c.name from rpg.characters c where c.id = v_cb.character_id),
      p_amount);
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Healing amount must be a positive integer (got %).', p_amount;
  end if;
  update rpg.encounter_combatants
  set hp_current = least(hp_current + p_amount, hp_max)
  where id = v_cb.id
  returning hp_current into v_hp;
  return jsonb_build_object(
    'name',       v_cb.display_name,
    'hp_current', v_hp,
    'hp_max',     v_cb.hp_max,
    'health',     rpg.health_label(v_hp, v_cb.hp_max));
end;
$$;

comment on function rpg.heal_combatant(text, text, integer) is
  'Heals on the board — one verb, both shapes: monster rows regain their own HP (capped at max) and return {name, hp_current, hp_max, health}; character-linked rows delegate to rpg.heal (cap at max, death saves reset from 0, sheet updated) and return its return.';

create function rpg.add_condition(
  p_adventure_slug text,
  p_name           text,
  p_condition      rpg.condition)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid        uuid := rpg.find_encounter(p_adventure_slug);
  v_cbid       uuid := rpg.find_combatant(v_eid, p_name);
  v_name       text;
  v_conditions rpg.condition[];
begin
  if p_condition is null then
    raise exception 'Condition must be one of: %.',
      (select string_agg(c.x::text, ', ')
       from unnest(enum_range(null::rpg.condition)) as c(x));
  end if;
  update rpg.encounter_combatants
  set conditions = case when p_condition = any (conditions) then conditions
                        else array_append(conditions, p_condition) end
  where id = v_cbid
  returning display_name, conditions into v_name, v_conditions;
  return jsonb_build_object('name', v_name, 'conditions', to_jsonb(v_conditions));
end;
$$;

comment on function rpg.add_condition(text, text, rpg.condition) is
  'Marks a 5e condition on a combatant (idempotent: re-adding is a no-op). For exhaustion, note the level (1-6) in the combatant''s notes — the flag alone is stored here. Returns the combatant''s conditions.';

create function rpg.remove_condition(
  p_adventure_slug text,
  p_name           text,
  p_condition      rpg.condition)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid        uuid := rpg.find_encounter(p_adventure_slug);
  v_cbid       uuid := rpg.find_combatant(v_eid, p_name);
  v_name       text;
  v_conditions rpg.condition[];
begin
  if p_condition is null then
    raise exception 'Condition must be one of: %.',
      (select string_agg(c.x::text, ', ')
       from unnest(enum_range(null::rpg.condition)) as c(x));
  end if;
  select cb.display_name, cb.conditions into v_name, v_conditions
  from rpg.encounter_combatants cb where cb.id = v_cbid;
  if not (p_condition = any (v_conditions)) then
    raise exception '"%" is not %; current conditions: %.',
      v_name, p_condition,
      coalesce(nullif(array_to_string(v_conditions, ', '), ''), '(none)');
  end if;
  update rpg.encounter_combatants
  set conditions = array_remove(conditions, p_condition)
  where id = v_cbid
  returning conditions into v_conditions;
  return jsonb_build_object('name', v_name, 'conditions', to_jsonb(v_conditions));
end;
$$;

comment on function rpg.remove_condition(text, text, rpg.condition) is
  'Clears a 5e condition from a combatant; errors — listing the current conditions — when it was not on them. Returns the combatant''s conditions.';

-- ---------------------------------------------------------------------------
-- WRITE VERB — ending the fight (auto-logs to the session notebook)
-- ---------------------------------------------------------------------------

create function rpg.end_encounter(
  p_adventure_slug  text,
  p_outcome         text default null,
  p_encounter_name  text default null)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_eid        uuid := rpg.find_encounter(p_adventure_slug, p_encounter_name);
  v_name       text;
  v_round      smallint;
  v_foes_total integer;
  v_foes_down  integer;
  v_party_down text;
  v_summary    text;
begin
  select e.name, e.round into v_name, v_round
  from rpg.encounters e where e.id = v_eid;
  select count(*),
         count(*) filter (where coalesce(cb.hp_current, ch.hp_current) = 0)
    into v_foes_total, v_foes_down
  from rpg.encounter_combatants cb
  left join rpg.characters ch on ch.id = cb.character_id
  where cb.encounter_id = v_eid and cb.side = 'foe';
  select string_agg(cb.display_name, ', ' order by lower(cb.display_name))
    into v_party_down
  from rpg.encounter_combatants cb
  left join rpg.characters ch on ch.id = cb.character_id
  where cb.encounter_id = v_eid
    and cb.side = 'party'
    and coalesce(ch.hp_current, cb.hp_current) = 0;
  if v_round = 0 then
    v_summary := format('Encounter "%s" ended before it began', v_name);
  else
    v_summary := format('Encounter "%s" ended after %s %s', v_name, v_round,
                        case when v_round = 1 then 'round' else 'rounds' end);
  end if;
  if v_foes_total > 0 then
    v_summary := v_summary
                 || format(': %s of %s foes down', v_foes_down, v_foes_total);
  end if;
  if v_party_down is not null then
    v_summary := v_summary || format('; at 0 HP: %s', v_party_down);
  end if;
  if p_outcome is not null and btrim(p_outcome) <> '' then
    v_summary := v_summary || format(' — %s', btrim(p_outcome));
  end if;
  v_summary := v_summary || '.';
  update rpg.encounters
  set status = 'ended', active_combatant_id = null
  where id = v_eid;
  -- Auto-log to the session notebook (0004): the fight becomes one durable
  -- sentence, and the caller gets back exactly what was logged.
  return rpg.log_event(p_adventure_slug, v_summary);
end;
$$;

comment on function rpg.end_encounter(text, text, text) is
  'Ends the fight: status ''ended'', turn pointer cleared, and one summary sentence — encounter name, rounds fought, foes down, party members at 0 HP, plus the outcome text if given — auto-logged to the session notebook via rpg.log_event. The optional third parameter names a specific open encounter (only ever needed to untangle several). Returns the logged entry.';

-- ---------------------------------------------------------------------------
-- READ VIEW — rpg.encounter_board
-- ---------------------------------------------------------------------------

create view rpg.encounter_board
with (security_invoker = on) as
select
  a.slug                                              as adventure_slug,
  e.name                                              as encounter,
  e.status,
  e.round,
  coalesce(cb.id = e.active_combatant_id, false)      as is_up,
  row_number() over (partition by e.id
                     order by cb.initiative desc nulls last,
                              lower(cb.display_name)) as turn_order,
  cb.display_name                                     as name,
  cb.side,
  cb.initiative,
  coalesce(ch.armor_class, cb.armor_class)            as armor_class,
  coalesce(ch.hp_current,  cb.hp_current)             as hp_current,
  coalesce(ch.hp_max,      cb.hp_max)                 as hp_max,
  rpg.health_label(coalesce(ch.hp_current, cb.hp_current),
                   coalesce(ch.hp_max,     cb.hp_max)) as health,
  cb.conditions,
  cb.notes
from rpg.encounters e
join rpg.adventures a on a.id = e.adventure_id
join rpg.encounter_combatants cb on cb.encounter_id = e.id
left join rpg.characters ch on ch.id = cb.character_id
where e.status <> 'ended'
order by a.slug, e.id,
         cb.initiative desc nulls last, lower(cb.display_name);

comment on view rpg.encounter_board is
  'The combat board, one row per combatant in initiative order, ready to render: turn marker (is_up), AC and HP coalesced from the character sheet or the monster row, the derived health label (fresh|wounded|bloodied|down — show foes the label, the party the numbers), conditions, notes. Canonical read: select * from rpg.encounter_board where adventure_slug = ''<slug>''; — re-read once per render, after the turn''s writes.';

commit;
