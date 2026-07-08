# Character art

Drop portrait images here — they deploy with the site automatically.

**Naming convention (zero configuration):** name the file after the character,
lowercase with dashes, and the app finds it by itself:

| Character    | Filename           |
|--------------|--------------------|
| Vesper Quill | `vesper-quill.png` |
| Brann Ashfoot| `brann-ashfoot.jpg`|
| Sable Wren   | `sable-wren.webp`  |

Accepted formats, tried in order: `.png`, `.jpg`, `.webp`.

**Explicit override:** set `rpg.characters.portrait_url` in the vault to any
relative path or absolute URL; it wins over the convention. If neither exists,
the app falls back to the initial-letter crest — nothing breaks.

**Sizing:** roughly square crops look best (the app renders them as covers in
rounded frames). ~512×512 and under ~400 KB per image keeps the page quick.
