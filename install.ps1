<#
.SYNOPSIS
    Installs this repo's Claude Code commands as a live deployment.

.DESCRIPTION
    Points ~/.claude/commands at this clone's commands/ with a directory junction, then adds a
    SessionStart hook to ~/.claude/settings.json so every new session pulls first. After this
    there is no deploy step: git pull IS the deploy.

    Run it from the clone you want deployed:

        git clone https://github.com/uriel-s/skills.git
        cd skills
        powershell -ExecutionPolicy Bypass -File .\install.ps1

    Safe to re-run. Nothing is deleted without a backup, and the settings file is validated
    before it replaces the real one.

    No administrator rights required - a junction does not need them (a symlink would).

    ASCII only, deliberately. PowerShell 5.1 reads a BOM-less file as ANSI, and a UTF-8 dash
    or ellipsis decodes into a smart quote, which PowerShell accepts as a string delimiter.
    That breaks parsing in a way the error messages do not point at.

.PARAMETER WhatIf
    Report what would change and exit without touching anything.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- helpers

function Say  { param($m) Write-Host "  $m" }
function Ok   { param($m) Write-Host "  [ ok ] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  [warn] $m" -ForegroundColor Yellow }
# Exit rather than throw: a PowerShell stack trace buries the one line that matters under a
# wall of red, and this script is aimed at someone who should not have to read one.
function Die  { param($m) Write-Host ""; Write-Host "  [FAIL] $m" -ForegroundColor Red; Write-Host ""; exit 1 }
function Step { param($m) Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }

$Stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'

# ---------------------------------------------------------------- 0. locate everything

Step "Checking this clone"

# The script lives at the repo root, so the clone is wherever the script is.
# Nothing to fill in, and nothing to get wrong.
$Clone = $PSScriptRoot
if (-not $Clone) { Die "Cannot determine the script location. Run the .ps1 from disk, not by pasting its contents." }

$CommandsDir = Join-Path $Clone 'commands'

if (-not (Test-Path (Join-Path $Clone '.git'))) {
    Die "$Clone is not a git clone. Clone the repo first, then run this script from inside it."
}
if (-not (Test-Path $CommandsDir)) {
    Die "No commands/ directory in $Clone. Is this the right repo?"
}

$CommandCount = (Get-ChildItem $CommandsDir -Filter *.md -File).Count
if ($CommandCount -eq 0) { Die "commands/ is empty - nothing to deploy." }

Ok "clone:    $Clone"
Ok "commands: $CommandCount files"

# The clone path is baked into settings.json below. Moving or renaming this folder later
# breaks the hook - and it breaks it SILENTLY, which is the whole problem with this design.
# Warn now about the locations people habitually tidy up.
$unstable = @('\Desktop\', '\Downloads\', '\Temp\', '\tmp\', '\OneDrive\')
foreach ($u in $unstable) {
    if ("$Clone\" -like "*$u*") {
        Warn "this clone is under a folder people tend to move or sync ($($u.Trim('\')))."
        Warn "Its path gets written into settings.json. If you move or rename it later, updates"
        Warn "stop with no error shown. Prefer somewhere permanent, e.g. $env:USERPROFILE\skills"
        Warn "Continuing anyway - re-run this script from the new location if you ever move it."
        break
    }
}

# Discover git rather than hard-coding a path - it differs per machine, and a hook that
# cannot find git fails silently forever.
$GitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $GitCmd) { Die "git is not on PATH. Install Git for Windows first." }
$GitExe = $GitCmd.Source
if (-not (Test-Path $GitExe)) { Die "git resolved to '$GitExe', which does not exist." }
Ok "git:      $GitExe"

$ClaudeDir    = Join-Path $env:USERPROFILE '.claude'
$Deployed     = Join-Path $ClaudeDir 'commands'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'
$BackupDir    = Join-Path $ClaudeDir 'backups'

if (-not (Test-Path $ClaudeDir)) {
    Die "$ClaudeDir does not exist. Start Claude Code once so it creates your profile, then re-run."
}
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

# Hook paths go into JSON, so use forward slashes.
$CloneFwd = $Clone -replace '\\', '/'
$GitFwd   = $GitExe -replace '\\', '/'

# ---------------------------------------------------------------- 1. junction

Step "Deploying commands to $Deployed"

$existing = $null
if (Test-Path $Deployed) { $existing = Get-Item $Deployed -Force }

