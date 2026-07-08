-- ============================================================================
-- 0016_character_portraits.sql
--
-- Character art: one nullable column, rpg.characters.portrait_url — the
-- explicit pointer to a character's portrait image.
--
-- How the webapp resolves art (why null is fine): when portrait_url is null,
-- the webapp tries a filename convention — art/<kebab-name>.png/.jpg/.webp,
-- files living in the repo at webapp/art/ and deployed with the site. The
-- column is the explicit OVERRIDE for when convention isn't enough (renamed
-- character, shared artwork, external host), not a requirement.
--
-- No check constraint on format: the value is a hint for a renderer — either
-- a path relative to the webapp's own origin (e.g. art/vesper-quill.png) or
-- an absolute URL — not a foreign key into the filesystem; a broken value
-- costs a broken <img>, nothing more.
--
-- NO NEW POLICIES OR GRANTS: policies and table-level privileges cover whole
-- rows, so the existing characters_api_select / characters_api_update
-- (authenticated, 0004 as narrowed by 0009) and the standing DML grants
-- already read and write this column. Stated so the reader doesn't wonder.
--
-- Deliberately tiny. Forward-only: lands as a new migration, never an edit
-- to an applied one.
-- ============================================================================

begin;

alter table rpg.characters
  add column portrait_url text;

comment on column rpg.characters.portrait_url is
  'Portrait image for the character: either a path relative to the webapp''s own origin (e.g. art/vesper-quill.png — the file lives in the repo at webapp/art/ and deploys with the site) or an absolute URL. Null is normal: the webapp then tries the filename convention art/<kebab-name>.png/.jpg/.webp, so this column is the explicit override, not a requirement. No format constraint — a renderer hint, not a foreign key into the filesystem.';

commit;
