-- ---------------------------------------------------------------------------
-- 0016_summary_event_kind.sql
--
-- Purpose: add a first-class 'summary' value to rpg.event_kind, the enum
--   classifying rpg.session_events (the GM's private session notebook).
--   The GM's closing ritual writes one comprehensive SUMMARY entry to the
--   private log at every pause/close — the catch-up entry. Session start
--   resumes from the latest summary: read the most recent 'summary' row,
--   then any entries logged after it.
--
-- Forward-only: enum values cannot be dropped without recreating the type;
--   this migration is not meant to be reversed.
--
-- Safety: ALTER TYPE ... ADD VALUE is purely additive — existing rows keep
--   their values, and existing functions taking rpg.event_kind (e.g.
--   rpg.log_event) accept the new value with no signature change.
-- ---------------------------------------------------------------------------

alter type rpg.event_kind add value if not exists 'summary';

comment on type rpg.event_kind is
  'What sort of session note this is: event (story fact, the catch-all), ruling (improvised ruling, flagged for post-session house-rule review), secret_revealed, thread (loose end), npc (someone the world should remember), summary (the closing ritual''s comprehensive catch-up entry; resume = latest summary plus entries after it).';
