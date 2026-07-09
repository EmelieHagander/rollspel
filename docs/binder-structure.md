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
├── gm-dnd5e.md                ← the GM prompt — read by path, mid-session
├── standing-instructions-dnd5e.md ← install-once Custom GPT identity (no blanks, no key)
├── first-evening-dnd5e.md     ← paste-in for a new table's FIRST evening
├── every-evening-dnd5e.md     ← paste-in address card for every later evening
└── character-creation-dnd5e.md ← paste-in character workshop, any day, no evening

docs/                          ← about the repo itself; never system-namespaced
└── how-to-run-an-evening.md   ← the owner's guide to both run-paths (webapp renders it)
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

- `worlds/dnd5e.md` — now (exists, `# Image style` included)
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

**The image style lives inside the world doc.** Every session-image prompt
starts from one standard style paragraph — the world's visual register, kept
in one place so all adventure images share one look. Its address is the
**reserved section `# Image style` inside `worlds/dnd5e.md`** — reserved in
the map's usual sense: the address is ruled here, the content is authored by
the owner/main session (it is game content, world-bound visual direction).
The GM prompt cites this address; the reader already holds the world doc when
it composes image prompts at close. If a system ever graduates to
`worlds/<tag>/`, each world file carries its own `# Image style` section —
the look belongs to the world, so it travels with the world.

**How adventures relate to a world:** an adventure set in a world declares it
with a `World:` line at the top of its hook document, citing the exact path —
`World: worlds/dnd5e.md`. An adventure with no `World:` line is a standalone
one-shot, bound to no world. The pointer lives on the adventure, never the
reverse: a world doc does not list its adventures — such a list is stale by
the second one-shot.

## Prompts

Prompts live flat in `prompts/`, tag in filename. A system's full set is
**five documents**, split by who reads them and when:

| Path | Reader, and when |
|---|---|
| `prompts/gm-<tag>.md` | The table-side GPT, by path, every session — the GM prompt itself: who to be and how to run the game. Both evening cards point their reader at it. |
| `prompts/standing-instructions-<tag>.md` | The owner installs it **once** — pasted into a Custom GPT's Instructions field, where it becomes the GPT's permanent identity — after which the table-side GPT carries it every session with no re-paste. Kin to `gm-<tag>.md` (a permanent identity the GPT *is*), not to the cards (per-occasion templates). The vault credentials live in the GPT's Actions configuration, never in the doc, so it holds **no key and no blanks** — and is therefore committed in full like `gm-<tag>.md`, untouched by the never-commit-the-filled-copy rule that guards the cards' key. |
| `prompts/first-evening-<tag>.md` | The owner, once per new table — copied, blanks filled, pasted into a fresh GPT for the **first** evening: the story kickoff, nothing more. The characters are already forged — that is the workshop card's work, done before game night — so this card connects binder and vault, verifies the table is ready (roster check against the vault; a forged-but-unattached character is attached; a character missing from the vault is **not** built tonight — the owner is sent to the workshop card and play proceeds with who is present), then opens the adventure as the GM prompt directs. |
| `prompts/every-evening-<tag>.md` | The owner, every **later** evening — the address card: where the binder and vault are, how to get in, what tonight's adventure and table are. |
| `prompts/character-creation-<tag>.md` | The owner and a player, **any time — no evening required**. Pasted into a fresh GPT, it is a standalone character-creation helper — **not a GM**, bound to no session: it builds characters at the player's pace (however many questions that takes), answers the system's rules questions along the way, saves finished characters to the vault, and files their binder dossiers. Self-contained; it never points at the GM prompt. |

Two of the five are permanent GM identities the table-side GPT *is*, not
cards the owner pastes per evening: `gm-<tag>.md`, which the GPT reads by
path mid-session, and `standing-instructions-<tag>.md`, which the owner
installs **once** into a Custom GPT and the GPT then carries unpasted. The
other three are the owner's per-occasion paste-in templates and answer one
question — *which do I paste?* — by name alone: a table's first evening,
`first-evening-`; any later evening, `every-evening-`; no evening at all,
just a character to build, `character-creation-`. Each is self-contained
(a first evening does not also need the address card; a Tuesday-lunch
character workshop needs no evening card at all).

