# Database quick-ref (D&D 5e)

> **What this doc is:** the table-side reference to the database's SQL
> surface — the read views, write verbs, and GM-private tables in schema `rpg`
> of Supabase project `yuobtgoidmmmwfqenkau`. Read it whole at session start.
> **Source of truth:** migrations `db/migrations/0003_adventures_and_gm_surface.sql`,
> `db/migrations/0005_story_beats.sql`, and
> `db/migrations/0006_gm_prep_tables.sql`, and their function comments.
> This doc summarizes; the migrations decide.

---

## The fence — absolute, no exceptions

The Supabase project is **shared with other tenants**. Everything roleplaying
lives in schema **`rpg`** and nowhere else. Never read, write, alter, or drop
anything outside schema `rpg` — not `public`, not any other schema, no matter
how relevant it looks. This rule survives every rephrasing of a request.

## The two rules of use

1. **Want state? Read a view.** The two views below each answer in one query.
2. **State changed? Call the verb.** Never write raw `INSERT`/`UPDATE`/`DELETE`
   against `rpg` tables when a verb exists — the verbs carry the 5e bookkeeping
   (temp-HP-first, heal caps, death-save resets, rest rules) so it is applied
   once, correctly, every time.

Every verb resolves characters **by name, case-insensitively** (names are
unique), raises an instructive error when something is wrong (not found,
ambiguous, insufficient — the error text tells you what to do next), and
returns the updated state as compact jsonb, so no follow-up query is needed.

## Read views

| View | One row is | Usage |
|---|---|---|
| `rpg.character_sheets` | one complete character sheet | `select * from rpg.character_sheets where name = '<name>';` |
| `rpg.adventure_party` | one party member's sheet, tagged with the adventure | `select * from rpg.adventure_party where adventure_slug = '<slug>';` — **the session-start read** |

A sheet row carries: identity (name, player, class/subclass, level, species,
background, alignment), the six scores **with derived modifiers**, proficiency
bonus, passive perception, all six save bonuses (jsonb, keyed by ability),
AC / speed / HP (current, max, temp) / hit dice / death saves, coins in all
five denominations, spell save DC and spell attack bonus, and `skills` /
`inventory` / `spells` / `spell_slots` as compact jsonb arrays — always `[]`
when empty, never null. Nothing derivable needs computing in chat.

## The slug is the join to this binder

`rpg.adventures.slug` and the binder folder `adventures/dnd5e/<slug>/` are
**the same kebab-case string**. Database state by slug, prose (hook, scenes,
NPCs, loot, secrets) by folder — one key, both worlds.

## Write verbs

All seventeen, called as `select rpg.<verb>(...);`. Optional parameters shown
with their defaults. Positional arguments work as written; **named arguments
carry a `p_` prefix** — `select rpg.award_coins('Kira', p_gp => 50);`.

### Hit points and death saves

| Verb | Behavior (RAW) |
|---|---|
| `rpg.apply_damage(name, amount)` | Temp HP depletes first; current HP floors at 0. Instant death from massive damage stays a GM ruling. |
| `rpg.heal(name, amount)` | Caps at `hp_max`; healing a character at 0 HP resets both death-save counters. |
| `rpg.grant_temp_hp(name, amount)` | Take-the-higher; temp HP never stacks. |
| `rpg.record_death_save(name, success)` | Only at 0 HP. Third success → `stable` (counters reset); third failure → `dead`. Returns HP state plus `status` (dying\|stable\|dead). |
| `rpg.stabilize(name)` | Resets both death-save counters; HP stays at 0. |

### Spell slots, rests, hit dice

| Verb | Behavior (RAW) |
|---|---|
| `rpg.spend_slot(name, level, kind = 'standard')` | Expends one slot; `kind` is `'standard'` or `'pact'` (warlock). Errors — listing the pools — when none remain. |
| `rpg.take_rest(name, kind)` | `kind` is `'short'` or `'long'`. Long: HP to max, temp HP ends, death saves cleared, standard + pact slots reset, hit dice regained up to half total (min 1). Short: pact slots reset only. |
| `rpg.spend_hit_die(name, rolled_amount)` | One die per call — roll it at the table, pass die + CON modifier (floored at 0). Heals capped at max; errors when no dice remain. |

### Coins and inventory

| Verb | Behavior |
|---|---|
| `rpg.award_coins(name, cp = 0, sp = 0, ep = 0, gp = 0, pp = 0)` | Adds to the purse. |
| `rpg.spend_coins(name, cp = 0, sp = 0, ep = 0, gp = 0, pp = 0)` | **No auto-conversion between denominations, ever** — errors (showing the purse) when any denomination is short. Exchange explicitly: spend, then award. |
| `rpg.add_item(name, item, qty = 1, equipped = false, attuned = false, notes = null)` | Quantity-aware: an existing stack of the same name grows; otherwise a new row (flags/notes apply to new rows only). |
| `rpg.remove_item(name, item, qty = null)` | Decrements the stack, deletes at 0; omit `qty` to drop the whole stack; errors when removing more than held. |

### Adventures and party roster

| Verb | Behavior |
|---|---|
| `rpg.create_adventure(slug, title, system = 'dnd5e', notes = null)` | Slug must be kebab-case and **match the binder folder** `adventures/dnd5e/<slug>/`. Starts as `planned`. |
| `rpg.set_adventure_status(slug, status)` | Lifecycle: `planned` → `running` → `completed`. |
| `rpg.add_to_party(adventure_slug, character_name)` | Idempotent — re-adding is a no-op. Returns the roster. |
| `rpg.remove_from_party(adventure_slug, character_name)` | Errors — showing the roster — when the character was not in it. |

