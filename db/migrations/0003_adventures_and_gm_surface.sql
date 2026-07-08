-- ============================================================================
-- 0003_adventures_and_gm_surface.sql
--
-- The ADVENTURE FAMILY plus the GM's CURATED SQL SURFACE. The table-side GM
-- is a ChatGPT connector speaking raw SQL, so this migration gives it a menu
-- instead of a kitchen:
--
--   READS  — two views, each a one-query complete answer:
--     rpg.character_sheets  — one row = one whole character sheet
--     rpg.adventure_party   — character_sheets through the roster, by slug
--
--   WRITES — domain verbs as functions, so 5e bookkeeping (temp-HP-first,
--     heal caps, death-save resets, rest rules) lives here once and is never
--     re-derived in chat. The GPT never composes multi-table joins or raw
--     UPDATEs mid-session.
--
-- New tables:
--   rpg.adventures            — one-shot adventures; slug joins to the binder
--   rpg.adventure_characters  — roster join (adventure <-> character)
--
-- Design decisions (stored vs derived):
--   * Views DERIVE everything derivable from 0001's stored scores: ability
--     modifiers, passive perception (expertise-aware), all six save bonuses,
--     per-skill bonuses, spell save DC and spell attack bonus. Nothing
--     derived is ever stored.
--   * Child-table detail (skills, inventory, spells, slot pools) is
--     aggregated into compact jsonb columns; empty aggregates read as [] —
--     never NULL — so the GPT needs no null-handling.
--   * Write functions resolve characters by name, case-insensitively, and
--     raise clear exceptions (not found / ambiguous / insufficient), because
--     the caller is a language model: the error text is the documentation.
--   * Every write verb returns the updated relevant state as compact jsonb,
--     so the caller sees what changed without a follow-up query.
--   * rpg.set_adventure_status is included beyond the core verb set: the
--     status column would otherwise need a raw UPDATE, which is exactly what
--     this surface exists to prevent.
--   * Coins: no auto-conversion between denominations, ever; spend errors on
--     insufficient funds in the exact denomination.
--
-- Security posture (shared project, advisor-clean):
--   * Views: security_invoker = on — the querying role's own rights and RLS
--     apply; no privilege lending.
--   * New tables: RLS ENABLED, NO policies (deny-by-default, as in 0001).
--     Trusted tooling connects as service_role, which bypasses RLS.
--   * Every function: SECURITY INVOKER (default), SET search_path = '' with
--     fully qualified body references (the 0002 convention, applied from
--     birth).
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Enums (fixed value sets)
-- ---------------------------------------------------------------------------

create type rpg.game_system as enum ('dnd5e', 'vtm', 'trudvang');

comment on type rpg.game_system is
  'Binder system tags: dnd5e (active), vtm and trudvang (planned). Matches the system subfolders in the campaign binder.';

create type rpg.adventure_status as enum ('planned', 'running', 'completed');

comment on type rpg.adventure_status is
  'One-shot lifecycle: planned (prepped, not started), running (mid-session), completed (played out).';

create type rpg.rest_kind as enum ('short', 'long');

comment on type rpg.rest_kind is
  '5e rest types, as taken by rpg.take_rest.';

-- ---------------------------------------------------------------------------
-- rpg.adventures — one-shot adventures
-- ---------------------------------------------------------------------------