**Two paths to the table, one GM.** `standing-instructions-<tag>.md` exists
because the owner's GM can run as a **Custom GPT**: the vault credentials
live in the GPT's Actions configuration (never in any prompt), so the
standing instructions carry no blanks and no key. Install them once and every
later evening opens with a single spoken sentence in a fresh chat — no card,
no fill-in, no key. This is the **install-once path**. The three
evening/character cards are the **paste-per-evening path** — the fallback for
a plain ChatGPT or Claude chat with no Actions and no git access, where the
owner fills each card's blanks (the key among them) and pastes it fresh each
time. The two paths are **siblings, not replacements**: both run through the
same `gm-<tag>.md`, and both build heroes through the same
`character-creation-<tag>.md`. For D&D 5e:

- `prompts/gm-dnd5e.md`, `prompts/standing-instructions-dnd5e.md`,
  `prompts/first-evening-dnd5e.md`, `prompts/every-evening-dnd5e.md`,
  `prompts/character-creation-dnd5e.md` — now
- the `vtm` and `trudvang` sets — when those systems arrive

*(History: `every-evening-dnd5e.md` was born `prompts/first-contact.md` and was
`git mv`'d when the true first-evening document arrived and took the "first"
name with better claim.)*

**A GM prompt is one document: charter and runtime protocol together.** The
prompt has two natures — who the GM is (soul, law, craft) and how it operates
turn by turn (turn loop, tool behavior, state read/write, secret visibility,
recap/save). Both instruct the same reader in the same session, so they travel
in the same file: the table-side GPT is handed exactly one path at session
start, has no search, and a companion file it must remember to fetch mid-scene
is a document lost, politely. For 5e, the runtime protocol's address is the
**reserved section `# Runtime protocol` inside `prompts/gm-dnd5e.md`** —
reserved in the map's usual sense: the address is ruled here, the content is
authored elsewhere (prompt content goes through Douglas, CLAUDE.md §4.2).

Four named files per system do not earn a subfolder — **ruled 2026-07-08**,
when the character-creation helper became the fourth. What triggers
`prompts/<tag>/` is prompt *variants*: several genuinely alternative prompts
for the **same seat** (two rival GM prompts, say), whose filenames could no
longer tell the reader which one to take. A new **seat** — a distinct
reader-and-occasion with its own unmistakable name, as the character
workshop is — extends the flat set instead: the trio is a quartet now and
may grow seat by seat, this map updating first each time. The honest limit
stands: the day the flat shelf stops answering *which do I paste?* by name
alone, that system graduates to `prompts/<tag>/`, this map updates first,
and every citation moves in the same commit. A runtime protocol is a
chapter, never a variant or a seat; it triggers nothing.

**The standing-instructions doc is a fifth seat, not a variant — ruled
2026-07-09.** It is a distinct reader-and-occasion (the Custom GPT's
permanent identity, installed once) with its own unmistakable name, so —
like the character workshop before it — it *extends* the flat set rather
than triggering `prompts/<tag>/`. The quartet is a quintet; the flat shelf
still answers *which do I paste?* by name across the three cards, and *what
do I install once?* has exactly one answer. The honest limit is unchanged.

**The close-down snippet is not a fifth card — ruled 2026-07-09.** The
closing ritual lives inside `prompts/gm-dnd5e.md` and the GM runs it
unprompted; the owner's "we're stopping tonight" nudge is one or two
sentences with no blanks, no key, and no addresses. What earns an evening
card its file is being a fill-the-blanks template; a two-sentence spoken
line filed beside them would read as a rival evening card and blur *which
do I paste?*. It therefore lives **inline in
`docs/how-to-run-an-evening.md`**, as a quoted snippet at the moment the
owner needs it — its spot is reserved there for **Douglas** to author
(prompt text goes through Douglas, CLAUDE.md §4.2). If the snippet ever
grows blanks or a key, it has become a template and graduates to
`prompts/close-evening-<tag>.md`, this map updating first.

**The owner's guide to both run-paths** is `docs/how-to-run-an-evening.md` —
one page, human-facing (the owner's webapp renders it by that stable
address), presenting the **install-once** setup first (do it once, then
every night is one sentence) with the **paste-per-evening** cards as the
fallback, and answering *which card do I paste, when?* along with the
close-down snippet above. It points at the standing-instructions doc and the
cards; they never point back at it, and the table-side GPT never reads it.

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
| `rules/dnd5e/database-quick-ref.md` | The database's SQL surface: the character vault (read views, write verbs, the `create_character` payload), the session notebook, the combat board (`rpg.encounter_board`), the public story stream and private GM log, the GM prep layer (areas, NPCs, plot points and their lifecycle verbs), the slug↔folder join, the `rpg`-schema fence |

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
