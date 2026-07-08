-- ============================================================================
-- 0010_complete_login_lockdown.sql
--
-- Completes the LOGIN-REQUIRED lockdown across the WHOLE rpg schema, after
-- merging origin/main's parallel GM-surface workstream.
--
-- Reconciliation context:
--   main's 0004_rpg_api_access.sql recorded a DELIBERATE open-anon decision:
--   it granted `anon` usage on schema rpg + DML on all tables, set ALTER
--   DEFAULT PRIVILEGES so FUTURE rpg tables auto-grant anon, and created the
--   permissive `<table>_api_*` policies (roles {anon, authenticated}). main's
--   0005_story_beats.sql then added story_beats with `story_beats_api_*`
--   SELECT/INSERT policies that likewise name {anon, authenticated}.
--
--   Our branch's 0007-0009 (formerly 0003-0005) chose LOGIN REQUIRED instead.
--   The OWNER has resolved the conflict in favour of login-required: the
--   parallel open-anon posture is OVERRIDDEN. 0009 already revoked anon on the
--   character family and narrowed those five tables' `_api_*` policies to
--   `authenticated`. This migration finishes the job for the objects the merge
--   brought in (story_beats, session_notebook, adventures, session_events, and
--   any table caught by the old anon default privileges).
--
-- What this does, all inside schema rpg:
--   1. Narrow the `story_beats_api_*` permissive policies (still naming
--      {anon, authenticated}) to `authenticated` only, matching 0009 — via
--      ALTER POLICY, preserving each policy's name and USING/WITH CHECK.
--   2. Revoke the anon DEFAULT PRIVILEGES that main's 0004 set, so FUTURE rpg
--      tables/sequences no longer auto-grant anon. Plain form (no FOR ROLE):
--      these defaults were set by the same MCP role we apply through, so a
--      plain revoke clears them.
--   3. Defensively re-assert that `anon` has NOTHING in schema rpg: revoke all
--      table/sequence/function privileges and `usage` on the schema — this
--      catches every table the old defaults may have granted anon
--      (session_notebook, story_beats, adventures, session_events, ...).
--      Revoking schema usage is the master lock: without it, anon cannot
--      reach any object in rpg regardless of per-object grants or policies.
--
-- UNCHANGED:
--   * `authenticated` keeps its usage + table DML grants (0007) and full
--     read/write through the now-authenticated-only `_api_*` policies. On
--     story_beats it keeps SELECT + INSERT only (the stream stays append-only
--     for clients, per main's 0005 design).
--   * `service_role` (the AI GM's key) is untouched — it bypasses RLS and
--     retains ALL, so GM narration and cleanup are unaffected.
--
-- Forward-only: lands as a new migration, never an edit to an applied one.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Narrow the story_beats permissive policies to `authenticated` only.
--    story_beats has SELECT + INSERT policies only (append-only by design);
--    there are no update/delete policies to narrow.
-- ---------------------------------------------------------------------------

alter policy story_beats_api_select on rpg.story_beats to authenticated;
alter policy story_beats_api_insert on rpg.story_beats to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Revoke the anon DEFAULT PRIVILEGES main's 0004_rpg_api_access set, so
--    future rpg objects stop auto-granting anon. Plain form binds to the
--    current (MCP) role, which is the role that set them.
-- ---------------------------------------------------------------------------

alter default privileges in schema rpg revoke all on tables    from anon;
alter default privileges in schema rpg revoke all on sequences from anon;
alter default privileges in schema rpg revoke all on functions from anon;

-- ---------------------------------------------------------------------------
-- 3. Defensively re-assert: `anon` has nothing in schema rpg. Covers every
--    table the old defaults may have granted (session_notebook, story_beats,
--    adventures, session_events, and the character family). The schema-usage
--    revoke is the master lock.
-- ---------------------------------------------------------------------------

revoke all privileges on all tables    in schema rpg from anon;
revoke all privileges on all sequences in schema rpg from anon;
revoke all privileges on all functions in schema rpg from anon;
revoke usage on schema rpg from anon;

commit;