create table rpg.adventures (
  id          uuid                  primary key default gen_random_uuid(),
  slug        text                  not null unique,
  title       text                  not null,
  system      rpg.game_system       not null default 'dnd5e',
  status      rpg.adventure_status  not null default 'planned',
  notes       text,
  created_at  timestamptz           not null default now(),
  updated_at  timestamptz           not null default now(),
  constraint adventures_slug_kebab_case
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

comment on table rpg.adventures is
  'One-shot adventures: the database half of an adventure whose prose lives in the campaign binder.';

comment on column rpg.adventures.slug is
  'Kebab-case join key to the binder folder adventures/dnd5e/<slug>/ in git — the slug here and the folder name there are the same string.';

create trigger adventures_set_updated_at
  before update on rpg.adventures
  for each row execute function rpg.set_updated_at();

alter table rpg.adventures enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.adventure_characters — the roster join
-- ---------------------------------------------------------------------------

create table rpg.adventure_characters (
  adventure_id  uuid  not null references rpg.adventures (id) on delete cascade,
  character_id  uuid  not null references rpg.characters (id) on delete cascade,
  primary key (adventure_id, character_id)
);

comment on table rpg.adventure_characters is
  'Party roster: which characters play in which adventure; deleting either side removes the roster row.';

-- FK indexes: adventure_id is covered by the primary key (leading column);
-- character_id gets its own.
create index adventure_characters_character_id_idx
  on rpg.adventure_characters (character_id);

alter table rpg.adventure_characters enable row level security;

-- ---------------------------------------------------------------------------
-- Lookup helpers (name/slug resolution with model-readable errors)
-- ---------------------------------------------------------------------------

create function rpg.find_character(p_name text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select c.id into strict v_id
  from rpg.characters c
  where lower(c.name) = lower(p_name);
  return v_id;
exception
  when no_data_found then
    raise exception 'No character named "%". For exact names: select name from rpg.character_sheets;', p_name;
  when too_many_rows then
    raise exception 'Character name "%" matches more than one character; use the exact full name.', p_name;
end;
$$;

comment on function rpg.find_character(text) is
  'Resolves a character name (case-insensitive) to its id; raises a clear error when not found or ambiguous. Internal helper for the write verbs.';

create function rpg.find_adventure(p_slug text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select a.id into strict v_id
  from rpg.adventures a
  where a.slug = lower(p_slug);
  return v_id;
exception
  when no_data_found then
    raise exception 'No adventure with slug "%". For existing slugs: select slug, title from rpg.adventures;', p_slug;
end;
$$;

comment on function rpg.find_adventure(text) is
  'Resolves an adventure slug to its id; raises a clear error when not found. Internal helper for the roster verbs.';

-- ---------------------------------------------------------------------------
-- Rules helpers (pure 5e lookups)
-- ---------------------------------------------------------------------------

create function rpg.ability_score(p_character_id uuid, p_ability rpg.ability)
returns smallint
language sql
stable
set search_path = ''
as $$
  select case p_ability
           when 'strength'     then c.strength
           when 'dexterity'    then c.dexterity
           when 'constitution' then c.constitution
           when 'intelligence' then c.intelligence
           when 'wisdom'       then c.wisdom
           when 'charisma'     then c.charisma
         end
  from rpg.characters c
  where c.id = p_character_id
$$;

comment on function rpg.ability_score(uuid, rpg.ability) is
  'Returns one of a character''s six stored ability scores, selected by ability enum. Internal helper for derived view columns.';

create function rpg.skill_ability(p_skill rpg.skill)
returns rpg.ability
language sql
immutable
set search_path = ''
as $$
  select (case p_skill
            when 'athletics'       then 'strength'
            when 'acrobatics'      then 'dexterity'
            when 'sleight_of_hand' then 'dexterity'
            when 'stealth'         then 'dexterity'
            when 'arcana'          then 'intelligence'
            when 'history'         then 'intelligence'
            when 'investigation'   then 'intelligence'
            when 'nature'          then 'intelligence'
            when 'religion'        then 'intelligence'
            when 'animal_handling' then 'wisdom'
            when 'insight'         then 'wisdom'
            when 'medicine'        then 'wisdom'
            when 'perception'      then 'wisdom'
            when 'survival'        then 'wisdom'
            when 'deception'       then 'charisma'
            when 'intimidation'    then 'charisma'
            when 'performance'     then 'charisma'
            when 'persuasion'      then 'charisma'
          end)::rpg.ability
$$;

comment on function rpg.skill_ability(rpg.skill) is
  '5e RAW mapping from skill to its governing ability (e.g. stealth -> dexterity).';

-- ---------------------------------------------------------------------------
-- State-snapshot helpers (the compact jsonb the write verbs return)
-- ---------------------------------------------------------------------------

create function rpg.hp_state(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
           'name',                 c.name,
           'hp_current',           c.hp_current,
           'hp_max',               c.hp_max,
           'hp_temp',              c.hp_temp,
           'hit_dice_remaining',   c.hit_dice_remaining,
           'hit_dice_total',       c.hit_dice_total,
           'death_save_successes', c.death_save_successes,
           'death_save_failures',  c.death_save_failures)
  from rpg.characters c
  where c.id = p_character_id
$$;

comment on function rpg.hp_state(uuid) is
  'Compact jsonb snapshot of a character''s hit points, hit dice, and death saves; the return shape of the HP-touching verbs.';

create function rpg.slot_state(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
           jsonb_agg(jsonb_build_object(
             'kind',      s.slot_kind,
             'level',     s.slot_level,
             'remaining', s.slots_total - s.slots_expended,
             'total',     s.slots_total)
           order by s.slot_kind, s.slot_level),
           '[]'::jsonb)
  from rpg.character_spell_slots s
  where s.character_id = p_character_id
$$;

comment on function rpg.slot_state(uuid) is
  'Compact jsonb array of a character''s spell-slot pools ({kind, level, remaining, total}); [] when the character has none.';

create function rpg.coin_state(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
           'name', c.name,
           'cp', c.coins_cp, 'sp', c.coins_sp, 'ep', c.coins_ep,
           'gp', c.coins_gp, 'pp', c.coins_pp)
  from rpg.characters c
  where c.id = p_character_id
$$;

comment on function rpg.coin_state(uuid) is
  'Compact jsonb snapshot of a character''s purse in all five 5e denominations.';

create function rpg.inventory_state(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
           jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'item',     i.name,
             'qty',      i.quantity,
             'equipped', i.equipped,
             'attuned',  i.attuned,
             'notes',    i.notes))
           order by lower(i.name)),
           '[]'::jsonb)
  from rpg.character_items i
  where i.character_id = p_character_id
