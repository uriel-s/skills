Run sections from a plan autonomously. Only stop for genuinely critical decisions. $ARGUMENTS

## Purpose

Execute multiple plan sections back-to-back, each going through work → review → conditional-fix → merge. The user is not at the screen during execution. The orchestrator stops only when a decision genuinely requires human judgment.

**All merges target an integration branch (`dev_main` or numbered fallback). Never merge to the trunk (`{base_branch}`). The `{base_branch}` merge is a separate manual step after /dev finishes.**

`{base_branch}` is whatever the project calls its trunk — `main`, `master`, `trunk`, etc. /dev autodetects it at pre-flight (see `## Pre-flight`), so it works on any project without configuration. Pass `--base <branch>` to override. The integration branch name `dev_main` is a fixed convention — it is **not** derived from `{base_branch}` and is not renamed when the trunk is `master`/`trunk`/etc.

## Plan file format

`.dev-plan.md` is user-authored. Required format:

```markdown
# Plan: <project or feature name>

## Section 1: <short title>
<2–5 sentences describing what to build, key files involved, and acceptance
criteria. This body gets passed verbatim to the work subagent.>

## Section 2: <short title>
<description>

## Section 3: <short title>
<description>
```

Rules:
- H2 headers, numbered sequentially starting at 1, exact format `## Section N: <title>`
- Title becomes the branch slug (lowercased, hyphenated, ≤40 chars)
- Everything between one H2 and the next is that section's body
- Top-level H1 is optional metadata, ignored by the orchestrator

## Files

- `.dev-plan.md` — input. User-authored. Editable mid-run; orchestrator detects edits.
- `.dev-state.md` — execution state, for resumability across crashes/reboots.
- `.dev-log.md` — append-only audit log.

`.dev-state.md` schema (free-form markdown the orchestrator reads narratively):

```
plan_path: .dev-plan.md
integration_branch: dev_main
base_branch: main
started_at: <ISO timestamp>
current_section: 3
current_phase: review
sections:
  - n: 1, title: "...", slug: "...", status: complete, branch: dev_main--section-1-<slug>, merged_at: <ts>, original_text_hash: <sha>
  - n: 2, title: "...", slug: "...", status: complete, branch: dev_main--section-2-<slug>, merged_at: <ts>, original_text_hash: <sha>
  - n: 3, title: "...", slug: "...", status: in_progress, branch: dev_main--section-3-<slug>, original_text_hash: <sha>
  - n: 4, title: "...", slug: "...", status: pending, original_text_hash: <sha>
```

`original_text_hash` is the sha of each section's body at /dev start. Used to detect mid-run plan edits.

## Arguments

- `--plan <path>` — alternate plan file (default `.dev-plan.md`)
- `--from <N>` — start at section N. Assumes sections `1..N-1` are already merged in the integration branch. **/dev does not verify this — user responsibility.** Conflicts with an existing `.dev-state.md` — combine with `--fresh`.
- `--fresh` — delete state file and start over (requires confirmation)
- `--base <branch>` — explicit trunk branch name (overrides autodetect). Default: autodetected at pre-flight from `git symbolic-ref --short refs/remotes/origin/HEAD`, with fallback to local `main` then `master`.

Default: read `.dev-plan.md`, auto-resume from `.dev-state.md` if it exists.

## Orchestrator/subagent split

This is the load-bearing architectural property.

**Main agent does (deterministic mechanics, no source-code reading):**
- Read/write state, plan, log files
- Git plumbing: `status`, `checkout`, `branch`, `merge`, `diff` existence checks
- Run test suite, lint, and security checks via .claude/checks.sh
- Apply decision matrix (count comparison only)
- Spawn subagents and parse their structured output

**Subagents do (judgment + code reading):**
- Implement section code (Phase B)
- Review diffs (Phase C)
- Apply fixes (Phase E)
- Plan-vs-merged contradiction check (Phase A, only when triggered)

Source code never enters main-agent context. This bounds main-agent context regardless of project size or section count.

## Pre-flight (Main Agent)

