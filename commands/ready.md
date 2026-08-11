Am I in a clean state to start work? Surveys branches and leftovers, offers cleanup. $ARGUMENTS

A **pre-work** command, not a post-merge tidy-up. Run it before starting something, when you
want to know what state the clone is in: which branches are finished, what scratch files
survived the last run, whether the trunk is current. It is the answer to "where was I?" for
someone who has been away, and the first command a new clone should meet.

It deletes exactly one kind of thing — **local branches whose every commit is already in the
trunk** — behind one gate. It never deletes a file, never deletes a remote branch, never
merges, never pushes. Everything else it does is report.

## Arguments

- `--base <ref>` — the trunk to measure against, if the detection below gets it wrong. Rarely
  needed; `/ready` with no arguments is the normal form.

## Pre-flight

1. `git rev-parse --git-dir` succeeds? If not → **STOP**: not a git repository.
   `git rev-parse HEAD` fails (a repo with no commits) → **STOP**: nothing to survey yet.
2. **Detection mode, decided first** because step 4 depends on it. Full mode requires all of:
   an `origin` remote parsing into `{owner}/{repo}`, `gh --version` and `gh auth status`
   succeeding, and `gh api repos/{owner}/{repo}` returning.
   - yes → **full mode**; also take `gh api user --jq .login` as `{login}`.
   - no → **ancestry-only mode**. Not an error, but it must be stated in the report and again
     at the gate, because it changes what "not merged" means (see Step 3).
   - **no `origin` at all** → ancestry-only, and additionally: skip Step 6 entirely and
     compare against the *local* trunk in Steps 3 and 4, saying so. Every `origin/{base}` below
     is `fatal:` in a repo without a remote, so this is not a nicety.
3. `git fetch --prune origin` when `origin` exists. `--prune` drops local *remote-tracking*
   refs (`origin/X`) for branches already deleted on the server — it deletes nothing on the
   server and no local branch. Without it, every branch GitHub auto-deleted on merge still
   appears to exist here. Fetch failure (offline) → **warn and continue** on cached refs; say
   the survey may be stale.
4. **Trunk**, in order, each verified to exist before it is accepted: `--base` → (full mode)
   `gh api repos/{owner}/{repo} --jq .default_branch` → `git symbolic-ref --short
   refs/remotes/origin/HEAD` → local `main`, then `master` → otherwise **ask**.
   The name may resolve to a branch that exists on the server but **not locally** — an old
   clone made before a `master`→`main` rename is the ordinary case. Verify with
   `git rev-parse --verify refs/heads/{base}`; if it is absent, say so, skip the behind-count
   in Step 4, and offer `git checkout {base}` (which creates it from `origin`) instead.

Everything downstream compares against **`origin/{base}`**, not the local branch of that name.
That is deliberate: it makes the survey correct even when your local trunk is months stale,
which is exactly the state someone returning to a clone is in.

## Step 1 — Setup warnings (never acts)

- `.claude/checks.sh` missing → warn: `/work`, `/dev`, `/dev-finish` and `/pr` all call it.
  Point at `/setup-project`.
- `CLAUDE.md` missing → warn: `/work` reads its Development Workflow.

Warnings only. Fixing setup is `/setup-project`'s job; a new clone legitimately has none of
this yet, and a command that stops here would block the very person it exists for.

**Do not add a "is your `bash` really Git Bash?" probe here.** Two were written and both
reported safe on a machine where the trap was live, because the agent's own shell is Git Bash
and every child process inherits its `PATH`. Measured 2026-08-10 on this machine, same command
both times: from a clean PowerShell, `(Get-Command bash).Source` is
`WindowsApps\bash.exe` (WSL, no Python); spawned from Git Bash it is
`C:\Program Files\Git\usr\bin\bash.exe`. A check that can only run where the defect cannot
appear is worse than no check — it reports safe and is believed. The real finding
(`bash` on Windows is often WSL2, so `bash .claude/checks.sh all` dies with
`python: command not found`) belongs in a project's `CLAUDE.md`, where it is a statement rather
than a measurement.

