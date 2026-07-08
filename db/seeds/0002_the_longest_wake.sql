-- ============================================================================
-- 0002_the_longest_wake.sql — SEED DATA (no DDL)
--
-- *** GM PREP LAYER FOR THE ADVENTURE "The Longest Wake" ***
-- Transcribes the already-authored binder folder
--   adventures/dnd5e/the-longest-wake/  (hook, scenes, npcs, secrets, loot)
-- into the GM's prep tables (0006): rpg.areas, rpg.npcs, rpg.plot_points.
-- Nothing here is invented and nothing is marked improvised that the folder
-- did not already so mark — every description / gm_notes / body value is a
-- faithful summary of that text, no more.
--
-- Data only: INSERTs exclusively. No CREATE/ALTER/DROP of anything. NOT a
-- migration; not in the ledger. Applied with execute_sql, after 0011.
-- Touches ONLY schema rpg (the Rollspel fence); nothing outside it.
--
-- FRESH-DISCOVERY RULE — the whole point of this seed: the story emerges in
-- play, so everything starts undiscovered. Every area relies on the default
-- visited = false, every NPC on discovered = false (0011), every plot point on
-- status = 'hidden'. None of these columns is set here; the defaults do it, and
-- nothing is seeded in a revealed/visited/resolved state.
--
-- PLAYER-FACING vs GM-ONLY (0006's line, kept): description columns are the
-- short, safe-to-read-aloud summary; every secret, motivation, twist, DC and
-- stat block lives in gm_notes / body (GM-only). This seed never puts a secret
-- in a description.
--
-- ADVENTURE FK: resolved through rpg.find_adventure('the-longest-wake'), which
-- RAISES if no such adventure row exists — so a missing adventure fails the
-- whole transaction loudly rather than inserting orphans. The row is expected
-- to be present already (slug 'the-longest-wake', dnd5e, status planned).
--
-- IDEMPOTENT: re-running is a no-op.
--   * areas    — ON CONFLICT DO NOTHING against the unique
--                (adventure_id, lower(name)) index.
--   * npcs     — no unique key on name, so each candidate is guarded by
--                WHERE NOT EXISTS on (adventure_id, lower(name)).
--   * plot_points — same guard on (adventure_id, lower(title)).
-- Cross-table FKs (npc→area, plot_point→area/npc) are resolved by subselect on
-- natural key at insert time, never hardcoded UUIDs. Insert order is areas,
-- then npcs (may reference areas), then plot_points (may reference both).
--
-- Prose is dollar-quoted ($t$…$t$) so the folder's many apostrophes need no
-- escaping.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Areas — the places, in play order (scenes.md). visited defaults false.
-- ---------------------------------------------------------------------------

insert into rpg.areas (adventure_id, name, description, gm_notes, sort_order)
select rpg.find_adventure('the-longest-wake'), v.name, v.description, v.gm_notes, v.sort_order
from (values
  (1::smallint,
   $t$The Ford$t$,
   $t$The ford at dusk on a bend of the Whitecow: rich land, fat cattle, new thatch, and from the great roundhouse harp, laughter, and the smell of a stew that is mostly water by now. A queue of strangers walks in through one gate while a thinner, better-fed queue strolls out another to re-enter. Guest-right is offered to everyone who arrives — it must be.$t$,
   $t$Arrival scene. A DC 12 Wisdom (Insight) reads the cost of the offered welcome in the greeter's face; within the hour the party is fed, seated, and by law at the wake. Threshold clue: at dawn the dew on the path down from the barrow holds a line of bare footprints walking toward the roundhouse that do not bend the grass. Lugán the quarry lad will show anyone who asks, for the price of being taken seriously.$t$),
  (2::smallint,
   $t$The Wake-hall$t$,
   $t$Mórr's great roundhouse, nine days into a wake that will not end. Old Mórr sits dead and dignified in his chair at the head of the fire, damp at the collar, smelling faintly of out-of-season hawthorn blossom. The room keeps the careful etiquette of people who have had nine days to normalize the impossible: drink, music, competitive grief, and guests arriving with the weather.$t$,
   $t$The set-piece social scene; run it as long as it is fun. Fial works the room, publicly magnificent and privately drowning. Nes sings a shortened "Mórr's Luck" — the missing verses are the receipt (a bard, DC 13 Intelligence (History), or any West training notices). Bré eats and converses beautifully and says nothing (Insight DC 16: his grief is technically perfect, nothing underneath). Étar will talk shop about the body to anyone respectful. At midnight, on cue, if the party is present, Mórr's lips move: "The stave." As the food visibly thins, if the party does nothing by scene's end, Fial swallows her pride and asks outright — bury my father so this ends, and the Ford will owe you what it can still pay.$t$),
  (3::smallint,
   $t$The Barrow$t$,
   $t$The burial mound on the rise above the village, where Old Mórr has been laid to rest three times with every rite done rightly — and from which, each following dawn, he returns to his chair. The stone bed inside is dry.$t$,
   $t$Every rite was done rightly; that is confirmable and true, and the failure is not procedural. DC 13 Intelligence (Investigation): the stone bed holds a shape of river-damp where a dry corpse should have lain, and hawthorn petals. From the barrow mouth there is a sightline to a lone hawthorn on a green mound upstream — the hollow hill. Nobody local will look directly at it.$t$),
  (4::smallint,
   $t$The Bog$t$,
   $t$Bog pools out past the village, sucking black peat under the night sky. The old men avoid one pool in particular.$t$,
   $t$Set piece, best at night. Difficult terrain; a fall risks a DC 12 Strength save or the creature begins sinking — restrained, DC 12 Athletics to pull free or be freed. Disturbing the stave's pool raises two will-o'-wisps (SRD stat block), the bog's words defending what it keeps. The stave was given "until Mórr's people need the truth of it": a party retrieving it for the village satisfies the letter and the wisps wink out the moment it leaves the water; a party grabbing it for leverage or loot does not, and the wisps fight in earnest. Scaling: one wisp for a bruised party, plus the improvised (marked) "pool's cold grip" — DC 12 Constitution save at round start within the pool or −10 ft speed. Lugán knows which pool. The stave carries its words with it: from the moment it surfaces, everyone touching it knows the terms by heart.$t$),
  (5::smallint,
   $t$The Hollow Hill$t$,
   $t$A green mound crowned by a lone hawthorn, its door only a door at dusk and dawn. Inside is one room far larger than the mound, a fire that gives light but no heat, and a tall, wintry, courteous host.$t$,
   $t$The climax, and it is a negotiation — run strictly by the world doc's Neighbor physics: they cannot lie, they keep the letter, they honor exact language, and they find mortals interesting. The Gentleman of the Hill waits with Bré at his shoulder holding the ledger. Live options, all of which work if played to the letter: pay the debt (a night of song from the finest voice — pin the contract to "the next dawn at Fiacc's Ford"; a publicly acclaimed PC bard may substitute, three performances at Charisma (Performance) DC 13/15/17, a failed one costs a chosen memory, marked improvised); renegotiate (the Gentleman is bored of the corpse arrangement and will end it cleanly for exact wording, while sloppy wording is accepted as spoken); the sky-iron knife (voids the debt by force majeure — and the prosperity with it, plus a Neighbor grudge with no expiry); or walk away (the wake never ends and the Ford eats itself hollow within the season). If it comes to blows he fights to conclude, not to kill, and the door participates.$t$)
) as v(sort_order, name, description, gm_notes)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- NPCs — the seven at the fire (npcs.md). discovered defaults false.
-- Combat stats stay NULL unless the entry gives explicit numbers (only the
-- Gentleman: AC 17 / 60 HP). area_id resolved by name where the entry clearly
-- places them (Mórr → Wake-hall, the Gentleman → Hollow Hill), else null.
-- ---------------------------------------------------------------------------

insert into rpg.npcs
  (adventure_id, area_id, name, role, disposition, status, srd_reference,
   armor_class, hp_max, hp_current, description, gm_notes)
select a.aid,
       ar.id,
       v.name, v.role, v.disposition::rpg.disposition, v.status::rpg.npc_status,
       v.srd_reference, v.armor_class::smallint, v.hp_max::integer, v.hp_current::integer,
       v.description, v.gm_notes
from (select rpg.find_adventure('the-longest-wake') as aid) a
cross join (values
  ($t$Old Mórr$t$, $t$dead chieftain, guest of honor$t$, $t$neutral$t$, $t$dead$t$, null, $t$The Wake-hall$t$, null, null, null,
   $t$The dead chieftain of Fiacc's Ford, its lord for forty years, seated composed and dignified in his chair at the head of the fire — damp at the collar, faintly scented with out-of-season hawthorn. Patiently, politely, unarguably dead.$t$,
   $t$Wants the stave found; he cannot rest with the terms unspoken. His midnight whisper, "the stave," is the only motion left in him, addressed to the room the way a man repeats the one thing he needs remembered. Furniture with gravity — the players should end the night fond of a corpse. Beyond hit points; no stat block.$t$),
  ($t$Fial$t$, $t$acting chieftain, Mórr's daughter$t$, $t$wary$t$, $t$alive$t$, $t$noble$t$, null, null, null, null,
   $t$Old Mórr's daughter and acting chieftain, running the Ford, the wake, and her own grief with the same iron competence. Hospitality as armor: "You'll eat first. Then we'll talk."$t$,
   $t$One honest sentence from breaking. Wants her father buried, the guests gone, and no one to ever know how near-empty the stores are — she will lie about the food before she lies about anything. Quest-giver, moral anchor, the cost of failure made visible. Does not know of the bargain (born two years after it) but knows her father feared hawthorn and would never say why. SRD noble if it matters; it shouldn't.$t$),
  ($t$Nes$t$, $t$the bard, Mórr's fosterling$t$, $t$neutral$t$, $t$alive$t$, $t$acolyte$t$, null, null, null, null,
   $t$Mórr's fosterling and the finest voice on that stretch of river — young, West-trained. Asked for "Mórr's Luck," she sings a shortened version; everything true comes out in song-quotes and deflection, and direct questions get performed answers.$t$,
   $t$The emotional spine. The only person in the village who has done the arithmetic: she is the finest voice at Mórr's fire, and she means to pay the debt herself before anyone else is taken — already decided, which is not the same as at peace. The verses she trims name the price aloud at the fire, which she fears is acknowledgment of the debt (she is right; Bré's quill moves the moment the full song is sung). Stats: SRD acolyte reskinned — swap divine flavor for bardic (marked improvised, per the folder).$t$),
  ($t$Étar$t$, $t$the herb-wife$t$, $t$friendly$t$, $t$alive$t$, $t$commoner$t$, null, null, null, null,
   $t$The herb-wife, who has prepared Old Mórr for burial five times and likes him better than most living clients. Clinical warmth and gallows humor with clean fingernails: "He's very considerate that way."$t$,
   $t$Clue dispenser who makes the impossible feel documented. Wants to be believed about the details: he is not decaying; the damp on him is river-water though the barrow is dry; and once, at midnight, she heard him whisper one word — "the stave" — which she'll only say outside, quietly. Also knows how near-empty the stores are and watches Fial not-say it. SRD commoner.$t$),
  ($t$Lugán$t$, $t$the quarry lad$t$, $t$friendly$t$, $t$alive$t$, $t$commoner$t$, null, null, null, null,
   $t$The quarry lad, fifteen, employed hauling quartz for the Mound — fast, precise, and braced to be dismissed. The first to see the dawn footprints.$t$,
   $t$Wants to be taken seriously by exactly one adult; treat him well and he is free exposition. Knows the paths, the bog pools, and which mound nobody looks at. He is first to see the line of bare dawn footprints — walking toward the roundhouse, not bending the grass — and will show them to anyone who takes him seriously. SRD commoner.$t$),
  ($t$Bré$t$, $t$the ninth-day guest$t$, $t$neutral$t$, $t$alive$t$, $t$spy$t$, null, null, null, null,
   $t$The ninth-day guest: eats well, grieves beautifully, helps with nothing, and has restarted his three-night guest-right three times with the punctuality of a man keeping books. Perfect manners with no fingerprints on them.$t$,
   $t$The players' first Neighbor. Bré is the Neighbors' clerk in mortal shape, attending to verify contract compliance until the ninth dawn. He cannot lie, but has simply never needed to volunteer anything; confronted with proof (the stave, the missing verses sung to his face) he corrects nothing, confirms the letter of whatever is put to him exactly, and compliments the party's diligence. His three-night re-entries taken to the letter are his little joke; named to his face he is delighted (one raised eyebrow) and answers three direct questions with the letter of the truth. Wants the ledger closed cleanly, either way. Stats improvised (marked): SRD spy chassis; at will becomes unnoticed when no one is directly watching (as invisibility, ends if he acts); immune to charm and sleep; sky-iron burns him. He never fights; he leaves.$t$),
  ($t$The Gentleman of the Hill$t$, $t$the Neighbor who made the bargain$t$, $t$neutral$t$, $t$alive$t$, $t$knight$t$, $t$The Hollow Hill$t$, 17, 60, 60,
   $t$The host of the hollow hill: tall as a spear, beautiful the way winter is beautiful, courteous to the last letter. He never lies, never hurries, and answers exactly the question asked and not one word more.$t$,
   $t$The Neighbor who made the bargain, forty years into an arrangement he now finds undignified. The climax; run him by the world doc's Neighbor physics — let exact language win and sloppy language teach. Wants the account settled without embarrassment to his house: he is bored of returning a corpse nightly, and boredom in his kind is nearly a mortal weakness, so a party offering an elegant exit negotiates uphill-with-the-wind. Courteous throughout; his menace is formal. Stats improvised (marked), only if players force it: SRD knight chassis, AC 17, 60 HP; his blade is winter (as longsword, damage is cold); 3/day step from any shadow to any other within sight (as misty step); 1/day a spoken word of binding (as hold person, DC 14); immune to charm, fright, sleep. Sky-iron negates his damage resistance to nonmagical bludgeoning/piercing/slashing, and its wounds cannot be regenerated. He fights to conclude, not to kill; the door participates.$t$)
) as v(name, role, disposition, status, srd_reference, area_name,
       armor_class, hp_max, hp_current, description, gm_notes)
left join rpg.areas ar
  on ar.adventure_id = a.aid and lower(ar.name) = lower(v.area_name)
where not exists (
  select 1 from rpg.npcs n
  where n.adventure_id = a.aid and lower(n.name) = lower(v.name)
);

-- ---------------------------------------------------------------------------
-- Plot points — the truths under the evening (secrets.md + hook). All start
-- status 'hidden' (default). Anchored to npc/area by subselect on natural key.
-- ---------------------------------------------------------------------------

insert into rpg.plot_points
  (adventure_id, title, kind, body, area_id, npc_id)
select a.aid,
       v.title, v.kind::rpg.plot_point_kind, v.body,
       ar.id, n.id
from (select rpg.find_adventure('the-longest-wake') as aid) a
cross join (values
  ($t$The bargain$t$, $t$secret$t$,
   $t$The truth under everything. Forty years ago, in a famine spring, young Mórr walked to the hollow hill at dusk and cut terms onto a tally stave: "Prosperity on Fiacc's Ford and all at Mórr's fire, for so long as Mórr sits at that fire. In payment: one night of song from the finest voice at his fire, payable when he leaves it." The prosperity clause ends when he leaves the fire — dying doesn't move him, but burying him does, and the payment clause triggers the same moment. So the Neighbors, precise beyond malice, enforce specific performance: each time the village buries him they return the collateral to his chair by dawn, because while Mórr sits at his fire prosperity legally continues, no debt falls due, and no term is breached. The corpse in the chair is not a haunting — it is contract maintenance. The Gentleman's unspoken position: the arrangement has become embarrassing, his house is laughed at behind its hands, and he wants a clean conclusion more than the song — the party's real leverage, if they find it. (World-level aha, GM framing only: the adventure plants the world's breadcrumbs without pointing — hospitality as absolute law, the hollow hill and hawthorn, the bog that keeps what it is given, the Mound upstream needing barley and quartz; if a player's eyes go wide, per the world doc the answer is never yes and never no.)$t$,
   null, $t$The Gentleman of the Hill$t$),
  ($t$Why Mórr whispers$t$, $t$secret$t$,
   $t$Mórr's last living act was regret; what is left of him is one instruction — "the stave." Find the terms, so his people can settle honestly what he settled recklessly. He gave the stave to the bog decades ago with the words "kept until Mórr's people need the truth of it," which is why the bog yields it to a party acting for the village and fights one acting for itself.$t$,
   null, $t$Old Mórr$t$),
  ($t$The ninth dawn$t$, $t$event$t$,
   $t$The adventure's clock. Nine nights of an unpaid, unacknowledged debt with the debtor absent from his fire in spirit constitutes abandonment. At the ninth dawn Bré rises, thanks Fial for a hospitality "kept to the letter," and walks toward the hollow hill without hurrying — the ledger closing, the house moving from maintenance to collection. Collection means Nes, the finest voice at that fire: no one is kidnapped; she is honor-bound and half-willing (she volunteered in her head days ago), which should be worse to watch. The party has until Bré reaches the hill to act, negotiate, or interfere; their actions before he arrives decide whether the hill scene is a negotiation or a rescue. Interfering with Bré directly is possible and unwise — he does not fight, he notes things down.$t$,
   $t$The Wake-hall$t$, null),
  ($t$Nes's arithmetic$t$, $t$secret$t$,
   $t$Nes has known since the second failed burial. The verses she trims from "Mórr's Luck" are not modesty: singing the full song at the fire names the price aloud at the fire, which she fears constitutes acknowledgment of the debt — and she is right, Bré's quill moves the moment it happens. If a PC gets the full verses sung, the debt is acknowledged early: nothing bad happens immediately, but Bré thanks the singer, and the party then negotiates from an acknowledged-debt position at the hill, which is cleaner, not worse. Her fear and the actual consequence differ; that gap is hers to be relieved about.$t$,
   null, $t$Nes$t$),
  ($t$Fial's ledger$t$, $t$secret$t$,
   $t$The stores run out tomorrow. Fial has been serving her own house's winter share for three days. If the wake ends tomorrow the Ford survives lean; every extra day costs a family's winter. She will never say this — Étar knows, and watches her not-say it.$t$,
   null, $t$Fial$t$),
  ($t$Bré's courtesy$t$, $t$revelation$t$,
   $t$Bré's guest-right re-entries are not freeloading: a clerk observing compliance must himself be flawlessly compliant, and the three-night rule taken to the letter is his little joke about the whole arrangement. If the party works this out and names it to his face, he is delighted (expressed as one raised eyebrow) and answers three direct questions with the letter of the truth. This is the cheapest good lead in the adventure and its best reward for cleverness.$t$,
   null, $t$Bré$t$),
  ($t$The funeral keeps failing$t$, $t$hook$t$,
   $t$The opening situation. Old Mórr, chieftain of Fiacc's Ford for forty years, died nine nights ago in his chair by the fire, at a great age, of nothing in particular. The wake has not ended because the funeral keeps failing: three times he has been laid in the barrow with every rite done rightly, and each following dawn he is back in his chair — seated, composed, slightly damp, patiently and unarguably dead. Nobody has said the word "Neighbors" aloud, because saying it aloud is an invitation. Meanwhile hospitality is absolute law: a dead chieftain above ground means the feast is still on, word of the marvel has spread up and down the river, guests keep arriving (some have found that walking out one gate and in the other restarts their three sacred nights), the stores are nearly out — and the acting chieftain would rather die than admit the Ford cannot feed its guests.$t$,
   null, null)
) as v(title, kind, body, area_name, npc_name)
left join rpg.areas ar
  on ar.adventure_id = a.aid and lower(ar.name) = lower(v.area_name)
left join rpg.npcs n
  on n.adventure_id = a.aid and lower(n.name) = lower(v.npc_name)
where not exists (
  select 1 from rpg.plot_points pp
  where pp.adventure_id = a.aid and lower(pp.title) = lower(v.title)
);

commit;
