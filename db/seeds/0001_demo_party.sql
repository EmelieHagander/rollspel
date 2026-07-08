-- ============================================================================
-- 0001_demo_party.sql  (SEED, not a migration)
--
-- Three demo D&D 5e player characters and all their child rows, mirroring the
-- character webapp's mock party so the live app looks identical to the mockup:
--
--   Vesper Quill   — Warlock (The Archfey), Tiefling, level 5
--   Brann Ashfoot  — Fighter (Battle Master), Dwarf, level 5
--   Sable Wren     — Cleric (Light Domain), Half-Elf, level 5
--
-- Why db/seeds/ and not db/migrations/:
--   db/migrations/ is forward-only schema history — an applied file is never
--   re-run. This is demo *data*, meant to be safely re-applied whenever the
--   live tables need repopulating, so it lives on its own shelf.
--
-- Idempotency:
--   Each character has a fixed, deterministic UUID. The seed deletes those
--   three characters by id first — ON DELETE CASCADE clears every child row
--   (skills, items, spell slots, spells) — then re-inserts the full party.
--   Re-running yields exactly the same rows with no duplicates and no orphans.
--   Child rows (items/spells) keep gen_random_uuid() ids; the app reads them
--   by character, not by a stable child id, so regeneration is harmless.
--
-- Fence: schema rpg only. No RLS is created, altered, or disabled here — the
-- policy question is deliberately left untouched.
--
-- Stored vs derived (per 0001): ability scores are stored; modifiers, saves,
-- passive perception, spell save DC / attack bonus, and proficiency_bonus are
-- DERIVED and are NOT written by this seed.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Idempotency: remove any prior copies of the three demo characters.
-- CASCADE clears character_skills / character_items / character_spell_slots /
-- character_spells for these ids.
-- ---------------------------------------------------------------------------

delete from rpg.characters
where id in (
  '11111111-1111-4111-8111-111111111111',  -- Vesper Quill
  '22222222-2222-4222-8222-222222222222',  -- Brann Ashfoot
  '33333333-3333-4333-8333-333333333333'   -- Sable Wren
);

-- ---------------------------------------------------------------------------
-- rpg.characters
-- (proficiency_bonus is generated; do not insert it)
-- ---------------------------------------------------------------------------

insert into rpg.characters (
  id, name, player_name, class, subclass, level, species, background, alignment,
  strength, dexterity, constitution, intelligence, wisdom, charisma,
  armor_class, speed, hp_max, hp_current, hp_temp,
  hit_die, hit_dice_total, hit_dice_remaining,
  death_save_successes, death_save_failures,
  save_proficiencies, spellcasting_ability,
  coins_cp, coins_sp, coins_ep, coins_gp, coins_pp, notes
) values
  (
    '11111111-1111-4111-8111-111111111111',
    'Vesper Quill', 'Emelie', 'Warlock', 'The Archfey', 5, 'Tiefling', 'Charlatan', 'chaotic_good',
    8, 14, 14, 11, 12, 18,
    14, 30, 37, 37, 0,
    'd8', 5, 5,
    0, 0,
    '{wisdom,charisma}', 'charisma',
    0, 12, 2, 41, 1, null
  ),
  (
    '22222222-2222-4222-8222-222222222222',
    'Brann Ashfoot', null, 'Fighter', 'Battle Master', 5, 'Dwarf', 'Soldier', 'lawful_neutral',
    17, 12, 16, 10, 13, 8,
    18, 25, 49, 31, 0,
    'd10', 5, 3,
    0, 0,
    '{strength,constitution}', null,
    30, 5, 0, 22, 0, null
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    'Sable Wren', null, 'Cleric', 'Light Domain', 5, 'Half-Elf', 'Acolyte', 'neutral_good',
    10, 12, 14, 11, 18, 13,
    17, 30, 38, 38, 6,
    'd8', 5, 5,
    0, 0,
    '{wisdom,charisma}', 'wisdom',
    0, 0, 0, 63, 3, null
  );

-- ---------------------------------------------------------------------------
-- rpg.character_skills  (a row = proficient; expertise doubles the bonus)
-- ---------------------------------------------------------------------------

insert into rpg.character_skills (character_id, skill, expertise) values
  -- Vesper Quill
  ('11111111-1111-4111-8111-111111111111', 'deception',    true),
  ('11111111-1111-4111-8111-111111111111', 'persuasion',   false),
  ('11111111-1111-4111-8111-111111111111', 'arcana',       false),
  ('11111111-1111-4111-8111-111111111111', 'intimidation', false),
  ('11111111-1111-4111-8111-111111111111', 'insight',      false),
  -- Brann Ashfoot
  ('22222222-2222-4222-8222-222222222222', 'athletics',    true),
  ('22222222-2222-4222-8222-222222222222', 'intimidation', false),
  ('22222222-2222-4222-8222-222222222222', 'perception',   false),
  ('22222222-2222-4222-8222-222222222222', 'survival',     false),
  -- Sable Wren
  ('33333333-3333-4333-8333-333333333333', 'medicine',   false),
  ('33333333-3333-4333-8333-333333333333', 'religion',   true),
  ('33333333-3333-4333-8333-333333333333', 'insight',    false),
  ('33333333-3333-4333-8333-333333333333', 'persuasion', false);

-- ---------------------------------------------------------------------------
-- rpg.character_spell_slots
-- ---------------------------------------------------------------------------