## Step 2 — Leftover run state (report only, never deletes)

`/dev` and `/work` write `.dev-plan.md`, `.dev-state.md`, `.dev-log.md` and `.work-context.md`.
All are gitignored, so **they outlive the run that wrote them** and nothing but the check below
ties them to the branch in front of you.

A run is **live** if `.dev-state.md` exists and its `integration_branch` is the branch you are
on. Otherwise the files may belong to an older run — report each one with the branch it names
and let the reader decide.

This is not tidiness. Live defect, 2026-08-06: a `.dev-plan.md` left behind by a run
merged days earlier would have made `/pr` push a one-commit typo fix as
`<login>/plan-quality-review-2026-08-05-follow-`, title the PR after already-merged work, and
describe it with that run's sections. The file was not wrong; it was simply still there. Being
told it is there is the whole fix.

**Naming them is the deliverable; deleting them is not this command's business.** An earlier
draft offered them for deletion and it was wrong twice over:

- `.dev-plan.md` is **user-authored** input, not generated state — `dev.md` calls it that and
  `dev-finish.md` line 50 says "Keep `.dev-plan.md` — it is user-authored." It is gitignored,
  so there is no SHA to print and no way back. Hand-written text is not scratch.
- "Not on the integration branch" does not mean "the run finished". `/dev` has nine stopping
  conditions, and a stopped run leaves `.dev-state.md` holding the section and phase that
  `/dev`'s resume mode needs, plus an append-only `.dev-log.md`. Checking out the trunk to look
  around — the exact use case in this file's first paragraph — would have marked both as
  garbage. The predicate came from `pr.md` pre-flight 9, where "stale" authorises *ignoring*
  the files. It was never strong enough to authorise deleting them.

`.work-context.md` **tracked by git** is a separate, harder finding — it must never be
committed. Report it as an error with `git rm --cached .work-context.md`. Never delete a
tracked file.

## Step 3 — Survey the branches

For every local branch except `{base}`, classify it.

**The one rule that makes this safe: every classification must be bound to the branch's
current tip.** Evidence that a *name* was once merged is not evidence about the commits sitting
on that branch now. Bind to the tip and both detectors below can only ever prove a branch
merged, never unmerged — so anything not positively proven is `keep`. Unbind them and the
command deletes live work while reporting it as merged; three separate ways of doing so were
found in review on 2026-08-10, all of them from evidence keyed to a name instead of a commit.

**Which name to ask GitHub about.** Not the local one. `/pr` pushes with
`HEAD:refs/heads/{login}/{slug}`, so the local branch keeps its own name while the PR is opened
against a different remote name — `feature-info-tab` locally, `<login>/feature-info-tab` on
GitHub. Querying the local name would report "no PR" for every branch `/pr` ever opened.

Read it from **`git config --get branch.{branch}.merge`** and strip `refs/heads/`. Not
`rev-parse --abbrev-ref {branch}@{upstream}`: once the remote branch is deleted on merge and
pruned by pre-flight 3, the upstream *config* survives but the remote-tracking ref does not, so
`@{upstream}` fails with exit 128 — on precisely the merged-and-cleaned-up branch this command
exists to find. Check the exit code before using any output. No config → use the local name.

Then, in order:

1. **Open PR first.** `gh pr list --head {remote_name} --state open --json number,url` → any
   hit → **open PR #N** → `keep`. Ask this before asking about merges: one head name can carry
   a merged PR *and* an open one, which is exactly what `pr.md` Step 7 produces when its
   "only closed/merged matches" prompt is answered with "open a new PR". Merged-first would
   delete a branch under active review.