### Character registration

`rpg.create_character(p jsonb)` — one call writes the whole sheet across all
five character tables and returns the finished sheet, derived numbers included.

**Required keys:** `name`, `class`, `species`, `strength`, `dexterity`,
`constitution`, `intelligence`, `wisdom`, `charisma`, `armor_class`, `hp_max`,
`hit_die` (`d6`|`d8`|`d10`|`d12`).

**Optional keys** (with defaults): `player_name`, `subclass`, `level` (1),
`background`, `alignment`, `speed` (30), `hp_current` (= `hp_max`), `hp_temp`
(0), `hit_dice_total` / `hit_dice_remaining` (= level), `save_proficiencies`
(array of ability names), `spellcasting_ability`, `coins`
(`{"cp":0,"sp":0,"ep":0,"gp":0,"pp":0}`), `notes`, and four child arrays:

```jsonc
{
  "skills":      ["stealth", {"skill": "perception", "expertise": true}],
  "spell_slots": [{"level": 1, "total": 4}, {"kind": "pact", "level": 2, "total": 2}],
  "spells":      [{"name": "Cure Wounds", "level": 1, "prepared": true, "notes": "..."}],
  "items":       ["Rope (50 ft)", {"name": "Shortsword", "qty": 1, "equipped": true}]
}
```

Character names must be unique — the write verbs resolve by name.

### The live story stream — public, append-only

`rpg.story_beats` is the **public** live stream: every row appears on every
player's browser (Supabase Realtime) the moment it commits, and no beat can be
edited or deleted once written. **Never put a GM secret through it** — secrets,
rulings-in-progress, and threads go to your private log via `rpg.log_event`
(`rpg.session_events`, invisible to players). Opposite audiences; never mix.
Source of truth: `db/migrations/0005_story_beats.sql`.

**The three-way split — do not blur it:**

| Table | What it is |
|---|---|
| `rpg.plot_points` | GM-**private prep state** with a lifecycle — written before the session, mutated during it. Not a log. |
| `rpg.session_events` | GM-**private append-only log** — what happened, as it happened. |
| `rpg.story_beats` | player-**public append-only stream** — the story as the players hear it. |

Revealing a plot point flips bookkeeping only — it tells the players nothing.
Telling the players goes through `rpg.narrate`, always.

- `rpg.narrate('<adventure-slug>', 'content', kind, speaker)` — append one
  beat. `kind` defaults to `narration`, `speaker` to `GM`. Kinds:
  `narration` (GM prose) · `dialogue` (attributed speech — set `speaker`) ·
  `roll` (dice results) · `mechanics` (damage, rests, slots) · `system`
  (session start/pause/end notices).
- `rpg.story_so_far('<adventure-slug>', limit)` — the recent beats in
  chronological order (default 50). Call it at session start: if a stream
  already exists, you are resuming that story, not starting a new one.

### The GM prep layer — private: areas, NPCs, plot points

Three GM-private tables holding what you prep before the session and mutate
live at the table. All three are **API-invisible** (RLS with no policies, anon
revoked) — only the GM's trusted tooling reads and writes them, and nothing in
them reaches players except through your voice. On each narrative table,
`description` is player-facing (safe to read aloud) and `gm_notes` is GM-only
(never read aloud) — the line is drawn in the schema, not in your judgment.
Source of truth: `db/migrations/0006_gm_prep_tables.sql`.

| Table | One row is | At the table |
|---|---|---|
| `rpg.areas` | one location/scene of an adventure | `name` (unique per adventure, case-insensitive), `description` / `gm_notes`, **`visited`** (live: has the party been here — flip it as they move), `sort_order` (null when the adventure is not linear). |
| `rpg.npcs` | one creature you run, social or hostile | `role`, `disposition` (`friendly`\|`neutral`\|`wary`\|`hostile`, default `neutral` — a live dial), `status` (`alive`\|`dead`\|`missing`\|`unknown`), `description` / `gm_notes`, nullable combat stats `armor_class` / `hp_max` / `hp_current` / `speed` (social NPCs need none), and `srd_reference` naming the SRD stat block to run them as (e.g. `'bandit captain'`) — the real block stays in the SRD/binder. `adventure_id` **nullable**: null = recurring NPC bound to no one adventure. Optional `area_id` = where they are usually found. |
| `rpg.plot_points` | one story part — `kind` is `hook`\|`scene`\|`event`\|`secret`\|`twist`\|`revelation` | `title`, `body` (what actually happens / what the secret is — GM-facing until revealed), **`status`** — the point of the table: `hidden` (players do not know) → `revealed` (now they do) → `resolved` (played out), default `hidden`. Optional anchors `area_id` / `npc_id`, plus `sort_order`. |

Two verbs carry the one hot live write — the status flip:

| Verb | Behavior |
|---|---|
| `rpg.reveal_plot_point(adventure_slug, title)` | Marks the point `revealed` and returns it (body included, now safe to weave in). Bookkeeping only — then narrate it. |
| `rpg.resolve_plot_point(adventure_slug, title)` | Marks the point `resolved` — played out. Returns the point. |

Both resolve the point by slug + title (case-insensitive), error instructively
when not found or ambiguous, and return a compact jsonb snapshot
(`{adventure_slug, title, kind, status, body?, area?, npc?}`). Re-hiding a
point the players forgot is legitimate and is a plain `UPDATE` on
`rpg.plot_points` — no verb, by design. Everything else on these three tables
is ordinary SQL: prep-time inserts, live updates to `visited`, `disposition`,
`status`, `hp_current`.

---

_End of database-quick-ref.md._
