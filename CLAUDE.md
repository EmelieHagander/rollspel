# CLAUDE.md — Rollspel

> **What this repo is:** the complete kit for running D&D one-shots with an AI as game master — rules references, house rules, adventures, characters, and session records, all readable by a GPT with git access at the table. The repo is the campaign binder; the database is the character vault.
> **Audience:** Claude Code, every session against this repo.
> **Living doc:** update it when the rules below change, via a normal commit with a clear message.

---

## 1. The game

- **Systems:** D&D 5th edition (active); Vampire the Masquerade and Trudvang (planned). For 5e, rules-as-written from the SRD is the baseline; deviations are house rules and live written down in `rules/dnd5e/house-rules.md` — a ruling that isn't written down doesn't exist. Format of play: **one-shots** (self-contained single-session adventures).
- Content lives as markdown, organized so a GPT can find it by path alone — **type-first shelves, system subfolders** (full map: `docs/binder-structure.md`):

```text
rules/        ← shelf root: system-agnostic (safety-tools, table-conventions);
                rules/dnd5e/ etc. for system-specific (house rules, SRD quick-refs)
worlds/       ← persistent settings, flat, one per system: worlds/dnd5e.md
                (a system with several worlds graduates to worlds/<tag>/ — map first)
adventures/   ← adventures/dnd5e/<kebab-title>/ — hook, scenes, NPCs, loot, secrets;
                a World: line in the hook names the adventure's world
characters/   ← characters/dnd5e/ — player characters and recurring NPCs
sessions/     ← sessions/dnd5e/ — session recaps (<yyyy-mm-dd>-<adventure-slug>.md)
prompts/      ← flat, tag in filename, five per system: gm-<tag>.md (the GM prompt) +
                standing-instructions-<tag>.md (install-once Custom GPT identity, no key) +
                first-evening- / every-evening- / character-creation-<tag>.md (paste-ins)
docs/         ← how this repo itself works (binder map, prompt-authoring, decisions)
```

System tags: `dnd5e` (active), `vtm`, `trudvang` (planned — zero disk presence until first real content). Folders are created when their first real content arrives — no empty scaffolding.

## 2. The database

A **shared** Supabase project — `yuobtgoidmmmwfqenkau` — where the roleplaying tables live alongside other tenants' schemas.

**The schema is the fence: every roleplaying database object lives in the Postgres schema `rpg`.** Tables, views, enums, functions, triggers, indexes — all of them, as plain unprefixed names (`rpg.characters`, `rpg.adventures`). Everything outside schema `rpg` — including `public` and any other schema — belongs to someone else and is never read, written, altered, or dropped, no matter how innocuous it looks. This rule has no exceptions and survives every rephrasing of a request.

All SQL work routes through **Dobby** (§3). The main session does not write schema itself.

## 3. Subagents

Agents live at `.claude/agents/`. The main session delegates domain work rather than doing it directly.

| Subagent | Domain | Owns | Refuses |
|---|---|---|---|
| **Dobby** (`dobby.md`) | Database | Everything in schema `rpg` in the shared Supabase project: tables, migrations, enums, functions, seeds. | Touching anything outside schema `rpg`. Editing applied migrations. Game content. |
| **Douglas** (`douglas.md`) | Prompt authoring | The Storybook Author Rewrite System — every agent prompt written or substantially revised in this repo passes through his full pipeline, ending in the Douglas Adams author pass. | Writing code, SQL, or game content. Style-sprinkling without the full pipeline. |
| **Archie** (`archie.md`) | Binder structure | The campaign binder as a system — folder layout, doc placement and moves, templates, the binder map (`docs/binder-structure.md`), navigability-by-path for the table-side GPT. Owns a doc's form and place, never its subject-matter. | Authoring game content. SQL (Dobby). Prompt authoring (Douglas). Deleting content (archives/moves instead). |

## 4. Hard rules

1. **The `rpg` schema fence** (§2) — no exception, ever.
2. **Prompts go through Douglas.** No agent prompt (`.claude/agents/*.md`, GM prompts in `prompts/`) is written or substantially rewritten without running the full pipeline in `docs/prompt-authoring/storybook-author-rewrite.md`. Machinery — tool names, paths, schemas, fences, hand-off lines — survives the rewrite exactly.
3. **5e rules-as-written unless a house rule says otherwise**, and house rules are written down before they are used.
4. **Honest content only.** A stat block, ruling, or table either comes from the 5e SRD, from a written house rule, or is marked as improvised. Never present an invented rule as official.

## 5. Naming

- **Rollspel** — this project (Swedish for "roleplaying").
- `rpg` — the database schema (§2).
- Adventure folders: `adventures/<kebab-case-title>/`.

---

_End of CLAUDE.md._