2. **Merged PR, bound to the tip.** `gh pr list --head {remote_name} --state merged --json
   number,url,mergedAt,headRefOid`. A hit counts **only if its `headRefOid` equals
   `git rev-parse {branch}`** → **merged (PR #N)** → `delete`. Otherwise it is not evidence
   about this branch: fall through to rule 3.

   The equality is the whole defence, and it closes four separate loss paths at once:
   commits added to the branch after its PR merged; a **recycled branch name**, where a new
   local `hotfix` for unrelated work inherits merged PR #7 from the old one (and pre-flight 3's
   prune is what removed the only thing telling them apart); a branch created from a
   remote-tracking ref, which inherits that ref as its upstream automatically; and a same-named
   head from a fork or the other developer, since `--head` filters on `headRefName` with no
   owner in it.
3. **Ancestry.** `git merge-base --is-ancestor {branch} origin/{base}`
   - exit 0 → **merged (ancestry)** → `delete`
   - non-zero → **not merged** → `keep`
4. **`/dev` section branches.** For a branch named `{X}--section-{N}-{slug}` where `X` is in
   this same survey and classified merged, additionally test
   `git merge-base --is-ancestor {section} {X}` → exit 0 → **merged (via {X})** → `delete`.

   **The ancestry test is mandatory; the name is not evidence.** `/dev` creates a section
   branch in Phase A and merges it in Phase G, and every one of its stopping conditions leaves
   a section branch holding commits `X` never received — `dev.md` explicitly keeps those
   branches. Inferring from the name alone deletes the unfinished section of a run whose
   integration branch was merged, which is a whole section of work, unpushed. The test itself
   is sound because `/dev` merges sections with `--no-ff`: ancestry *inside* `X` survives even
   when `X` reached the trunk as a squash. If `X` is absent locally, infer nothing.

**Ancestry-only mode is a weaker instrument and the report must say so.** Squash-merge produces
a new SHA with no ancestry link to the branch, so git reports a squash-merged branch as
unmerged. Measured on PR #3, 2026-08-06: branch tip `f4b4845`, merge commit
`3725e8f` — `git branch --merged origin/main` did not list it, `git merge-base --is-ancestor`
said no, and `gh pr list --head <branch> --state merged` found it. In ancestry-only mode the
`delete` list is a *subset* of what is really merged, never a superset — safer than full mode,
not more dangerous, and it is also why `git branch --merged` is not used anywhere here.

Report as a table — branch, state with its evidence, action — and include the current branch,
marked. Standing on a merged branch is the single most useful thing this command can tell
someone about to start work. **Detached HEAD** is not a branch: say so, mark no current branch,
and let Step 4 offer the checkout.

## Step 4 — Trunk position

Report where you are, and — when a local `{base}` exists — `git rev-list --count
{base}..origin/{base}` commits behind.

If you are not on `{base}`, or the local `{base}` is behind `origin/{base}`, **offer**
`git checkout {base}` then `git pull --ff-only`, and say why it comes before the deletions:
git refuses to delete the branch you are standing on, so a merged current branch cannot be
cleaned up until you step off it.

Working tree not clean → **do not offer the switch**. Say the tree is dirty and show
`git status --short`. Never stash, never discard, never carry changes across with `checkout`.
`--ff-only` on the pull: a trunk that cannot fast-forward means local commits on the trunk, and
that is a conversation, not a step in a cleanup command.

Declining is fine and the survey stays valid — it measured against `origin/{base}` all along.

## Step 5 — One gate

Every deletable branch, in one block, with the evidence for each, and one question:

```
Delete these local branches:
  merge-setup-commands       merged - every commit is in origin/master
  feature-info-tab           merged - PR #3, tip f4b4845 matches the merged PR
  dev_main--section-2-cache  merged - inside dev_main, which merged as PR #12

Keeping: spike-caching (open PR #7), old-idea (closed PR #5), scratch (not merged)

Leftover run files (NOT deleted, listed so you know they are there):
  .dev-plan.md    from a run on branch 'dev_main' - user-authored, never removed here
  .dev-state.md   run stopped at section 5; /dev resume needs this

Each deleted SHA is printed, so `git branch <name> <sha>` restores it.

Delete the 3 branches? (y / n / or name the ones to KEEP - anything named is kept)
```

