Run a complete UI/UX quality check on the current project. $ARGUMENTS

## Step 0: Discovery

If `.claude/project-params.md` exists (written by /setup-project), read its `## UI layer`
section **and** its `Framework-specific review checks` line — Step 2 needs both — and use them
as a discovery shortcut: re-verify cheaply instead of searching from scratch; if the project
has drifted, trust what you find over the list. If `## UI layer` says the project has no UI
layer, report that and stop. Otherwise detect:

- **UI framework** — PySide6/PyQt/tkinter (Python imports), React/Vue/Svelte/Angular
  (package.json). If NO UI layer is found → report "No UI layer detected — nothing to check"
  and stop.
- **UI files** — e.g. `src/ui/`, `src/components/`, `client/src/`.
- **Style definitions** — e.g. `src/ui/styles.py`, theme files, CSS/QSS.
- **UI tests + runner** — e.g. `tests/ui/` with pytest-qt, `**/*.test.tsx` with vitest/jest.

## Step 1: Run existing UI tests

Use the detected runner and test location (e.g. `python -m pytest tests/ui/ -v --tb=short`).
If no UI tests exist, skip and say so in the report — do not fail the run.

## Step 2: Launch 2 agents in parallel

Inline the Step 0 findings — UI file paths, style definition paths, and the framework-specific
checks — directly into both agent prompts. Subagents never read `.claude/project-params.md`
themselves; anything not passed through is lost.

**Agent 1 — UX Review.** Read all UI files. Check:
- Feedback states — loading, success, error for every user action
- Empty states — what the user sees with no data, in every view/component
- Error states — errors caught, user-friendly messages, UI recovers
- Accessibility — tooltips, keyboard navigation, ARIA/accessible names
- Navigation — can the user tell where they are; consistent patterns
- Consistency — same patterns across views, uniform terminology

**Agent 2 — Design & Style Review.** Read style definitions + all inline styles. Check:
- Color contrast — WCAG AA (4.5:1 normal text, 3:1 large); list the specific color pairs found
- Color harmony — cohesive palette, no clashing colors
- Font hierarchy — extract all sizes, check consistency, minimum 12px
- Spacing consistency — extract all values, check for a consistent scale
- Component styling — similar components styled alike, centralized styles
- Style violations — hardcoded values outside the theme/constants file

**Framework-specific checks (both agents, per detected framework):**
- PySide6/PyQt: QSS compliance, signal/slot usage, GUI-thread blocking, QTimer/QThread cleanup,
  widget lifecycle
- React: hook rules, re-render optimization, prop drilling, key usage
- Vue: reactivity gotchas, composition API patterns, template vs script style

Each agent MUST verify findings against actual code before reporting. Findings tables use the
shared schema: `# | Severity | Category | File:Line | Issue | Suggested Fix`.

## Step 3: Combined report

Merge test results + both agents' findings into one report with these sections: Test Results,
UX Issues table, WCAG Contrast table, Design Issues table, Style Violations table, Style
Metrics (font sizes, spacing values, color count), What's Working Well.

## Rules

- Review only — do NOT modify code without explicit user approval.
- Do NOT invent findings; an empty table is a valid result.
- Adapt checks to the detected framework; skip categories that don't apply and say so.