$$;

comment on function rpg.inventory_state(uuid) is
  'Compact jsonb array of a character''s inventory ({item, qty, equipped, attuned, notes?}); [] when empty.';

create function rpg.party_state(p_adventure_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
           'adventure_slug', a.slug,
           'title',          a.title,
           'status',         a.status,
           'party',          coalesce(
             (select jsonb_agg(c.name order by c.name)
              from rpg.adventure_characters ac
              join rpg.characters c on c.id = ac.character_id
              where ac.adventure_id = a.id),
             '[]'::jsonb))
  from rpg.adventures a
  where a.id = p_adventure_id
$$;

comment on function rpg.party_state(uuid) is
  'Compact jsonb snapshot of an adventure and its party roster (character names); the return shape of the roster verbs.';

-- ---------------------------------------------------------------------------
-- READ VIEWS — the GPT's menu
-- ---------------------------------------------------------------------------

create view rpg.character_sheets
with (security_invoker = on) as
select
  c.id,
  c.name,
  c.player_name,
  c.class,
  c.subclass,
  c.level,
  c.species,
  c.background,
  c.alignment,

  -- the six scores and their derived modifiers
  c.strength, c.dexterity, c.constitution, c.intelligence, c.wisdom, c.charisma,
  rpg.ability_modifier(c.strength)     as strength_mod,
  rpg.ability_modifier(c.dexterity)    as dexterity_mod,
  rpg.ability_modifier(c.constitution) as constitution_mod,
  rpg.ability_modifier(c.intelligence) as intelligence_mod,
  rpg.ability_modifier(c.wisdom)       as wisdom_mod,
  rpg.ability_modifier(c.charisma)     as charisma_mod,

  c.proficiency_bonus,

  -- 10 + WIS mod + proficiency if proficient in perception (doubled on expertise)
  10 + rpg.ability_modifier(c.wisdom)
     + coalesce(
         (select c.proficiency_bonus * (case when sk.expertise then 2 else 1 end)
          from rpg.character_skills sk
          where sk.character_id = c.id and sk.skill = 'perception'),
         0)                                          as passive_perception,

  c.save_proficiencies,
  -- all six computed save bonuses, keyed by ability
  (select jsonb_object_agg(
            a.ability,
            rpg.ability_modifier(rpg.ability_score(c.id, a.ability))
            + case when a.ability = any (c.save_proficiencies)
                   then c.proficiency_bonus else 0 end)
   from unnest(enum_range(null::rpg.ability)) as a(ability)) as save_bonuses,

  c.armor_class,
  c.speed,
  c.hp_current, c.hp_max, c.hp_temp,
  c.hit_die, c.hit_dice_remaining, c.hit_dice_total,
  c.death_save_successes, c.death_save_failures,
  c.coins_cp, c.coins_sp, c.coins_ep, c.coins_gp, c.coins_pp,

  c.spellcasting_ability,
  case when c.spellcasting_ability is not null
       then 8 + c.proficiency_bonus
              + rpg.ability_modifier(rpg.ability_score(c.id, c.spellcasting_ability))
  end                                                as spell_save_dc,
  case when c.spellcasting_ability is not null
       then c.proficiency_bonus
              + rpg.ability_modifier(rpg.ability_score(c.id, c.spellcasting_ability))
  end                                                as spell_attack_bonus,

  -- proficient skills only, with the full computed check bonus;
  -- non-proficient checks are just the ability modifier above
  coalesce(
    (select jsonb_agg(jsonb_build_object(
              'skill',     sk.skill,
              'expertise', sk.expertise,
              'bonus',     rpg.ability_modifier(
                             rpg.ability_score(c.id, rpg.skill_ability(sk.skill)))
                           + c.proficiency_bonus
                             * (case when sk.expertise then 2 else 1 end))
            order by sk.skill)
     from rpg.character_skills sk
     where sk.character_id = c.id),
    '[]'::jsonb)                                     as skills,

  rpg.inventory_state(c.id)                          as inventory,

  coalesce(
    (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
              'name',     sp.name,
              'level',    sp.spell_level,
              'prepared', sp.prepared,
              'notes',    sp.notes))
            order by sp.spell_level, lower(sp.name))
     from rpg.character_spells sp
     where sp.character_id = c.id),
    '[]'::jsonb)                                     as spells,

  rpg.slot_state(c.id)                               as spell_slots,

  c.notes,
  c.updated_at
