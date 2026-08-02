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
| `/review` | Full agent-based code review of the current branch |
| `/quality-review` | Deep quality audit of a whole project — architecture, tests, docs, dead code |
| `/ui-test` | UI/UX check of the running app |
| `/red-team` | Tries to kill an idea *before* you build it — redundant? over-engineered? |
| `/learn` | Pulls one engineering lesson out of what you just changed |
| `/setup-project` | Generates `.claude/checks.sh` for a Python project — run once per project |
| `/setup-review` | Installs project-specific `/review` and `/ui-test` from the master templates |

`/red-team` and `/learn` are manual only — nothing calls them automatically.

## Per-project setup

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
