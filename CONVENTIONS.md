# Shared Conventions — Claude Command System

Maintainers' document (NOT a command; lives only in this repo, not in `~/.claude/commands/`).
Single source of truth for definitions shared across the command files. Subagent prompts must
be self-contained — they never read this file at runtime — so several blocks below are COPIED
into command files. Each block lists where its copies live; when editing here, update every
copy in the same change.

## Deployment model

- **Source of truth:** this repo (`commands/*.md`), versioned in git.
- **Live deployment:** `~/.claude/commands/` (global — available in every project) is a
  directory junction pointing at the deployment clone's `commands/` directory, set up once by
  `install.ps1` together with a `SessionStart` hook (`git pull --ff-only --quiet`). `git pull`
  *is* the deploy, and deletions propagate automatically.
- **No per-project command copies.** Commands are never copied into a project's
  `.claude/commands/`. A master edit therefore takes effect in every project on the next
  session start, with no per-project reinstall step and nothing that can drift.
- **Per-project data:** `/setup-project` **generates** exactly two files — `.claude/checks.sh`
  (the toolchain contract) and `.claude/project-params.md` (a discovery cache read by
  `review.md` Step 1 (trunk) and Step 2 (rules), and `ui-test.md` Step 0). Both are
  regenerable; neither is hand-maintained. It touches three more, listed below, under
  different rules.
- **Three git-level files, added 2026-08-06** (`/setup-project` Step 4): `.gitignore` gets
  run-artifact patterns, `.gitattributes` gets `*.sh text eol=lf`, and `.githooks/pre-push`
  refuses pushes straight to the trunk. All three are user-owned and NOT regenerable, so they
  are handled the opposite way from the two generated files: append-only or
  ask-before-replacing, idempotent, never silently overwritten. They earn their place because
  the alternatives are behavioural guards doing structural jobs — `work.md` carries a standing
  "never commit `.work-context.md`, stage explicitly, no `git add -A`" rule, and `/pr`'s trunk
  refusal only covers the `/pr` path. `/pr` is what raised the stakes: it turned these from
  local clutter into pushed content.
- The push guard is versioned once and opted out of **per machine**
  (`git config claude.allowTrunkPush true`), because the maintainer legitimately pushes the
  trunk after a local `/dev-finish` merge while everyone else should not. Same file, different
  behaviour per clone — the alternative, per-developer hook variants, would drift immediately.
- **The hook file alone does not install the guard.** `core.hooksPath` is per-clone config and
  is not committed, so a fresh clone gets a dormant file — and on projects that use
  `pre-commit` it **must stay dormant**, because setting `core.hooksPath` replaces
  `.git/hooks/` and silently disables existing `pre-commit` hooks (see `README.md` under
  *Per-project setup*).
- Every field written into `project-params.md` must have a named reader above. A field nobody
  reads is the exact defect that got `/setup-review` deleted — when adding one, cite its
  consumer here or leave it out.
- Only the agent EXECUTING a command file reads the cache — never the leaf agents it spawns.
  (Under `/dev` that executing agent is itself a subagent; the rule is about position in the
  tree, not about being a subagent.) Leaf agents get no file access to it, so each consumer
  must inline the relevant parameters into its agent prompts (`review.md` Step 2,
  `ui-test.md` Step 2).
- Project params are a shortcut, never authoritative: every consumer re-verifies cheaply and
  trusts what it finds over the cache. A missing `project-params.md` degrades to full
  discovery, so it is a warning, never a blocker.

Superseded (2026-08-05): `/setup-review` installed stamped copies of `review.md` / `ui-test.md`
into each project. It was removed — `review.md` never read the parameters section it generated,
so the forked copies cost drift-detection machinery for no benefit.

## Severity ladder (canonical)

Copies: `review.md` Step 5 (definitions) + Step 5b (calibration ladder); `dev.md` consumes the
resulting counts in Phase D.

- **Critical** — currently breaks for a real user: failing test, runtime error, broken feature,
  exploitable security hole within the documented threat model, or active data loss.
- **Major** — definite present-day bug not yet caught by tests; OR explicit project-rule
  violation with user-facing impact; OR a false-passing test / weak assertion hiding a real
  bug; OR a new feature/function/class with no test coverage.
- **Minor** — style, naming, documentation gaps, refactoring suggestions, partial test
  coverage. "Could be better" lives here.

Calibration: zero Critical/Major findings is a valid, successful result. Never inflate.

## Findings table schema (canonical)

Copies: `review.md` Step 3 agent specs; `dev.md` Phase C output contract.

```
# | Severity | Category | Origin | File:Line | Issue | Suggested Fix
```

`Origin` = `in-diff` (code authored/modified in the reviewed diff) or `outside-diff` (defect
originates in code outside the diff that the reviewed code depends on).

`File:Line` = repo-relative path with forward slashes, byte-identical to `git diff
--name-only` output (no `./` prefix, no absolute paths, no Windows drive letters or
backslashes), then `:<line>` — e.g. `src/app/main.py:42`. Required because dev.md's Phase D
machine-compares File values against `git diff --name-only`; Phase D additionally parses by
stripping the trailing `:<digits>` suffix (last colon followed only by digits) and normalizes
backslashes / `./` / absolute prefixes defensively.

