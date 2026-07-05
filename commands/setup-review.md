Generate project-specific `/review` and `/ui-test` slash commands for the current project. $ARGUMENTS

## Instructions

### Step 1: Project Discovery

Detect everything automatically — do NOT ask the user.

**Find these:**
- **Tech stack & framework** — read `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, or equivalent. Identify the language(s), framework(s), and package manager.
- **Architecture docs** — search for `ARCHITECTURE.md`, `CONTRIBUTING.md`, `docs/architecture*`, `docs/design*`, `docs/code-review*`.
- **Coding guidelines** — search for `CLAUDE.md`, `.editorconfig`, linter configs, style guides.
- **Test patterns** — find test files, identify framework (pytest, jest, vitest, etc.) and naming conventions.
- **Main branch** — run `git branch -r` to determine `main`, `master`, or other.
- **Project structure** — note directory layout and architectural pattern (layered, MVC, monolith, etc.).

For **fullstack/monorepo** projects: identify each part separately (e.g., "React frontend in `client/`, FastAPI backend in `server/`").

### Step 2: Generate `.claude/commands/review.md`

Create the file. The generated command must follow this structure:

1. Identify changed files via `git diff <main_branch>...HEAD`
2. Read project guideline/architecture files for calibration
3. Launch **3 agents in parallel**, each returning a findings table (`# | Severity | Category | File:Line | Issue | Suggested Fix`)
4. Consolidate, deduplicate, verify findings against actual code
5. Classify severity (Critical / Major / Minor)
6. Fix if user approves — one commit, max 2 review-fix cycles

**The 3 agents must be:**

| Agent | Focus | What to tailor |
|-------|-------|---------------|
| **1: Structure & Architecture** | Import direction, module boundaries, layer violations, coupling | Reference actual architecture docs found. If the project has documented layer rules, check against them. If not, check for general dependency hygiene and circular imports. |
| **2: Code Quality & Security** | Docstrings, naming, type safety, security anti-patterns, SRP, file size | Reference actual coding guidelines found. Match the project's documented conventions (e.g., Google-style docstrings, specific naming rules). |
| **3: Tests & Framework Patterns** | Test coverage, naming, plus **framework-specific** best practices | This is the agent that varies most. Tailor checks to the detected framework — e.g., Qt thread safety for PySide6, hook rules for React, N+1 queries for Django, goroutine leaks for Go, ownership patterns for Rust. |

**Important generation rules:**
- Reference **actual file paths** found in discovery — don't use placeholders or generic paths
- Every `{{placeholder}}` must be resolved — none should appear in the output
- Include the instruction: "Each agent MUST verify findings against actual code before reporting"
- Include: "Do NOT auto-merge — present results and let the user decide"
- If a `docs/code-review-template.md` or similar exists, instruct agents to follow it

### Example Output

For reference, here's what a good generated `review.md` looks like for a Python/Qt project:

```
Run a full agent review on the current branch. $ARGUMENTS

Process:

1. **Identify changes** — run `git diff main...HEAD --name-only` and `git diff main...HEAD --stat`.

2. **Read project rules** for review calibration:
   - ARCHITECTURE.md
   - CLAUDE.md § Code Readability & Comments
   - CLAUDE.md § Error Handling Strategy
   - docs/gui-design.md
   - docs/code-review-template.md

3. **Launch 3 agents in parallel:**

   **Agent 1: Structure & Architecture**
   - Read: changed files + ARCHITECTURE.md
   - Check: import direction per layer rules, signal connections, __init__.py exports, cross-layer coupling
   - Return: findings table (# | Severity | Category | File:Line | Issue | Suggested Fix)

   **Agent 2: Code Quality & Security**
   - Read: changed files + CLAUDE.md § Code Readability + CLAUDE.md § Security
   - Check: docstrings (Google-style), naming conventions, type hints, security anti-patterns, file size (<300 lines), SRP
   - Return: findings table (same format)

   **Agent 3: UI, Tests & Qt Patterns**
   - Read: changed files + docs/gui-design.md + CLAUDE.md § Testing Rules
   - Check: QSS color compliance, signal/slot usage, GUI thread blocking, QTimer/QThread cleanup, test coverage, test naming (test_<what>_<expected>)
   - Return: findings table (same format)

   Each agent MUST verify findings against actual code before reporting.
   Each agent follows calibration rules from docs/code-review-template.md.

4. **Consolidate** — merge, deduplicate, verify each finding.

5. **Classify severity:**
   - Critical: breaks functionality, security vulnerability, data loss
   - Major: violates project rules, likely bug, maintainability risk
   - Minor: style, naming, documentation

   Present findings table + dismissed false positives.

6. **Fix** — if user approves, fix by severity (Critical → Major → Minor). One commit. Re-verify.

Rules:
- Full review (3 agents, all categories) regardless of scope
- Maximum 2 review-fix cycles
- Do NOT auto-merge — present results and let the user decide
```

