# How to run an evening

> **What this doc is:** the owner's one-page guide to the paste-in cards in
> `prompts/` — which card to paste when, and how to close the night. Written
> for a human (the webapp renders this page as a menu item); the address is
> stable and the table-side GPT never needs it.

---

## The one rule for every card

Every card below is a **template**. Using one is always the same three steps:

1. **Copy** the card's text.
2. **Fill in** every `<angle-bracket>` blank (tonight's adventure, the players, the key).
3. **Paste** the filled result into a **fresh** GPT or Claude chat.

**Never save or commit the filled copy anywhere** — it contains your database
key. The blank card in the binder is the only version that is ever stored.

## Which card, when?

| You want to… | Paste this card | When |
|---|---|---|
| Build a character | `prompts/character-creation-dnd5e.md` | Any day — no game night needed |
| Start a brand-new table's **first** evening | `prompts/first-evening-dnd5e.md` | Once per new table |
| Start **any later** evening | `prompts/every-evening-dnd5e.md` | Every game night after the first |
| Stop for tonight | The close-down snippet below | The end of any evening |

## 1. Make the heroes — any day

**Card: `prompts/character-creation-dnd5e.md`**

Characters are built *before* game night, at whatever pace the player likes —
a Tuesday lunch break is fine. Paste this card into a fresh chat and it
becomes a patient character workshop: it answers every rules question, builds
the character with the player, and saves the finished hero to the vault.
Do this once per hero, before their first evening.

## 2. Start the evening

**A new table's very first night — card: `prompts/first-evening-dnd5e.md`**

Paste this once, for a table that has never played together. It checks the
heroes are in place and opens the story. (If someone arrives without a
character, they build one another day with the workshop card — not tonight.)

**Every night after that — card: `prompts/every-evening-dnd5e.md`**

Paste this at the start of every later evening. It tells the GM where
everything lives; the GM remembers the whole story on its own from there —
you never need to explain what happened last time.

Each card is complete by itself: one evening, one card, one fresh chat.

## 3. Stop for tonight

When the evening is over — pausing mid-story or finishing the adventure —
just tell the GM. It knows the full closing ritual and runs it by itself:
it saves the story's state, writes its own hand-over, and delivers the
evening's image prompts. If you want a ready-made line, paste this:

> *(Close-down snippet — reserved. This prompt text is authored by Douglas,
> per CLAUDE.md §4.2, and will appear here. Until then, plain words work:
> tell the GM you're done for tonight, and it will close the books.)*

Once the GM says goodnight, the chat can be closed and forgotten. Next
game night, the every-evening card picks the story up exactly where it
stopped.

---

_End of how-to-run-an-evening.md._
