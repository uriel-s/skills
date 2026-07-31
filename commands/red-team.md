Adversarially stress-test an idea, plan, or proposal BEFORE building it — a skeptic whose job is to KILL it, so you catch wasted effort before you build. Manual only. $ARGUMENTS

## Purpose

A MANUAL, on-demand command — runs ONLY when I type `/red-team`, never
automatically, and NOT wired into `/work`, `/dev`, or any other command. When I
invoke it, take an idea, plan, or proposal and try to **kill it**: prove it is
redundant, over-engineered, solving a non-problem, or better done another way.
The goal is to catch wasted effort *before* I build — not to please me. An AI
proposing its own ideas leans toward "yes, let's build it"; this command
deliberately runs the opposite instinct.

## Input

- `$ARGUMENTS` = the thing to attack: a plan, a feature idea, a skill/command
  proposal, a refactor, an architecture choice.
- No argument → attack the most recent concrete proposal in the conversation.
- Optional: a path or repo to ground the critique against real code.

## How it works

Spawn independent **skeptic subagent(s)** — independence matters; a fresh agent
with no attachment to the idea judges it more honestly than the one that
proposed it.

- **Default:** 1 skeptic for a single, small idea.
- **Panel:** for a big or multi-item proposal, or when I say "thorough", spawn a
  small panel (~3), each attacking from a distinct angle — *redundancy*,
  *over-engineering / simpler alternative*, *are the premises even true* — and
  require a majority to KILL.

Each skeptic is told: your job is NOT to praise — try to kill it. And the rule
that makes this actually work:

> **Verify against reality; do not argue from assumptions.** Read the actual
> code, config, and docs before claiming "already handled" or "redundant", and
> state what was checked. Assumption-based critique is worthless — the value is
> in catching real facts (e.g. "that lint rule is already enabled", "that
> number is a phantom", "an existing test already covers this").

## Survival rubric

An idea SURVIVES only if it clears ALL of:
1. Solves a real, recurring problem (not hypothetical).
2. Not already covered by existing tooling, tests, or code.
3. It is the simplest form that works — no gold-plating.
4. Can't be done better/cheaper another way (a config edit, a hook, an existing
   tool, a one-liner, a doc).

Weaponize these anti-patterns: don't wrap a one-liner in a skill; don't
duplicate a deterministic gate (lint/hook/CI); don't build for unknown-shape or
hypothetical needs; don't build a vague catch-all.

## Output

For each item (or the single idea):
- **Verdict:** BUILD / DOWNGRADE (to config / hook / checklist / existing tool) /
  KILL.
- **Strongest case against** — 1-3 sentences. This is the point of the exercise.
- **What survives** — only if BUILD: the minimal version worth building, with any
  gold-plating stripped.

Then:
- **Over-kill watch** — the 1-2 items most likely to be wasted effort.
- **Safest bets** — the 1-2 that could NOT be killed.
- **Bottom line** — a direct recommendation on what (if anything) to build.

## Rules

- Manual only — never auto-run, never wired to `/work` or `/dev`.
- Default to skepticism: the burden is on the idea to survive; when uncertain,
  lean KILL or DOWNGRADE, not BUILD.
- Verify against real code/docs before any "already handled" claim; say what was
  checked.
- Attack the idea, not the person. No praise, no filler.
- Attack only REAL weaknesses — do not invent hypothetical problems the idea does
  not have.
- Proportional effort: 1 skeptic for a small idea; a ~3 panel for a big or
  multi-item proposal.
- Cost: this spawns subagents (real tokens) — which is exactly why it is manual.
  Use it at a genuine build-decision point, not for trivial changes.