Your generated file should follow this pattern but be **tailored to the actual project** — different framework checks, different doc references, different agent names.

### Step 3: Generate `.claude/commands/ui-test.md`

If the project has a UI layer (detected via PySide6/PyQt/tkinter/React/Vue/Svelte/Angular imports), generate a project-specific `/ui-test` command.

**Discovery (use what you already found in Step 1):**
- **UI framework** — PySide6, React, Vue, etc.
- **UI files location** — e.g., `src/ui/`, `src/components/`, `client/src/`
- **Style definitions** — e.g., `src/ui/styles.py`, `src/theme.ts`, CSS files
- **Existing UI tests** — e.g., `tests/ui/`, `**/*.test.tsx`
- **Test runner** — pytest-qt, vitest, jest, etc.

**The generated command must follow this structure:**

1. **Run existing UI tests** — use the detected test runner and test location. If no UI tests exist, skip and note it in the report.

2. **Launch 2 agents in parallel:**

   **Agent 1: UX Review** — read all UI files and check:
   - Feedback states (loading, success, error for every user action)
   - Empty states (what the user sees with no data, in every view/component)
   - Error states (are errors caught, user-friendly, UI recovers?)
   - Accessibility (tooltips, keyboard navigation, ARIA/accessible names)
   - Navigation (can user tell where they are? consistent patterns?)
   - Consistency (same patterns across views, uniform terminology)

   **Agent 2: Design & Style Review** — read style definitions + all inline styles and check:
   - Color contrast (WCAG AA: 4.5:1 normal, 3:1 large text) — list specific color pairs from the code
   - Color harmony (cohesive palette, no clashing colors)
   - Font hierarchy (extract all sizes, check consistency, min 12px)
   - Spacing consistency (extract all values, check for consistent scale)
   - Component styling (similar components styled alike, centralized styles)
   - Style violations (hardcoded values outside the theme/constants file)

3. **Combined report** — merge test results + both agent findings into one report with: Test Results, UX Issues table, WCAG table, Design Issues table, Style Violations table, Style Metrics, What's Working Well.

**Important generation rules:**
- Reference **actual file paths** found in discovery (e.g., `src/ui/views/*.py`, not generic placeholders)
- Specify the **exact test command** (e.g., `python -m pytest tests/ui/ -v --tb=short`)
- List the **exact style file** to read (e.g., `src/ui/styles.py`)
- List the **exact UI files** for agents to read
- Include framework-specific checks:
  - **PySide6/PyQt**: QSS compliance, signal/slot patterns, GUI thread blocking, widget lifecycle
  - **React**: hook rules, re-render optimization, prop drilling, key usage
  - **Vue**: reactivity gotchas, composition API patterns, template vs script style
- Include: "Each agent MUST verify findings against actual code before reporting"

**Example for a PySide6 project:**

```
Run a complete UI/UX quality check. $ARGUMENTS

## Step 1: Run tests
\`\`\`bash
python -m pytest tests/ui/ -v --tb=short
\`\`\`

## Step 2: Launch 2 agents in parallel

### Agent 1 — UX Review
Read: src/ui/main_window.py, src/ui/views/*.py, src/ui/widgets/*.py
Check: feedback states, empty states, error states, accessibility, navigation, consistency
[detailed criteria...]

### Agent 2 — Design Review
Read: src/ui/styles.py, then grep for setStyleSheet() across src/ui/
Check: WCAG contrast, color harmony, font hierarchy, spacing, button styling, inline violations
[detailed criteria...]

## Step 3: Combined report
[report template...]
```

If the project has **no UI layer**, skip this step entirely and note: "No UI layer detected — skipping /ui-test generation."

### Step 4: Report

After creating the file(s), output:

```
Created:
- .claude/commands/review.md
- .claude/commands/ui-test.md  (or "skipped — no UI layer detected")

Detected:
- Stack: [language + framework]
- UI Framework: [PySide6 / React / Vue / none]
- Architecture: [pattern or "not documented"]
- Guidelines: [docs found or "none — using defaults"]
- Tests: [framework] ([count] test files)
- UI Tests: [found at path / none]
- Main branch: [branch]

Available commands:
- /review — full code review
- /ui-test — UI/UX quality check
```

## Rules

- Do NOT ask the user any questions — auto-detect everything
- Do NOT modify any existing files besides `.claude/commands/review.md` and `.claude/commands/ui-test.md`
- If `.claude/commands/review.md` already exists, warn the user and ask whether to overwrite or skip
- Same for `.claude/commands/ui-test.md` — warn and ask if it exists
- Create the `.claude/commands/` directory if it doesn't exist