if ($existing -and $existing.LinkType -eq 'Junction') {
    $target = @($existing.Target)
    if ($target -contains $CommandsDir) {
        Ok "already a junction pointing here - nothing to do"
    }
    else {
        Say "currently a junction pointing at: $target"
        if ($PSCmdlet.ShouldProcess($Deployed, "Re-point junction to $CommandsDir")) {
            Remove-Item $Deployed -Force -Recurse
            New-Item -ItemType Junction -Path $Deployed -Target $CommandsDir | Out-Null
            Ok "re-pointed"
        }
    }
}
elseif ($existing) {
    # A real directory with real files - typically an older hand-copied install.
    # Back it up before it is destroyed.
    $backup = Join-Path $BackupDir "commands-backup-$Stamp"
    $n = (Get-ChildItem $Deployed -File -Recurse).Count
    Say "found a real directory with $n file(s) - this is the copy the junction replaces"

    # Anything here that is not in the repo disappears from the live set. It survives in the
    # backup, but nobody thinks to look there. Name the files now, while it is still cheap.
    $repoNames = @(Get-ChildItem $CommandsDir -Filter *.md -File | ForEach-Object { $_.Name })
    $goneNames = @(Get-ChildItem $Deployed -Filter *.md -File | Where-Object { $repoNames -notcontains $_.Name } | ForEach-Object { $_.Name })
    if ($goneNames.Count -gt 0) {
        Warn "$($goneNames.Count) command(s) here are NOT in the repo and will stop being available:"
        foreach ($g in $goneNames) { Warn "    $g" }
        Warn "They are kept in the backup below. If any is one you still want, it belongs in the"
        Warn "repo - copy it out of the backup, commit it, and everyone gets it."
    }
    if ($PSCmdlet.ShouldProcess($Deployed, "Back up to $backup, then replace with a junction")) {
        Copy-Item $Deployed $backup -Recurse
        if ((Get-ChildItem $backup -File -Recurse).Count -ne $n) {
            Die "backup is incomplete - stopping before deleting anything"
        }
        Ok "backed up to $backup"
        Remove-Item $Deployed -Recurse -Force
        New-Item -ItemType Junction -Path $Deployed -Target $CommandsDir | Out-Null
        Ok "replaced with a junction"
    }
}
else {
    if ($PSCmdlet.ShouldProcess($Deployed, "Create junction to $CommandsDir")) {
        New-Item -ItemType Junction -Path $Deployed -Target $CommandsDir | Out-Null
        Ok "created (nothing was there before)"
    }
}

if (-not $WhatIfPreference) {
    $link = Get-Item $Deployed -Force
    if ($link.LinkType -ne 'Junction') { Die "expected a junction at $Deployed, found '$($link.LinkType)'" }
    $seen = (Get-ChildItem $Deployed -Filter *.md -File).Count
    if ($seen -ne $CommandCount) { Die "$seen command(s) visible through the junction, expected $CommandCount" }
    Ok "$seen commands visible through the junction"
}

# ---------------------------------------------------------------- 1b. disarm the old installer

Step "Checking for an older hand-copied install"

# Before this repo was deployed by junction, the commands were handed around as a zip with an
# INSTALL.bat that xcopy'd them into ~/.claude/commands. Running that again now would copy
# files THROUGH the junction into the clone: the clone goes dirty, --ff-only starts failing,
# and updates stop with nothing shown. Rename the installer so it cannot be double-clicked by
# accident. Nothing is deleted - the files stay exactly where they are.
$searchRoots = @(
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'Downloads'),
    $env:USERPROFILE
) | Where-Object { Test-Path $_ } | Select-Object -Unique

$found = @()
foreach ($root in $searchRoots) {
    foreach ($name in @('INSTALL.bat', 'INSTALL.sh')) {
        $hits = Get-ChildItem -Path $root -Filter $name -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
        foreach ($h in $hits) {
            # Only ones sitting next to a commands/ folder of .md files - that is this specific
            # installer, not some unrelated program's.
            $sib = Join-Path $h.DirectoryName 'commands'
            if ((Test-Path $sib) -and (Get-ChildItem $sib -Filter *.md -File -ErrorAction SilentlyContinue)) {
                $found += $h.FullName
            }
        }
    }
}
# The roots overlap (Desktop is under USERPROFILE), so the same file turns up more than once.
$found = @($found | Sort-Object -Unique)

if ($found.Count -eq 0) {
    Ok "none found"
}
else {
    foreach ($path in $found) {
        Say "found: $path"
        $disabled = "$path.DISABLED-superseded-by-git"
        if (Test-Path $disabled) { Ok "already disabled"; continue }
        if ($PSCmdlet.ShouldProcess($path, "Rename so it cannot be run again")) {
            Rename-Item $path -NewName (Split-Path $disabled -Leaf)
            Ok "renamed to $(Split-Path $disabled -Leaf)"
        }
    }
    Say "Nothing was deleted - only renamed, so it cannot be run by accident. That folder is"
    Say "superseded now; remove it whenever you like."
}

# ---------------------------------------------------------------- 2. pull-only guard

Step "Making this clone pull-only"

# This clone is a deployment, not a workspace. An accidental commit-and-push from here would
# change the commands for everyone who pulls. Pulls keep working; pushes fail immediately.
# Undo with:  git remote set-url --push origin <the real url>
$guard = 'DISABLED-this-is-a-deployment-clone-push-from-your-working-clone'
$pushUrl = & $GitExe -C $Clone remote get-url --push origin 2>$null
if ($pushUrl -eq $guard) {
    Ok "already pull-only"
}
else {
    if ($PSCmdlet.ShouldProcess($Clone, "Disable pushing from this clone")) {
        & $GitExe -C $Clone remote set-url --push origin $guard
        Ok "pushes from this clone are now blocked (pulls unaffected)"
    }
}