Branch names in that list are **local** names. The remote name only ever appears inside the
evidence text; a local branch pushed by `/pr` is `feature-info-tab` here, never
`<login>/feature-info-tab`, or the `git branch -d` that follows matches nothing.

One gate, not one question per branch: with five branches, per-item prompts teach the user to
answer `y` without reading, which is the exact failure the gate exists to prevent. `n` is the
outcome of not understanding the question.

Then delete, printing each SHA as it goes.

**Attempt `git branch -d` first; fall back to `-D` only after showing the refusal.** `-d`
checks the branch against **its upstream**, or against HEAD when no upstream is set — not
against the trunk. So it is a real guard against a branch that has advanced past what was
pushed, and no guard at all for a pushed branch that never moved. It is worth running for the
first case, and it must not be described as confirming the classification. Measured 2026-08-09
in this repo: `merge-setup-commands`, ordinary merge commit, no upstream, deleted cleanly under
`-d` — so `-D` is only needed for squash-merges.

**A refusal must be read, never pre-explained.** An earlier draft printed "(needs -D)" beside
each line with squash-merge as the reason; when the refusal instead means unmerged commits, or
`cannot delete branch 'x' used by worktree at ...` — which refuses under both `-d` **and**
`-D` — the one honest signal in the run has been explained away in advance. Show git's message,
then act on what it says: a worktree refusal is not a merge question, so skip that branch and
report it, exactly as for the branch you are standing on.

**Nothing outside that list may be deleted, under any answer**, and nothing on the `keep` list
becomes deletable by naming it — rejected work is not garbage, and a closed PR is often
reopened.

## Step 6 — Remote branches (report only)

Skip entirely without an `origin`. Otherwise list branches on `origin` that are proven merged
by the same rules, excluding `{base}`.

- `{login}/...` → show `git push origin --delete {name}` for the user to run.
- Anything else → list it and say it belongs to another developer. Leave it.

**This command never deletes on `origin`.** A remote deletion is not revertible from here and
is visible to everyone else on the repo, which is a different class of act from removing a
local pointer. It is also mostly unnecessary: repos with `delete_branch_on_merge` clean up on
their own, so what shows up here is either from before that was enabled or a branch merged some
other way — both worth a human look.

## End-of-run signal

```
STATUS: READY — on {base}, up to date, nothing left over.
STATUS: READY WITH NOTES — {n} notes: {one line}.
STATUS: STOPPED — {one-line reason}.
```

## Rules

- **Never delete anything not positively proven merged, and every proof must be bound to the
  branch's current tip.** A merged PR counts only when its `headRefOid` is the branch tip; a
  section branch counts only when ancestry inside its integration branch says so. Name-shaped
  evidence is not evidence.
- **Branches only.** This command deletes no files — not `.dev-plan.md` (user-authored), not
  `.dev-state.md` or `.dev-log.md` (a stopped `/dev` run resumes from them), not a tracked file
  under any circumstances. It reports them.
- Local branches only. Never `git push origin --delete`, never merge, never push, never stash,
  never discard a working-tree change.
- Ask GitHub before git. `git branch --merged` and `git merge-base --is-ancestor` both miss
  every squash-merge, so they are the fallback, never the source.
- An open PR outranks a merged one on the same head name.
- Ancestry-only mode must announce itself in the report and again at the gate. Silently
  degrading to a weaker check is worse than not running.
- Compare against `origin/{base}`, never a local trunk branch — except with no `origin` at all,
  which is announced.
- Missing `checks.sh` or `CLAUDE.md` is a warning, never a stop. A fresh clone has neither, and
  that user is who this command is for.
- A live `/dev` run (its `integration_branch` is the current branch) is untouchable.
- One gate for every deletion. Show git's refusal instead of predicting it.
