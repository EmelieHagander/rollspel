# SRD quick-reference: combat

Source: D&D 5e SRD 5.1. This file summarizes rules-as-written; it contains no house rules (those live in `rules/dnd5e/house-rules.md`).

## Combat sequence

1. **Determine surprise.** A creature that doesn't notice a threat is surprised: it can't move or act on its first turn and can't take reactions until that turn ends.
2. **Roll initiative:** Dexterity check, everyone once; order runs highest to lowest for the whole combat. GM may break ties (commonly: higher Dex first).
3. **Take turns.** On a turn: **move** (up to speed, splittable around actions) and take **one action**, plus at most **one bonus action** (only if a feature grants one) and **free interaction** with one object. **One reaction** per round, taken on anyone's turn when triggered.

## Actions

- **Attack** — one attack roll (or more with Extra Attack).
- **Cast a Spell** — casting time 1 action (a spell with a 1 bonus-action casting time limits other spells that turn to cantrips with 1-action casting time).
- **Dash** — extra movement equal to your speed.
- **Disengage** — your movement doesn't provoke opportunity attacks this turn.
- **Dodge** — attacks against you have disadvantage; you make Dex saves with advantage (until your next turn; lost if incapacitated or speed 0).
- **Help** — give a creature advantage on its next ability check, or on its next attack roll against a creature within 5 ft of you (before your next turn).
- **Hide** — Dexterity (Stealth) check vs. searchers' Perception.
- **Ready** — choose a trigger and a response action (or movement); take it as a reaction when triggered. A readied spell is cast now (slot spent) and held with concentration.
- **Search** — Wisdom (Perception) or Intelligence (Investigation) check.
- **Use an Object** — interact with a second object or one needing an action.

## Attack rolls

d20 + ability modifier + proficiency bonus (if proficient with the weapon) vs. target's AC.

- Melee uses Strength (finesse weapons: Str or Dex); ranged uses Dexterity (thrown melee weapons: Str).
- **Natural 20:** hit and **critical hit** — roll all the attack's damage dice twice, then add modifiers. **Natural 1:** miss, always.
- **Unseen attacker:** attacks against a target that can't see you have **advantage**; attacking a target you can't see has **disadvantage**.
- **Ranged in melee:** ranged attack rolls have disadvantage when a hostile creature that isn't incapacitated is within 5 ft.
- **Prone targets:** melee attacks against them have advantage; ranged attacks have disadvantage.

## Cover

- **Half cover:** +2 to AC and Dexterity saves.
- **Three-quarters cover:** +5 to AC and Dexterity saves.
- **Total cover:** can't be targeted directly.

## Movement

- Difficult terrain costs double. Standing up from prone costs half your speed.
- Moving through a hostile creature's space: only if it's two sizes larger or smaller (and it's difficult terrain). You can move through allies' spaces.
- **Opportunity attack:** when a creature you can see moves out of your reach, you may use your reaction for one melee attack. Avoided by Disengage, teleporting, or being moved without using movement/action/reaction.

## Grapple and shove (special melee attacks)

Replace **one attack** of your Attack action; target no more than one size larger.

- **Grapple:** your Strength (Athletics) vs. their Strength (Athletics) or Dexterity (Acrobatics). Success: target is grappled (speed 0). Escape: their action, same contest.
- **Shove:** same contest. Success: knock **prone** or push **5 ft** away.

## Two-weapon fighting

When you Attack with a light melee weapon in one hand, a bonus action lets you attack with a different light melee weapon in the other — **no ability modifier to that damage** (unless the modifier is negative).

## Damage, dying, death

- **Resistance:** half damage. **Vulnerability:** double. Applied after all other modifiers.
- **At 0 HP:** unconscious and **dying** (monsters typically just die). **Instant death** if the excess damage equals or exceeds your HP maximum.
- **Death saving throws:** at the start of each of your turns at 0 HP, roll a flat d20. 10+ = success, 9− = failure. Three successes: **stable**. Three failures: **dead**. Natural 1: two failures. Natural 20: regain 1 HP.
- **Damage while at 0 HP:** one death-save failure (two if a critical hit). Melee attacks against an unconscious creature within 5 ft are criticals (attacks have advantage).
- **Stabilize:** DC 10 Wisdom (Medicine) as an action, or the *spare the dying* cantrip. Stable creatures regain 1 HP after 1d4 hours.
- **Healing at 0 HP:** any healing brings the creature conscious; death saves reset.

## Concentration

One concentrating spell at a time. Broken by: casting another concentration spell, being incapacitated or killed, or taking damage — Constitution save DC 10 or half the damage taken, whichever is **higher**.

## Rests

- **Short rest** (1+ hour): spend hit dice to heal (d + Con modifier each).
- **Long rest** (8 hours, once per 24h): regain all HP, half your total hit dice (minimum 1), and spent resources per their rules. Standard spell slots return on a long rest; warlock pact slots return on a short **or** long rest.