insert into rpg.character_spell_slots (character_id, slot_kind, slot_level, slots_total, slots_expended) values
  -- Vesper Quill — Pact Magic
  ('11111111-1111-4111-8111-111111111111', 'pact',     3, 2, 1),
  -- Brann Ashfoot — none (non-caster)
  -- Sable Wren — standard slots
  ('33333333-3333-4333-8333-333333333333', 'standard', 1, 4, 2),
  ('33333333-3333-4333-8333-333333333333', 'standard', 2, 3, 1),
  ('33333333-3333-4333-8333-333333333333', 'standard', 3, 2, 0);

-- ---------------------------------------------------------------------------
-- rpg.character_spells  (spell_level 0 = cantrip; all prepared)
-- ---------------------------------------------------------------------------

insert into rpg.character_spells (character_id, name, spell_level, prepared) values
  -- Vesper Quill
  ('11111111-1111-4111-8111-111111111111', 'Eldritch Blast',   0, true),
  ('11111111-1111-4111-8111-111111111111', 'Minor Illusion',   0, true),
  ('11111111-1111-4111-8111-111111111111', 'Prestidigitation', 0, true),
  ('11111111-1111-4111-8111-111111111111', 'Hex',              1, true),
  ('11111111-1111-4111-8111-111111111111', 'Charm Person',     1, true),
  ('11111111-1111-4111-8111-111111111111', 'Misty Step',       2, true),
  ('11111111-1111-4111-8111-111111111111', 'Hunger of Hadar',  3, true),
  ('11111111-1111-4111-8111-111111111111', 'Fly',              3, true),
  -- Brann Ashfoot — none (non-caster)
  -- Sable Wren
  ('33333333-3333-4333-8333-333333333333', 'Sacred Flame',     0, true),
  ('33333333-3333-4333-8333-333333333333', 'Light',            0, true),
  ('33333333-3333-4333-8333-333333333333', 'Cure Wounds',      1, true),
  ('33333333-3333-4333-8333-333333333333', 'Guiding Bolt',     1, true),
  ('33333333-3333-4333-8333-333333333333', 'Scorching Ray',    2, true),
  ('33333333-3333-4333-8333-333333333333', 'Spirit Guardians', 3, true),
  ('33333333-3333-4333-8333-333333333333', 'Daylight',         3, true);

-- ---------------------------------------------------------------------------
-- rpg.character_items
-- ---------------------------------------------------------------------------

insert into rpg.character_items (character_id, name, quantity, equipped, attuned, notes) values
  -- Vesper Quill
  ('11111111-1111-4111-8111-111111111111', 'Rod of the Pact Keeper +1',              1, false, true,  'your spell attacks bite a little deeper'),
  ('11111111-1111-4111-8111-111111111111', 'Studded leather',                        1, true,  false, null),
  ('11111111-1111-4111-8111-111111111111', 'Dagger',                                 2, true,  false, null),
  ('11111111-1111-4111-8111-111111111111', 'Fine clothes & a forged writ of nobility', 1, false, false, 'the charlatan''s toolkit'),
  ('11111111-1111-4111-8111-111111111111', 'Potion of healing',                      2, false, false, '2d4+2, when the bargain isn''t enough'),
  -- Brann Ashfoot
  ('22222222-2222-4222-8222-222222222222', 'Longsword',   1, true,  false, null),
  ('22222222-2222-4222-8222-222222222222', 'Shield',      1, true,  false, null),
  ('22222222-2222-4222-8222-222222222222', 'Chain mail',  1, true,  false, null),
  ('22222222-2222-4222-8222-222222222222', 'Handaxe',     2, false, false, 'for throwing'),
  ('22222222-2222-4222-8222-222222222222', 'Rations',     5, false, false, null),
  -- Sable Wren
  ('33333333-3333-4333-8333-333333333333', 'Mace',                   1, true,  false, null),
  ('33333333-3333-4333-8333-333333333333', 'Chain mail',             1, true,  false, null),
  ('33333333-3333-4333-8333-333333333333', 'Shield',                 1, true,  false, null),
  ('33333333-3333-4333-8333-333333333333', 'Holy symbol (sunburst)', 1, false, true,  'channels the domain''s fire'),
  ('33333333-3333-4333-8333-333333333333', 'Potion of healing',      1, false, false, null);

commit;

-- ============================================================================
-- Expected row counts after applying this seed (per table, these three chars):
--   rpg.characters            3   (1 + 1 + 1)
--   rpg.character_skills      13   (5 + 4 + 4)
--   rpg.character_spell_slots  4   (1 + 0 + 3)
--   rpg.character_spells      15   (8 + 0 + 7)
--   rpg.character_items       15   (5 + 5 + 5)
--
-- Verification SELECT (run after apply):
--   select c.name,
--          (select count(*) from rpg.character_skills      s where s.character_id = c.id) as skills,
--          (select count(*) from rpg.character_spell_slots l where l.character_id = c.id) as slots,
--          (select count(*) from rpg.character_spells      p where p.character_id = c.id) as spells,
--          (select count(*) from rpg.character_items       i where i.character_id = c.id) as items
--   from rpg.characters c
--   where c.id in (
--     '11111111-1111-4111-8111-111111111111',
--     '22222222-2222-4222-8222-222222222222',
--     '33333333-3333-4333-8333-333333333333'
--   )
--   order by c.name;
-- ============================================================================
