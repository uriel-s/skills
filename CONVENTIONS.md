# Shared Conventions — Claude Command System

Maintainers' document (NOT a command; lives only in this repo, not in `~/.claude/commands/`).
Single source of truth for definitions shared across the command files. Subagent prompts must
be self-contained — they never read this file at runtime — so several blocks below are COPIED
into command files. Each block lists where its copies live; when editing here, update every
copy in the same change.

## Deployment model

- **Source of truth:** this repo (`commands/*.md`), versioned in git.
- **Live deployment:** `~/.claude/commands/` (global — available in every project). Deploy by
  copying `commands/*.md` there after committing.
- **No per-project command copies.** Commands are never copied into a project's
  `.claude/commands/`. A master edit therefore takes effect in every project immediately, with
  no per-project reinstall step and nothing that can drift.
- **Per-project data:** `/setup-project` writes exactly two files — `.claude/checks.sh` (the
  toolchain contract) and `.claude/project-params.md` (a discovery cache read by `review.md`
  Step 2 and `ui-test.md` Step 0). Both are regenerable; neither is hand-maintained.
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

Exit 0 = green, non-zero = red. A SKIP is not a failure. `all` deliberately does not
short-circuit: `dev.md` Phase F and `dev-finish.md` must report which stage failed, which a
`&&` chain cannot answer once the first stage is red.

Fallback when the script is missing entirely: run `python -m pytest` / `python -m ruff check .`
directly and report the degradation.

Only `all`, `test`, and `lint` are invoked by the command files today; the rest exist for
manual use and for `all` to aggregate.

Nothing may invoke `pytest` directly — `checks.sh test <paths>` covers the narrow-run case, and
bypassing it silently drops `QT_QPA_PLATFORM=offscreen`. The one sanctioned exception is
`dev.md`'s fix phase calling `ruff check --fix`: `checks.sh` is a verification contract and
never rewrites files, so auto-fix has no subcommand by design.

## Trunk detection (canonical algorithm)

Copies: `dev.md` pre-flight, `review.md` Step 1, `setup-project.md` Step 1.

1. Explicit override (`--base`) if given → verify it exists.
2. `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`) if set and exists.
3. Local `main`, then local `master` — first existing wins.
4. Otherwise: ask the user (or, for non-interactive discovery, use the current branch + note).

## Branch naming (/dev)

Copies: `dev.md` throughout; consumed by `dev-finish.md` cleanup.

- Integration branch: `dev_main` (numbered fallbacks `dev_main_2`, `dev_main_3`, ...).
- Section branches: `{integration_branch}--section-{N}-{slug}` (slug ≤40 chars, lowercased,
  hyphenated). The `--` separator is mandatory: git cannot create `X/...` while branch `X`
  exists, and field evidence (2026-07-05) shows executors improvise inconsistent schemes when
  handed the impossible `/` form.
