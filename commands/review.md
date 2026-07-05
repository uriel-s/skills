Run a full agent-based code review on the current branch. $ARGUMENTS

Stop criterion:
If a review cycle produces zero Critical/Major findings with real
user impact in the documented threat model, declare done. Do NOT
run another review cycle. Empty results are the success signal,
not a prompt to re-run with looser criteria.

Process:

1. **Identify changes** — run `git diff main...HEAD --name-only` to get all changed files. Run `git diff main...HEAD --stat` for a summary. If no changes found against `main`, try `master`.

2. **Discover project rules** — search the repo for guideline files:
   - `CLAUDE.md`, `CONTRIBUTING.md`, `.editorconfig`, linter configs
   - Architecture docs (`ARCHITECTURE.md`, `docs/architecture*`, `docs/design*`)
   - Any `docs/code-review-template.md` or similar review guidelines
   - Test conventions (look at existing tests for patterns)

   Use whatever you find to calibrate the review. If a project has its own review template, follow it.

3. **Launch 3 agents in parallel** to review all changed files (a 4th agent runs sequentially in Step 6):

   **Agent 1: Structure & Architecture**
   - Read: all changed files + any architecture/design docs found
   - Check: dependency direction, import hygiene, layer violations, module boundaries, `__init__.py` exports, cross-module coupling
   - Return: findings table (# | Severity | Category | File:Line | Issue | Suggested Fix)

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

5b. **Threat-model harm-path check** — for each Critical and Major
    finding, write one sentence answering:

    "What concrete user-facing harm path does this open, given the
     project's documented threat model (per the project's CLAUDE.md /
     SECURITY.md / equivalent)?"

    Rules:
    - If you cannot articulate a concrete harm path within the threat
      model: downgrade Critical → Major, or Major → Minor.
    - Minor findings without a concrete harm path should be DROPPED,
      not downgraded further.
    - **EXCEPTION — Architecture-decision violations:** a finding that
      violates a *specifically cited, numbered or named* architecture
      decision (an ADR/decision-record entry or a named architectural
      pattern documented as a hard rule in the project's design docs)
      may stay at Major even without an articulated user-facing harm
      path. The finding MUST cite the decision identifier or doc
      section explicitly (e.g., "Decision #N: <name>"). Vague
      invocations like "violates documented practice" do NOT qualify.
      This exception does NOT apply to Critical — Critical still
      requires present-day breakage even when an architecture
      decision is violated.
      Code style, naming conventions, docstring rules, type-hint
      requirements, and testing conventions are NOT "architecture
      decisions" for this purpose, even when they appear in
      CLAUDE.md.
    - Genuine Critical/Major findings OUTSIDE the documented threat
      model and OUTSIDE the architecture-decision exception are
      allowed only if the harm path is articulated explicitly. No
      mechanical pass-through. No abstract "violates best practice"
      reasoning.
    - This rule applies to Critical/Major only. Existing Minor
      classifications (style, partial test coverage) are NOT subject
      to harm-path articulation.

6. **Sister-paths sweep** — launch ONE additional agent
   (sequentially, AFTER the three review agents from Step 3) with
   this single job:

   - Read the last 10 commits matching `fix(...)`:
         git log --grep="^fix" --oneline -n 10
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