# ---------------------------------------------------------------- 3. auto-update hook

Step "Adding the auto-update hook to settings.json"

if (Test-Path $SettingsPath) {
    $raw = Get-Content $SettingsPath -Raw
    try { $settings = $raw | ConvertFrom-Json }
    catch { Die "$SettingsPath is not valid JSON. Fix or move it first - this script will not overwrite a file it cannot parse." }
    Ok "read existing settings"
}
else {
    $settings = New-Object PSObject
    Warn "no settings.json - creating one"
}

# Is our hook already there? Match on the clone path, so re-running is a no-op.
$already = $false
if ($settings.PSObject.Properties.Name -contains 'hooks') {
    if ($settings.hooks.PSObject.Properties.Name -contains 'SessionStart') {
        foreach ($group in @($settings.hooks.SessionStart)) {
            foreach ($h in @($group.hooks)) {
                if ($h.args -and (@($h.args) -contains $CloneFwd)) { $already = $true }
            }
        }
    }
}

if ($already) {
    Ok "hook already present for this clone - left as is"
}
else {
    $newHook = [PSCustomObject]@{
        type          = 'command'
        command       = $GitFwd
        args          = @('-C', $CloneFwd, 'pull', '--ff-only', '--quiet')
        timeout       = 20
        async         = $true
        statusMessage = 'Updating Claude commands'
    }
    $newGroup = [PSCustomObject]@{ hooks = @($newHook) }

    if ($settings.PSObject.Properties.Name -notcontains 'hooks') {
        $settings | Add-Member -MemberType NoteProperty -Name hooks -Value (New-Object PSObject)
    }
    if ($settings.hooks.PSObject.Properties.Name -notcontains 'SessionStart') {
        $settings.hooks | Add-Member -MemberType NoteProperty -Name SessionStart -Value @()
    }
    # Append, never replace. Another SessionStart hook may already be doing something else.
    $settings.hooks.SessionStart = @(@($settings.hooks.SessionStart) + $newGroup)

    $json = $settings | ConvertTo-Json -Depth 100

    # Validate BEFORE it goes anywhere near the real file. A settings.json that fails to parse
    # silently disables every setting in it.
    try { $null = $json | ConvertFrom-Json }
    catch { Die "the merged settings would not be valid JSON - nothing was written" }

    if ($PSCmdlet.ShouldProcess($SettingsPath, "Add SessionStart hook")) {
        $sb = $null
        if (Test-Path $SettingsPath) {
            $sb = Join-Path $BackupDir "settings-backup-$Stamp.json"
            Copy-Item $SettingsPath $sb
            Ok "backed up to $sb"
        }
        # UTF-8 without BOM. Set-Content on PowerShell 5.1 would write ANSI by default.
        [System.IO.File]::WriteAllText($SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))

        try {
            $null = (Get-Content $SettingsPath -Raw) | ConvertFrom-Json
            Ok "hook written and re-validated on disk"
        }
        catch {
            Die "the file on disk does not parse - restore from $sb"
        }
    }
}

# ---------------------------------------------------------------- 4. prove it works

Step "Testing the hook command"

if (-not $WhatIfPreference) {
    # Run exactly what the hook will run. A silent failure found now is worth far more than one
    # found in two months: when this hook fails, it fails invisibly by design.
    & $GitExe -C $Clone pull --ff-only --quiet
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        Ok "pull succeeded (exit 0) - updates will arrive on their own"
    }
    else {
        Warn "pull exited $code. Your session will still open normally (the hook cannot block it)"
        Warn "but updates will NOT arrive until this is fixed. Usual causes: no network, or this"
        Warn "clone is not on a branch."
        Warn "Check with:  git -C '$Clone' status --short --branch"
    }
    $head = & $GitExe -C $Clone log -1 --format='%h %s'
    Say "now at: $head"
}

# ---------------------------------------------------------------- done

Step "Done"

if ($WhatIfPreference) {
    Say "-WhatIf was set: nothing above was actually changed."
}
else {
    Say "~/.claude/commands  ->  $CommandsDir"
    Say "Updates pull automatically at the start of every new Claude Code session."
    Say ""
    Say "Next: open a NEW Claude Code session and type / - you should see $CommandCount commands."
    Say ""
    Write-Host "  DO NOT MOVE OR RENAME THIS FOLDER:" -ForegroundColor Yellow
    Write-Host "    $Clone" -ForegroundColor Yellow
    Write-Host "  Its path is stored in settings.json. If it moves, updates stop and nothing" -ForegroundColor Yellow
    Write-Host "  says so - the commands keep working, frozen at today's version. If you do" -ForegroundColor Yellow
    Write-Host "  move it, just run install.ps1 again from the new location." -ForegroundColor Yellow
    Say ""
    Say "Edit the commands in a SEPARATE working clone, never in this one. This clone is the"
    Say "live deployment and pushing from it is blocked."
}
Write-Host ""