from rpg.characters c;

comment on view rpg.character_sheets is
  'One row per character = the complete sheet: identity, scores with derived modifiers, passive perception, save bonuses, AC/HP/hit dice/death saves, coins, spell DC and attack bonus, plus skills/inventory/spells/slot pools as compact jsonb ([] when empty). The GPT''s primary read.';

create view rpg.adventure_party
with (security_invoker = on) as
select
  a.slug   as adventure_slug,
  a.title  as adventure_title,
  a.status as adventure_status,
  cs.*
from rpg.adventures a
join rpg.adventure_characters ac on ac.adventure_id = a.id
join rpg.character_sheets cs on cs.id = ac.character_id;

comment on view rpg.adventure_party is
  'character_sheets joined through the roster: select * from rpg.adventure_party where adventure_slug = ''<slug>'' is the session-start read.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — hit points and death saves
-- ---------------------------------------------------------------------------

create function rpg.apply_damage(p_name text, p_amount integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  if coalesce(p_amount, -1) < 0 then
    raise exception 'Damage amount must be a non-negative integer (got %).', p_amount;
  end if;
  -- RAW: temp HP depletes first; overflow hits current HP, which floors at 0.
  update rpg.characters
  set hp_temp    = greatest(hp_temp - p_amount, 0),
      hp_current = greatest(hp_current - greatest(p_amount - hp_temp, 0), 0)
  where id = v_id;
  return rpg.hp_state(v_id);
end;
$$;

comment on function rpg.apply_damage(text, integer) is
  'Deals damage: temp HP depletes first (RAW), current HP floors at 0. Dropping to 0 does not auto-record death saves; instant-death from massive damage is a GM ruling. Returns the HP state.';

create function rpg.heal(p_name text, p_amount integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Healing amount must be a positive integer (got %).', p_amount;
  end if;
  -- RAW: healing caps at max; any healing from 0 HP resets death saves.
  update rpg.characters
  set hp_current           = least(hp_current + p_amount, hp_max),
      death_save_successes = case when hp_current = 0 then 0 else death_save_successes end,
      death_save_failures  = case when hp_current = 0 then 0 else death_save_failures  end
  where id = v_id;
  return rpg.hp_state(v_id);
end;
$$;

comment on function rpg.heal(text, integer) is
  'Restores hit points, capped at hp_max; healing a character at 0 HP resets both death-save counters (RAW). Returns the HP state.';

create function rpg.grant_temp_hp(p_name text, p_amount integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Temp HP amount must be a positive integer (got %).', p_amount;
  end if;
  -- RAW: temp HP never stacks — take the higher of old and new.
  update rpg.characters
  set hp_temp = greatest(hp_temp, p_amount)
  where id = v_id;
  return rpg.hp_state(v_id);
end;
$$;

comment on function rpg.grant_temp_hp(text, integer) is
  'Grants temporary hit points, RAW take-the-higher: the new pool replaces the old only if larger; temp HP never stacks. Returns the HP state.';

create function rpg.record_death_save(p_name text, p_success boolean)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id     uuid := rpg.find_character(p_name);
  v_hp     integer;
  v_s      smallint;
  v_f      smallint;
  v_status text;
begin
  if p_success is null then
    raise exception 'record_death_save needs true (success) or false (failure).';
  end if;
  select hp_current, death_save_successes, death_save_failures
    into v_hp, v_s, v_f
  from rpg.characters
  where id = v_id;
  if v_hp > 0 then
    raise exception '"%" has % HP; death saving throws are only rolled at 0 HP.', p_name, v_hp;
  end if;
  if p_success then
    v_s := least(v_s + 1, 3);
  else
    v_f := least(v_f + 1, 3);
  end if;
  if v_s >= 3 then
    -- RAW: third success -> stable; both counters reset.
    v_status := 'stable';
    v_s := 0;
    v_f := 0;
  elsif v_f >= 3 then
    v_status := 'dead';
  else
    v_status := 'dying';
  end if;
  update rpg.characters
  set death_save_successes = v_s,
      death_save_failures  = v_f
  where id = v_id;
  return rpg.hp_state(v_id) || jsonb_build_object('status', v_status);
end;
$$;

comment on function rpg.record_death_save(text, boolean) is
  'Records one death saving throw for a character at 0 HP. Third success -> status ''stable'' and counters reset (RAW); third failure -> status ''dead''. Returns the HP state plus a status field (dying|stable|dead).';

create function rpg.stabilize(p_name text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  -- RAW: a stable creature stays at 0 HP; both death-save counters reset.
  update rpg.characters
  set death_save_successes = 0,
      death_save_failures  = 0
  where id = v_id;
  return rpg.hp_state(v_id) || jsonb_build_object('status', 'stable');
end;
$$;

comment on function rpg.stabilize(text) is
  'Stabilizes a character (e.g. Medicine check or Spare the Dying): resets both death-save counters; HP stays where it is. Returns the HP state.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — spell slots, rests, hit dice
-- ---------------------------------------------------------------------------

create function rpg.spend_slot(
  p_name  text,
  p_level integer,
  p_kind  rpg.slot_kind default 'standard')
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  update rpg.character_spell_slots
  set slots_expended = slots_expended + 1
  where character_id = v_id
    and slot_kind = p_kind
    and slot_level = p_level
    and slots_expended < slots_total;
  if not found then
    raise exception 'No % level-% spell slots remaining for "%". Pools: %', p_kind, p_level, p_name, rpg.slot_state(v_id);
  end if;
  return jsonb_build_object(
    'name', (select c.name from rpg.characters c where c.id = v_id),
    'spell_slots', rpg.slot_state(v_id));
end;
$$;

comment on function rpg.spend_slot(text, integer, rpg.slot_kind) is
  'Expends one spell slot of the given level from the given pool (default ''standard''; ''pact'' for warlock Pact Magic). Errors — listing the pools — when none remain. Returns the slot state.';

create function rpg.take_rest(p_name text, p_kind rpg.rest_kind)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  if p_kind = 'long' then
    -- RAW long rest: HP to max, temp HP ends, death saves cleared,
    -- regain spent hit dice up to half the total (minimum 1).
    update rpg.characters
    set hp_current           = hp_max,
        hp_temp              = 0,
        death_save_successes = 0,
        death_save_failures  = 0,
        hit_dice_remaining   = least(hit_dice_total,
                                     hit_dice_remaining
                                     + greatest(hit_dice_total / 2, 1))
    where id = v_id;
    -- Both standard and pact slot pools reset on a long rest.
    update rpg.character_spell_slots
    set slots_expended = 0
    where character_id = v_id;
  else
    -- RAW short rest: pact slots reset; hit-die spending is a separate,
    -- per-die verb (rpg.spend_hit_die) because each die is rolled.
    update rpg.character_spell_slots
    set slots_expended = 0
    where character_id = v_id
      and slot_kind = 'pact';
  end if;
  return rpg.hp_state(v_id)
         || jsonb_build_object('rest', p_kind, 'spell_slots', rpg.slot_state(v_id));
end;
$$;

comment on function rpg.take_rest(text, rpg.rest_kind) is
  'Applies a rest. Long: HP to max, temp HP ends, death saves cleared, standard + pact slots reset, hit dice regained up to half total (min 1, RAW). Short: pact slots reset only — spend hit dice individually via rpg.spend_hit_die. Returns HP and slot state.';

create function rpg.spend_hit_die(p_name text, p_rolled_amount integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  if coalesce(p_rolled_amount, -1) < 0 then
    raise exception 'Rolled amount must be >= 0: the die roll plus CON modifier, floored at 0 (got %).', p_rolled_amount;
  end if;
  update rpg.characters
  set hit_dice_remaining   = hit_dice_remaining - 1,
      hp_current           = least(hp_max, hp_current + p_rolled_amount),
      death_save_successes = case when hp_current = 0 and p_rolled_amount > 0
                                  then 0 else death_save_successes end,
      death_save_failures  = case when hp_current = 0 and p_rolled_amount > 0
                                  then 0 else death_save_failures end
  where id = v_id
    and hit_dice_remaining > 0;
  if not found then
    raise exception '"%" has no hit dice remaining.', p_name;
  end if;
  return rpg.hp_state(v_id);
end;
$$;

comment on function rpg.spend_hit_die(text, integer) is
  'Spends one hit die: decrements hit_dice_remaining and heals by the rolled amount (die + CON modifier, rolled at the table), capped at hp_max. Errors when no dice remain. Returns the HP state.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — coins and inventory
-- ---------------------------------------------------------------------------

create function rpg.award_coins(
  p_name text,
  p_cp integer default 0,
  p_sp integer default 0,
  p_ep integer default 0,
  p_gp integer default 0,
  p_pp integer default 0)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
  v_cp integer := coalesce(p_cp, 0);
  v_sp integer := coalesce(p_sp, 0);
  v_ep integer := coalesce(p_ep, 0);
  v_gp integer := coalesce(p_gp, 0);
  v_pp integer := coalesce(p_pp, 0);
begin
  if least(v_cp, v_sp, v_ep, v_gp, v_pp) < 0 then
    raise exception 'Coin amounts must be non-negative (got cp=% sp=% ep=% gp=% pp=%).', v_cp, v_sp, v_ep, v_gp, v_pp;
  end if;
  update rpg.characters
  set coins_cp = coins_cp + v_cp,
      coins_sp = coins_sp + v_sp,
      coins_ep = coins_ep + v_ep,
      coins_gp = coins_gp + v_gp,
      coins_pp = coins_pp + v_pp
  where id = v_id;
  return rpg.coin_state(v_id);
end;
$$;

comment on function rpg.award_coins(text, integer, integer, integer, integer, integer) is
  'Adds coins to a character''s purse; all five 5e denominations, no auto-conversion. Returns the purse.';

create function rpg.spend_coins(
  p_name text,
  p_cp integer default 0,
  p_sp integer default 0,
  p_ep integer default 0,
  p_gp integer default 0,
  p_pp integer default 0)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
  v_cp integer := coalesce(p_cp, 0);
  v_sp integer := coalesce(p_sp, 0);
  v_ep integer := coalesce(p_ep, 0);
  v_gp integer := coalesce(p_gp, 0);
  v_pp integer := coalesce(p_pp, 0);
begin
  if least(v_cp, v_sp, v_ep, v_gp, v_pp) < 0 then
    raise exception 'Coin amounts must be non-negative (got cp=% sp=% ep=% gp=% pp=%).', v_cp, v_sp, v_ep, v_gp, v_pp;
  end if;
  update rpg.characters
  set coins_cp = coins_cp - v_cp,
      coins_sp = coins_sp - v_sp,
      coins_ep = coins_ep - v_ep,
      coins_gp = coins_gp - v_gp,
      coins_pp = coins_pp - v_pp
  where id = v_id
    and coins_cp >= v_cp
    and coins_sp >= v_sp
    and coins_ep >= v_ep
    and coins_gp >= v_gp
    and coins_pp >= v_pp;
  if not found then
    raise exception 'Insufficient funds: tried to spend cp=% sp=% ep=% gp=% pp=%, purse is %. There is no auto-conversion between denominations — exchange coins explicitly (spend then award).', v_cp, v_sp, v_ep, v_gp, v_pp, rpg.coin_state(v_id);
  end if;
  return rpg.coin_state(v_id);
end;
$$;

comment on function rpg.spend_coins(text, integer, integer, integer, integer, integer) is
  'Removes coins from a character''s purse, denomination by denomination with no auto-conversion; errors — showing the purse — when any denomination is short. Returns the purse.';

create function rpg.add_item(
  p_name     text,
  p_item     text,
  p_qty      integer default 1,
  p_equipped boolean default false,
  p_attuned  boolean default false,
  p_notes    text    default null)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_character(p_name);
begin
  if coalesce(p_qty, 0) <= 0 then
    raise exception 'Quantity must be a positive integer (got %).', p_qty;
  end if;
  if p_item is null or btrim(p_item) = '' then
    raise exception 'Item name must not be empty.';
  end if;
  -- Quantity-aware: an existing stack (case-insensitive name match) grows;
  -- otherwise a new row is created.
  update rpg.character_items
  set quantity = quantity + p_qty
  where id = (select i.id
              from rpg.character_items i
              where i.character_id = v_id
                and lower(i.name) = lower(p_item)
              order by i.created_at
              limit 1);
  if not found then
    insert into rpg.character_items
      (character_id, name, quantity, equipped, attuned, notes)
    values
      (v_id, btrim(p_item), p_qty,
       coalesce(p_equipped, false), coalesce(p_attuned, false), p_notes);
  end if;
  return jsonb_build_object(
    'name', (select c.name from rpg.characters c where c.id = v_id),
    'inventory', rpg.inventory_state(v_id));
end;
$$;

comment on function rpg.add_item(text, text, integer, boolean, boolean, text) is
  'Adds an item to a character''s inventory, quantity-aware: an existing stack of the same name grows, otherwise a new row is created (equipped/attuned/notes apply to new rows only). Returns the inventory.';

create function rpg.remove_item(
  p_name text,
  p_item text,
  p_qty  integer default null)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id      uuid := rpg.find_character(p_name);
  v_item_id uuid;
  v_have    integer;
begin
  select i.id, i.quantity
    into v_item_id, v_have
  from rpg.character_items i
  where i.character_id = v_id
    and lower(i.name) = lower(p_item)
  order by i.created_at
  limit 1;
  if v_item_id is null then
    raise exception '"%" carries no item named "%". Inventory: %', p_name, p_item, rpg.inventory_state(v_id);
  end if;
  if p_qty is null then
    -- No quantity given: remove the whole stack.
    delete from rpg.character_items where id = v_item_id;
  elsif p_qty <= 0 then
    raise exception 'Quantity must be a positive integer (got %); omit it to remove the whole stack.', p_qty;
  elsif p_qty > v_have then
    raise exception '"%" has only % x "%"; cannot remove %.', p_name, v_have, p_item, p_qty;
  elsif p_qty = v_have then
    delete from rpg.character_items where id = v_item_id;
  else
    update rpg.character_items
    set quantity = quantity - p_qty
    where id = v_item_id;
  end if;
  return jsonb_build_object(
    'name', (select c.name from rpg.characters c where c.id = v_id),
    'inventory', rpg.inventory_state(v_id));
end;
$$;

comment on function rpg.remove_item(text, text, integer) is
  'Removes an item from a character''s inventory, quantity-aware: decrements the stack, deletes the row at 0; omit the quantity to drop the whole stack; errors when removing more than held. Returns the inventory.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — adventures and roster
-- ---------------------------------------------------------------------------

create function rpg.create_adventure(
  p_slug   text,
  p_title  text,
  p_system rpg.game_system default 'dnd5e',
  p_notes  text default null)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'Slug "%" must be kebab-case (lowercase letters, digits, single hyphens) — it names the binder folder adventures/dnd5e/<slug>/.', p_slug;
  end if;
  if p_title is null or btrim(p_title) = '' then
    raise exception 'Title must not be empty.';
  end if;
  insert into rpg.adventures (slug, title, system, notes)
  values (p_slug, btrim(p_title), p_system, p_notes)
  returning id into v_id;
  return rpg.party_state(v_id);
exception
  when unique_violation then
    raise exception 'An adventure with slug "%" already exists.', p_slug;
end;
$$;

comment on function rpg.create_adventure(text, text, rpg.game_system, text) is
  'Creates an adventure (status ''planned''); the slug must be kebab-case and match the binder folder adventures/dnd5e/<slug>/. Returns the adventure with its (empty) party.';

create function rpg.set_adventure_status(p_slug text, p_status rpg.adventure_status)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_adventure(p_slug);
begin
  update rpg.adventures
  set status = p_status
  where id = v_id;
  return rpg.party_state(v_id);
end;
$$;

comment on function rpg.set_adventure_status(text, rpg.adventure_status) is
  'Moves an adventure through its lifecycle: planned -> running -> completed. Returns the adventure with its party.';

create function rpg.add_to_party(p_adventure_slug text, p_character_name text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_aid uuid := rpg.find_adventure(p_adventure_slug);
  v_cid uuid := rpg.find_character(p_character_name);
begin
  insert into rpg.adventure_characters (adventure_id, character_id)
  values (v_aid, v_cid)
  on conflict do nothing;  -- already in the party: harmless, roster returned
  return rpg.party_state(v_aid);
end;
$$;

comment on function rpg.add_to_party(text, text) is
  'Adds a character to an adventure''s party roster (idempotent: re-adding is a no-op). Returns the adventure with its party.';

create function rpg.remove_from_party(p_adventure_slug text, p_character_name text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_aid uuid := rpg.find_adventure(p_adventure_slug);
  v_cid uuid := rpg.find_character(p_character_name);
begin
  delete from rpg.adventure_characters
  where adventure_id = v_aid
    and character_id = v_cid;
  if not found then
    raise exception '"%" is not in the party for "%". Roster: %', p_character_name, p_adventure_slug, rpg.party_state(v_aid);
  end if;
  return rpg.party_state(v_aid);
end;
$$;

comment on function rpg.remove_from_party(text, text) is
  'Removes a character from an adventure''s party roster; errors — showing the roster — when the character was not in it. Returns the adventure with its party.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — character registration (one call, five tables)
-- ---------------------------------------------------------------------------

create function rpg.create_character(p jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id       uuid;
  v_missing  text;
  v_level    smallint;
  v_hp_max   integer;
  v_hd_total smallint;
begin
  select string_agg(t.k, ', ') into v_missing
  from unnest(array[
    'name', 'class', 'species',
    'strength', 'dexterity', 'constitution', 'intelligence', 'wisdom', 'charisma',
    'armor_class', 'hp_max', 'hit_die']) as t(k)
  where p ->> t.k is null;
  if v_missing is not null then
    raise exception 'create_character payload is missing required keys: %.', v_missing;
  end if;

  -- Write verbs resolve characters by name, so names must stay unique.
  if exists (select 1 from rpg.characters c
             where lower(c.name) = lower(p ->> 'name')) then
    raise exception 'A character named "%" already exists; character names must be unique (the write verbs resolve by name).', p ->> 'name';
  end if;

  v_level    := coalesce((p ->> 'level')::smallint, 1);
  v_hp_max   := (p ->> 'hp_max')::integer;
  v_hd_total := coalesce((p ->> 'hit_dice_total')::smallint, v_level);

  insert into rpg.characters (
    name, player_name, class, subclass, level, species, background, alignment,
    strength, dexterity, constitution, intelligence, wisdom, charisma,
    armor_class, speed,
    hp_max, hp_current, hp_temp,
    hit_die, hit_dice_total, hit_dice_remaining,
    save_proficiencies, spellcasting_ability,
    coins_cp, coins_sp, coins_ep, coins_gp, coins_pp,
    notes)
  values (
    p ->> 'name',
    p ->> 'player_name',
    p ->> 'class',
    p ->> 'subclass',
    v_level,
    p ->> 'species',
    p ->> 'background',
    (p ->> 'alignment')::rpg.alignment,
    (p ->> 'strength')::smallint,
    (p ->> 'dexterity')::smallint,
    (p ->> 'constitution')::smallint,
    (p ->> 'intelligence')::smallint,
    (p ->> 'wisdom')::smallint,
    (p ->> 'charisma')::smallint,
    (p ->> 'armor_class')::smallint,
    coalesce((p ->> 'speed')::smallint, 30),
    v_hp_max,
    coalesce((p ->> 'hp_current')::integer, v_hp_max),
    coalesce((p ->> 'hp_temp')::integer, 0),
    (p ->> 'hit_die')::rpg.hit_die,
    v_hd_total,
    coalesce((p ->> 'hit_dice_remaining')::smallint, v_hd_total),
    coalesce(
      (select array_agg(s.x::rpg.ability)
       from jsonb_array_elements_text(
              coalesce(p -> 'save_proficiencies', '[]'::jsonb)) as s(x)),
      '{}'),
    (p ->> 'spellcasting_ability')::rpg.ability,
    coalesce((p -> 'coins' ->> 'cp')::integer, 0),
    coalesce((p -> 'coins' ->> 'sp')::integer, 0),
    coalesce((p -> 'coins' ->> 'ep')::integer, 0),
    coalesce((p -> 'coins' ->> 'gp')::integer, 0),
    coalesce((p -> 'coins' ->> 'pp')::integer, 0),
    p ->> 'notes')
  returning id into v_id;

  -- skills: ["stealth", {"skill": "perception", "expertise": true}, ...]
  insert into rpg.character_skills (character_id, skill, expertise)
  select v_id,
         (case when jsonb_typeof(t.e) = 'string'
               then t.e #>> '{}'
               else t.e ->> 'skill' end)::rpg.skill,
         coalesce((t.e ->> 'expertise')::boolean, false)
  from jsonb_array_elements(coalesce(p -> 'skills', '[]'::jsonb)) as t(e);

  -- spell_slots: [{"level": 1, "total": 4}, {"kind": "pact", "level": 2, "total": 2}]
  insert into rpg.character_spell_slots
    (character_id, slot_kind, slot_level, slots_total, slots_expended)
  select v_id,
         coalesce((t.e ->> 'kind')::rpg.slot_kind, 'standard'),
         (t.e ->> 'level')::smallint,
         (t.e ->> 'total')::smallint,
         coalesce((t.e ->> 'expended')::smallint, 0)
  from jsonb_array_elements(coalesce(p -> 'spell_slots', '[]'::jsonb)) as t(e);

  -- spells: [{"name": "Cure Wounds", "level": 1, "prepared": true, "notes": "..."}]
  insert into rpg.character_spells
    (character_id, name, spell_level, prepared, notes)
  select v_id,
         t.e ->> 'name',
         (t.e ->> 'level')::smallint,
         coalesce((t.e ->> 'prepared')::boolean, true),
         t.e ->> 'notes'
  from jsonb_array_elements(coalesce(p -> 'spells', '[]'::jsonb)) as t(e);

  -- items: ["Rope (50 ft)", {"name": "Shortsword", "qty": 1, "equipped": true}]
  insert into rpg.character_items
    (character_id, name, quantity, equipped, attuned, notes)
  select v_id,
         case when jsonb_typeof(t.e) = 'string'
              then t.e #>> '{}'
              else t.e ->> 'name' end,
         coalesce((t.e ->> 'qty')::integer, 1),
         coalesce((t.e ->> 'equipped')::boolean, false),
         coalesce((t.e ->> 'attuned')::boolean, false),
         t.e ->> 'notes'
  from jsonb_array_elements(coalesce(p -> 'items', '[]'::jsonb)) as t(e);

  -- Hand back the finished sheet, derived numbers included.
  return (select to_jsonb(cs) from rpg.character_sheets cs where cs.id = v_id);
end;
$$;

comment on function rpg.create_character(jsonb) is
  'Registers a complete new character across all five character tables from one jsonb payload. Required keys: name, class, species, the six ability scores, armor_class, hp_max, hit_die (d6|d8|d10|d12). Optional: player_name, subclass, level (default 1), background, alignment, speed (default 30), hp_current (default hp_max), hp_temp, hit_dice_total/remaining (default level), save_proficiencies (ability names), spellcasting_ability, coins {cp,sp,ep,gp,pp}, skills (skill name or {skill, expertise}), spell_slots ({kind?, level, total}), spells ({name, level, prepared?, notes?}), items (name or {name, qty?, equipped?, attuned?, notes?}), notes. Returns the finished character sheet.';

commit;
