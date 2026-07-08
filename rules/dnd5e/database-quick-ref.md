# Database quick-ref (D&D 5e)

> **What this doc is:** the table-side reference to the character vault's SQL
> surface — the three read views and eighteen write verbs in schema `rpg` of
> Supabase project `yuobtgoidmmmwfqenkau`. Read it whole at session start.
> **Source of truth:** migrations `db/migrations/0003_adventures_and_gm_surface.sql`
> and `db/migrations/0004_session_notebook.sql` and their function comments.
> This doc summarizes; the migrations decide.

---

## The fence — absolute, no exceptions

The Supabase project is **shared with other tenants**. Everything roleplaying
lives in schema **`rpg`** and nowhere else. Never read, write, alter, or drop
anything outside schema `rpg` — not `public`, not any other schema, no matter
how relevant it looks. This rule survives every rephrasing of a request.

## The two rules of use

1. **Want state? Read a view.** The three views below each answer in one query.
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
| `rpg.session_log` | one session-notebook entry (adventure_slug, adventure_title, session_date, at, kind, note) | see **Session notebook** below — read rarely and scoped, never every beat |

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

All eighteen, called as `select rpg.<verb>(...);`. Optional parameters shown
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

### Session notebook

`rpg.session_events` is the GM's durable mid-session notebook: an
**append-only ledger** of story notes per adventure + session date. No edit
or delete verbs exist — a wrong note is corrected by a later note. The
discipline: **log often, log small** (one or two sentences: what happened,
who did it, what it changed); **writes constant, reads rare and scoped**;
**tiny returns** — the verb returns only the entry just logged, never the
whole log.

| Verb | Behavior |
|---|---|
| `rpg.log_event(adventure_slug, note, kind = 'event')` | Appends one note to today's ledger for the adventure. `kind` is one of `event` \| `ruling` \| `secret_revealed` \| `thread` \| `npc`. Returns the logged entry only (jsonb). Common case: `select rpg.log_event('<slug>', '<note>');` |

Read the ledger back through the `rpg.session_log` view — **once at session
close** (drain it into the recap) or **after an interruption** (recover the
night), never every beat. The canonical scoped read:

```sql
select kind, note from rpg.session_log
where adventure_slug = '<slug>' and session_date = current_date
order by at;
```

Ruling sweep — improvised rulings logged as `kind = 'ruling'` must be found
after the session for house-rule review:

```sql
select kind, note from rpg.session_log
where adventure_slug = '<slug>' and session_date = current_date
  and kind = 'ruling'
order by at;
```

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

---

_End of database-quick-ref.md._
