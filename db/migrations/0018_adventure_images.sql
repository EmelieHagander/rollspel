-- ============================================================================
-- 0018_adventure_images.sql
--
-- SESSION IMAGES ("moments"). The owner shares in-session images with every
-- player for immersion; the webapp renders them as a per-adventure gallery on
-- the Story tab. Anyone at the table may add a moment or take one down; the
-- whole table sees them all.
--
-- STORAGE: same decision and rationale as 0017 (character_art) — Supabase
-- Storage buckets live in the `storage` schema, OUTSIDE the rpg fence, so the
-- image goes into the vault itself as a data:image/...;base64,... payload.
-- The client downscales to ~1200px max dimension and steps quality down until
-- the payload fits the cap. Party-scale galleries make this a reasonable
-- fence-clean trade-off; revisit if a gallery ever grows into an archive.
--
-- SHAPE:
--   * Plain rows with their own uuid id — unlike character_art (a per-
--     character upserted singleton), an adventure accumulates MANY moments.
--   * created_at only, NO updated_at / trigger: rows are add/delete only.
--     There is no update policy and no client-side edit — a moment is shared
--     or removed, never revised. (Caption edits can come later as a new
--     migration adding an update policy + trigger, if ever wanted.)
--   * created_by is nullable and INFORMATIONAL: the uploader's auth.uid(),
--     with no FK to auth.users (0007 rationale: the fence keeps our DDL out
--     of other schemas; identity columns compare against auth.uid(), not
--     constrain against auth tables). Nothing gates on it — it just lets the
--     table know who shared a moment.
--
-- ACCESS POSTURE — shared, like character_art, but THREE verbs only:
-- select / insert / delete for authenticated (using (true) / with check
-- (true)); deliberately NO update policy — the gallery is append/remove only.
-- anon: nothing, as everywhere since 0009/0010. The GM (service_role)
-- bypasses RLS and may also write moments.
--
-- Forward-only: lands as a new migration, never an edit to an applied one.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- rpg.adventure_images — an adventure's shared gallery of moments
-- ---------------------------------------------------------------------------

create table rpg.adventure_images (
  id            uuid         primary key default gen_random_uuid(),
  adventure_id  uuid         not null
                             references rpg.adventures (id) on delete cascade,
  caption       text         not null default '',
  data_url      text         not null,
  created_by    uuid,
  created_at    timestamptz  not null default now(),
  constraint adventure_images_is_image_data_url
    check (data_url like 'data:image/%'),
  -- Same cap as character_art (0017): ~650 KB decoded; the client downscales
  -- (~1200px max dimension, quality stepped down) until it fits.
  constraint adventure_images_size_cap
    check (length(data_url) <= 900000)
);

comment on table rpg.adventure_images is
  'Session images ("moments") shared to the whole table for immersion: one adventure''s gallery, rendered on the Story tab — everyone sees them, anyone at the table may add or remove one, and the GM (service_role) may also write them. Data-URLs in the vault for the same fence reason as rpg.character_art (Storage buckets live outside schema rpg). Append/remove only — no updates; caption editing would be a future migration.';

comment on column rpg.adventure_images.created_by is
  'auth.uid() of the uploader — informational only, nothing gates on it. Nullable, and no FK to auth.users (0007 rationale): the fence keeps rpg DDL out of other schemas.';

comment on column rpg.adventure_images.data_url is
  'The image itself: data:image/...;base64,... — checked to start with data:image/ and capped at 900,000 characters (~650 KB decoded). The client downscales to ~1200px max dimension and steps quality down until it fits; the cap is the backstop, not the target.';

-- Gallery read is "this adventure''s moments in order"; the leading column
-- also covers the adventure_id FK (house rule: every FK column indexed).
create index adventure_images_adventure_id_created_at_idx
  on rpg.adventure_images (adventure_id, created_at);

-- No updated_at trigger: add/delete only (see header).

-- ---------------------------------------------------------------------------
-- RLS — shared posture, three verbs; no update policy by design
-- ---------------------------------------------------------------------------

alter table rpg.adventure_images enable row level security;

create policy adventure_images_api_select on rpg.adventure_images
  for select to authenticated
  using (true);

create policy adventure_images_api_insert on rpg.adventure_images
  for insert to authenticated
  with check (true);

create policy adventure_images_api_delete on rpg.adventure_images
  for delete to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- Grants — mirroring the policy surface exactly (no update)
-- ---------------------------------------------------------------------------

grant select, insert, delete
  on rpg.adventure_images
  to authenticated;

commit;
