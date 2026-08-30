Follow the Development Workflow from CLAUDE.md strictly for this task: $ARGUMENTS

## Step-by-step process

### 1. Analyze (Main Agent)
Read all relevant code before proposing changes. Identify the files and modules involved.

### 2. Plan (Main Agent)
Break the task into small, focused sub-tasks (maximum 5). For each sub-task, list:
- What to do
- Which files are involved

Order sub-tasks so that interface-defining work (APIs, schemas, data models) comes first, and code that consumes those interfaces comes after.

If the task requires more than 5 sub-tasks: without `--auto`, tell me to split it into multiple `/work` runs; with `--auto`, return `STATUS: NEEDS_SPLIT` with `BLOCKER: <why it does not fit in 5>` immediately — do not ask the user.

If `$ARGUMENTS` contains `--auto` **as a standalone whole word** (not inside a longer token,
and not merely quoted or mentioned inside the task description — a task that *talks about*
`--auto` is not a request to enable it):
  - Skip the approval prompt. Proceed directly with the proposed sub-task list.
  - Skip branch creation. The caller has already prepared and checked out
    the working branch. Stay on it.
  - Log the auto-approved plan to stdout so the user can read it after the run.
Otherwise:
  - Present the list to me and WAIT for my approval before proceeding.
  - Create a feature branch before the first commit.

### 3. Execute — One Subagent Per Sub-task

For each approved sub-task, follow this cycle:

#### a. Spawn a subagent
Launch a **general-purpose Agent** for the sub-task with this prompt structure:

```
You are executing sub-task {{N}} of {{total}}: "{{subtask_description}}"

## Project Context
- Working directory: {{cwd}}
- Branch: {{branch_name}}
- Read and follow all rules from CLAUDE.md in the project root (if it is missing or empty, this command file's rules are the only contract — note that in your report)

## Files to work with
{{relevant_file_paths}}

## Context from previous sub-tasks
Read `.work-context.md` in the project root for context from previous sub-tasks.
If the file does not exist, this is the first sub-task.

## Your task
1. Read the relevant files listed above
2. Implement the sub-task: {{subtask_description}}
3. Write tests for your changes
4. Run: bash .claude/checks.sh test {{relevant_test_files}} — {{relevant_test_files}}
   MUST be the explicit test file path(s) or node id(s) you created or touched for
   this sub-task (e.g. `tests/test_foo.py` or `tests/test_foo.py::test_bar`).
   NEVER run `checks.sh test` with no path arguments and never pass a directory
   (e.g. `tests/`) — either triggers a full parallel run of the entire suite,
   which is what the one-time `checks.sh all` at the end of /work is for. If you
   are unsure which test file covers your change, name the file you just wrote
   or edited — do not fall back to a directory or a bare run to "be safe". If
   `.claude/checks.sh` does not exist, run `python -m pytest {{relevant_test_files}}`
   instead (same rule: explicit file/node ids only) and say so in your report
5. Run: bash .claude/checks.sh lint — if `.claude/checks.sh` does not exist,
   run `python -m ruff check .` instead and say so in your report
6. If tests or checks fail, fix and re-run until clean

## Output format
When done, report:
- **Summary**: What you did (2-3 sentences)
- **Files changed**: List of file paths (modified or created)
- **New APIs**: Any new functions/classes/endpoints with signatures and file paths
- **Test results**: Pass/fail + relevant output
- **Decisions**: Any non-obvious choices you made and why

IMPORTANT: Do NOT commit. Do NOT create branches. Just write code and run tests.
```

#### b. Report results to me
After the subagent finishes, show me:
- Sub-task summary
- Files changed
- Test results (pass/fail)
- Any decisions the subagent made

#### c. If tests failed — fix BEFORE committing
The commit step below requires green tests. If the subagent reported test failures:
If `$ARGUMENTS` contains `--auto`:
  - Spawn a fix subagent once with the error context.
  - If the fix succeeds (tests now green), continue to step d: the fix
    is committed together with the sub-task's own changes, as that
    sub-task's single commit (the fix subagent, like every subagent,
    does not commit itself).
  - If tests still fail after that single fix attempt, stop /work and
    return `STATUS: NEEDS_DECISION` with `BLOCKER: <one-line reason>`.
    Do NOT commit the broken state.
  - Do NOT ask the user — return control to the caller.
