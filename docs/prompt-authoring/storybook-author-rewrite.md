# Storybook Author Rewrite System

This system rewrites agent prompts into compact, adaptive story prompts while preserving operational meaning.

The goal is not to make the prompt funny, literary, or decorative. The goal is to make the agent's world obvious enough that good behavior follows naturally.

**House author:** Douglas Adams. Every prompt written in this repo receives its final whole-prompt rewrite through his lens — dry precision, concrete absurdity, exact situational wording, world-building that makes bureaucracy, tools, doors, ledgers, fences, and failure modes feel physically obvious.

## Core principles

Less is more.
Every word must earn its place. A prompt should say the thing once, in the strongest usable form. Repetition is allowed only when the repeated item is an interface, a numbered fence, or a load-bearing handle cited elsewhere.

Softcode judgment.
Do not turn every desired behavior into a rule. When behavior can be carried by role, setting, metaphor, craft, responsibility, or consequence, make it part of the world.

Hardcode interfaces.
Tool names, schemas, file paths, exact labels, numbered fences, approval gates, stopping conditions, and final hand-off formats stay precise. These are not story material. They are machinery.

Storybook first.
The agent should know where it is, what kind of work happens there, what belongs to it, what belongs elsewhere, and what kind of failure it exists to prevent.

Author-bound last.
The author pass is not decoration. It is a final whole-prompt rewrite through a chosen authorial lens to find the exact words, rhythm, and descriptions that make the world self-explanatory.

## Why storybook prompting

Storybook prompting creates operational reality.

A rule says:

"Do not mention a teammate unless you call the tool."

A world says:

"A name spoken in chat is only a name spoken in chat; the tool is the door."

The second version gives the agent physics. Once the tool is understood as a door, the agent can adapt across cases without needing every case listed.

Storybook prompting is used because modern reasoning models can infer behavior from a coherent world better than from a crowded rulebook. The story gives boundaries without boxing the model into brittle if/then compliance.

## Why author-bound rewriting

Great authors are trained to choose words that make a situation real.

The author is not used for jokes. The author is used as a compression lens.

"Douglas Adams" should mean dry precision, concrete absurdity, exact situational wording, and world-building that makes bureaucracy, tools, doors, ledgers, fences, and failure modes feel physically obvious.

The author pass must rewrite the whole prompt. It must not sprinkle style over old paragraphs. If the old structure survives untouched, the rewrite failed.

## Pipeline

### Step 1 — Load-bearing extraction

Read the original prompt and extract only what must survive.

Separate:

* routing metadata
* tool names
* exact file paths
* exact commands
* exact schemas or labels
* numbered rules or invariants
* approval gates
* refusal fences
* final hand-off line
* domain ownership
* catastrophic failure modes
* useful identity/story lines

Output a load-bearing inventory before rewriting.

### Step 2 — Less-is-more compression

Remove repetition, negative framing, and historical ghosts.

Keep what the agent needs to inhabit the current world. Do not explain what the system is not unless the absence prevents a catastrophic mistake.

Replace repeated paragraphs with one strong sentence.

Delete explanations the model can infer.

### Step 3 — Softcode judgment

For each behavioral rule, decide whether it is:

* world-physics
* protocol
* catastrophic fence

World-physics becomes story.

Protocol stays exact.

Catastrophic fences stay terse and explicit.

### Step 4 — Storybook draft

Write the prompt in a clean neutral voice first.

The draft must answer:

* Who is this agent?
* What world does it live in?
* What does it protect?
* What does it touch?
* What does it never touch?
* What failure is it here to prevent?
* Where does it look before acting?
* What does it hand off?

This draft should already work before the author pass.

### Step 5 — Fresh-eyes audit

Read the draft as if you have never seen the old prompt.

Check:

* Does the story make the role obvious?
* Is anything repeated?
* Are rules hiding where story would work better?
* Are protocols still exact?
* Are catastrophic fences still visible?
* Are old-system ghosts still present?
* Does the prompt invite adaptation inside clear walls?
* Does the agent sound like a worker in a world, or a checklist with a name?

Revise until the answer is yes.

### Step 6 — Whole author-bound rewrite

Rewrite the entire audited draft through the chosen authorial lens.

Do not preserve sentence structure.

Do not decorate paragraphs.

Do not add jokes for their own sake.

Do not imitate surface quirks while leaving the old manual intact.

Use the author to find the correct words for the situation.

Preserve:

* YAML/frontmatter
* tool names
* exact identifiers
* numbered fences
* file paths
* commands
* approval gates
* final hand-off line
* operational meaning

### Step 7 — Fidelity gate

Compare the author-bound version against the load-bearing inventory.

Every required item must be present, exact, or intentionally represented by a stable pointer.

If a behavior was softened, verify that it was safe to soften.

If a numbered rule moved, verify that the number still resolves.

If a protocol became story, reject it and restore the protocol.

### Step 8 — Runtime test

Test the prompt on real historical tasks.

Score:

* task completion
* tool correctness
* unnecessary questions
* unnecessary refusals
* domain-boundary discipline
* verbosity
* whether the agent adapts inside its story
* whether the author voice helped or became theatre

The author voice succeeds only if behavior improves.
