-- ============================================================================
-- 0006_gm_prep_tables.sql
--
-- THE GM'S PREP LAYER for D&D 5e one-shots — what the game master preps
-- before the session and mutates live at the table, in schema rpg (the
-- Rollspel fence; nothing of ours lives outside it):
--
--   rpg.areas        — the locations/scenes of an adventure, with visited state
--   rpg.npcs         — every creature the GM runs, social or hostile
--   rpg.plot_points  — hooks, scenes, events, secrets, twists, revelations —
--                      with live hidden/revealed/resolved tracking
--
-- Creation order matters: npcs references areas, and plot_points references
-- both — so areas, then npcs, then plot_points. All three hang off the live
-- rpg.adventures (0003).
--
-- NAMING NOTE — why this family is called plot_points, not story_beats:
-- the natural names are taken. rpg.story_beats and rpg.beat_kind belong to
-- the PUBLIC live-narration stream (0005: narration|dialogue|roll|mechanics|
-- system, rendered on every player's browser), and rpg.event_kind classifies
-- the GM's private session log (rpg.session_events / rpg.log_event). The
-- prep-tracking concept here — story parts with a knowledge lifecycle — is a
-- third thing, so it gets a third, unconfusable family: plot_points with
-- rpg.plot_point_kind and rpg.plot_point_status.
--
-- THE THREE-WAY SPLIT (do not blur it):
--   rpg.plot_points     — GM-PRIVATE PREP STATE: written before the session,
--                         MUTATED during it (status flips, notes grow). Has a
--                         lifecycle; not a log.
--   rpg.session_events  — GM-PRIVATE APPEND-ONLY LOG: what happened, as it
--                         happened — rulings, threads, secrets-in-motion.
--   rpg.story_beats     — PLAYER-PUBLIC APPEND-ONLY STREAM: the story as the
--                         players hear it, live on their screens.
-- Nothing in this file is player-visible: even the player-facing description
-- columns reach players through the GM's voice (rpg.narrate), never through
-- the API. Revealing a plot point here flips prep state only — it does not
-- tell the players anything; narrate does that.
--
-- Design decisions:
--   * DB vs binder split — the database holds the shapes needed mid-session
--     (state, dispositions, what has been revealed); full prose lives in the
--     campaign binder (the git repo). description/body are short summaries,
--     not the adventure text.
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
--   * plot_points.status is THE point of the table: 'hidden' (players do
--     not know) → 'revealed' (now they do) → 'resolved' (played out).
--     Everything else about a plot point could live in markdown; this cannot.
--     Forward-moving in play, but not constrained — a GM may legitimately
--     re-hide a point the players forgot (raw UPDATE; no verb needed).
--   * sort_order is nullable smallint on areas and plot_points — the GM's
--     intended sequence, absent when the adventure is not linear.
--   * NO owner_id / per-user layer anywhere — the per-user experiment was
--     applied and rolled back (ledger: 0003_owner_and_rls then
--     0004_drop_per_user_layer) and is not reintroduced here.
--   * VERBS, minimal by design: the status flip is the one hot, repeated
--     live write in this family, so it gets reveal_plot_point /
--     resolve_plot_point (slug + title resolution, model-readable errors,
--     compact jsonb returns — the 0003/0005 style, reusing
--     rpg.find_adventure). Everything else on these tables is ordinary
--     prep-time SQL the table-side GPT already speaks; no further surface.
--
-- ACCESS POSTURE — GM-PRIVATE, mirroring the live rpg.session_events
-- precedent exactly: RLS ENABLED with ZERO policies (deny-by-default for the
-- API client roles), plus REVOKE ALL from anon on each table — the schema's
-- default privileges (0004) auto-grant full CRUD to anon and authenticated
-- on every new table, so the anon grant is explicitly taken back;
-- authenticated's grants are left in place but are dead under policy-less
-- RLS, exactly as on session_events. service_role bypasses RLS (BYPASSRLS)
-- and is how the GM's trusted tooling reads and writes this layer.
-- No policy block is ever added to these tables without a new migration
-- that says so in as many words.
--
-- Reuses rpg.set_updated_at (0001, hardened 0002) for the update triggers
-- and rpg.find_adventure (0003) for slug resolution; re-creates neither.
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Enums (fixed value sets, living in schema rpg)
-- ---------------------------------------------------------------------------

create type rpg.disposition as enum (
  'friendly', 'neutral', 'wary', 'hostile'
);

comment on type rpg.disposition is
  'How an NPC receives the party; a live dial the GM turns, not a stat.';

create type rpg.npc_status as enum (
  'alive', 'dead', 'missing', 'unknown'
);

comment on type rpg.npc_status is
  'Whether an NPC is still in play; ''unknown'' is for when the players ask and the GM honestly is not sure either.';

create type rpg.plot_point_kind as enum (
  'hook', 'scene', 'event', 'secret', 'twist', 'revelation'
);

comment on type rpg.plot_point_kind is
  'What kind of story part a plot point is. Prep vocabulary for the GM''s private tracking — distinct from rpg.beat_kind (the public stream''s rendering vocabulary) and rpg.event_kind (the GM log''s classification).';

create type rpg.plot_point_status as enum (
  'hidden', 'revealed', 'resolved'
);

comment on type rpg.plot_point_status is
  'Plot-point lifecycle: hidden (players do not know) → revealed (now they do) → resolved (played out). Forward-moving in play, but not constrained — a GM may legitimately re-hide a point the players forgot.';

-- ---------------------------------------------------------------------------
-- rpg.areas — locations/scenes of an adventure
-- ---------------------------------------------------------------------------

create table rpg.areas (
  id            uuid         primary key default gen_random_uuid(),
  adventure_id  uuid         not null references rpg.adventures (id) on delete cascade,
  name          text         not null,

  -- player-facing; safe to read aloud (through the GM's voice — this table
  -- itself is API-invisible)
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
  'GM-private: locations/scenes of an adventure, with live visited state; description is player-facing prose (read aloud by the GM — never served by the API), gm_notes holds the traps, hidden doors, and what the room is really for.';

comment on column rpg.areas.description is
  'Player-facing — safe to read aloud.';

comment on column rpg.areas.gm_notes is
  'GM-only: traps, hidden doors, the room''s real purpose — never read aloud.';

comment on column rpg.areas.sort_order is
  'The GM''s intended sequence; null when the adventure is not linear.';

create index areas_adventure_id_idx
  on rpg.areas (adventure_id);

create unique index areas_adventure_id_name_key
  on rpg.areas (adventure_id, lower(name));

create trigger areas_set_updated_at
  before update on rpg.areas
  for each row execute function rpg.set_updated_at();

-- GM-private posture (see header): RLS on, no policies, anon revoked.
alter table rpg.areas enable row level security;
revoke all on rpg.areas from anon;

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
  armor_class    smallint         constraint npcs_armor_class_range
                                    check (armor_class between 1 and 30),
  hp_max         integer          constraint npcs_hp_max_positive
                                    check (hp_max > 0),
  hp_current     integer          constraint npcs_hp_current_nonnegative
                                    check (hp_current >= 0),
  speed          smallint         constraint npcs_speed_nonnegative
                                    check (speed >= 0),
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
  'GM-private: every creature the GM runs, social or hostile — description is player-facing prose (read aloud by the GM), gm_notes holds secrets/motivations/voice; combat stats are nullable and minimal, and srd_reference names the SRD stat block that carries the rest.';

comment on column rpg.npcs.adventure_id is
  'Null = recurring NPC not bound to one adventure; set = cascades away with the adventure.';

comment on column rpg.npcs.area_id is
  'Where they are usually found; set null when the area is dropped.';

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

-- GM-private posture (see header): RLS on, no policies, anon revoked.
alter table rpg.npcs enable row level security;
revoke all on rpg.npcs from anon;

-- ---------------------------------------------------------------------------
-- rpg.plot_points — hooks, scenes, events, secrets, twists, revelations
-- ---------------------------------------------------------------------------

create table rpg.plot_points (
  id            uuid                   primary key default gen_random_uuid(),
  adventure_id  uuid                   not null references rpg.adventures (id) on delete cascade,
  title         text                   not null,
  kind          rpg.plot_point_kind    not null,

  -- what actually happens / what the secret is (GM-facing until revealed)
  body          text,

  -- THE point of this table: live tracking of what the players know
  status        rpg.plot_point_status  not null default 'hidden',

  -- where the plot point is anchored; survives the anchor being dropped
  area_id       uuid                   references rpg.areas (id) on delete set null,

  -- who the plot point hangs on; survives the NPC being dropped
  npc_id        uuid                   references rpg.npcs (id) on delete set null,

  -- the GM's intended sequence; null when the adventure is not linear
  sort_order    smallint,

  created_at    timestamptz            not null default now(),
  updated_at    timestamptz            not null default now()
);

comment on table rpg.plot_points is
  'GM-private: story parts of an adventure — hooks, scenes, events, secrets, twists, revelations — whose status is tracked live: hidden (players do not know) → revealed (now they do) → resolved (played out). NOT the public stream (rpg.story_beats) and NOT the GM log (rpg.session_events): this is prep state with a lifecycle. Revealing a row here flips bookkeeping only — telling the players goes through rpg.narrate.';

comment on column rpg.plot_points.status is
  'Plot-point lifecycle, updated live at the table: ''hidden'' → ''revealed'' → ''resolved''. This column is why plot points live in the database instead of the binder.';

comment on column rpg.plot_points.body is
  'What actually happens / what the secret is; GM-facing while status = ''hidden''.';

comment on column rpg.plot_points.sort_order is
  'The GM''s intended sequence; null when the adventure is not linear.';

create index plot_points_adventure_id_idx
  on rpg.plot_points (adventure_id);

create index plot_points_area_id_idx
  on rpg.plot_points (area_id);

create index plot_points_npc_id_idx
  on rpg.plot_points (npc_id);

create trigger plot_points_set_updated_at
  before update on rpg.plot_points
  for each row execute function rpg.set_updated_at();

-- GM-private posture (see header): RLS on, no policies, anon revoked.
alter table rpg.plot_points enable row level security;
revoke all on rpg.plot_points from anon;

-- ---------------------------------------------------------------------------
-- Lookup helper — plot-point resolution with model-readable errors
-- (the 0003 find_character/find_adventure pattern)
-- ---------------------------------------------------------------------------

create function rpg.find_plot_point(p_adventure_slug text, p_title text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_aid uuid := rpg.find_adventure(p_adventure_slug);
  v_id  uuid;
begin
  select pp.id into strict v_id
  from rpg.plot_points pp
  where pp.adventure_id = v_aid
    and lower(pp.title) = lower(p_title);
  return v_id;
exception
  when no_data_found then
    raise exception 'No plot point titled "%" in adventure "%". For its plot points: select title, kind, status from rpg.plot_points where adventure_id = rpg.find_adventure(''%'');', p_title, p_adventure_slug, p_adventure_slug;
  when too_many_rows then
    raise exception 'Plot point title "%" matches more than one row in adventure "%"; retitle one of them, or update by id.', p_title, p_adventure_slug;
end;
$$;

comment on function rpg.find_plot_point(text, text) is
  'Resolves an adventure slug + plot-point title (case-insensitive) to the plot point''s id; raises a clear error when not found or ambiguous. Internal helper for the plot-point verbs.';

-- ---------------------------------------------------------------------------
-- State-snapshot helper — the compact jsonb the plot-point verbs return
-- ---------------------------------------------------------------------------

create function rpg.plot_point_state(p_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
           'adventure_slug', a.slug,
           'title',          pp.title,
           'kind',           pp.kind,
           'status',         pp.status,
           'body',           pp.body,
           'area',           ar.name,
           'npc',            n.name))
  from rpg.plot_points pp
  join rpg.adventures a on a.id = pp.adventure_id
  left join rpg.areas ar on ar.id = pp.area_id
  left join rpg.npcs  n  on n.id  = pp.npc_id
  where pp.id = p_id
$$;

comment on function rpg.plot_point_state(uuid) is
  'Compact jsonb snapshot of one plot point ({adventure_slug, title, kind, status, body?, area?, npc?}); the return shape of the plot-point verbs.';

-- ---------------------------------------------------------------------------
-- WRITE VERBS — the status flip, the one hot live write in this family.
-- Re-hiding a forgotten point is a plain UPDATE; it earns no verb.
-- ---------------------------------------------------------------------------

create function rpg.reveal_plot_point(p_adventure_slug text, p_title text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_plot_point(p_adventure_slug, p_title);
begin
  update rpg.plot_points
  set status = 'revealed'
  where id = v_id;
  return rpg.plot_point_state(v_id);
end;
$$;

comment on function rpg.reveal_plot_point(text, text) is
  'Marks a plot point ''revealed'' — the players now know. Bookkeeping only: this flips GM-private prep state and returns the plot point (body included, now safe to weave in); actually telling the players goes through rpg.narrate.';

create function rpg.resolve_plot_point(p_adventure_slug text, p_title text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid := rpg.find_plot_point(p_adventure_slug, p_title);
begin
  update rpg.plot_points
  set status = 'resolved'
  where id = v_id;
  return rpg.plot_point_state(v_id);
end;
$$;

comment on function rpg.resolve_plot_point(text, text) is
  'Marks a plot point ''resolved'' — played out at the table. Returns the plot point. To re-hide a point the players forgot, use a plain UPDATE on rpg.plot_points.';

-- ---------------------------------------------------------------------------
-- EXECUTE grants — service_role only. The verbs are SECURITY INVOKER against
-- GM-private, policy-less-RLS tables, so they are inert for anon and
-- authenticated whatever their EXECUTE rights say; the explicit grant below
-- names the one role that can actually use them (the 0005 posture: the grant
-- is the documented, greppable contract).
-- ---------------------------------------------------------------------------

grant execute
  on function rpg.reveal_plot_point(text, text)
  to service_role;

grant execute
  on function rpg.resolve_plot_point(text, text)
  to service_role;

commit;
