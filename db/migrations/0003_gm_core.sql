-- ============================================================================
-- 0003_gm_core.sql
--
-- The GM FAMILY for D&D 5e one-shots — what the game master needs live at
-- the table, in schema rpg (the Rollspel fence; nothing of ours lives
-- outside it):
--
--   rpg.adventures   — one row per one-shot; slug ties it to the binder
--                      folder adventures/<slug>/ in the git repo
--   rpg.areas        — the locations/scenes of an adventure
--   rpg.npcs         — every creature the GM runs, social or hostile
--   rpg.story_beats  — hooks, events, secrets, twists, revelations —
--                      with live hidden/revealed/resolved tracking
--
-- Creation order matters: npcs references areas, and story_beats references
-- both — so adventures, then areas, then npcs, then story_beats.
--
-- Design decisions:
--   * DB vs binder split — the database holds the shapes needed mid-session
--     (state, dispositions, what has been revealed); full prose lives in the
--     campaign binder (the git repo). premise/description/body are short
--     summaries, not the adventure text.
--   * player-facing vs GM-only — every narrative table splits description
--     (safe to read aloud) from gm_notes (secrets, motivations, traps —
--     never read aloud). The GPT at the table needs that line drawn in the
--     schema, not in its judgment.
--   * NPC combat stats — armor_class / hp_max / hp_current / speed only,
--     ALL nullable, because social NPCs need none. Modifiers and full stat
--     blocks are deliberately NOT modeled: srd_reference names the SRD stat
--     block to run the NPC as ('bandit captain'), and the real block stays
--     in the SRD/binder — the honest-content rule made schema.
--   * npcs.adventure_id is NULLABLE — null means a recurring NPC not bound
--     to any one adventure; bound NPCs cascade away with their adventure.
--   * story_beats.status is THE point of the table: 'hidden' (players do
--     not know) → 'revealed' (now they do) → 'resolved' (played out).
--     Everything else about a beat could live in markdown; this cannot.
--   * sort_order is nullable smallint on areas and story_beats — the GM's
--     intended sequence, absent when the adventure is not linear.
--
-- RLS: ENABLED on every table, with NO policies — same rationale as 0001:
-- shared Supabase project, deny-by-default; trusted tooling connects as
-- service_role, which bypasses RLS.
--
-- Reuses rpg.set_updated_at() from 0001 (hardened with search_path = '' in
-- 0002); no new functions here.
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Enums (fixed value sets, living in schema rpg)
-- ---------------------------------------------------------------------------

-- Adventure lifecycle: authoring → playable → at the table → done.
create type rpg.adventure_status as enum (
  'draft', 'ready', 'running', 'completed'
);

-- How an NPC receives the party; a live dial the GM turns, not a stat.
create type rpg.disposition as enum (
  'friendly', 'neutral', 'wary', 'hostile'
);

-- Whether an NPC is still in play; 'unknown' is for when the players ask
-- and the GM honestly is not sure either.
create type rpg.npc_status as enum (
  'alive', 'dead', 'missing', 'unknown'
);

-- What kind of story part a beat is.
create type rpg.beat_kind as enum (
  'hook', 'scene', 'event', 'secret', 'twist', 'revelation'
);

-- Beat lifecycle: hidden (players do not know) → revealed (now they do)
-- → resolved (played out). Forward-moving in play, but not constrained —
-- a GM may legitimately re-hide a beat the players forgot.
create type rpg.beat_status as enum (
  'hidden', 'revealed', 'resolved'
);

-- ---------------------------------------------------------------------------
-- rpg.adventures — one row per one-shot
-- ---------------------------------------------------------------------------

create table rpg.adventures (
  id          uuid                  primary key default gen_random_uuid(),

  -- kebab-case key tying the row to the binder folder adventures/<slug>/
  slug        text                  not null unique
                                    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title       text                  not null,

  -- one-paragraph hook summary; the full prose lives in the binder
  premise     text,

  status      rpg.adventure_status  not null default 'draft',

  -- GM-only; never read aloud
  gm_notes    text,

  created_at  timestamptz           not null default now(),
  updated_at  timestamptz           not null default now()
);

comment on table rpg.adventures is
  'One row per D&D 5e one-shot; slug ties the row to the binder folder adventures/<slug>/ in the git repo, where the full prose lives — premise here is only the hook summary.';

comment on column rpg.adventures.premise is
  'One-paragraph player-facing hook summary; full adventure text lives in the campaign binder.';

comment on column rpg.adventures.gm_notes is
  'GM-only notes — never read aloud to players.';

create trigger adventures_set_updated_at
  before update on rpg.adventures
  for each row execute function rpg.set_updated_at();

alter table rpg.adventures enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.areas — locations/scenes of an adventure
-- ---------------------------------------------------------------------------

create table rpg.areas (
  id            uuid         primary key default gen_random_uuid(),
  adventure_id  uuid         not null references rpg.adventures (id) on delete cascade,
  name          text         not null,

  -- player-facing; safe to read aloud
  description   text,

  -- GM-only: traps, hidden doors, what the room is really for
  gm_notes      text,

  -- live state: has the party been here yet?
  visited       boolean      not null default false,

  -- the GM's intended sequence; null when the adventure is not linear
  sort_order    smallint,

  created_at    timestamptz  not null default now(),
  updated_at    timestamptz  not null default now()
);

