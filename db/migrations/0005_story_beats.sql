-- ============================================================================
-- 0005_story_beats.sql
--
-- THE LIVE STORY STREAM. The table-side GM (a ChatGPT connector speaking raw
-- SQL) writes narration beats as rows in rpg.story_beats; the browser webapp
-- subscribes via Supabase Realtime, so every player at the table sees the
-- story appear simultaneously.
--
-- NAMING NOTE — story_beats vs session_events (read before touching either):
--   rpg.session_events (created by the concurrent GM-surface session, with
--   rpg.event_kind and rpg.log_event) is the GM's PRIVATE bookkeeping log —
--   rulings, plot threads, SECRETS — deliberately browser-invisible (RLS
--   enabled, zero policies; only service_role reads it). rpg.story_beats
--   (this file) is the PUBLIC live stream every player's browser renders.
--   Same neighbourhood, opposite audiences: the two must NEVER merge, no
--   verb may write across them, and rpg.narrate() must NEVER be used for GM
--   secrets — a narrated beat is on every player's screen the moment it
--   commits. Secrets go through rpg.log_event; story goes through narrate.
--
-- New objects (all inside schema rpg, touching none of the GM-log family):
--   rpg.beat_kind        — enum: what sort of beat a row is
--   rpg.story_beats      — the append-only stream, one row per beat
--   rpg.narrate(...)     — write verb: resolve adventure by slug, insert beat
--   rpg.story_so_far(...)— read verb: last N beats in chronological order
--
-- Design decisions:
--   * ORDERING: `id bigint generated always as identity` is the sort key.
--     Identity is strictly monotonic per insert and never ties, unlike
--     created_at (two beats inside the same millisecond sort unstably, which
--     a live-rendering client would show as reordering flicker). GENERATED
--     ALWAYS also stops clients supplying their own ids, so the stream order
--     is the insert order, full stop. created_at stays for display.
--   * BEAT KINDS: narration | dialogue | roll | mechanics | system. This is
--     the rendering vocabulary the webapp needs — prose block (narration),
--     attributed speech (dialogue), dice result (roll), rules bookkeeping
--     like damage or slots (mechanics), out-of-fiction table notices like
--     session start/pause (system) — without over-slicing; a forward-only
--     `alter type ... add value` extends it cheaply if play demands more.
--   * APPEND-ONLY BY CONSTRUCTION, at two layers. (1) RLS: the client roles
--     (anon, authenticated) get SELECT and INSERT policies ONLY — with RLS
--     enabled and no UPDATE/DELETE policy, those commands are deny-by-default
--     for the browser and the GPT; the story, once told, is told. (2) Belt-
--     and-braces: 0004's default privileges auto-GRANT update/delete on every
--     new rpg table, so this file REVOKEs them on story_beats from the
--     client roles — the privilege layer then agrees with the policy layer,
--     and a future accidental permissive policy could not silently reopen
--     writes. service_role bypasses RLS (BYPASSRLS) and keeps ALL, which is
--     the deliberate owner-cleanup path (trimming a test stream, GDPR-ish
--     tidying) — cleanup is a trusted-tooling act, not a table-side one.
--   * GRANTS otherwise NOT duplicated: 0004's `alter default privileges in
--     schema rpg` already covers SELECT/INSERT for anon+authenticated, ALL
--     for service_role, and usage/select on the identity column's implicit
--     sequence — verified against 0004 §3; only the append-only REVOKE above
--     deviates from that baseline, so only it is stated here.
--   * VERBS follow 0003's established style: slug resolution via
--     rpg.find_adventure (model-readable errors), SECURITY INVOKER,
--     SET search_path = '' with fully qualified references, compact return
--     of what changed. rpg.narrate puts p_content second and defaults
--     p_kind/p_speaker ('narration'/'GM') — a deliberate reordering from the
--     spec sketch, because Postgres forbids non-defaulted parameters after
--     defaulted ones, and the overwhelmingly common call is the GM narrating:
--     select rpg.narrate('<slug>', 'text...');
--   * REALTIME: the table is added to the supabase_realtime publication in
--     an idempotent DO block (guarded on publication existence and current
--     membership). Realtime postgres_changes respects RLS, so the SELECT
--     policy below is also what lets the browser's anon subscription receive
--     rows. INSERT payloads carry the full new row under the default replica
--     identity (primary key) — no REPLICA IDENTITY change needed for an
--     insert-only stream.
--
-- FENCE NOTE: `alter publication supabase_realtime add table
-- rpg.story_beats` is the one statement in this file that names an object
-- outside schema rpg — the publication itself, which is Supabase's single
-- sanctioned realtime switchboard and cannot live inside rpg. It is within
-- the fence's spirit: it alters replication OF OUR TABLE ONLY (adds one
-- rpg-schema table to the member list) and reads/writes nothing belonging to
-- any other tenant. No other statement leaves schema rpg.
--
-- RLS posture per 0004's warning: default privileges cover grants only,
-- never policies — this table ships its own policy block below.
--
-- Forward-only: 0001–0004 and the GM session's migrations are applied
-- history; this lands as a new migration touching none of their objects.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Enum
-- ---------------------------------------------------------------------------

create type rpg.beat_kind as enum
  ('narration', 'dialogue', 'roll', 'mechanics', 'system');

comment on type rpg.beat_kind is
  'Story-stream beat kinds, chosen as the webapp''s rendering vocabulary: narration (GM prose), dialogue (attributed speech), roll (dice result), mechanics (rules bookkeeping: damage, slots, rests), system (out-of-fiction table notices: session start/pause/recap). Distinct from rpg.event_kind, which classifies the GM''s private log.';

-- ---------------------------------------------------------------------------
-- rpg.story_beats — the append-only story stream
-- ---------------------------------------------------------------------------

create table rpg.story_beats (
  id            bigint         generated always as identity primary key,
  adventure_id  uuid           not null references rpg.adventures (id) on delete cascade,
  kind          rpg.beat_kind  not null default 'narration',
  speaker       text           not null default 'GM',
  content       text           not null,
  created_at    timestamptz    not null default now(),
  constraint story_beats_content_not_blank check (btrim(content) <> ''),
  constraint story_beats_speaker_not_blank check (btrim(speaker) <> '')
);

comment on table rpg.story_beats is
  'The PUBLIC live story stream: one row per narration beat, written by the table-side GM via rpg.narrate and pushed to every player''s browser via Supabase Realtime. APPEND-ONLY BY DESIGN for the API client roles — SELECT + INSERT policies only, no UPDATE/DELETE policy and those privileges revoked; service_role (RLS-bypassing trusted tooling) is the sole cleanup path. NOT the GM''s private log — that is rpg.session_events (browser-invisible, secrets allowed); never merge the two, never narrate a secret.';

comment on column rpg.story_beats.id is
  'Identity bigint, GENERATED ALWAYS: the stream''s sort key. Strictly insert-ordered and tie-free, unlike created_at; clients render and paginate by id.';

comment on column rpg.story_beats.speaker is
  'Who the beat belongs to: ''GM'' (default) or a character/NPC name. Display attribution only — not a foreign key, since NPCs and one-off voices have no character row.';

comment on column rpg.story_beats.content is
  'The beat itself, as markdown. Stored verbatim (no trimming): leading whitespace can be meaningful markdown. Player-visible the moment it commits — no secrets.';

-- Hot query and FK index in one: the stream read is always
-- "this adventure's beats in id order", and adventure_id leads the key.
create index story_beats_adventure_id_id_idx
  on rpg.story_beats (adventure_id, id);

-- ---------------------------------------------------------------------------
-- RLS — own policy block (0004: default privileges never carry policies).
-- SELECT + INSERT only: RLS itself makes the stream append-only for clients.
-- ---------------------------------------------------------------------------

alter table rpg.story_beats enable row level security;

create policy story_beats_api_select on rpg.story_beats
  for select to anon, authenticated
  using (true);

create policy story_beats_api_insert on rpg.story_beats
  for insert to anon, authenticated
  with check (true);

-- Deliberately NO update or delete policies: deny-by-default makes the
-- stream append-only for anon/authenticated. service_role bypasses RLS
-- for owner cleanup.

-- Belt-and-braces: 0004's default privileges auto-granted UPDATE/DELETE on
-- this table at creation; take them back so the privilege layer matches the
-- policy layer and no future policy slip can reopen client-side rewriting.
revoke update, delete on rpg.story_beats from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Realtime — add the stream to the supabase_realtime publication.
-- (See FENCE NOTE in the header: this is the one statement naming an object
-- outside schema rpg; it alters replication of our table only.)
-- Idempotent: guarded on the publication existing and on membership, so the
-- migration survives environments where the publication is absent.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_catalog.pg_publication
             where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_catalog.pg_publication_tables
                   where pubname = 'supabase_realtime'
                     and schemaname = 'rpg'
                     and tablename = 'story_beats') then
      alter publication supabase_realtime add table rpg.story_beats;
    end if;
  else
    raise warning 'Publication supabase_realtime not found: rpg.story_beats was NOT added. Add it manually once the publication exists: alter publication supabase_realtime add table rpg.story_beats;';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- WRITE VERB — rpg.narrate
-- ---------------------------------------------------------------------------

create function rpg.narrate(
  p_adventure_slug text,
  p_content        text,
  p_kind           rpg.beat_kind default 'narration',
  p_speaker        text          default 'GM')
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_aid  uuid := rpg.find_adventure(p_adventure_slug);
  v_beat rpg.story_beats%rowtype;
begin
  if p_content is null or btrim(p_content) = '' then
    raise exception 'Narration content must not be empty.';
  end if;
  if p_speaker is null or btrim(p_speaker) = '' then
    raise exception 'Speaker must not be empty; omit it to default to ''GM''.';
  end if;
  insert into rpg.story_beats (adventure_id, kind, speaker, content)
  values (v_aid, coalesce(p_kind, 'narration'), btrim(p_speaker), p_content)
  returning * into v_beat;
  return jsonb_build_object(
    'id',             v_beat.id,
    'adventure_slug', lower(p_adventure_slug),
    'kind',           v_beat.kind,
    'speaker',        v_beat.speaker,
    'content',        v_beat.content,
    'created_at',     v_beat.created_at);
end;
$$;

comment on function rpg.narrate(text, text, rpg.beat_kind, text) is
  'Appends one beat to an adventure''s PUBLIC live story stream (rpg.story_beats — players'' browsers receive it via Realtime the moment it commits, so NEVER narrate a GM secret; secrets go through rpg.log_event). Common call: select rpg.narrate(''<slug>'', ''text''); kind defaults to ''narration'', speaker to ''GM'' — pass kind (narration|dialogue|roll|mechanics|system) and speaker for other beats. Returns the new beat row.';

-- ---------------------------------------------------------------------------
-- READ VERB — rpg.story_so_far
-- ---------------------------------------------------------------------------

create function rpg.story_so_far(
  p_adventure_slug text,
  p_limit          integer default 50)
returns setof rpg.story_beats
language plpgsql
stable
set search_path = ''
as $$
declare
  v_aid uuid := rpg.find_adventure(p_adventure_slug);
begin
  if coalesce(p_limit, 0) <= 0 then
    raise exception 'Limit must be a positive integer (got %).', p_limit;
  end if;
  -- Newest N selected first, then flipped: the caller reads them in
  -- chronological order, ending at the current moment — a mid-session recap.
  return query
    select recent.*
    from (select b.*
          from rpg.story_beats b
          where b.adventure_id = v_aid
          order by b.id desc
          limit p_limit) recent
    order by recent.id;
end;
$$;

comment on function rpg.story_so_far(text, integer) is
  'The most recent beats of an adventure''s public story stream (rpg.story_beats), in chronological order (default 50) — for a GPT catching up mid-session. Rows come back oldest-first and end at the latest beat.';

-- ---------------------------------------------------------------------------
-- EXECUTE grants — explicit, matching the 0004 posture of naming what the
-- API roles may call (Postgres''s default PUBLIC EXECUTE would suffice, but
-- the explicit grant is the documented, greppable contract).
-- ---------------------------------------------------------------------------

grant execute
  on function rpg.narrate(text, text, rpg.beat_kind, text)
  to anon, authenticated, service_role;

grant execute
  on function rpg.story_so_far(text, integer)
  to anon, authenticated, service_role;

commit;