## STATUS vocabulary (canonical)

Copies: `work.md` (--auto returns), `dev.md` Phase B/C prompts and end-of-run signal.

- Work agents: `SUCCESS | FAILED | NEEDS_SPLIT | NEEDS_DECISION`
- Review agents: `COMPLETE | FAILED`
- /dev end-of-run: `DONE | STOPPED | FAILED`

## Argument parsing (canonical)

Copies: `pr.md` Arguments; the `--auto` rule in `work.md` Rules.

Command files are read by a model, not parsed by a shell, so a rigid flag grammar is a
constraint we impose rather than one the platform requires. Default to accepting **both** the
documented flag and an equivalent phrase in prose ("open it as a draft" = `--draft`). Document
the flag as canonical so machine callers and reports have one stable spelling.

**Exception — flags that suppress a safety gate must require their exact token, as a
whole word, and must never be inferred from prose.** Today that is `/pr`'s `--yes` (skips the
confirmation before an irreversible push) and `/work`'s `--auto` (suppresses the plan-approval
gate). Field evidence: `/work` once entered unattended mode because a task *description*
merely mentioned `--auto`. Fuzzy matching makes that class of bug more likely, not less.

The test for which side a flag falls on: **what does a false positive cost?** A misread
`--draft` costs one needless question. A misread `--yes` costs an unapproved push, and no
local revert undoes it.

## Output size limits (canonical)

Copies: inlined into each subagent prompt in `dev.md` Phases B, C, E (plus the reference
section at the bottom of dev.md).

- Total subagent response under 8KB.
- `BLOCKER`: max 200 chars. `DECISIONS`: max 5 items × 100 chars.
- `FINDINGS_TABLE`: max 30 rows × 200 chars; overflow → top 30 by severity + `TRUNCATED: yes`.

## Python toolchain contract

All target projects are Python (decision 2026-07-05). Copies: `work.md` subagent prompt and
Step 4; `dev.md` Phases E/F/G. Canonical script: `templates/checks.sh` in this repo, emitted
into projects by `/setup-project` (which substitutes only the `SRC=` / `TESTS=` lines). The
copy inlined in `setup-project.md` Step 2 must stay byte-identical to `templates/checks.sh`.

`.claude/checks.sh <subcommand>`:

| Subcommand | Runs | Notes |
|---|---|---|
| `test` | `python -m pytest "$@"` | full suite by default; trailing args narrow it to specific paths. `QT_QPA_PLATFORM=offscreen` for headless Qt |
| `lint` | `python -m ruff check <src> <tests>` | no auto-fix |
| `format` | `python -m ruff format --check <src> <tests>` | check only, never rewrites |
| `arch` | `lint-imports` | SKIP if import-linter missing |
| `types` | `python -m mypy <src>` | SKIP if mypy missing |
| `sec` | `bandit -q -r <src>` + `pip-audit` | each SKIPs independently if missing |
| `all` | every check above | runs ALL, reports EVERY failure — no early abort |

`security` is accepted as an alias for `sec` (pre-2026-07-31 projects call it that).

`sec` does **not** scan for secrets — bandit reads code patterns and pip-audit reads
dependencies. Nothing in `checks.sh` would catch a committed key. That gap was harmless while
every command stayed local; `pr.md` Step 3 covers it with a diff-scoped grep because a pushed
secret cannot be withdrawn, only rotated.

Exit 0 = green, non-zero = red. A SKIP is not a failure. `all` deliberately does not
short-circuit: `dev.md` Phase F, `dev-finish.md` Step 3 and `pr.md` Step 1 must report which stage failed, which a
`&&` chain cannot answer once the first stage is red.

Fallback when the script is missing entirely: run `python -m pytest` / `python -m ruff check .`
directly and report the degradation.

Only `all`, `test`, and `lint` are invoked by the command files today; the rest exist for
manual use and for `all` to aggregate.

Nothing may invoke `pytest` directly — `checks.sh test <paths>` covers the narrow-run case, and
bypassing it silently drops `QT_QPA_PLATFORM=offscreen`. The one sanctioned exception is
`dev.md`'s fix phase calling `ruff check --fix`: `checks.sh` is a verification contract and
never rewrites files, so auto-fix has no subcommand by design.

## Cumulative pre-integration review (canonical)

Copies: `dev-finish.md` Step 1, `pr.md` Step 2.

Both commands close out a branch, and both run the same review first: `/review` over the
branch's **whole** cumulative diff against the trunk. Under `/dev` each section was reviewed
alone with a one-cycle fix budget, so this pass is what catches regressions that appeared
*between* sections; after a plain `/work` run it is simply the branch's first review.

Deliberately **not** factored into a shared command. The common part is one line — "run
`/review` against the trunk" — while the callers differ in base (`{base_branch}` vs
`origin/{base}`), in where it sits relative to `checks.sh all` (after the merge vs before
the push), and in what a Critical/Major result means (block the merge vs offer to open the
PR anyway). A third command whose entire body is parameters is the defect that got
`/setup-review` deleted; these two copies plus this block are cheaper and drift visibly.

