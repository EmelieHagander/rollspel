-- ============================================================================
-- 0017_character_art.sql
--
-- CHARACTER ART UPLOADS. Players upload a portrait straight from the webapp;
-- the image lands in the vault itself as a data-URL row in rpg.character_art.
--
-- STORAGE DECISION (owner-made, recorded here): Supabase Storage buckets live
-- in the `storage` schema — OUTSIDE the rpg fence — so the fence-clean choice
-- is to keep the bytes in our own schema as a `data:image/...;base64,...`
-- payload. At party scale (a handful of characters, client-side downscaled to
-- <= 512px, roughly 100-200 KB each) that is a reasonable trade-off; revisit
-- only if the vault ever hosts dozens of portraits.
--
-- OWN TABLE, DELIBERATELY. The blob does NOT live on rpg.characters: the app
-- loads the party's character rows on every login, and a fat data-URL must
-- never ride along with `select *` on rpg.characters. Art loads separately,
-- one row per character, upserted on the primary key.
--
-- TIMESTAMPS: updated_at only, no created_at — a deliberate omission, not an
-- oversight. This is a one-row-per-character upserted singleton: every write
-- replaces the whole payload, so "when was it first uploaded" has no consumer,
-- while "how fresh is this art" (cache-busting, sync) is exactly updated_at.
-- A created_at would be a rumor of a history the table does not keep.
--
-- ACCESS POSTURE — the character family's shared model: characters are shared
-- table property (characters_api_update already lets any authenticated player
-- edit any character), so their art follows suit — full CRUD for
-- authenticated, using (true). anon: nothing, as everywhere since 0009/0010
-- (no schema usage, no grants, no policy names it). service_role bypasses RLS.
--
-- RESOLUTION ORDER in the webapp (this table is source #1): character_art
-- (this table) -> characters.portrait_url (0016) -> the webapp/art/
-- <kebab-name>.png/.jpg/.webp filename convention -> initial crest. The 0016
-- column and the convention remain as alternative sources; nothing here
-- replaces them.
--
-- Forward-only: lands as a new migration, never an edit to an applied one.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- rpg.character_art — one uploaded portrait per character
-- ---------------------------------------------------------------------------

create table rpg.character_art (
  character_id  uuid         primary key
                             references rpg.characters (id) on delete cascade,
  data_url      text         not null,
  updated_at    timestamptz  not null default now(),
  constraint character_art_is_image_data_url
    check (data_url like 'data:image/%'),
  -- ~650 KB decoded ceiling (base64 inflates ~4/3); the client aims far
  -- lower (<= 512px downscale, ~100-200 KB).
  constraint character_art_size_cap
    check (length(data_url) <= 900000)
);

comment on table rpg.character_art is
  'Uploaded character portraits as data-URLs, one row per character, upserted on the primary key. In the vault rather than Supabase Storage because buckets live in the storage schema — outside the rpg fence — and party-scale images (client-downscaled to <= 512px, ~100-200 KB) make blob-in-Postgres a reasonable fence-clean trade-off; revisit at dozens of portraits. Deliberately its OWN table so the fat payload never rides along with select * on rpg.characters (party rows load every login; art loads separately). Webapp resolution order: this table -> characters.portrait_url -> art/<kebab-name> file convention -> initial crest.';

comment on column rpg.character_art.data_url is
  'The image itself: data:image/...;base64,... — checked to start with data:image/ and capped at 900,000 characters (~650 KB decoded). The client downscales before upload; the cap is the vault''s backstop, not the target.';

-- FK index: covered by the primary key (character_id IS the primary key).

create trigger character_art_set_updated_at
  before update on rpg.character_art
  for each row execute function rpg.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — shared posture, matching the character family
-- ---------------------------------------------------------------------------

alter table rpg.character_art enable row level security;

create policy character_art_api_select on rpg.character_art
  for select to authenticated
  using (true);

create policy character_art_api_insert on rpg.character_art
  for insert to authenticated
  with check (true);

create policy character_art_api_update on rpg.character_art
  for update to authenticated
  using (true) with check (true);

create policy character_art_api_delete on rpg.character_art
  for delete to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select, insert, update, delete
  on rpg.character_art
  to authenticated;

commit;
