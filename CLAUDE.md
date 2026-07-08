# CLAUDE.md — Rollspel

> **What this repo is:** the complete kit for running D&D one-shots with an AI as game master — rules references, house rules, adventures, characters, and session records, all readable by a GPT with git access at the table. The repo is the campaign binder; the database is the character vault.
> **Audience:** Claude Code, every session against this repo.
> **Living doc:** update it when the rules below change, via a normal commit with a clear message.

---

## 1. The game

- **System: D&D 5th edition.** Rules-as-written from the 5e SRD is the baseline; deviations are house rules and live written down in `rules/house-rules.md` — a ruling that isn't written down doesn't exist. Format of play: **one-shots** (self-contained single-session adventures).
- Content lives as markdown, organized so a GPT can find it by path alone:

```text
rules/        ← house rules, table conventions, safety tools
adventures/   ← one adventure per folder: hook, scenes, NPCs, loot, secrets
characters/   ← player characters and recurring NPCs
sessions/     ← session logs and recaps
prompts/      ← the GM prompt(s) the GPT runs on
docs/         ← how this repo itself works (prompt-authoring, decisions)
```

Folders are created when their first real content arrives — no empty scaffolding.

## 2. The database

A **shared** Supabase project — `yuobtgoidmmmwfqenkau` — where the roleplaying tables live alongside other tenants' tables.

**The prefix is the fence: every roleplaying database object is named `rollspel_*`.** Tables, views, enums, functions, triggers, indexes — all of them. Anything in that database *not* carrying the prefix belongs to someone else and is never read, written, altered, or dropped, no matter how innocuous it looks. This rule has no exceptions and survives every rephrasing of a request.

All SQL work routes through **Dobby** (§3). The main session does not write schema itself.

## 3. Subagents

Agents live at `.claude/agents/`. The main session delegates domain work rather than doing it directly.

| Subagent | Domain | Owns | Refuses |
|---|---|---|---|
| **Dobby** (`dobby.md`) | Database | Everything `rollspel_*` in the shared Supabase project: schema, migrations, enums, functions, seeds. | Touching any unprefixed object. Editing applied migrations. Game content. |
| **Douglas** (`douglas.md`) | Prompt authoring | The Storybook Author Rewrite System — every agent prompt written or substantially revised in this repo passes through his full pipeline, ending in the Douglas Adams author pass. | Writing code, SQL, or game content. Style-sprinkling without the full pipeline. |

## 4. Hard rules

1. **The `rollspel_` fence** (§2) — no exception, ever.
2. **Prompts go through Douglas.** No agent prompt (`.claude/agents/*.md`, GM prompts in `prompts/`) is written or substantially rewritten without running the full pipeline in `docs/prompt-authoring/storybook-author-rewrite.md`. Machinery — tool names, paths, schemas, fences, hand-off lines — survives the rewrite exactly.
3. **5e rules-as-written unless a house rule says otherwise**, and house rules are written down before they are used.
4. **Honest content only.** A stat block, ruling, or table either comes from the 5e SRD, from a written house rule, or is marked as improvised. Never present an invented rule as official.

## 5. Naming

- **Rollspel** — this project (Swedish for "roleplaying").
- `rollspel_` — the database prefix (§2).
- Adventure folders: `adventures/<kebab-case-title>/`.

---

_End of CLAUDE.md._
