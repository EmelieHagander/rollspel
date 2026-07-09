# How to run an evening

> **What this doc is:** the owner's one-page guide to running the game — the
> **install-once** setup (recommended) and the **paste-per-evening** cards in
> `prompts/` (the fallback), plus how to close the night. Written for a human
> (the webapp renders this page as a menu item); the address is stable and the
> table-side GPT never needs it.

---

## Two ways to run — pick one

There are two paths to the table, and they run the **same** game master:

- **The install-once setup (recommended).** Build a Custom GPT once, and every
  game night after is a single sentence in a fresh chat — no card to paste, no
  blanks to fill, no key to handle. Set it up once; then forget the setup ever
  existed.
- **The paste-per-evening cards (fallback).** For a plain ChatGPT or Claude
  chat with no Custom GPT — you copy a card, fill its blanks (your database key
  among them), and paste it fresh every single night.

Both paths build heroes the same way (the character workshop below), run the
same GM, and close the night the same way. If you can make a Custom GPT, use
the install-once setup — the rest of your evenings get much shorter.

## Make the heroes — any day, either path

**Card: `prompts/character-creation-dnd5e.md`**

Characters are built *before* game night, at whatever pace the player likes —
a Tuesday lunch break is fine. Paste this card into a fresh chat and it
becomes a patient character workshop: it answers every rules question, builds
the character with the player, and saves the finished hero to the vault.
Do this once per hero, before their first evening. It works the same whichever
run-path you use tonight.

## The install-once setup — recommended

Do this **once**, and never again:

1. **Make a Custom GPT.** In ChatGPT, create a new Custom GPT for your table.
2. **Give it its identity.** Paste `prompts/standing-instructions-dnd5e.md`
   into the Custom GPT's **Instructions** field. That document *is* the GPT
   now — it carries no blanks to fill and no key.
3. **Give it the vault, safely.** Put your database service key in the Custom
   GPT's **Actions** configuration (its authentication settings) — never in the
   Instructions, never in any chat. The key lives there, once, out of sight.

That is the whole setup. From then on, **every** game night is one fresh chat
and one sentence naming tonight's adventure — the GPT already knows who it is,
where the binder and vault are, and how to get in. If you'd like a ready-made
opening line to type:

> **Let's continue The Longest Wake.** Swap in tonight's adventure — that one
> sentence is the whole start, and the GM takes back the story from there. To
> open a fresh story instead of resuming an old one, say **Start <adventure>**.

To stop for the night, see **Stop for tonight** below — closing works the same
on either path.

## The paste-per-evening cards — fallback

Use these only when you are **not** running the Custom GPT — a plain ChatGPT or
Claude chat with no Actions and no saved identity.

**The one rule for every card.** Every card here is a **template**. Using one
is always the same three steps:

1. **Copy** the card's text.
2. **Fill in** every `<angle-bracket>` blank (tonight's adventure, the players, the key).
3. **Paste** the filled result into a **fresh** GPT or Claude chat.

**Never save or commit the filled copy anywhere** — it contains your database
key. The blank card in the binder is the only version that is ever stored.
(The install-once setup avoids this risk entirely: its key lives in Actions,
never in text.)

**Which card, when?**

| You want to… | Paste this card | When |
|---|---|---|
| Start a brand-new table's **first** evening | `prompts/first-evening-dnd5e.md` | Once per new table |
| Start **any later** evening | `prompts/every-evening-dnd5e.md` | Every game night after the first |

**A new table's very first night — `prompts/first-evening-dnd5e.md`.** Paste
this once, for a table that has never played together. It checks the heroes
are in place and opens the story. (If someone arrives without a character,
they build one another day with the workshop card — not tonight.)

**Every night after that — `prompts/every-evening-dnd5e.md`.** Paste this at
the start of every later evening. It tells the GM where everything lives; the
GM remembers the whole story on its own from there — you never need to explain
what happened last time.

Each card is complete by itself: one evening, one card, one fresh chat.

## Stop for tonight — either path

When the evening is over — pausing mid-story or finishing the adventure —
just tell the GM. It knows the full closing ritual and runs it by itself:
it saves the story's state, writes its own hand-over, and delivers the
evening's image prompts. If you want a ready-made line, paste this:

> We're stopping here for tonight. Close the books: run your full closing
> ritual from `prompts/gm-dnd5e.md`, every step in order — it handles a pause
> and a finished adventure alike. Say goodnight when the last step is confirmed.

Once the GM says goodnight, the chat can be closed and forgotten. Next
game night, you pick the story up exactly where it stopped — one sentence in
the Custom GPT, or the every-evening card in a plain chat.

---

_End of how-to-run-an-evening.md._