Shared in both copies: present the findings table; Critical/Major → ask rather than decide;
Minor-only or clean → proceed.

## Trunk detection (canonical algorithm)

Copies: `dev.md` pre-flight, `review.md` Step 1, `setup-project.md` Step 1, `pr.md`
pre-flight 5, `ready.md` pre-flight 2.

1. Explicit override (`--base`) if given → verify it exists.
2. `Trunk branch` from `.claude/project-params.md` if present → verify the branch exists locally.
3. `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`) if set and exists.
4. Local `main`, then local `master` — first existing wins.
5. Otherwise: ask the user (or, for non-interactive discovery, use the current branch + note).

Steps 1 and 2 are conditional on the call site, and a site omitting one is correct, not
drifted: `/dev`, `/review`, `/pr` and `/ready` accept `--base`, and only `review.md` reads the
cache (`setup-project.md` WRITES that field, so it cannot read it). Every site implements
steps 3–5.

`/pr` and `/ready` additionally insert their own step between 1 and 2: `gh api
repos/{owner}/{repo} --jq .default_branch`. That is not drift — both ask GitHub what is
merged, so GitHub's own default branch is authoritative over any local inference about which
branch is trunk. `/ready` takes it only in full mode (its pre-flight 4); with no working `gh`
it falls straight through to step 3.

**Local vs remote base.** Steps 2–4 all resolve to a *local* branch, which is correct for
every command that merges locally. `/pr` merges on GitHub, so once the base name is
resolved it compares against `origin/{base}` after an explicit fetch — a stale local trunk
would otherwise produce a review diff that does not match the PR. This is why `review.md`
takes `--base <ref>` (any ref, including remote-tracking) rather than `--base <branch>`.

## Branch naming (/dev)

Copies: `dev.md` throughout; consumed by `dev-finish.md` cleanup, by `pr.md` Step 4 (which
must NOT derive a remote branch name from these) and Step 8 (which deletes the section
branches), and by `ready.md` Step 3 rule 4 (which recognises section branches by this pattern
but must still prove the merge with ancestry — the name is not evidence).

- Integration branch: `dev_main` (numbered fallbacks `dev_main_2`, `dev_main_3`, ...).
- Section branches: `{integration_branch}--section-{N}-{slug}` (slug ≤40 chars, lowercased,
  hyphenated). The `--` separator is mandatory: git cannot create `X/...` while branch `X`
  exists, and field evidence (2026-07-05) shows executors improvise inconsistent schemes when
  handed the impossible `/` form.

## Remote branch naming (/pr)

Copies: `pr.md` Step 4 (writes them); `ready.md` Step 3 (reads them back — it must query
GitHub by the *remote* name and print the *local* one, and it uses the `{login}/` prefix in
Step 6 to tell your remote branches from the other developer's). Local names above are
per-machine; these are shared.

- `{gh-login}/{slug}`, pushed via `git push -u origin HEAD:refs/heads/{name}` so the local
  branch keeps its own name.
- `{gh-login}` comes from `gh api user --jq .login`, but only after `gh api
  repos/{owner}/{repo} --jq .permissions.push` confirms that account has push on *this*
  repo. `gh` authenticates several accounts per machine and `api user` returns the active
  one, which need not be the one that owns or can write the remote.
- `{slug}` never derives from a `/dev` convention name (`dev_main`, `dev_main_N`): those are
  identical across every run and every developer, so they collide by construction. Source
  order is plan title → section 1 title → current branch name → `work-{short-sha}`.
- An existing upstream on `origin` outranks all of the above and is reused verbatim — that
  is what makes a repeat run update its PR instead of opening a rival one.

## Push & merge prohibition (canonical)

Copies (wording may compress, meaning may not): `work.md` Step 3.d + Rules; `dev.md` Rules;
`dev-finish.md` Rules; `review.md` Rules; `pr.md` Rules; `ready.md` Rules.

**Default: never push, never merge, never delete a branch without explicit user approval in
the current session.** Approval for one of those is not approval for another, and approval
in one run does not carry to the next.

`/ready` is the one command whose *purpose* is branch deletion, and it stays inside the
default rather than claiming an exception: local branches only, only ones positively proven
merged, all of them behind one gate in the session that runs it. It never deletes on a remote
— it prints the `git push origin --delete` line and leaves it. That is the line between a
revertible local pointer and an act everyone else on the repo sees.

**The single sanctioned exception is `/pr`**, bounded to exactly this shape:

| | |
|---|---|
| what | the current branch, nothing else |
| where | `origin`, one remote branch matching the `/pr` naming rule above |
| how | fast-forward only — **never** `--force` or `--force-with-lease` |
| when | after `/pr`'s one confirmation gate, or with `--yes` |

Anything outside that shape stays forbidden inside `/pr` too. `/pr` never merges: it opens
a PR and a human merges it on GitHub. `/dev-finish` is the only command that merges to a
trunk, and only a local one.

A local merge is revertible and a push is not, which is why `/dev-finish` can verify after
its merge while `/pr` must verify before its push.
