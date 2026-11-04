Extract one short engineering lesson from recent changes — concepts, architecture, design, and idiomatic Python. Manual only. $ARGUMENTS

## Purpose

A MANUAL, on-demand command — runs ONLY when I type `/learn`, never
automatically, and NOT wired to /work or /dev in any way. When I invoke it,
take the most recent change(s) and extract ONE short lesson that sharpens
engineering depth — CONCEPTS, ARCHITECTURE, DESIGN DECISIONS, and idiomatic
Python patterns. Nice-to-have: quick, never blocks shipping.

The goal is continuous architectural reflection: distilling the concepts,
trade-offs, and language idioms behind what was built into a concise reference.

## Input

- Default: `git diff` of the last commit.
- Optional arg: a range (e.g. `HEAD~3..HEAD`) to review a whole /dev run, or a
  path to focus on.

## Output — ONE "Learning Card", max ~1 screen

Don't dump the diff — pick the single most instructive decision. Four tight
parts:

**1. The concept / pattern (named)** — the most important engineering concept or
design pattern in this change. Name it, define it in general terms (not just as
it appears here), and say why it fits. Turning "it works" into "this is called
X" is the whole point.

**2. The design decision & trade-off** — what alternative existed, why this one
won, and what it costs. The "why" behind the architecture — this is what grows
real judgment.

**3. One Python idiom** — one notable Python construct or idiom in the diff
(comprehension, context manager, dataclass, `is` vs `==`, truthiness,
generator, unpacking, decorator, descriptor, protocol...). Two lines, using the
real line as the example.

**4. Worth remembering** — name one term or idea from this change to internalize
or look up later. Low pressure.

## Glossary log

After the card, append the concept name (part 1) as a one-line entry to
`.learn-log.md` in the repo root — a running personal glossary. Before picking
part 1, read `.learn-log.md` and prefer a concept NOT covered recently, so
lessons don't repeat and understanding compounds over time.

## Rules

- SHORT — one lesson per run, skimmable in a minute. One good lesson beats five.
- Skip basics (loops, variables, syntax). Focus on concepts, design/architecture
  reasoning, and idiomatic Python specifics.
- No praise, no filler. Teach.
- NO planted or hypothetical bugs. Teach what IS there, not what could break.
- If the change is trivial (docs, rename, formatting), say "nothing to learn
  here" and stop — don't manufacture a lesson.
