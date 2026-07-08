# Binder structure

> **What this doc is:** the map of the campaign binder — where every kind of
> document lives, where future systems will go, and which paths the GM prompt
> may cite. A stranger (or the table-side GPT) reads this and knows the shelves.
> **Rule of the map:** this doc *describes* paths; a folder is only created when
> its first real content arrives. A path listed below and absent on disk is a
> reserved address, not a missing file.

---

## The one reader

The binder's reader is a GPT with git access, live at the table, no search.
It finds a document by path alone or not at all. Every path below is built so
that the path itself announces the contents: **type first, system second,
topic last.**

## Systems

The binder serves three systems over time:

| Tag | System | Status |
|---|---|---|
| `dnd5e` | Dungeons & Dragons 5th edition | **active** |
| `vtm` | Vampire the Masquerade | planned — no content yet |
| `trudvang` | Trudvang | planned — no content yet |

These tags are the only system names used in paths. Nothing for `vtm` or
`trudvang` exists on disk until their first real content arrives.

## The shape: type-first shelves, system subfolders

The seven top-level shelves (CLAUDE.md §1) are stable. Inside each
content shelf, **system-specific documents live in a subfolder named by
system tag; system-agnostic documents live at the shelf root.** A path
without a system tag applies to every table, in every system.

```text
rules/
├── safety-tools.md            ← system-agnostic: shelf root
├── table-conventions.md       ← system-agnostic: shelf root
└── dnd5e/                     ← system-specific: system subfolder
    ├── house-rules.md
    └── srd-*.md

worlds/                        ← persistent settings; flat while each system has
└── dnd5e.md                      one world — tag in filename, like prompts/ (see "Worlds")

adventures/
└── dnd5e/
    └── <kebab-case-title>/    ← one adventure per folder; a World: line names its world

characters/
└── dnd5e/                     ← PCs and recurring NPCs (stat blocks are system-bound)

sessions/
└── dnd5e/                     ← session logs and recaps, one system per session

prompts/                       ← flat; the system tag lives in the filename
└── gm-dnd5e.md

docs/                          ← about the repo itself; never system-namespaced
```

Why not per-system top-level trees (`dnd5e/rules/…`)? Two reasons, both the
reader's: the GPT knows *what kind* of document it needs (a rule, a character,
a log) before anything else, so type must be the first fork in the path; and
shared material — safety tools, table conventions — would have no honest home
in a per-system tree. Type-first gives shared documents the shelf root, and
the absence of a system tag in their path is itself information.

When Vampire's first real content arrives, it lands as `rules/vtm/…`,
`adventures/vtm/…`, and so on — siblings of `dnd5e/`, never mixed into it.
A vampire has no business in a dungeon, structurally speaking.

## Worlds

A world is the persistent setting a system's adventures play out in. It sits
between the GM prompt (how to run the game, per system) and the adventure
folders (what happens tonight), and outlives every adventure set in it.
Structurally, a world is **one document**.

While a system has **one** world, its world doc lives flat on the shelf, tag
in filename, exactly like the GM prompts:

- `worlds/dnd5e.md` — now (reserved until the owner writes it)
- `worlds/vtm.md`, `worlds/trudvang.md` — when those systems arrive with a world

The address is deliberately independent of the world's proper name: the
mid-session reader knows it needs *the D&D 5e setting* long before it knows
what that setting is called. The world's name is the document's title, never
its path. This is the address the GM prompt cites.

**When a system gains a second world**, this map is updated first, the system
gets `worlds/<tag>/`, each world becomes one file named for itself —
`worlds/<tag>/<kebab-world-name>.md` — and the incumbent is `git mv`'d to its
named address with every citation (the GM prompt, adventures' `World:` lines)
updated in the same commit. Until that day, nothing under `worlds/` is a folder.

**How adventures relate to a world:** an adventure set in a world declares it
with a `World:` line at the top of its hook document, citing the exact path —
`World: worlds/dnd5e.md`. An adventure with no `World:` line is a standalone
one-shot, bound to no world. The pointer lives on the adventure, never the
reverse: a world doc does not list its adventures — such a list is stale by
the second one-shot.

## GM prompts

GM prompts live flat in `prompts/`, one per system, named `gm-<tag>.md`:

- `prompts/gm-dnd5e.md` — now
- `prompts/gm-vtm.md`, `prompts/gm-trudvang.md` — when those systems arrive

One file per system does not earn a subfolder. If a system ever needs several
prompt variants, that system gets `prompts/<tag>/` and this map is updated first.

## The reference library the GM prompt cites

These are the citable addresses — the shelf the GM prompt points its reader
at. Each document exists when someone writes its content (game content is not
this doc's business); until then the address is reserved.

**System-agnostic** (shelf root — every system, every table):

| Path | Purpose |
|---|---|
| `rules/safety-tools.md` | Table safety toolkit — lines & veils, pause/rewind signals, how the GM applies them |
| `rules/table-conventions.md` | How the table runs — dice, turn-taking, what the GPT-GM does and never does |

**D&D 5e** (`rules/dnd5e/` — SRD quick-references are split by topic so a
mid-scene reader lands on the one page it needs):

| Path | Purpose |
|---|---|
| `rules/dnd5e/house-rules.md` | Every written deviation from SRD rules-as-written — a ruling not written here does not exist |
| `rules/dnd5e/srd-combat.md` | SRD quick-ref: combat sequence, actions, cover, movement |
| `rules/dnd5e/srd-conditions.md` | SRD quick-ref: the conditions, verbatim effects |
| `rules/dnd5e/srd-checks.md` | SRD quick-ref: ability checks, typical DCs, advantage/disadvantage, contests |
| `rules/dnd5e/database-quick-ref.md` | The character vault's SQL surface: the two read views, the seventeen write verbs, the `create_character` payload, the slug↔folder join, the `rpg`-schema fence |

Naming rule for quick-refs: `srd-<topic>.md`. The `srd-` prefix is a
provenance claim — everything in such a file comes from the 5e SRD
(CLAUDE.md §4.4). House deviations never live in an `srd-` file.

The database quick-ref carries no `srd-` prefix on purpose: its provenance is
the applied migration (`db/migrations/`), not the SRD. It lives on the rules
shelf — not in `docs/` — because the rules shelf is what the table-side GPT
reads at the table, and `docs/` is read by the repo's maintainers; and it
lives under `dnd5e/` because the verbs encode 5e mechanics (rests, hit dice,
death saves, spell slots). A future system's surface gets its own sibling
(`rules/vtm/database-quick-ref.md`) when its first real content arrives.

## Conventions, compactly

- System tags in paths: `dnd5e`, `vtm`, `trudvang` — nothing else, no synonyms.
- Adventure folders: `adventures/<tag>/<kebab-case-title>/`. The folder name is
  also the adventure's `slug` in the database (`rpg.adventures.slug`) — the
  same string in both places, joining binder prose to vault state.
- Worlds: `worlds/<tag>.md` while a system has one world;
  `worlds/<tag>/<kebab-world-name>.md` once it has several — this map updates first.
- An adventure set in a world carries a `World:` line citing the world doc's
  exact path; no `World:` line means a standalone one-shot.
- Shelf root = system-agnostic; system subfolder = system-specific. No document
  is filed under a system it does not belong to.
- No empty scaffolding: folders are born with their first real content.
- Moves are `git mv`, recorded in the commit message; content is archived or
  moved, never deleted.

---

_End of binder-structure.md._