0. Pre-cleanup: `rm -f .work-context.md` (leftover from any prior /work run that may have crashed mid-execution).
1. **Resume vs fresh — decided FIRST**, before any tree/branch gates (a crashed run legitimately sits on a section branch, possibly with a dirty tree, so the fresh-mode gates below would wrongly block every resume):
   - If `--fresh` was passed → confirm with the user, delete `.dev-state.md`, continue to step 3.
   - If `--from <N>` was passed and `.dev-state.md` exists (without `--fresh`) → **STOP, ask** — `--from` conflicts with an existing run; rerun with `--fresh --from <N>` to discard it.
   - If `.dev-state.md` exists and every section is `complete` → previous run already finished; **STOP**: report done, suggest `--fresh` for a new run.
   - If `.dev-state.md` exists otherwise → **resume mode** (step 2).
   - Else → **fresh mode** (step 3).
2. **Resume mode:**
   - Read `integration_branch` and `base_branch` from state — do NOT re-detect; the run already owns them. If the state file is unreadable, or a branch it records no longer exists → **STOP, ask** (stopping condition 9).
   - If a merge is in progress (`MERGE_HEAD` exists) → `git merge --abort` first.
   - Append `RESUME at section N phase P` to log.
   - Jump to `current_section` / `current_phase` and redo that phase from scratch per `## Recovery semantics`. (`current_phase: preflight` means: enter Phase A of `current_section` normally.) Steps 3–4 below are skipped entirely — resume cleanliness is handled by the recovery hard-reset, not by the fresh-mode gates.
