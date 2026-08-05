Run a full agent-based code review on the current branch. $ARGUMENTS

Stop criterion:
If a review cycle produces zero Critical/Major findings with real
user impact in the documented threat model, declare done. Do NOT
run another review cycle. Empty results are the success signal,
not a prompt to re-run with looser criteria.

Process:

1. **Identify changes** — determine the trunk branch first. If `.claude/project-params.md` exists and names a `Trunk branch`, verify that branch exists locally and use it; otherwise autodetect: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the `origin/` prefix); if unset, use local `main`, then `master`; if none exists, ask the user which branch to diff against. Then run `git diff <trunk>...HEAD --name-only` and `git diff <trunk>...HEAD --stat`. An empty diff against an existing trunk means "nothing to review" — report that and stop; do NOT silently fall back to a different branch.

2. **Discover project rules** — if `.claude/project-params.md` exists (written by
   /setup-project), read it first and use it as a discovery shortcut: re-verify its paths
   cheaply instead of searching from scratch, and if the project has drifted, trust what you
   find over the list. Otherwise, search the repo for guideline files:
   - `CLAUDE.md`, `CONTRIBUTING.md`, `.editorconfig`, linter configs
   - Architecture docs (`ARCHITECTURE.md`, `docs/architecture*`, `docs/design*`)
   - Any `docs/code-review-template.md` or similar review guidelines
   - Test conventions (look at existing tests for patterns)

   Use whatever you find to calibrate the review. If a project has its own review template, follow it.
   Pass the relevant parameters (framework-specific checks, test conventions, doc paths) into
   the agent prompts in Step 3 — subagents do not read this file themselves.

3. **Launch 3 agents in parallel** to review all changed files (a 4th agent runs sequentially in Step 6):

   **Agent 1: Structure & Architecture**
   - Read: all changed files + any architecture/design docs found
   - Check: dependency direction, import hygiene, layer violations, module boundaries, `__init__.py` exports, cross-module coupling
   - Return: findings table (# | Severity | Category | File:Line | Issue | Suggested Fix; File = repo-relative path, forward slashes, exactly as `git diff --name-only` prints it, then `:<line>`)

   **Agent 2: Code Quality & Security**
   - Read: all changed files + any coding guidelines found
   - Check: docstrings, naming conventions, type hints, security anti-patterns (eval, hardcoded secrets, shell injection), file size, single responsibility
   - Return: findings table (same format)

   **Agent 3: Tests & UI/Framework Patterns**
   - Read: all changed files + any test conventions and UI/design guidelines found
   - Check: test coverage for changes, test naming conventions, framework-specific best practices (detect from imports: Qt, React, Django, FastAPI, etc.), thread safety, resource cleanup
   - Return: findings table (same format)

   Each agent MUST verify findings against actual code before reporting — expect ~20% false positive rate. Discard anything that doesn't hold up on re-read.

4. **Consolidate** — merge findings from all 3 agents. Deduplicate. Verify each finding against the actual code.

5. **Classify** — assign severity:

   - **Critical:** currently breaks for a real user — failing test,
     runtime error, broken feature, exploitable security hole within
     the project's documented threat model (CLAUDE.md / SECURITY.md),
     or active data loss happening now.

   - **Major:** definite present-day bug not yet caught by tests, OR
     explicit project-rule violation with real user-facing impact in
     the documented threat model, OR a test that passes despite
     hiding a real bug (false-passing test, weak assertion), OR a new
     feature/function/class added without any test coverage.

   - **Minor:** style, naming, documentation gaps, refactoring
     suggestions without a concrete rule violation, partial test
     coverage (missing edge cases). "Could be better" lives here.

   **Calibration:** It is expected and correct for well-reviewed diffs
   to produce zero Critical/Major findings. Do NOT invent or inflate
   findings to fill the report. An empty Major list is a valid,
   successful result.

   **Recalibration example:** A test that asserts only
   `result is not None` was previously flagged Critical
   (false-passing test). Under these rules it is Major — it is a
   future risk, not a present break.

   Present the final findings table + dismissed false positives table.

5b. **Severity calibration ladder** — applied to each Critical and
    Major finding, in order; the FIRST matching rule decides and
    later rules are not consulted. Findings classified Minor in
    Step 5 are never touched by this ladder.

    0. **No threat-model document.** If the project has no documented
       threat model (no CLAUDE.md / SECURITY.md / equivalent with
       security or harm guidance), skip this ladder entirely, keep
       the Step 5 severities, and add one line to the report: "No
       threat model documented — 5b calibration skipped."
    1. **Defined-Major exemption.** A false-passing test, a weak
       assertion hiding a real bug, or a new feature/function/class
       with no test coverage stays Major by definition (Step 5) — no
       harm-path articulation required. These are future risks by
       nature; that is exactly why Step 5 defines them as Major.
    2. **Architecture-decision exception.** A finding that violates a
       *specifically cited, numbered or named* architecture decision
       (an ADR/decision-record entry or a named architectural pattern
       documented as a hard rule in the project's design docs) stays
       Major without a harm path. The finding MUST cite the decision
       identifier or doc section explicitly (e.g., "Decision #N:
       <name>"); vague "violates documented practice" does NOT
       qualify. Code style, naming conventions, docstring rules,
       type-hint requirements, and testing conventions are NOT
       architecture decisions for this purpose, even when they
       appear in CLAUDE.md. This exception never upholds Critical —
       Critical always requires present-day breakage.
    3. **Concrete harm-path test.** Write one sentence: "What
       concrete user-facing harm path does this finding open?" The
       harm path may lie inside OR outside the documented threat
       model, but it must be concrete — no abstract "violates best
       practice" reasoning. Articulated → severity stands. Not
       articulable → downgrade one level (Critical → Major,
       Major → Minor).
    4. **Drop rule for downgraded findings.** A finding that arrived
       at Minor via rule 3 is DROPPED from the report — it already
       failed the concreteness test. Findings that were Minor from
       Step 5 remain listed as Minor (they are not subject to this
       ladder at all).

6. **Sister-paths sweep** — launch ONE additional agent
   (sequentially, AFTER the three review agents from Step 3) with
   this single job:

   - Read the last 10 commits matching `fix(...)`:
         git log --grep="^fix" --oneline -n 10
   - Skip fix commits that belong to the branch currently under
     review (e.g., "fix: address review findings" commits created in
     this run) — re-scanning them only re-raises findings that were
     already reviewed.
   - For each fix pattern, check ONLY whether the same fix was
     applied to direct sister code paths — same module, same class
     family, same command/handler tier.

     Example: a fix in a service's `create_*` method should be
     checked against sibling `update_*` / `delete_*` methods on the
     same service, and against equivalent CRUD methods on related
     services in the same tier — NOT the entire codebase.

   - Do NOT perform a general codebase-wide pattern scan.
   - Findings from this agent follow the same Step 5 + Step 5b
     severity, harm-path, and architecture-decision rules.

   This step is intentionally isolated to ONE agent. Do NOT instruct
   the three Step-3 agents to perform this sweep — keep the noise
   contained.

7. **Fix** — if user approves, fix findings grouped by severity (Critical → Major → Minor). One commit for all review fixes. Then re-verify fixes are correct.

Rules:
- Always run full review (3 agents, all categories) regardless of scope
- Maximum 2 review-fix cycles
- Do NOT auto-merge — present results and let the user decide
- Adapt categories to the project's tech stack — don't check for things irrelevant to the project