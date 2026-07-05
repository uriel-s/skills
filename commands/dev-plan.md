Author or lint `.dev-plan.md` for a /dev run. $ARGUMENTS

Two modes, chosen automatically:

## Mode A — Author (when $ARGUMENTS describes a feature/goal)

1. Read the codebase enough to plan: structure, key modules, existing patterns relevant to the
   goal. Do not modify anything.
2. Draft sections following the /dev plan contract:
   - Format: optional `# Plan: <name>` H1, then `## Section N: <short title>` numbered
     sequentially from 1, each with a 2–5 sentence body: what to build, key files involved,
     acceptance criteria.
   - **Sizing rule:** each section must be implementable by /work in ≤5 sub-tasks. Too big →
     split it. When unsure, smaller sections — /dev's overhead per section is minutes.
   - **Ordering rule:** interface-defining sections (APIs, schemas, data models) come before
     sections that consume those interfaces.
   - Titles must produce unique slugs (lowercased, hyphenated, ≤40 chars) — duplicate slugs
     would collide on branch names.
3. Present the draft to the user, iterate on feedback, then write `.dev-plan.md` (ask before
   overwriting an existing one).

## Mode B — Lint (when no goal is given, or $ARGUMENTS contains `--lint`)

Check the existing `.dev-plan.md` (missing → report and stop):

- Header format: exact `## Section N: <title>`, numbered sequentially starting at 1, no gaps
  or duplicates.
- Every section has a non-empty body with recognizable acceptance criteria.
- Slugs (lowercased, hyphenated, ≤40 chars) are unique across sections.
- Sizing: flag any section that plainly needs more than 5 sub-tasks (a NEEDS_SPLIT waiting to
  happen at Phase B).
- Cross-section sanity: later sections don't contradict or undo earlier ones; consumers come
  after the interfaces they use.

Report issues as a table (`Section | Problem | Suggested fix`). Fix them only with user
approval.

## Rules

- Never start /dev automatically — this command only prepares the plan.
- Mode A reads the codebase but modifies nothing except `.dev-plan.md` (with approval on
  overwrite).
- A plan that lints clean here must parse in /dev pre-flight; if /dev still rejects it, that is
  a /dev-plan bug — report it.