comment on table rpg.areas is
  'Locations/scenes of an adventure, with live visited state; description is player-facing and safe to read aloud, gm_notes holds the traps, hidden doors, and what the room is really for.';

comment on column rpg.areas.description is
  'Player-facing — safe to read aloud.';

comment on column rpg.areas.gm_notes is
  'GM-only: traps, hidden doors, the room''s real purpose — never read aloud.';

create index areas_adventure_id_idx
  on rpg.areas (adventure_id);

create unique index areas_adventure_id_name_key
  on rpg.areas (adventure_id, lower(name));

create trigger areas_set_updated_at
  before update on rpg.areas
  for each row execute function rpg.set_updated_at();

alter table rpg.areas enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.npcs — every creature the GM runs, social or hostile
-- ---------------------------------------------------------------------------

create table rpg.npcs (
  id             uuid             primary key default gen_random_uuid(),

  -- null = recurring NPC not bound to any one adventure
  adventure_id   uuid             references rpg.adventures (id) on delete cascade,

  -- where they are usually found; survives the area being dropped
  area_id        uuid             references rpg.areas (id) on delete set null,

  name           text             not null,
  role           text,
  disposition    rpg.disposition  not null default 'neutral',

  -- player-facing; safe to read aloud
  description    text,

  -- GM-only: secrets, motivations, voice — never read aloud
  gm_notes       text,

  status         rpg.npc_status   not null default 'alive',

  -- lightweight combat stats, ALL nullable — social NPCs need none;
  -- modifiers and full stat blocks are deliberately not modeled (see header)
  armor_class    smallint         check (armor_class between 1 and 30),
  hp_max         integer          check (hp_max > 0),
  hp_current     integer          check (hp_current >= 0),
  speed          smallint         check (speed >= 0),
  -- null-tolerant by design: a NULL on either side makes the comparison
  -- unknown, and CHECK passes on unknown
  constraint npcs_hp_current_within_max
    check (hp_current <= hp_max),

  -- name of the SRD stat block to run them as (e.g. 'bandit captain');
  -- the block's prose stays in the SRD/binder — honest-content rule
  srd_reference  text,

  created_at     timestamptz      not null default now(),
  updated_at     timestamptz      not null default now()
);

comment on table rpg.npcs is
  'Every creature the GM runs, social or hostile: description is player-facing and safe to read aloud, gm_notes holds secrets/motivations/voice; combat stats are nullable and minimal — srd_reference names the SRD stat block that carries the rest.';

comment on column rpg.npcs.adventure_id is
  'Null = recurring NPC not bound to one adventure; set = cascades away with the adventure.';

comment on column rpg.npcs.description is
  'Player-facing — safe to read aloud.';

comment on column rpg.npcs.gm_notes is
  'GM-only: secrets, motivations, voice — never read aloud.';

comment on column rpg.npcs.srd_reference is
  'Name of the SRD stat block to run this NPC as (e.g. ''bandit captain''); the actual block lives in the SRD/binder, never invented here.';

create index npcs_adventure_id_idx
  on rpg.npcs (adventure_id);

create index npcs_area_id_idx
  on rpg.npcs (area_id);

create trigger npcs_set_updated_at
  before update on rpg.npcs
  for each row execute function rpg.set_updated_at();

alter table rpg.npcs enable row level security;

-- ---------------------------------------------------------------------------
-- rpg.story_beats — hooks, events, secrets, twists, revelations
-- ---------------------------------------------------------------------------

create table rpg.story_beats (
  id            uuid             primary key default gen_random_uuid(),
  adventure_id  uuid             not null references rpg.adventures (id) on delete cascade,
  title         text             not null,
  kind          rpg.beat_kind    not null,

  -- what actually happens / what the secret is (GM-facing until revealed)
  body          text,

  -- THE point of this table: live tracking of what the players know
  status        rpg.beat_status  not null default 'hidden',

  -- where the beat is anchored; survives the anchor being dropped
  area_id       uuid             references rpg.areas (id) on delete set null,

  -- who the beat hangs on; survives the NPC being dropped
  npc_id        uuid             references rpg.npcs (id) on delete set null,

  -- the GM's intended sequence; null when the adventure is not linear
  sort_order    smallint,

  created_at    timestamptz      not null default now(),
  updated_at    timestamptz      not null default now()
);

comment on table rpg.story_beats is
  'Story parts of an adventure — hooks, scenes, events, secrets, twists, revelations — whose status is tracked live: hidden (players do not know) → revealed (now they do) → resolved (played out).';

comment on column rpg.story_beats.status is
  'Beat lifecycle, updated live at the table: ''hidden'' → ''revealed'' → ''resolved''. This column is why beats live in the database instead of the binder.';

comment on column rpg.story_beats.body is
  'What actually happens / what the secret is; GM-facing while status = ''hidden''.';

create index story_beats_adventure_id_idx
  on rpg.story_beats (adventure_id);

create index story_beats_area_id_idx
  on rpg.story_beats (area_id);

create index story_beats_npc_id_idx
  on rpg.story_beats (npc_id);

create trigger story_beats_set_updated_at
  before update on rpg.story_beats
  for each row execute function rpg.set_updated_at();

alter table rpg.story_beats enable row level security;

commit;
