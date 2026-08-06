# Claude Code — commands & skills

Personal slash commands for [Claude Code](https://claude.com/claude-code), plus the
project toolchain template they depend on. Portable: clone anywhere, copy into place, done.

## Install

Copy the commands into your global Claude Code directory — they then work in every project
on that machine:

```bash
git clone https://github.com/uriel-s/skills.git
cp skills/commands/*.md ~/.claude/commands/
```

On Windows (PowerShell):

```powershell
git clone https://github.com/uriel-s/skills.git
Copy-Item skills\commands\*.md "$env:USERPROFILE\.claude\commands\" -Force
```

Type `/` in Claude Code to confirm they show up.

## The commands

| Command | What it does |
|---|---|
| `/work` | Runs one task through the full development workflow — plan, implement, test, lint |
| `/dev` | Runs whole sections from a plan autonomously; stops only for real decisions |
| `/dev-plan` | Writes or lints the `.dev-plan.md` that `/dev` consumes |
| `/dev-finish` | Closes a `/dev` run: final review, trunk merge, cleanup |
| `/pr` | Closes a branch the other way: checks, review, push, open a pull request |
| `/review` | Full agent-based code review of the current branch |
| `/quality-review` | Deep quality audit of a whole project — architecture, tests, docs, dead code |
| `/ui-test` | UI/UX check of the running app |
| `/red-team` | Tries to kill an idea *before* you build it — redundant? over-engineered? |
| `/learn` | Pulls one engineering lesson out of what you just changed |
| `/setup-project` | Sets a Python project up for all of the above — run once per project |

`/red-team` and `/learn` are manual only — nothing calls them automatically.

### Finishing a branch: `/dev-finish` or `/pr`

Two ways out of a finished branch, and which one you use depends on whether you are the
person who approves the merge:

```
              ┌── /dev-finish ── review ── merge to local trunk ── checks ── cleanup
/work ──┐     │                                    (you approve your own merge)
        ├─────┤
/dev  ──┘     │
              └── /pr ────────── checks ── review ── scan ── push ── open PR
                                                  (someone else approves the merge)
```

`/dev-finish` verifies *after* its merge, because a local merge is revertible. `/pr`
verifies *before* its push, because a push is not — and because a red branch costs a
reviewer their time and a CI run.

That is also why `/pr` has a scan step and `/dev-finish` does not. It greps the outgoing
diff for secrets, run artifacts, and oversized files — `checks.sh sec` covers neither
secrets nor file size, and a pushed key cannot be withdrawn, only rotated.

`/pr` is the only command allowed to push, and only under a tight shape: the current
branch, one remote branch named `<gh-login>/<slug>`, fast-forward only, after one
confirmation. It never merges — a human does that on GitHub. Repeat runs update the same
PR rather than opening a second one, which is the normal loop when a reviewer asks for
changes. `/dev-finish` needs `.dev-state.md` and so only works after `/dev`; `/pr` treats
it as optional and works after a plain `/work` too.

**`/pr` is a quality gate, not a security gate.** It runs on the author's machine in the
author's agent, so what it reports is a claim. If you need something unfakeable, that is CI
on the pull request plus branch protection on the trunk — not a slash command.

## Per-project setup

Run `/setup-project` once in a new project. It touches five files, and nothing else:

| File | Who reads it |
|---|---|
| `.claude/checks.sh` | `/work`, `/dev`, `/dev-finish`, `/pr` — how to test and lint this project |
| `.claude/project-params.md` | `/review`, `/ui-test` — a discovery cache: trunk branch, doc paths, test layout, UI framework |
| `.gitignore` | git — appended with the scratch files `/work` and `/dev` leave behind |
| `.gitattributes` | git — appended with `*.sh text eol=lf`, so a committed `checks.sh` isn't checked out as CRLF and killed by `$'\r'` |
| `.githooks/pre-push` | git — refuses pushes straight to the trunk |

The first two are generated and overwritten freely. The last three are yours: the two dotfiles
are only ever appended to, and an existing `pre-push` hook is never replaced without asking.

**The hook needs one line per clone.** `core.hooksPath` is local config and is not committed,
so cloning the repo gets you the hook file and no hook. Everyone runs this once:

```bash
git config core.hooksPath .githooks
```

The push guard is one file for the whole team, opted out of per machine — the maintainer who
merges locally and pushes the trunk runs `git config claude.allowTrunkPush true` once; nobody
else does. `git push --no-verify` bypasses it, so it stops accidents, not intent. That is all
a client-side hook can do, and on a private repo on GitHub's free plan — where branch
protection cannot be enabled at all — it is most of what is available.

The commands themselves are never copied into your project — they stay global in
`~/.claude/commands/`, so editing one here applies everywhere at once. `project-params.md` is
only a shortcut: every command re-verifies it cheaply and trusts what it actually finds, so a
missing or stale one costs speed, never correctness.

### checks.sh

`/work` and `/dev` don't know how to test your project. They call `.claude/checks.sh`
instead, and `/setup-project` generates it from [templates/checks.sh](templates/checks.sh):

```
checks.sh test [paths]   pytest — whole suite, or just the paths you name
checks.sh lint           ruff check
checks.sh format         ruff format --check   (never rewrites)
checks.sh arch           import-linter
checks.sh types          mypy
checks.sh sec            bandit + pip-audit
checks.sh all            every check above
```

Exit 0 means green. Missing optional tools are SKIPped, not failed, so this works on a
project that has only ruff and pytest wired up.

`all` deliberately runs *every* check and reports *all* failures rather than stopping at the
first — the commands need to say which stage broke, and a `&&` chain can't answer that once
the first one is red.

Python only, by design.

## Note on line endings

[.gitattributes](.gitattributes) pins everything to LF. `checks.sh` is a bash script: with
CRLF it dies on `$'\r': command not found`. Don't remove it on Windows.

## Maintainer docs

Not needed to *use* the commands — read these before *changing* one.

- [CONVENTIONS.md](CONVENTIONS.md) — definitions shared across several command files
  (severity ladder, findings table, the `checks.sh` contract). Subagent prompts can't read
  files at runtime, so these blocks are copied into the commands by hand; each block lists
  where its copies live. Change one, change them all.
- [BACKLOG.md](BACKLOG.md) — known rough edges, ranked. Pick from here.
- [REMEDIATION.md](REMEDIATION.md) — the 2026-07-05 overhaul: what was broken, what was
  decided, what shipped. History, not a to-do list.

## Deploying a change

The commands only take effect from `~/.claude/commands/`, so editing a file here changes
nothing until you copy it over:

```powershell
Copy-Item commands\*.md "$env:USERPROFILE\.claude\commands\" -Force
```

Easy to forget in the other direction too — edit `~/.claude/commands/` directly and this repo
silently falls behind. That has already happened once, for two weeks. Commit, then deploy.

**Deleting a command needs a second step.** `Copy-Item` only ever adds and overwrites — it
never removes. A command you delete from `commands/` keeps working in every project until you
also delete it from the deployment:

```powershell
Remove-Item "$env:USERPROFILE\.claude\commands\<name>.md"
```

Miss that step and the repo says a command is gone while `/` still offers it. To check what is
actually deployed: `Get-ChildItem "$env:USERPROFILE\.claude\commands\"`.
