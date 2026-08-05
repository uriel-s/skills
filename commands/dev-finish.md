Finish a completed /dev run: final review, approved trunk merge, cleanup. $ARGUMENTS

This is the missing end of the /dev lifecycle. /dev merges sections into the integration
branch and stops; this command takes the integration branch the rest of the way.

## Pre-flight

1. `.dev-state.md` exists and every section has `status: complete`? If not → **STOP**: report
   what's incomplete and suggest resuming /dev.
2. Read `integration_branch` and `base_branch` from state. Both branches exist? If not → **STOP**.
3. Working tree clean? If not → **STOP, ask**.
4. `git log {base_branch}..{integration_branch}` non-empty? If empty → **STOP**: nothing to merge.

## Step 1 — Final review

Run the `/review` command (`~/.claude/commands/review.md`) on the integration branch, diffing against `{base_branch}`
(the run's full cumulative diff — per-section reviews used a single fix cycle each, so this
catches regressions that slipped between sections). Present the findings table.

- Critical/Major findings → recommend fixing before the merge (e.g. via /work on the
  integration branch) and **ask the user** whether to fix first, merge anyway, or abort.
- Minor-only or clean → proceed to Step 2.

## Step 2 — Merge to trunk (requires explicit approval)

Never merge without the user's explicit go-ahead in this session.

1. `git checkout {base_branch}`
2. `git merge --no-ff {integration_branch} -m "merge: <plan title> ({N} sections via /dev)"`
3. Merge conflict → **STOP**: abort the merge (`git merge --abort`), report, and leave
   resolution to the user.

## Step 3 — Post-merge verify

`bash .claude/checks.sh all` on `{base_branch}`. Red → report which stage failed and **ask**:
revert the merge (`git revert -m 1 <merge-commit>`) or leave it for manual fixing. Do not
decide alone.

## Step 4 — Cleanup (only after green verify, with approval)

1. List the section branches (`git branch --list '{integration_branch}--section-*'`) and the
   integration branch; ask once for approval to delete them all.
2. Delete approved branches.
3. Archive run artifacts: move `.dev-state.md` and `.dev-log.md` to
   `.dev-archive/<YYYY-MM-DD>-state.md` / `<YYYY-MM-DD>-log.md` (create the dir if needed).
   Keep `.dev-plan.md` — it is user-authored.

## End-of-run signal

Output exactly one of:

```
STATUS: MERGED — {integration_branch} → {base_branch} ({N} sections). Branches cleaned: <yes/no>.
STATUS: STOPPED — {one-line reason}.
```

## Rules

- Never push to remote without explicit user approval.
- Never merge or delete branches without explicit approval in this session.
- Read state from `.dev-state.md`; do not guess branch names.
