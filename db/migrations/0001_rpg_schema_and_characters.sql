-- ============================================================================
-- 0001_rpg_schema_and_characters.sql
--
-- Creates the `rpg` schema (the Rollspel fence: every roleplaying object
-- lives here and nowhere else) and the CHARACTER FAMILY for D&D 5e one-shots:
--
--   rpg.characters             — one row per player character
--   rpg.character_skills       — skill proficiencies (proficient / expertise)
--   rpg.character_items        — inventory
--   rpg.character_spell_slots  — live slot tracking per spell level
--   rpg.character_spells       — known / prepared spells (text names, SRD prose
--                                stays in the campaign binder)
--
-- Deliberately NOT in this migration (later GM-family migration):
-- NPCs, monsters, adventures, encounters, session records.
--
-- Design decisions (stored vs derived):
--   * proficiency_bonus  — DERIVED from level as a generated column
--                          (2 + (level-1)/4); cannot drift.
--   * ability modifiers  — DERIVED via rpg.ability_modifier(score); not stored.
--   * passive perception — DERIVED: 10 + ability_modifier(wisdom)
--                          + proficiency_bonus if perception row exists in
--                          character_skills (doubled on expertise). Not stored.
--   * AC, speed, HP, hit dice, death saves — STORED live session state.
--
-- RLS: ENABLED on every table, with NO policies. This is a shared Supabase
-- project; deny-by-default protects the room if the `rpg` schema is ever
-- exposed through the API. Trusted tooling connects as service_role, which
-- bypasses RLS. Policies come later if an end-user client ever appears.
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The room
-- ---------------------------------------------------------------------------

create schema rpg;

comment on schema rpg is
  'Rollspel: all D&D 5e one-shot roleplaying objects. The schema is the tenant fence — nothing of ours lives outside it.';

-- ---------------------------------------------------------------------------
-- Enums (fixed 5e value sets)
-- ---------------------------------------------------------------------------

create type rpg.ability as enum (
  'strength', 'dexterity', 'constitution',
  'intelligence', 'wisdom', 'charisma'
);

create type rpg.skill as enum (
  'acrobatics', 'animal_handling', 'arcana', 'athletics', 'deception',
  'history', 'insight', 'intimidation', 'investigation', 'medicine',
  'nature', 'perception', 'performance', 'persuasion', 'religion',
  'sleight_of_hand', 'stealth', 'survival'
);

create type rpg.alignment as enum (
  'lawful_good',    'neutral_good', 'chaotic_good',
  'lawful_neutral', 'true_neutral', 'chaotic_neutral',
  'lawful_evil',    'neutral_evil', 'chaotic_evil'
);

-- Hit dice only; d4/d20 are not hit dice for any 5e class.
create type rpg.hit_die as enum ('d6', 'd8', 'd10', 'd12');

-- ---------------------------------------------------------------------------
-- Helper functions (small, single-purpose, reusable)
-- ---------------------------------------------------------------------------

create function rpg.ability_modifier(score integer)
returns integer
language sql
immutable
returns null on null input
as $$
  select floor((score - 10) / 2.0)::integer
$$;

comment on function rpg.ability_modifier(integer) is
  '5e ability modifier: floor((score - 10) / 2). Modifiers are derived, never stored.';

create function rpg.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function rpg.set_updated_at() is
  'Trigger function: stamps updated_at on every UPDATE.';

-- ---------------------------------------------------------------------------
-- rpg.characters — the core table
-- ---------------------------------------------------------------------------

create table rpg.characters (
  id                    uuid          primary key default gen_random_uuid(),

  -- identity
  name                  text          not null,
  player_name           text,
  class                 text          not null,
  subclass              text,
  level                 smallint      not null default 1
                                      check (level between 1 and 20),
  species               text          not null,
  background            text,
  alignment             rpg.alignment,

  -- the six ability scores (modifiers derived via rpg.ability_modifier)
  strength              smallint      not null check (strength     between 1 and 30),
  dexterity             smallint      not null check (dexterity    between 1 and 30),
  constitution          smallint      not null check (constitution between 1 and 30),
  intelligence          smallint      not null check (intelligence between 1 and 30),
  wisdom                smallint      not null check (wisdom       between 1 and 30),
  charisma              smallint      not null check (charisma     between 1 and 30),

  -- derived, generated so it cannot drift from level
  proficiency_bonus     smallint      generated always as (2 + (level - 1) / 4) stored,

  -- defenses & movement (stored: depend on gear/features, not derivable here)
  armor_class           smallint      not null check (armor_class between 1 and 30),
  speed                 smallint      not null default 30 check (speed >= 0),

  -- live hit points
  hp_max                integer       not null check (hp_max > 0),
  hp_current            integer       not null
                                      check (hp_current >= 0),
  hp_temp               integer       not null default 0 check (hp_temp >= 0),
  constraint characters_hp_current_within_max
    check (hp_current <= hp_max),

  -- hit dice (total stored separately from level: multiclass-safe)
  hit_die               rpg.hit_die   not null,
  hit_dice_total        smallint      not null check (hit_dice_total between 1 and 20),
  hit_dice_remaining    smallint      not null,
  constraint characters_hit_dice_remaining_within_total
    check (hit_dice_remaining between 0 and hit_dice_total),

  -- death saves (live state at 0 HP; reset on stabilize/heal)
  death_save_successes  smallint      not null default 0
                                      check (death_save_successes between 0 and 3),
  death_save_failures   smallint      not null default 0
                                      check (death_save_failures between 0 and 3),

  -- saving-throw proficiencies: a pure set of <= 6 enum values with no
  -- per-entry state, so an enum array beats a child table here
  save_proficiencies    rpg.ability[] not null default '{}',

  -- spellcasting (null for non-casters); save DC / attack bonus derive from
  -- this + proficiency_bonus, so they are not stored
  spellcasting_ability  rpg.ability,

  notes                 text,

  created_at            timestamptz   not null default now(),
  updated_at            timestamptz   not null default now()
);