Otherwise:
  - Either spawn a new subagent with the error context to fix, or report
    to me and ask how to proceed. Do NOT commit until tests pass. Once
    they pass, continue to step d as normal.

#### d. Commit on green — no approval needed
Commit the changes with a focused message on the feature branch.
Do NOT ask "Commit? Redo? Skip?" — commit automatically and continue to the next sub-task.

Never commit `.work-context.md` — it is scratch state, deleted at the end
of the run. Stage the sub-task's files explicitly (no `git add -A` /
`git add .`); if it got staged anyway, run `git reset .work-context.md`
before committing.

> **NEVER merge or push without explicit user approval.** After all sub-tasks are done, ask the user before merging the feature branch or pushing to remote.

#### e. Update context bridge file
Write `.work-context.md` in the project root (overwrite with full accumulated state).
Keep it minimal — only three things:

```
## Previous sub-tasks completed:

### Sub-task N: "description"
- Files changed: [list]
- New APIs: [signatures and file paths]
- Decisions: [only choices that affect future sub-tasks]
```

Do NOT include information the next subagent can discover by reading the code itself.

#### f. If sub-task is rejected or skipped
Do NOT run destructive cleanup automatically.
Stop and ask the user for explicit approval before any cleanup command (including `git checkout .` or `git clean`).
If approved, clean up only files related to the rejected/skipped sub-task.

### 4. Summary
After all sub-tasks are done:
1. Run `bash .claude/checks.sh all` to verify everything works together (lint + security + full test suite).
   If `.claude/checks.sh` does not exist, run `python -m pytest` and
   `python -m ruff check .` directly and note the missing script in the summary.
   Skip this step when `$ARGUMENTS` contains `--auto` — the caller's verify
   gate runs these checks right after /work returns, so a duplicate run here
   is wasted work.
2. Summarize what was completed
3. Report the exact branch name used for this /work run
4. Delete `.work-context.md`

## Rules
- Do NOT ask for commit approval — commit and continue automatically after each sub-task, but only once its tests pass (Step 3.c runs before the commit)
- Do NOT merge or push without explicit user approval
- Do NOT skip the test step
- Per-sub-task test runs must name explicit file/node ids, never a bare
  `checks.sh test` or a directory — that silently fans out into a full
  parallel run of the whole suite per sub-task instead of the fast narrow
  one. The full suite runs once, in Step 4.1.
- Do NOT combine sub-tasks
- Maximum 5 sub-tasks per session — split into multiple /work runs if needed
- Each sub-task runs in its own fresh subagent for clean context
- Subagents do NOT commit — the main agent commits automatically after each sub-task
- Context bridge is persisted in `.work-context.md`, not passed inline — and it is never committed (stage files explicitly, not `git add -A`)
- If a sub-task is rejected or skipped, ask user approval before cleanup and avoid repo-wide destructive cleanup
- The `--auto` flag suppresses three things in /work: the plan-approval
  gate (Step 2), branch creation (Step 2), and the final full-pytest run
  (Step 4.1). All other gates remain in force — in particular, NEVER merge
  or push without explicit user approval, regardless of --auto.
- `--auto` suppresses a safety gate, so it is recognised ONLY as a standalone
  whole word, never inferred from prose and never matched inside a longer
  token or inside the task description. A task that merely mentions `--auto`
  must not enable it. (Flags that do NOT suppress a gate are the opposite —
  those may be recognised from plain language.)
- Under --auto, a single test-fix attempt is allowed (Step 3.c). On second
  failure, /work returns `STATUS: NEEDS_DECISION` rather than asking the user.
  A plan needing more than 5 sub-tasks returns `STATUS: NEEDS_SPLIT`.
- /dev calls /work with --auto. Standalone use of --auto is also fine for
  small/well-scoped tasks where you trust the sub-task split.
