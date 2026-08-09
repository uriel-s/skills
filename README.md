# Claude Code — commands & skills

Personal slash commands for [Claude Code](https://claude.com/claude-code), plus the
project toolchain template they depend on. Clone anywhere, point `~/.claude/commands` at the
clone, done — from then on `git pull` *is* the deploy.

## Install

One line, pasted into PowerShell — not as administrator:

```powershell
cd $env:USERPROFILE; git clone https://github.com/uriel-s/skills.git; if (Test-Path .\skills\install.ps1) { powershell -ExecutionPolicy Bypass -File .\skills\install.ps1 } else { Write-Host '  [FAIL] The clone did not succeed - see the error above. Nothing was installed.' -ForegroundColor Red }
```

The `if` is not decoration. PowerShell's `;` means *continue regardless*, so without it a failed
clone — no network, no credentials, `skills` already there — still runs the second half, and
`powershell -File` on a missing path drops into an **interactive shell**: a banner and a prompt,
with nothing saying the clone failed. Measured, not theorised.

That is the whole install. Nothing to fill in: the script deploys the clone it is sitting in,
so there is no path to type wrong. `-ExecutionPolicy Bypass` applies to that one run only and
changes no setting.

Then open a new Claude Code session and type `/` to confirm the commands are there.

It clones into your home folder on purpose. **The clone's path is written into
`settings.json`, so moving or renaming the folder later stops updates — silently.** The script
warns if you install from somewhere people habitually tidy up (Desktop, Downloads, OneDrive,
temp). If you do move it, re-run `install.ps1` from the new location.

[install.ps1](install.ps1) is safe to re-run and reports everything it does. Add `-WhatIf` to
see the plan without changing anything. It backs up `~/.claude/commands` and `settings.json`
into `~/.claude/backups/` before touching either, refuses to proceed if the backup comes out
short, and validates the merged `settings.json` *before* it replaces the real one — a settings
file that fails to parse silently disables every setting in it.

### What it actually does

**Points `~/.claude/commands` at the clone's `commands/` with a directory junction.** No copy
and no deploy step, and because the deployment is a real checkout, `/pr` can report which
version of a command ran (its Provenance line) instead of `unknown`. Junction, not symlink: a
symlink needs administrator rights on Windows, a junction does not.

**Adds a `SessionStart` hook to `~/.claude/settings.json`** so every new session pulls first.
Existing settings and any existing hooks are merged, never replaced.

**Blocks pushing from that clone.** The deployment is not a workspace: an accidental
commit-and-push from it would change the commands for everyone who pulls. Pulls are unaffected.
Undo with `git remote set-url --push origin <url>`.

**Runs the hook command once and reports the result** — because when this hook fails, it fails
invisibly (see below), so the install is the one moment a silent failure is cheap to catch.

**Disarms an older hand-copied install, if it finds one.** Before this, the commands were
handed around as a zip with an `INSTALL.bat` that `xcopy`'d them into `~/.claude/commands`.
Running that again *after* the junction exists would copy files straight through it into the
clone: the clone goes dirty, `--ff-only` starts failing, and updates stop with nothing shown.
The script renames those installers to `.DISABLED-superseded-by-git` so they cannot be
double-clicked by accident. Nothing is deleted — only renamed, and only files sitting next to
a `commands/` folder of `.md` files.

### The hook, if you ever need to write it by hand

```json
"hooks": {
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "C:/Program Files/Git/cmd/git.exe",
          "args": ["-C", "<absolute path to the clone>", "pull", "--ff-only", "--quiet"],
          "timeout": 20,
          "async": true,
          "statusMessage": "Updating Claude commands"
        }
      ]
    }
  ]
}
```

Three details carry the weight:

- **`args`, not a command string.** With `args` the executable is spawned directly, with no
  shell involved. On a machine where `bash` resolves to WSL2 — which cannot see `C:\` paths —
  a shell-form hook fails silently and the commands quietly stop updating.
- **Absolute path to `git.exe`.** A hook does not necessarily inherit your `PATH`, and a hook
  that cannot find `git` fails the same silent way. `install.ps1` discovers it per machine.
- **`async: true`.** The hook runs in the background, so no network failure, conflict, or
  detached head can delay session start. It fails soft by construction rather than by
  remembering to append `|| true`.

**Fail-soft cuts both ways, and this is the part to remember.** Measured 2026-08-09: with the
deployment clone on a detached HEAD, the hook exited 1 and the session opened with *no visible
sign at all*. That is the required behaviour — a hook must never hang a session — but it means
a real breakage is equally invisible. The commands keep working and simply freeze at the last
version pulled. To check:

```powershell
git -C "<the deployment clone>" status --short --branch
```

Anything other than `## master...origin/master` with no files listed means updates have stopped.

### Maintainer: two clones

Whoever *develops* the commands wants a second clone. A junction aimed straight at the working
repo means any `git checkout` silently changes the live commands in every project — a
half-finished command on a feature branch becomes the one `/pr` runs.

```
Source/commands              the working repo — edit here, switch branches freely
Source/SKILLS-DO-NOT-EDIT    a second clone, only ever on master
                                  ^
              ~/.claude/commands  (the junction points here)
```

The live clone is named for its rule because nothing else enforces it. The auto-pull hook fails
soft, so a stray commit made there would stop updates *silently* rather than loudly.

## Onboarding a second developer

Everything they need, and nothing else:

1. The one-line install from [Install](#install) above.
2. Open a new Claude Code session, type `/`, confirm the commands are listed.
3. `pre-commit install` in each work project.

That is all. They already have git and GitHub credentials if they have ever pushed a branch;
`install.ps1` stops with a clear message if either is missing, or if Claude Code has not been
run at least once (it needs `~/.claude` to exist).

One clone is enough for them — they never edit the commands, so the two-clone split above has
no purpose here, and `install.ps1` blocks pushing from the clone it deploys.

Explicitly **not**:

- **Not** `git config core.hooksPath .githooks`. It silently disables every pre-commit hook on
  the clone — see [Per-project setup](#per-project-setup).
- **Not** `git config claude.allowTrunkPush true`. That one is the maintainer's.

## Adding your own, without disturbing these

`~/.claude/commands` is no longer a folder — it is a checkout. Anything written there lands
inside the deployment clone. An untracked file does not break `git pull` on its own, but the
day someone commits a command with the same name, the pull fails with *"untracked working tree
files would be overwritten by merge"* — and since the hook fails soft, the failure is invisible
and your commands quietly freeze.

So there is exactly one forbidden location, and everywhere else is free:

| What you are building | Where it goes | Touches this repo? |
|---|---|---|
| A personal skill, available in every project | `~/.claude/skills/<name>/SKILL.md` | no |
| A command for one project only | `<project>/.claude/commands/<name>.md` | no |
| A skill for one project only | `<project>/.claude/skills/<name>/` | no |
| Something both of you should have | this repo, then commit and push | yes — that is the point |
| — | `~/.claude/commands/` **never** | it *is* the clone |

Measured 2026-08-09: `~/.claude/skills/` is a plain directory, is not linked to anything here,
and a skill placed in it loads in the next session while the deployment clone stays clean and
`git pull --ff-only` keeps returning 0. Of the sixteen directories under `~/.claude`, exactly
one — `commands` — is a junction.

Note the formats differ, which is also why `commands/` has not been renamed to `skills/`: a
command is a flat `.md` file, a skill is a directory holding `SKILL.md` with `name` and
`description` frontmatter.

The only name rule: do not reuse one of the names below for a private skill. Anything else is
yours, and two people picking the same private name never collide — those files never meet.

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
| `.githooks/pre-push` | git — refuses pushes straight to the trunk, *if* activated (see below — usually it should not be) |

The first two are generated and overwritten freely. The last three are yours: the two dotfiles
are only ever appended to, and an existing `pre-push` hook is never replaced without asking.

**The push guard is dormant, and on most projects it must stay that way.** `.githooks/pre-push`
is versioned, but the `git config core.hooksPath .githooks` that would activate it is local
config — and **do not run it on a project that uses pre-commit**. `core.hooksPath` *replaces*
the hooks directory rather than adding to it, so that one line silently kills every hook in
`.git/hooks/`, and `pre-commit install` then refuses to run while it is set — the obvious
repair is blocked too. Measured on a real project on 2026-08-06: 11 hooks would have gone
(ruff, ruff-format, mypy, bandit, import-linter, architecture-map, file-size…).

Run `pre-commit install`, and nothing else. No trunk guard is the status quo here, not a
regression: `/pr` already refuses to run on the trunk, so the only path left uncovered is a
deliberate manual `git push origin main`. If the guard is ever wanted, the shape is known — a
`pre-push`-stage entry in `.pre-commit-config.yaml`, leaving pre-commit the single owner of the
hooks directory.

`git config claude.allowTrunkPush true` is the maintainer's opt-out of that guard, for the
person who legitimately merges locally and pushes the trunk. While the guard is dormant it has
no effect at all; nobody else runs it either way. And `git push --no-verify` bypasses any
client-side hook, so this class of guard stops accidents, never intent — on a private repo on
GitHub's free plan, where branch protection cannot be enabled at all, that is most of what is
available.

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

There is no deploy step. Commit, push, and the change reaches every machine at that machine's
next session start. **Deletions travel too** — the deployment *is* the checkout, so a command
removed here is gone everywhere, with nothing extra to remember.

That last part is the whole reason for the junction. Under the old copy-based deployment,
`Copy-Item` only ever added and overwrote: a command deleted from `commands/` kept working in
every project until you also ran `Remove-Item` on the deployed copy, so the repo could claim a
command was gone while `/` still offered it. Drift ran the other way as well — edit
`~/.claude/commands/` directly and this repo silently falls behind, which happened once for two
weeks.

**Edit in the working clone, never in the live one.** See
[Maintainer: two clones](#maintainer-two-clones) for why that separation exists and what breaks
without it.

To see what is actually deployed and from where:

```powershell
Get-Item "$env:USERPROFILE\.claude\commands" | Select-Object LinkType, Target
git -C "$env:USERPROFILE\.claude\commands" log -1 --oneline
```

The second command working at all is the point: the deployment carries its own version, which
is what lets `/pr` name the commit a review ran under instead of reporting `unknown`.
