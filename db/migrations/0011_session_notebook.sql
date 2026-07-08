-- ============================================================================
-- 0004_session_notebook.sql
--
-- The GM's SESSION NOTEBOOK: a durable, append-only ledger of mid-session
-- story facts. The table-side GM (ChatGPT, raw SQL) currently keeps its
-- running narrative only in the chat window, which is fragile; its GitHub
-- write access is uncertain, so the vault is the durable notebook.
--
-- New objects:
--   rpg.event_kind      — enum: what sort of note this is
--   rpg.session_events  — the ledger itself (append-only by convention)
--   rpg.log_event       — the ONE write verb (verb #18 in the GM surface)
--   rpg.session_log     — the scoped read view
--
-- Design decisions (agreed with the owner):
--   * Writes cheap and constant, reads rare and scoped: the GM logs a line
--     whenever something worth remembering happens, and reads the ledger
--     back only at session close (to drain into the recap) or after an
--     interruption (to recover the night) — never every beat.
--   * TINY RETURNS: rpg.log_event returns only the entry just logged, never
--     the whole log. A write that echoes the full ledger back into the chat
--     window would defeat the point of moving it out of the chat window.
--   * APPEND-ONLY BY CONVENTION: no edit or delete verbs exist or will. A
--     wrong note is corrected by a later note, the way a paper ledger is.
--   * session_date is its own column (not derived from `at`): two runs of
--     the same one-shot on different nights are different ledgers, and the
--     canonical read scopes by slug + date. It defaults to current_date
--     (the server clock, UTC on Supabase); a session that straddles UTC
--     midnight still reads back whole by dropping the date predicate.
--   * kind defaults to 'event' (the catch-all), and the parameter order is
--     (slug, note, kind) so the common case is the shortest call:
--     select rpg.log_event('slug', 'text');
--   * 'ruling' is deliberately its own kind: improvised rulings must be
--     findable post-session for house-rule review (CLAUDE.md hard rule 3 —
--     a ruling that isn't written down doesn't exist).
--   * Slug resolution reuses rpg.find_adventure (0003); its error already
--     teaches the caller how to list valid slugs.
--
-- Security posture (shared project, advisor-clean, per 0001–0003):
--   * rpg.session_events: RLS ENABLED, NO policies (deny-by-default).
--   * rpg.session_log: security_invoker = on.
--   * rpg.log_event: SECURITY INVOKER (default), SET search_path = '' with
--     fully qualified body references.
--
-- Forward-only: once applied, this file is history — changes get a new
-- migration.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Enum (fixed value set)
-- ---------------------------------------------------------------------------

create type rpg.event_kind as enum (
  'event',            -- a story fact worth remembering (the catch-all)
  'ruling',           -- an improvised ruling, flagged for post-session house-rule review
  'secret_revealed',  -- a prepped secret the players now know
  'thread',           -- a loose end left dangling
  'npc'               -- someone the world should remember
);

comment on type rpg.event_kind is
  'What sort of session note this is: event (story fact, the catch-all), ruling (improvised ruling, flagged for post-session house-rule review), secret_revealed, thread (loose end), npc (someone the world should remember).';

-- ---------------------------------------------------------------------------
-- rpg.session_events — the ledger
-- ---------------------------------------------------------------------------

create table rpg.session_events (
  id            uuid            primary key default gen_random_uuid(),
  adventure_id  uuid            not null references rpg.adventures (id) on delete cascade,
  session_date  date            not null default current_date,
  at            timestamptz     not null default now(),
  kind          rpg.event_kind  not null default 'event',
  note          text            not null,
  constraint session_events_note_not_blank
    check (btrim(note) <> '')
);

comment on table rpg.session_events is
  'The GM''s session notebook: an append-only-by-convention ledger of mid-session story notes per adventure and session date — no edit or delete verbs exist; a wrong note is corrected by a later note.';

comment on column rpg.session_events.session_date is
  'Which night''s ledger this entry belongs to: two runs of the same one-shot on different dates are different ledgers. Defaults to the server''s current_date (UTC).';

-- The canonical read is one adventure's one night, in order — this index
-- serves it exactly (and covers the adventure_id FK as its leading column).
create index session_events_adventure_id_session_date_at_idx
  on rpg.session_events (adventure_id, session_date, at);

alter table rpg.session_events enable row level security;

-- ---------------------------------------------------------------------------
-- WRITE VERB — rpg.log_event
-- ---------------------------------------------------------------------------

create function rpg.log_event(
  p_adventure_slug text,
  p_note           text,
  p_kind           rpg.event_kind default 'event')
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_aid          uuid := rpg.find_adventure(p_adventure_slug);
  v_session_date date;
  v_at           timestamptz;
begin
  if p_note is null or btrim(p_note) = '' then
    raise exception 'A session note must say something. One or two sentences: what happened, who did it, what it changed.';
  end if;
  insert into rpg.session_events (adventure_id, kind, note)
  values (v_aid, coalesce(p_kind, 'event'), btrim(p_note))
  returning session_date, at into v_session_date, v_at;
  -- Tiny returns: only the entry just logged, never the whole ledger.
  return jsonb_build_object(
    'adventure_slug', lower(p_adventure_slug),
    'session_date',   v_session_date,
    'at',             v_at,
    'kind',           coalesce(p_kind, 'event'),
    'note',           btrim(p_note));
end;
$$;

comment on function rpg.log_event(text, text, rpg.event_kind) is
  'Appends one note to an adventure''s session ledger: select rpg.log_event(''<slug>'', ''<note>''); add a kind (ruling|secret_revealed|thread|npc) when it is more than a plain event. Keep each note to one or two sentences — log often, log small. Returns only the logged entry, never the whole log; read the ledger back via rpg.session_log.';

-- ---------------------------------------------------------------------------
-- READ VIEW — rpg.session_log
-- ---------------------------------------------------------------------------

create view rpg.session_log
with (security_invoker = on) as
select
  a.slug   as adventure_slug,
  a.title  as adventure_title,
  e.session_date,
  e.at,
  e.kind,
  e.note
from rpg.session_events e
join rpg.adventures a on a.id = e.adventure_id
order by e.at;

comment on view rpg.session_log is
  'The session ledger, readable by slug. Canonical scoped read: select kind, note from rpg.session_log where adventure_slug = ''<slug>'' and session_date = current_date order by at; — read it once at session close to drain into the recap, or after an interruption to recover the night, never every beat.';

commit;