3. **Fresh-mode gates:**
   1. **Determine `{base_branch}`** (the project's trunk):
      - If `--base <branch>` was passed → use it. Verify the branch exists locally; if not → **STOP, ask**.
      - Else autodetect: `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`. If non-empty and the branch exists locally → use it.
      - Else fallback: try local `main` first, then `master`. First existing wins.
      - If still nothing found → **STOP, ask the user** to pass `--base <branch>` explicitly.
      - **Display the chosen `{base_branch}` in the pre-flight log** so the user can interrupt if it's wrong (e.g. autodetect picked the wrong long-lived branch).
   2. Working tree clean? If not → **STOP, ask**.
   3. On `{base_branch}`? If not → **STOP, ask**.
   4. `.dev-plan.md` exists and parses into ≥1 section? If not → **STOP, ask**.
   5. Dependencies present? `.claude/checks.sh` exists. Missing → **STOP, ask** — /dev cannot run without it; run /setup-project first. (`work.md` and `review.md` are global commands in `~/.claude/commands/`, not project files — do not check for project copies.) If `.claude/project-params.md` is missing, warn but continue: /review falls back to searching the repo from scratch.
   6. Baseline tests green on `{base_branch}`? If not → **STOP, ask**.
4. **Fresh mode — choose integration branch and initialize:**
   - Choose integration branch:
     - If `dev_main` doesn't exist → create from `{base_branch}`, use it.
     - If `dev_main` exists with **no** commits ahead of `{base_branch}` → reuse it (it's effectively empty).
     - If `dev_main` exists with commits ahead of `{base_branch}` → **STOP, ask the user**:
       > "`dev_main` has N unmerged commit(s) from a previous run. Continue building on `dev_main`, or start fresh on the next numbered branch (`dev_main_2`, `dev_main_3`, ...)?"

       - "continue" → use existing `dev_main`.
       - "fresh" → find the lowest `dev_main_K` (K ≥ 2) that doesn't exist or has no commits ahead of `{base_branch}`, create from `{base_branch}` if needed, use it.
   - Snapshot each section's body hash into state. **Persist `base_branch` and `integration_branch` in `.dev-state.md`** so resume mode does not re-detect.
   - Initialize `.dev-state.md` (with chosen branch + base) and `.dev-log.md`.
   - Checkout the chosen integration branch.

## Per-section loop

### Phase A — Section pre-flight (Main Agent + conditional Subagent)

1. Re-read `.dev-plan.md`. If it no longer parses, the section count changed, or `## Section {N}` is missing or renumbered → **STOP, ask** (only body edits to existing sections are supported mid-run). Otherwise compute current hash of section N's body.
2. Compare to `original_text_hash` in state.
   - **Hashes match** → skip to step 4. Plan unchanged for this section.
   - **Hashes differ** → user edited this section's body during the run. Spawn the **Plan-Drift subagent** (below). If it returns `CONTRADICTS: yes` → **STOP, ask**. Otherwise update the stored hash and proceed.
3. Plan-Drift subagent prompt:
   ```
   You are the Plan-Drift agent.

   Original section {N} text:
   {original body}

   Current section {N} text:
   {current body}

   Already merged in {integration_branch}: sections 1..{N-1}.

   ## Task
   Read the diff between {integration_branch} and the trunk: `git diff {base_branch}...{integration_branch}`.
   Determine whether the current section text contradicts work in progress.
   Contradiction means ANY of:
   1. Requires undoing, refactoring, or removing already-merged code, OR
   2. Materially changes the scope of section {N} (the section /dev is
      about to start processing) — adds new acceptance criteria,
      removes acceptance criteria, or changes the target deliverable.
   Refinement (typos, clarifications, narrower scope of FUTURE sections,
   adding implementation hints) is NOT contradiction.

   ## Output — return EXACTLY:
   CONTRADICTS: yes | no
   REASON: <one line>
   ```
4. Create branch `{integration_branch}--section-{N}-{slug}` off `{integration_branch}`. Checkout. (The `--` separator is deliberate: git cannot create branch `X/...` while branch `X` exists, so a `/`-based scheme would fail on the first section.)
5. Update state → section {N} `status: in_progress`, `current_phase: work`. Append to log.

### Phase B — Work (Subagent)

Spawn fresh general-purpose Agent. **Prompt:**

```
You are the Work agent for section {N} of /dev.

Branch: {integration_branch}--section-{N}-{slug} (already checked out)
Section title: {title}
Section body:
{body}

## Task
Execute the `/work` command (`~/.claude/commands/work.md`) with `--auto` for the section above.
- The --auto flag suppresses the plan-approval gate per work.md.
- Maximum 5 sub-tasks. If the section needs more, return STATUS=NEEDS_SPLIT.
- Do NOT merge. Do NOT push. Stay on the section branch.
- Delete `.work-context.md` when done.

## Output — return the structure below. Extra prose is acceptable but every
required field must be present and parseable. Missing fields → orchestrator
will treat as FAILED.

STATUS: SUCCESS | FAILED | NEEDS_SPLIT | NEEDS_DECISION
SUBTASKS_COMPLETED: <done>/<planned>
FILES_CHANGED: <comma-separated paths>
NEW_APIS: <signatures with file paths, or "none">
TESTS: <pass> passed, <fail> failed
DECISIONS: <non-obvious choices, or "none">
BLOCKER: <one line, only if STATUS != SUCCESS>

Output size limits: total response under 8KB; BLOCKER max 200 chars;
DECISIONS max 5 items, max 100 chars each.
```

**Main agent on return:**
- `SUCCESS` → Phase C
- `NEEDS_SPLIT` → **STOP**, surface BLOCKER
- `NEEDS_DECISION` → **STOP**, surface BLOCKER
- `FAILED` → retry **once**. Before the retry: `git reset --hard {integration_branch}` on the section branch and `rm -f .work-context.md`, so the retry starts clean instead of on top of the failed attempt's partial commits. Second failure → **STOP**.
  *Note: retry is most useful for transient (tool/network) failures; logic failures usually fail again identically.*

### Phase C — Review (Subagent)

Update state → `current_phase: review`. Spawn fresh Agent. **Prompt:**

```
You are the Review agent for section {N} of /dev.

Branch: {integration_branch}--section-{N}-{slug}
Diff target: {integration_branch} (NOT {base_branch})

## Task
Execute the `/review` command (`~/.claude/commands/review.md`) with these adjustments. review.md is
written for standalone use; wherever it and this prompt disagree, THIS
PROMPT WINS:
- Use `git diff {integration_branch}...HEAD --name-only` and `--stat`
- Run the 3 parallel review agents per review.md Step 3. SKIP Step 6
  (sister-paths sweep) — under /dev it runs later instead, inside
  /dev-finish's cumulative review of the whole integration branch.
- SKIP review.md Step 7 (fix) and its "Maximum 2 review-fix cycles"
  rule. Do NOT offer to fix. Do NOT merge. Review only — /dev has its
  own fix phase with a 1-cycle budget.
- `File:Line` format contract: repo-relative path with forward
  slashes, byte-identical to how `git diff --name-only` prints it (no
  `./` prefix, no absolute paths, no Windows drive letters or
  backslashes), then a colon and the line number — e.g.
  `src/app/main.py:42`. The orchestrator machine-compares File values
  against `git diff --name-only` output; any other format corrupts
  that comparison.
- Tag each finding as "architectural" if and only if it involves at
  least one of:
  * Changing the signature (parameters, return type) of a function or
    class that already exists in the integration branch (was merged
    in a previous section).
  * Adding or removing an export in a previously-merged `__init__.py`.
  * Modifying the schema (fields, types) of a dataclass, Pydantic
    model, or ORM model that was merged in a previous section.
  * Changing a database migration that was merged in a previous
    section.
  * Introducing a new import between two previously-existing Python
    packages (top-level directories with `__init__.py`) that were
    independent. New packages created within this section don't count.
  Otherwise, tag as NOT architectural. When in doubt, tag as NOT
  architectural — `TOUCHES_PREVIOUS_SECTIONS` provides a separate
  safety net, so false positives here just cause unnecessary STOPs.
- Distinguish defects from scope-expansion suggestions:
  * A finding goes in `FINDINGS_TABLE` only if it identifies a defect
    in code authored or modified in this section's diff (`git diff
    {integration_branch}...HEAD`).
  * Observations like "file X outside the diff also has this pattern,
    you might want to update it for consistency" are scope-expansion
    suggestions, NOT findings. Put them in `OUT_OF_SCOPE_SUGGESTIONS`
    so they remain visible without triggering Phase D stops.
  * If a finding inside the diff cites a defect that originates from
    code outside the diff (e.g., the section calls a buggy merged
    function), it stays in `FINDINGS_TABLE` — the section depends
    on that other code being correct, so it's a real blocker. Tag
    such rows `outside-diff` in the `Origin` column; rows about code
    authored or modified in this section's diff are `in-diff`.

## Output — return the structure below. Extra prose acceptable; required
fields must be present.

STATUS: COMPLETE | FAILED
CRITICAL_COUNT: <N>
MAJOR_COUNT: <N>
MINOR_COUNT: <N>
ARCHITECTURAL: yes | no
FINDINGS_TABLE: |
  # | Severity | Category | Origin | File:Line | Issue | Suggested Fix
  <full deduped, verified table; Origin = in-diff | outside-diff;
   File:Line per the format contract above (repo-relative, forward
   slashes, `path:line`)>
DISMISSED_FALSE_POSITIVES: <count>
OUT_OF_SCOPE_SUGGESTIONS: |
  Free-text list of optional improvements that touch files outside
  this section's diff. NOT counted in CRITICAL/MAJOR/MINOR_COUNT.
  NOT classified by severity. Visible in the report but does not
  affect Phase D decisions. Write "none" if there are no suggestions.

Output size limits: total response under 8KB. FINDINGS_TABLE max 30 rows,
each row max 200 chars (Issue + Suggested Fix combined); if more findings
exist, return the top 30 by severity and add a line `TRUNCATED: yes`.
```

### Phase D — Decision matrix (Main Agent, deterministic)

**Before applying the matrix, the main agent computes
`TOUCHES_PREVIOUS_SECTIONS` deterministically (no subagent involved):**

1. Run `git diff {integration_branch}...HEAD --name-only`. Save the
   result as `touched_files`.
2. Parse `FINDINGS_TABLE` from Phase C output. Extract each row's
   `File` from the `File:Line` cell by stripping the trailing
   `:<digits>` suffix — split on the LAST colon that is followed only
   by digits, so a contract-violating absolute Windows path
   (`C:\...:42`) cannot truncate to `C`. Then normalize defensively
   before comparing: backslashes → `/`, strip a leading `./`, and if
   the path is still absolute, strip the repo root prefix
   (`git rev-parse --show-toplevel`). A row is **outside-diff** if its
   `Origin` column says so, or its normalized `File` is NOT in
   `touched_files`.
3. If any outside-diff row has severity Critical or Major, set
   `TOUCHES_PREVIOUS_SECTIONS = yes`. Otherwise `no`. (Minor
   outside-diff rows stay visible in the report but do not stop the
   run — stopping on any Minor that cites a merged file made false
   STOPs routine.)

Apply in order. First match wins:

```
CRITICAL_COUNT >= 1                  → STOP, ask user
TOUCHES_PREVIOUS_SECTIONS == yes     → STOP, ask user
ARCHITECTURAL == yes                 → STOP, ask user
MAJOR_COUNT > 6                      → STOP, ask user  # overwhelming = section likely broken
MAJOR_COUNT >= 3                     → Phase E (fix)
else (clean)                         → skip Phase E, go to Phase F
```

Thresholds are **hard-coded**. Main agent does not interpret. Tune by editing the file.

On STOP: write reason to log and state, output End-of-run signal `STOPPED`, exit.

### Phase E — Fix (Subagent, only if Phase D routes here)

Update state → `current_phase: fix`. Spawn fresh Agent. **Prompt:**

```
You are the Fix agent for section {N} of /dev.

Branch: {integration_branch}--section-{N}-{slug} (already checked out)

## Findings to fix
{paste FINDINGS_TABLE — Major and Minor rows only;
 Critical/Architectural never reach this phase}

## Task
- Fix every listed finding. Do NOT introduce unrelated changes.
- Run tests after each fix group: `bash .claude/checks.sh test`
- Run `bash .claude/checks.sh lint` to verify lint passes. If lint reports
  fixable issues, run `python -m ruff check --fix src/ tests/`, re-stage,
  and amend your fix commit. Final state should be ONE commit that passes
  `bash .claude/checks.sh lint` cleanly.
- Commit message: "fix: address review findings (section {N})"
- Do NOT merge. Do NOT push.

## Output — return the structure below.

STATUS: SUCCESS | PARTIAL | FAILED
FIXED: <count>
SKIPPED: <count, with one-line reason each>
TESTS: <pass>/<fail>
BLOCKER: <one line, only if not SUCCESS>

Output size limits: total response under 8KB; BLOCKER max 200 chars;
SKIPPED reasons max one line each.
```

**Main agent on return:**
- `SUCCESS` → Phase F
- `PARTIAL` (any skipped) → **STOP**
- `FAILED` → **STOP**

**Fix budget: 1 cycle per section.** No re-review-after-fix loops. Bad fixes get caught by the Phase F gate, which runs the full suite on the section's final content. (Phase G's post-merge test is not a second net: it re-runs only when the merge changed the tree, which is the abnormal case.)

### Phase F — Verify gate (Main Agent)

Update state → `current_phase: verify`. One deterministic check. Must be green to proceed.

1. `bash .claude/checks.sh all` (runs lint, security, and the full test suite). Red → **STOP**.

Green → Phase G.

**Do not narrow this to save time, and do not add a lighter tier for it to call.**
Both were proposed and measured on 2026-08-24 (12-core box): every
check in `all` except pytest totals **11 seconds** — ruff 1+1, architecture-map
0, file-size 1, public-api 3, import-linter 1, bandit 3, mypy 1 warm — and
`pip_audit .` is **~30 s**, not the multi-minute cost its reputation suggests.
`all` is the test suite plus ~40 seconds. There is no meaningful time in the
non-pytest checks to reclaim, so a conditional-`pip_audit` branch or a new
`checks.sh gate` subcommand buys tens of seconds for real complexity.

Where the time actually went was Phase G re-running the suite on an identical
tree (step 4 there), and a project suite pinned to one core. Both are fixed at
their source. If a run still feels slow, measure the project's pytest — not this
gate.

### Phase G — Merge to integration branch (Main Agent)

1. Update state → `current_phase: merge`. Checkout `{integration_branch}`.
2. `git merge --no-ff {integration_branch}--section-{N}-{slug} -m "merge: section {N} — {title}"`
3. Merge conflict → **STOP**.
4. Post-merge test — **only when the merge actually changed something.** Compare
   the merged tree to the section branch's:
   ```
   git rev-parse "{integration_branch}--section-{N}-{slug}^{tree}"
   git rev-parse "HEAD^{tree}"
   ```
   - **Identical** → skip the test. Phase F ran the full suite on this exact
     content minutes ago; re-running it cannot discover anything. Log the skip
     **with its reason** ("post-merge test skipped — merged tree identical to
     section branch"), so a reader can tell a proven skip from a gate that
     silently never ran.
   - **Different** → the merge resolved a conflict, or the integration branch
     moved. Run `bash .claude/checks.sh test`. Red → **STOP**.

   This is the normal case, not an edge case: the section branch is cut from the
   integration branch in Phase A and nothing else touches it during a run, so a
   `--no-ff` merge of it produces the same tree. Measured on a 6-section run
   (2026-08-24): identical in 4 of 4 sections checked, at 612 + 802 + 470 + 497
   seconds — **40 minutes** re-testing bytes that had just been tested.

   **Phase F is not the one to cut.** The same run tried skipping *verify* by
   hand and recorded the result: section 3's `check_public_api_preserved.py`
   failure was caught early and cheaply only because the per-section verify ran.
   Phase F earns its cost; this duplicate does not.
5. Update state: **rewrite section N's existing row in place** — set `status: complete` and add `merged_at` — then set `current_section: N+1`, `current_phase: preflight`. Never append a second row for a section that already has one. A 2026-08-24 run left section 5 listed twice, `complete` and `in_progress`, which a resume would read as unfinished work on an already-merged section.
6. Append to log.
7. **Keep the section branch.** Don't delete until /dev finishes successfully.

### Phase H — Continue

More sections? → loop to Phase A.
Else → End-of-run.

## End-of-run signal

Output **exactly one** of these as the final visible line:

```
STATUS: DONE — {N} sections merged to {integration_branch}. Recommended next step: run `/review` manually on {integration_branch} as a final human-overseen check (per-section reviews use a single fix cycle, so this catches regressions that slipped through). Then approve the merge {integration_branch} → {base_branch}.
STATUS: STOPPED at section {N} phase {X} — {one-line reason}. See .dev-log.md for details.
STATUS: FAILED at section {N} phase {X} — {one-line reason}. See .dev-log.md for details.
```

Format is fixed so the user can scan it in two seconds.

## Stopping conditions (consolidated)

The orchestrator stops and asks the user **only** for these:

1. Pre-flight (fresh mode): dirty tree, wrong branch, missing/empty plan, missing dependencies (checks.sh), baseline red, or a state file from an already-finished run
2. Pre-flight (fresh mode only): `dev_main` has unmerged commits — continue or start fresh?
3. Plan edit detected and Plan-Drift agent reports contradiction
4. Work agent: `NEEDS_SPLIT`, `NEEDS_DECISION`, or two consecutive `FAILED`
5. Review: any STOP rule in the Phase D decision matrix matched (the matrix is the single source of truth for review thresholds)
6. Fix: `PARTIAL` with skips, or `FAILED`
7. Tests or lint red at Phase F or post-merge
8. Merge conflict on integration branch
9. State file in unrecoverable state on resume

Anything outside this list: proceed silently.

## Subagent output handling

Subagents return structured fields with possible surrounding prose. Main agent:
- Extracts each required field by name
- Fails only if a required field is missing or unparseable
- Does NOT fail just because the subagent added extra explanation

A failed parse triggers one retry with the same prompt. Second failure → STOP.

### Output size limits (apply to all subagent prompts)

- Total response under 8KB. Summarize if approaching the limit.
- `BLOCKER`: max 200 chars.
- `DECISIONS`: max 5 items, max 100 chars each.
- `FINDINGS_TABLE` (Phase C): max 30 rows. Each row max 200 chars
  (Issue + Suggested Fix combined). If more findings exist, return the
  top 30 by severity and add a line `TRUNCATED: yes`.

These limits are inlined verbatim into each subagent prompt (Phases B, C,
E) — subagents never see this file, so the prompt copies are the
authoritative text. When changing a limit, keep the prompt copies in sync.

## Recovery semantics

On /dev startup with an existing `.dev-state.md`:

1. Read last `current_phase`.
2. Redo that phase **from scratch**. No partial-progress detection.
   - **Before re-running Phase B:** hard-reset the section branch to the
     integration branch:
     `git checkout {integration_branch}--section-{N}-{slug} && git reset --hard {integration_branch}`
     This discards any partial commits from the interrupted run. /work
     then sees a clean tree and replans against current code, with no
     leak from the previous attempt. Also delete `.work-context.md` if
     it exists — leftover state from an interrupted /work run.
   - Re-running Phase E with the fix already applied: fix agent will
     report most findings already resolved and produce an empty/no-op
     commit, which is fine.
3. **Special case:** if `current_phase: merge` and `git log {integration_branch}` shows the merge commit already exists (crash between merge and state update), update state and continue to Phase H. Otherwise redo the merge.

Phase boundaries are short — redo cost is minutes, not hours.

## Rules

- Always merge to integration branch. Never to `{base_branch}` (the trunk).
- One commit per Phase E fix; sub-tasks each get their own commit per /work
- Do not delete section branches until /dev finishes successfully
- Do not push
- Do not bypass the decision matrix
- One fix cycle per section
- Subagents may return prose alongside structured fields; orchestrator parses what it needs
- Main agent never reads source code; that lives in subagents