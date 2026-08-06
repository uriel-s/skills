Open or update a pull request for the current branch: checks, review, push, PR. $ARGUMENTS

The remote counterpart of `/dev-finish`. That command merges the work into the trunk
locally; this one pushes it and opens a pull request for **someone else** to merge. Works
after `/dev` (reads `.dev-state.md`) and after a plain `/work` run — `.dev-state.md` is
optional here, which is the difference from `/dev-finish`.

**A quality gate, not a security gate.** It runs on the author's machine in the author's
agent, so what it reports is a claim. The proof is CI on the PR and the reviewer's own read.

## Arguments

- `--base <ref>` — PR target branch (default: the repo's GitHub default branch)
- `--branch <name>` — remote branch name, verbatim, skipping the naming rules in Step 4
- `--no-review` — skip Step 2 (use when you just reviewed the branch yourself)
- `--draft` / `--title <text>` / `--reviewer <login>` — override the Step 4 defaults
- `--yes` — skip the Step 5 confirmation gate

Accept all of these in plain language too ("open it as a draft", "skip the review",
"reviewer is alice") — this file is read by a model, not parsed by a shell.

**`--yes` is the one exception: it requires that exact token and is NEVER inferred from
prose.** Every other flag mismatched costs one needless question; `--yes` mismatched means
an unapproved push. A sibling bug is on record — `/work` once entered unattended mode
because a task description merely *mentioned* `--auto`.

## Pre-flight

1. `gh --version` and `gh auth status` both succeed? If not → **STOP**: point at `gh auth login`.
2. `git remote get-url origin` parses into `{owner}/{repo}`? If not → **STOP**.
3. **Resolve identity against the repo, not the machine.** `gh api user` returns the
   *active* gh account, which on a multi-account machine need not own or be able to write
   this repo. So check first:
   `gh api repos/{owner}/{repo} --jq '.permissions.push'`
   - 404 / error → the active account cannot see this repo. **STOP**: show `gh auth status`
     (it lists every authenticated account) and suggest `gh auth switch`.
   - `false` → **STOP**: name the account; it can read but not push.
   - `true` → only now take `gh api user --jq .login` as `{login}`.
4. Working tree clean? If not → **STOP, ask**. `.work-context.md` present: tracked by git →
   **STOP** (it must never be committed); untracked → warn and continue.
5. **PR base**, in order: `--base` → `gh api repos/{owner}/{repo} --jq .default_branch`
   (authoritative — it is where the PR actually goes) → `git symbolic-ref --short
   refs/remotes/origin/HEAD` → local `main`, then `master`.
   Then `git fetch origin {base}`. Everything downstream compares against
   **`origin/{base}`**, never the local branch of that name: a stale local trunk yields a
   diff that does not match what GitHub will show.
6. **Refuse to run on the trunk.** If the current branch is `{base}` (or any branch matching
   `main`/`master`) → **STOP**. This is a safety rule, not a technicality: the trunk may have
   no server-side protection, in which case this check is one of the few real guards against
   pushing straight to it. It is only a partial one — it protects the `/pr` path only, and a
   manual `git push` walks around it. A `pre-push` hook is the complete version.
7. `git log origin/{base}..HEAD` non-empty? If empty → **STOP**: nothing to propose.
8. `git rev-list --count HEAD..origin/{base}` > 0 → the branch is behind. **Warn, do not
   stop**, and carry the count into Step 5: green local checks say nothing about the merge
   result, and GitHub does not test the merge.
9. `.dev-state.md` present? Read `integration_branch`, `base_branch`, and the sections.
   Absent is normal. Do **not** require every section to be `complete` — incomplete sections
   produce a draft PR (Step 4), not a stop.

## Step 1 — Checks

`bash .claude/checks.sh all`. Runs before the push, not after it: `/dev-finish` can verify
after its merge because a local merge is revertible, and a push is not.

**Red → report which stage failed, then ask.** Do not stop dead:

```
checks.sh all: RED (sec)
  pip-audit: pillow 10.2.0 — GHSA-xxxx

Abort, or open as a draft anyway?
```

A hard stop here is wrong, because `checks.sh all` is not purely a property of the branch:
`run_sec` calls `pip-audit` with no arguments, which audits **the whole active Python
environment**. A stale package the author installed for some other project turns every `/pr`
red, for a defect they cannot fix from inside this repo. An unfixable stop does not produce
careful work — it produces `git push` plus the web "New pull request" button, which skips the
scan, the review and the PR body all at once.

If the author proceeds, the PR is **forced to draft** (it cannot be merged by accident) and
the body records `checks: RED (<stage>)`. The gate moves from blocking to visible: the
reviewer sees the state on the PR instead of trusting that checks passed.

Script missing → run `python -m pytest` and `python -m ruff check .` directly, and say so in
the report and the PR body.

Script missing → run `python -m pytest` and `python -m ruff check .` directly, and say so in
the report and the PR body.

## Step 2 — Review

Skip if `--no-review`. Otherwise run `/review` (`~/.claude/commands/review.md`) with
`--base origin/{base}` — the branch's cumulative diff against the trunk as the remote has it.

Present the findings table, then:
- **Critical/Major** → **ask**: fix first (e.g. `/work` on this branch), open the PR anyway,
  or abort. Opening anyway is legitimate — a PR requests review, it does not claim
  perfection — but it must be a decision, not a default.
- After any fix → **re-run Step 1**, then continue. **One fix cycle, then move on** — the same
  budget `/dev` gives a section. Do not re-review after fixing and fix again; if the branch
  still has Critical/Major findings after one cycle, that is what the PR and its reviewer are
  for. An unbounded loop here lands on the least experienced user, on the branch with the most
  findings.
- **Minor-only or clean** → continue.

The counts go into the PR body either way. When skipped, the body says
`Review: skipped by author` — a skip is allowed, a silent skip is not.

## Step 3 — Pre-push scan

The last point at which anything can be kept off a server. Scan `git diff
origin/{base}...HEAD` — the added lines only.

**Three dots, not two.** Two-dot diffs the two trees, so anything the trunk *deleted* while
this branch was away shows up as a line this branch "added" — pre-flight 8 exists precisely
because the branch is often behind, which is exactly when the two forms diverge. Three-dot
diffs from the merge base, i.e. only what this branch actually contributes, which is also
what GitHub shows on the PR. Getting this wrong means stopping the author over a key someone
else removed, and a file count in Step 5 that does not describe the diff being approved.
`review.md` already uses the three-dot form; the `git log origin/{base}..HEAD` in pre-flight
7 is correctly two-dot (it lists commits, not content).

1. **Secrets.** `checks.sh sec` does not cover this (bandit reads code patterns, pip-audit
   reads dependencies). Grep for at least: `-----BEGIN [A-Z ]*PRIVATE KEY`, `AKIA[0-9A-Z]{16}`,
   `gh[pousr]_[A-Za-z0-9]{20,}`, `xox[baprs]-`, and `(password|passwd|secret|token|api[_-]?key)
   \s*[=:]\s*["'][^"']{8,}`. Any hit → **STOP, ask**. Do not push and then clean up: a pushed
   secret stays reachable through the API and caches after the branch is deleted, so it must
   be rotated, not withdrawn.
2. **Run artifacts.** `.dev-state.md`, `.dev-log.md`, `.dev-plan.md`, `.work-context.md`,
   `.dev-archive/` appearing in the diff → **warn**. They are scratch state; locally they are
   harmless, but tracked they land in every PR.
   The fix, if the author takes it, is a complete three-step one: `git rm --cached <paths>`,
   append them to `.gitignore`, then **commit that** (`chore: stop tracking run artifacts`).
   Stopping after `git rm --cached` is worse than doing nothing — it leaves the tree dirty
   (which pre-flight 4 forbids) and, being uncommitted, does not remove anything from the PR
   diff. Either do all three or leave it and just report. Never leave it half-applied.

## Step 4 — Resolve the PR shape

**Remote branch**, first match wins:
1. An upstream already set and pointing at `origin` (`git rev-parse --abbrev-ref @{upstream}`)
   → **reuse verbatim**, *unless* the remote name it points at is a `/dev` convention name
   (`dev_main`, `dev_main_2`, ...). This is what makes a repeat run update its own PR instead
   of opening a rival one, so it outranks everything below — but a single earlier
   `git push -u origin dev_main`, which a newcomer may well have run before learning `/pr`,
   would otherwise pin the remote branch to the one name rule 3 forbids, and both developers'
   branches collide there. In that case **warn**, ignore the upstream, and fall through to
   rule 3.
2. `--branch <name>` → verbatim.
3. `{login}/{slug}`, where `{slug}` comes from the `.dev-plan.md` H1 → section 1's title →
   the current branch name. **Never** from a `/dev` convention name (`dev_main`,
   `dev_main_2`, ...) — identical on every run and for both developers, so it collides by
   construction; skip to the next source. Slugify: lowercase, non-alphanumeric → `-`,
   collapse, trim, ≤40 chars; empty or degenerate result (a non-ASCII title) →
   `work-{git rev-parse --short HEAD}`.
4. Nothing usable → **STOP, ask** for `--branch`.

**Draft** if `--draft`, or if any `.dev-state.md` section is not `complete`, or if Step 1 was
red and the author chose to proceed. The last one is not optional — red checks must not
produce a mergeable PR.
**Title:** `--title` → `.dev-plan.md` H1 → the single commit's subject → humanized `{slug}`.
**Reviewer:** `--reviewer` → otherwise the collaborators with push who are not `{login}`
(`gh api repos/{owner}/{repo}/collaborators`), proposed as the default in Step 5. If that
call fails, just ask.

**Body** — write to a temp file *outside the repo* and pass `--body-file`; multi-line
`--body` through a shell quote is fragile on Windows.

```markdown
## What changed
<one bullet per completed section from .dev-log.md; no log → one per commit subject>

## Verification
- `checks.sh all`: <green | green, N stages SKIPped (not installed) | **RED (<stage>)** — <one line>>
- `/review` vs `origin/{base}`: <C> Critical, <M> Major, <m> Minor<, N fixed> | skipped by author
- <if behind: "N commits behind origin/{base} — the merge result is untested.">

## Provenance
- Commands: <`git -C ~/.claude/commands rev-parse --short HEAD`, else "unknown (not a checkout)">
```

Provenance answers "which version of the review ran here" before the reviewer reads any
code. It resolves only when `~/.claude/commands` is a checkout or a link to one; `unknown`
is itself the useful signal.

## Step 5 — Confirm (one gate)

Unless `--yes`, print exactly what will happen and ask **one** question:

```
Push     {current_branch} → origin/{remote_branch}  ({N} commits, {M} files)
PR       {owner}/{repo}  {base} ← {remote_branch}   [draft]
         "{title}"
Reviewer {default}
Review   {C} Critical, {M} Major, {m} Minor    checks.sh all: green
{warning line, if behind}

Proceed? (y = go / n = abort / or name a different reviewer)
```

`{M} files` is the three-dot count from Step 3 — the same diff GitHub will show, not the
two-dot one.

One gate, not one per step — and one question inside it. This is the first action in the
system that leaves the machine and notifies other people, and no local revert undoes it, so
the author must read one block and answer once. A reviewer name typed instead of y/n replaces
the default and re-asks; anything else aborts.

## Step 6 — Push

`git push -u origin HEAD:refs/heads/{remote_branch}`

`HEAD:refs/heads/...` pushes under a different remote name without renaming the local branch,
so `dev_main` stays `dev_main` locally. `-u` sets the upstream that Step 4 rule 1 reads next
run.

If the remote branch exists, first check `git merge-base --is-ancestor origin/{remote_branch}
HEAD`. Not an ancestor → **STOP**: the remote holds commits this branch does not, so the push
would discard someone's work. **Never `--force`, never `--force-with-lease`, under any
argument.** A rejected push → **STOP** and report git's message verbatim; do not retry with
new flags.

## Step 7 — Open or update the PR

`gh pr list --head {remote_branch} --state open --json number,url,isDraft` — query by
`--head`, since the local and remote branch names differ here by design.

- **Open PR exists** → Step 6 already updated it. Do not create a second one; report its
  number, URL, and the commits added.
- **None** → `gh pr create --base {base} --head {remote_branch} --title "{title}"
  --body-file {tmp}` [`--draft`] [`--reviewer {login}`]. If `gh` rejects `--draft` (not
  available on every plan/visibility combination), retry once without it and prefix the
  title with `WIP: ` instead — and say which happened.
- **Only closed/merged matches** → **STOP, ask**: reopen, or open a new PR.

## Step 8 — Cleanup (only with approval)

Only when `.dev-state.md` exists: list the section branches (`git branch --list
'{integration_branch}--section-*'`) and ask once to delete them. They are local-only and the
integration branch's `--no-ff` merges keep their history — safe, but still a deletion, so
still asked.

**Never delete the integration branch:** the PR is built on it, review comments arrive there,
and the next run pushes from it. **Never archive `.dev-state.md` / `.dev-log.md`**
(`/dev-finish` Step 4.3 does; this command must not) — a second run needs them, and they are
archived when the work is merged, not when it is proposed.

## End-of-run signal

Output exactly one of, followed by `Next: gh pr checks {N}` (CI starts after this command exits):

```
STATUS: PR OPENED — #{N} {url} ({remote_branch} → {base})[, draft].
STATUS: PR UPDATED — #{N} {url} (+{K} commits).
STATUS: STOPPED — {one-line reason}.
```

## Rules

- **The push exception.** Every other command forbids pushing without explicit approval.
  This is the one exception, bounded to: **the current branch**, to **one remote branch**
  matching Step 4, on **`origin`**, **fast-forward only**, after Step 5 or `--yes`. Never the
  trunk, never a force, never a second branch. Anything outside that shape is still forbidden.
- Never merge. `/pr` proposes; a human merges on GitHub. `/dev-finish` is the only command
  that merges to a trunk, and only a local one.
- Never run on the trunk (pre-flight 6). Never delete the integration branch. Never archive
  the run's state or log.
- `checks.sh all` and the pre-push scan both run before the push. A secret is a hard stop —
  it cannot be withdrawn once pushed. Red checks are not: they are surfaced, and proceeding
  forces a draft and is recorded in the PR body, because `checks.sh all` can go red on the
  author's environment rather than on the branch.
- Review against `origin/{base}`, never a local trunk branch.
- `.dev-state.md` is optional; never require every section to be complete.
- Verify gh identity against `repos/{owner}/{repo}` before trusting `gh api user`.
- `--yes` requires its exact token and is never inferred from prose.