comment on table rpg.characters is
  'Player characters for D&D 5e one-shots: identity, ability scores, and live mid-session state (HP, hit dice, death saves); modifiers, passive perception, and spell DCs are derived, not stored.';

comment on column rpg.characters.save_proficiencies is
  'Set of abilities the character is proficient in for saving throws; save bonus = ability_modifier + proficiency_bonus when listed.';

comment on column rpg.characters.hp_temp is
  'Temporary hit points; deplete before hp_current and do not stack (5e RAW: take the higher).';

create trigger characters_set_updated_at
  before update on rpg.characters
  for each row execute function rpg.set_updated_at();

alter table rpg.characters enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.character_skills — skill proficiencies
-- (child table, not an array: skills carry per-entry state — expertise)
-- ---------------------------------------------------------------------------

create table rpg.character_skills (
  character_id  uuid       not null references rpg.characters (id) on delete cascade,
  skill         rpg.skill  not null,
  expertise     boolean    not null default false,
  primary key (character_id, skill)
);

comment on table rpg.character_skills is
  'Skill proficiencies per character: a row means proficient; expertise = true doubles the proficiency bonus. Absent row = not proficient.';

-- FK index: covered by the primary key (character_id is its leading column).

alter table rpg.character_skills enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.character_items — inventory
-- ---------------------------------------------------------------------------

create table rpg.character_items (
  id            uuid         primary key default gen_random_uuid(),
  character_id  uuid         not null references rpg.characters (id) on delete cascade,
  name          text         not null,
  quantity      integer      not null default 1 check (quantity > 0),
  equipped      boolean      not null default false,
  attuned       boolean      not null default false,
  notes         text,
  created_at    timestamptz  not null default now(),
  updated_at    timestamptz  not null default now()
);

comment on table rpg.character_items is
  'Inventory: what a character carries, with quantity and equipped/attuned flags; the 3-attuned-items cap is a table rule the GM enforces, not a constraint.';

create index character_items_character_id_idx
  on rpg.character_items (character_id);

create trigger character_items_set_updated_at
  before update on rpg.character_items
  for each row execute function rpg.set_updated_at();

alter table rpg.character_items enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.character_spell_slots — live slot tracking
-- ---------------------------------------------------------------------------

create table rpg.character_spell_slots (
  character_id    uuid      not null references rpg.characters (id) on delete cascade,
  slot_level      smallint  not null check (slot_level between 1 and 9),
  slots_total     smallint  not null check (slots_total >= 0),
  slots_expended  smallint  not null default 0,
  primary key (character_id, slot_level),
  constraint character_spell_slots_expended_within_total
    check (slots_expended between 0 and slots_total)
);

comment on table rpg.character_spell_slots is
  'Live spell-slot tracking per spell level (1-9): total available and expended this session; a long rest resets slots_expended to 0.';

-- FK index: covered by the primary key (character_id is its leading column).

alter table rpg.character_spell_slots enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.character_spells — known / prepared spells
-- (text name + optional notes; SRD spell prose lives in the campaign binder.
--  A spell lookup table is a later migration if it ever earns its keep.)
-- ---------------------------------------------------------------------------

create table rpg.character_spells (
  id            uuid         primary key default gen_random_uuid(),
  character_id  uuid         not null references rpg.characters (id) on delete cascade,
  name          text         not null,
  spell_level   smallint     not null check (spell_level between 0 and 9),
  prepared      boolean      not null default true,
  notes         text,
  created_at    timestamptz  not null default now(),
  updated_at    timestamptz  not null default now()
);

comment on table rpg.character_spells is
  'Spells a character knows, by name; spell_level 0 = cantrip; prepared = castable today (known-casters simply leave every spell prepared). Rules text lives in the SRD, not here.';

create index character_spells_character_id_idx
  on rpg.character_spells (character_id);

create unique index character_spells_character_id_name_key
  on rpg.character_spells (character_id, lower(name));

create trigger character_spells_set_updated_at
  before update on rpg.character_spells
  for each row execute function rpg.set_updated_at();

alter table rpg.character_spells enable row level security;

commit;
