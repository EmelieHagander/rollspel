-- ============================================================================
-- 0001_sample_party.sql — SEED DATA (no DDL)
--
-- *** SAMPLE ROWS FOR FRONTEND DEVELOPMENT ***
-- A four-character level-3 adventuring party so the in-progress frontend has
-- realistic rows to render. Safe to DELETE wholesale when real play begins
-- (all rows carry fixed '5eed....' UUIDs; children cascade from characters).
--
-- Idempotent: every row has a deterministic fixed UUID or a composite natural
-- key, and every INSERT ends in ON CONFLICT DO NOTHING — re-running is a no-op.
--
-- Data only: INSERTs exclusively. No CREATE/ALTER/DROP of anything.
-- Touches ONLY the character family in schema `rpg`; nothing GM-family.
--
-- SRD honesty (CLAUDE.md hard rule 4): all four builds are 5e SRD 5.1 legal —
-- standard array (15/14/13/12/10/8) + SRD racial bonuses, class hit dice with
-- average HP per level after 1st, save proficiencies per class, AC computed
-- from listed gear. Approximations are flagged inline:
--   * Rónal (Champion fighter): Fighting Style = Dueling (no AC effect).
--     Second Wind / Action Surge are class features with no table; not stored.
--   * Tuala (hill dwarf): HP includes +1/level Dwarven Toughness; speed 25.
--     Circle of the Land (Forest): Guidance = bonus cantrip; Barkskin and
--     Spider Climb = circle spells, always prepared, free of the 6-prepared cap.
--   * Órla (College of Lore bard): 8 skill rows = 3 class + 2 half-elf +
--     3 Lore bonus proficiencies; Entertainer background overlaps were
--     re-picked per PHB/SRD duplicate-proficiency guidance. Expertise (lvl 3):
--     Performance, Persuasion. Known-caster: all spells stay prepared = true.
--   * Senán (Fiend warlock): Pact Magic = 2 slots, both 2nd level, slot_kind
--     'pact' (short-rest recharge). Pact of the Blade; invocations (Agonizing
--     Blast, Devil's Sight) have no table and are not stored. Thaumaturgy and
--     Hellish Rebuke are tiefling Infernal Legacy racials, noted on their rows.
--
-- Character sketches in `notes` are original flavor (improvised, not SRD, and
-- deliberately world-neutral — no setting lore).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Characters
-- ---------------------------------------------------------------------------
-- Ability arrays (standard array + racial):
--   Rónal  human (+1 all):            STR 16 DEX 14 CON 15 INT  9 WIS 13 CHA 11
--   Tuala  hill dwarf (+2 CON +1 WIS):STR 10 DEX 13 CON 16 INT 12 WIS 16 CHA  8
--   Órla   half-elf (+2 CHA, +1 DEX/CON): STR 8 DEX 15 CON 14 INT 12 WIS 10 CHA 17
--   Senán  tiefling (+1 INT +2 CHA):  STR  8 DEX 13 CON 14 INT 13 WIS 10 CHA 17
-- HP at level 3 (max at 1st, average after):
--   Rónal  d10: 10+2 + 2*(6+2)            = 28
--   Tuala  d8:  8+3+1 + 2*(5+3+1)         = 30  (Dwarven Toughness +1/level)
--   Órla   d8:  8+2 + 2*(5+2)             = 24
--   Senán  d8:  8+2 + 2*(5+2)             = 24
-- AC:
--   Rónal  chain mail 16 + shield 2       = 18
--   Tuala  leather 11 + DEX 1 + shield 2  = 14
--   Órla   leather 11 + DEX 2             = 13
--   Senán  leather 11 + DEX 1             = 12

insert into rpg.characters
  (id, name, player_name, class, subclass, level, species, background, alignment,
   strength, dexterity, constitution, intelligence, wisdom, charisma,
   armor_class, speed, hp_max, hp_current,
   hit_die, hit_dice_total, hit_dice_remaining,
   save_proficiencies, spellcasting_ability,
   coins_cp, coins_sp, coins_ep, coins_gp, coins_pp, notes)
values
  ('5eed0001-0000-4000-a000-000000000001', 'Rónal', null,
   'Fighter', 'Champion', 3, 'Human', 'Soldier', 'lawful_neutral',
   16, 14, 15, 9, 13, 11,
   18, 30, 28, 28,
   'd10', 3, 3,
   '{strength,constitution}', null,
   0, 20, 0, 45, 0,
   'A weathered veteran who counts the exits before sitting down; slow to anger, slower to retreat.'),

  ('5eed0001-0000-4000-a000-000000000002', 'Tuala', null,
   'Druid', 'Circle of the Land (Forest)', 3, 'Hill Dwarf', 'Hermit', 'true_neutral',
   10, 13, 16, 12, 16, 8,
   14, 25, 30, 30,
   'd8', 3, 3,
   '{intelligence,wisdom}', 'wisdom',
   55, 30, 0, 12, 0,
   'A dry-humored healer who trusts moss more than maps and lectures her patients while stitching them.'),

  ('5eed0001-0000-4000-a000-000000000003', 'Órla', null,
   'Bard', 'College of Lore', 3, 'Half-Elf', 'Entertainer', 'chaotic_good',
   8, 15, 14, 12, 10, 17,
   13, 30, 24, 24,
   'd8', 3, 3,
   '{dexterity,charisma}', 'charisma',
   0, 8, 0, 25, 2,
   'A collector of other people''s stories who repays them in better versions; talks her way through most doors.'),

  ('5eed0001-0000-4000-a000-000000000004', 'Senán', null,
   'Warlock', 'The Fiend', 3, 'Tiefling', 'Sage', 'chaotic_neutral',
   8, 13, 14, 13, 10, 17,
   12, 30, 24, 24,
   'd8', 3, 3,
   '{wisdom,charisma}', 'charisma',
   26, 0, 10, 18, 0,
   'A polite scholar with an impolite patron; reads the fine print aloud so everyone hears what they agree to.')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Skills (row = proficient; expertise doubles proficiency bonus)
-- ---------------------------------------------------------------------------
-- Rónal: 2 class (Athletics, Perception) + Soldier background (Intimidation;
--   Athletics overlap re-picked into the class choices).
-- Tuala: 2 class (Nature, Perception) + Hermit background (Medicine, Religion).
-- Órla: 3 class + 2 half-elf + 3 College of Lore (see header).
-- Senán: 2 class (Arcana, Deception) + Sage background (History, Investigation;
--   Sage's Arcana overlap re-picked as Investigation).

insert into rpg.character_skills (character_id, skill, expertise) values
  -- Rónal
  ('5eed0001-0000-4000-a000-000000000001', 'athletics',       false),
  ('5eed0001-0000-4000-a000-000000000001', 'perception',      false),
  ('5eed0001-0000-4000-a000-000000000001', 'intimidation',    false),
  -- Tuala
  ('5eed0001-0000-4000-a000-000000000002', 'nature',          false),
  ('5eed0001-0000-4000-a000-000000000002', 'perception',      false),
  ('5eed0001-0000-4000-a000-000000000002', 'medicine',        false),
  ('5eed0001-0000-4000-a000-000000000002', 'religion',        false),
  -- Órla (expertise: Performance, Persuasion — bard level 3)
  ('5eed0001-0000-4000-a000-000000000003', 'performance',     true),
  ('5eed0001-0000-4000-a000-000000000003', 'persuasion',      true),
  ('5eed0001-0000-4000-a000-000000000003', 'deception',       false),
  ('5eed0001-0000-4000-a000-000000000003', 'insight',         false),
  ('5eed0001-0000-4000-a000-000000000003', 'perception',      false),
  ('5eed0001-0000-4000-a000-000000000003', 'acrobatics',      false),
  ('5eed0001-0000-4000-a000-000000000003', 'sleight_of_hand', false),
  ('5eed0001-0000-4000-a000-000000000003', 'history',         false),
  -- Senán
  ('5eed0001-0000-4000-a000-000000000004', 'arcana',          false),
  ('5eed0001-0000-4000-a000-000000000004', 'deception',       false),
  ('5eed0001-0000-4000-a000-000000000004', 'history',         false),
  ('5eed0001-0000-4000-a000-000000000004', 'investigation',   false)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

insert into rpg.character_items (id, character_id, name, quantity, equipped, attuned, notes) values
  -- Rónal (fighter)
  ('5eed0002-0000-4000-a000-000000000001', '5eed0001-0000-4000-a000-000000000001', 'Chain Mail',            1, true,  false, 'AC 16, heavy; disadvantage on Stealth checks'),
  ('5eed0002-0000-4000-a000-000000000002', '5eed0001-0000-4000-a000-000000000001', 'Shield',                1, true,  false, '+2 AC'),
  ('5eed0002-0000-4000-a000-000000000003', '5eed0001-0000-4000-a000-000000000001', 'Longsword',             1, true,  false, '1d8 slashing, versatile (1d10)'),
  ('5eed0002-0000-4000-a000-000000000004', '5eed0001-0000-4000-a000-000000000001', 'Light Crossbow',        1, false, false, '1d8 piercing, range 80/320, loading, two-handed'),
  ('5eed0002-0000-4000-a000-000000000005', '5eed0001-0000-4000-a000-000000000001', 'Crossbow Bolts',       20, false, false, null),
  ('5eed0002-0000-4000-a000-000000000006', '5eed0001-0000-4000-a000-000000000001', 'Dungeoneer''s Pack',    1, false, false, null),
  ('5eed0002-0000-4000-a000-000000000007', '5eed0001-0000-4000-a000-000000000001', 'Worn Campaign Medal',   1, false, false, 'flavor item; keeps it polished, never says which war'),
  -- Tuala (druid)
  ('5eed0002-0000-4000-a000-000000000008', '5eed0001-0000-4000-a000-000000000002', 'Leather Armor',         1, true,  false, 'AC 11 + Dex modifier'),
  ('5eed0002-0000-4000-a000-000000000009', '5eed0001-0000-4000-a000-000000000002', 'Shield (wooden)',       1, true,  false, '+2 AC; non-metal, per druid custom'),
  ('5eed0002-0000-4000-a000-000000000010', '5eed0001-0000-4000-a000-000000000002', 'Scimitar',              1, false, false, '1d6 slashing, finesse, light'),
  ('5eed0002-0000-4000-a000-000000000011', '5eed0001-0000-4000-a000-000000000002', 'Quarterstaff',          1, false, false, '1d6 bludgeoning, versatile (1d8)'),
  ('5eed0002-0000-4000-a000-000000000012', '5eed0001-0000-4000-a000-000000000002', 'Sprig of Mistletoe',    1, true,  false, 'druidic focus'),
  ('5eed0002-0000-4000-a000-000000000013', '5eed0001-0000-4000-a000-000000000002', 'Explorer''s Pack',      1, false, false, null),
  ('5eed0002-0000-4000-a000-000000000014', '5eed0001-0000-4000-a000-000000000002', 'Herbalism Kit',         1, false, false, null),
  ('5eed0002-0000-4000-a000-000000000015', '5eed0001-0000-4000-a000-000000000002', 'Pressed-Flower Journal',1, false, false, 'flavor item; one flower from every place she has slept'),
  -- Órla (bard)
  ('5eed0002-0000-4000-a000-000000000016', '5eed0001-0000-4000-a000-000000000003', 'Leather Armor',         1, true,  false, 'AC 11 + Dex modifier'),
  ('5eed0002-0000-4000-a000-000000000017', '5eed0001-0000-4000-a000-000000000003', 'Rapier',                1, true,  false, '1d8 piercing, finesse'),
  ('5eed0002-0000-4000-a000-000000000018', '5eed0001-0000-4000-a000-000000000003', 'Dagger',                1, false, false, '1d4 piercing, finesse, light, thrown (20/60)'),
  ('5eed0002-0000-4000-a000-000000000019', '5eed0001-0000-4000-a000-000000000003', 'Lute',                  1, false, false, 'musical instrument; bardic spellcasting focus'),
  ('5eed0002-0000-4000-a000-000000000020', '5eed0001-0000-4000-a000-000000000003', 'Diplomat''s Pack',      1, false, false, null),
  ('5eed0002-0000-4000-a000-000000000021', '5eed0001-0000-4000-a000-000000000003', 'Deck of Cards (one missing)', 1, false, false, 'flavor item; she will not say which card, or why'),
  -- Senán (warlock)
  ('5eed0002-0000-4000-a000-000000000022', '5eed0001-0000-4000-a000-000000000004', 'Leather Armor',         1, true,  false, 'AC 11 + Dex modifier'),
  ('5eed0002-0000-4000-a000-000000000023', '5eed0001-0000-4000-a000-000000000004', 'Dagger',                2, false, false, '1d4 piercing, finesse, light, thrown (20/60)'),
  ('5eed0002-0000-4000-a000-000000000024', '5eed0001-0000-4000-a000-000000000004', 'Rod (arcane focus)',    1, true,  false, 'warlock spellcasting focus'),
  ('5eed0002-0000-4000-a000-000000000025', '5eed0001-0000-4000-a000-000000000004', 'Scholar''s Pack',       1, false, false, null),
  ('5eed0002-0000-4000-a000-000000000026', '5eed0001-0000-4000-a000-000000000004', 'Brass Key',             1, false, false, 'flavor item; fits no lock found so far')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Spell slots
-- Level-3 full casters (druid, bard): 4x 1st, 2x 2nd, kind 'standard'.
-- Level-3 warlock Pact Magic: 2 slots, both 2nd level, kind 'pact'.
-- Rónal (fighter, Champion) correctly has zero rows here.
-- ---------------------------------------------------------------------------

insert into rpg.character_spell_slots (character_id, slot_kind, slot_level, slots_total, slots_expended) values
  ('5eed0001-0000-4000-a000-000000000002', 'standard', 1, 4, 0),  -- Tuala
  ('5eed0001-0000-4000-a000-000000000002', 'standard', 2, 2, 0),
  ('5eed0001-0000-4000-a000-000000000003', 'standard', 1, 4, 0),  -- Órla
  ('5eed0001-0000-4000-a000-000000000003', 'standard', 2, 2, 0),
  ('5eed0001-0000-4000-a000-000000000004', 'pact',     2, 2, 0)   -- Senán
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Spells (spell_level 0 = cantrip; all names from the 5e SRD lists)
-- Tuala prepares WIS mod (3) + level (3) = 6 leveled spells; circle spells free.
-- Órla knows 6 spells + 2 cantrips (known-caster: everything stays prepared).
-- Senán knows 4 spells + 2 cantrips; racials noted.
-- ---------------------------------------------------------------------------

insert into rpg.character_spells (id, character_id, name, spell_level, prepared, notes) values
  -- Tuala (druid, Circle of the Land — Forest)
  ('5eed0003-0000-4000-a000-000000000001', '5eed0001-0000-4000-a000-000000000002', 'Druidcraft',     0, true, null),
  ('5eed0003-0000-4000-a000-000000000002', '5eed0001-0000-4000-a000-000000000002', 'Produce Flame',  0, true, null),
  ('5eed0003-0000-4000-a000-000000000003', '5eed0001-0000-4000-a000-000000000002', 'Guidance',       0, true, 'bonus cantrip from Circle of the Land'),
  ('5eed0003-0000-4000-a000-000000000004', '5eed0001-0000-4000-a000-000000000002', 'Cure Wounds',    1, true, null),
  ('5eed0003-0000-4000-a000-000000000005', '5eed0001-0000-4000-a000-000000000002', 'Healing Word',   1, true, null),
  ('5eed0003-0000-4000-a000-000000000006', '5eed0001-0000-4000-a000-000000000002', 'Entangle',       1, true, null),
  ('5eed0003-0000-4000-a000-000000000007', '5eed0001-0000-4000-a000-000000000002', 'Faerie Fire',    1, true, null),
  ('5eed0003-0000-4000-a000-000000000008', '5eed0001-0000-4000-a000-000000000002', 'Thunderwave',    1, true, null),
  ('5eed0003-0000-4000-a000-000000000009', '5eed0001-0000-4000-a000-000000000002', 'Flaming Sphere', 2, true, null),
  ('5eed0003-0000-4000-a000-000000000010', '5eed0001-0000-4000-a000-000000000002', 'Barkskin',       2, true, 'circle spell (Forest): always prepared, free of prepared cap'),
  ('5eed0003-0000-4000-a000-000000000011', '5eed0001-0000-4000-a000-000000000002', 'Spider Climb',   2, true, 'circle spell (Forest): always prepared, free of prepared cap'),
  -- Órla (bard, College of Lore)
  ('5eed0003-0000-4000-a000-000000000012', '5eed0001-0000-4000-a000-000000000003', 'Vicious Mockery', 0, true, null),
  ('5eed0003-0000-4000-a000-000000000013', '5eed0001-0000-4000-a000-000000000003', 'Mage Hand',       0, true, null),
  ('5eed0003-0000-4000-a000-000000000014', '5eed0001-0000-4000-a000-000000000003', 'Charm Person',    1, true, null),
  ('5eed0003-0000-4000-a000-000000000015', '5eed0001-0000-4000-a000-000000000003', 'Healing Word',    1, true, null),
  ('5eed0003-0000-4000-a000-000000000016', '5eed0001-0000-4000-a000-000000000003', 'Sleep',           1, true, null),
  ('5eed0003-0000-4000-a000-000000000017', '5eed0001-0000-4000-a000-000000000003', 'Faerie Fire',     1, true, null),
  ('5eed0003-0000-4000-a000-000000000018', '5eed0001-0000-4000-a000-000000000003', 'Invisibility',    2, true, null),
  ('5eed0003-0000-4000-a000-000000000019', '5eed0001-0000-4000-a000-000000000003', 'Shatter',         2, true, null),
  -- Senán (warlock, The Fiend)
  ('5eed0003-0000-4000-a000-000000000020', '5eed0001-0000-4000-a000-000000000004', 'Eldritch Blast',   0, true, null),
  ('5eed0003-0000-4000-a000-000000000021', '5eed0001-0000-4000-a000-000000000004', 'Prestidigitation', 0, true, null),
  ('5eed0003-0000-4000-a000-000000000022', '5eed0001-0000-4000-a000-000000000004', 'Hex',              1, true, null),
  ('5eed0003-0000-4000-a000-000000000023', '5eed0001-0000-4000-a000-000000000004', 'Charm Person',     1, true, null),
  ('5eed0003-0000-4000-a000-000000000024', '5eed0001-0000-4000-a000-000000000004', 'Misty Step',       2, true, null),
  ('5eed0003-0000-4000-a000-000000000025', '5eed0001-0000-4000-a000-000000000004', 'Hold Person',      2, true, null),
  ('5eed0003-0000-4000-a000-000000000026', '5eed0001-0000-4000-a000-000000000004', 'Thaumaturgy',      0, true, 'tiefling Infernal Legacy (racial cantrip, Charisma)'),
  ('5eed0003-0000-4000-a000-000000000027', '5eed0001-0000-4000-a000-000000000004', 'Hellish Rebuke',   1, true, 'tiefling Infernal Legacy: cast at 2nd level, once per long rest')
on conflict do nothing;

commit;
