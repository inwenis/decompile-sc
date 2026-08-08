#Requires -Version 7
<#
.SYNOPSIS
One-click deployed install of the modded StarCraft 1.16.1: builds the plugin from HEAD,
assembles a self-contained copy of the game + plugin at -DeployRoot, and creates/updates
a desktop shortcut that launches it windowed with the full feature set on -- no terminal,
no arguments.

.DESCRIPTION
Run this after every merge. It is idempotent: re-running overwrites the deployed version
cleanly (mirrors the game tree, overwrites the plugin binaries and launcher, re-saves the
shortcut).

What it does, in order:
  1. Guards -DeployRoot: canonicalises it (device prefix, 8.3 short names, symlinks/
     junctions -- tools/plugin/sc-canonical-path.ps1, the same routine
     run-with-plugin.ps1 uses for its pristine-install guard) and refuses a target
     inside this repo, under C:\git (any repo/worktree), under C:\sc-work (the
     working-copy scratch root) or -SourceGameDir specifically, or under
     C:\sc-install (hard rule: never write there).
  2. Refuses if StarCraft is currently running -- ANY StarCraft process, not only one
     running from -DeployRoot (redeploying over a locked scplugin.dll would abort
     mid-copy, after /MIR had already purged; see "Why the running-game check is
     name-based" below for why it is not scoped tighter).
  3. Refuses if <DeployRoot>\game contains a reparse point (symlink/junction): /MIR
     purging through one deletes files in whatever it points at, and /XJ does not
     stop that on the robocopy build this was verified against.
  4. Builds scplugin.dll + scinject.exe from the current checkout (tools/plugin/build.ps1
     -- already asserts both are PE32/x86 and fails the build otherwise).
  5. Mirrors -SourceGameDir (default the working copy, C:\sc-work\1161-base) into
     <DeployRoot>\game -- the same StarCraft.exe bytes, not a rebuild of anything.
     characters\ (player profiles), save\ (single-player saved games) and Maps\Replays\
     (replays) are excluded from the mirror in both directions, so anything the deployed
     game itself writes there survives every future redeploy. See "What survives a
     redeploy, and what does not" below.
  6. Copies the freshly built plugin binaries, plus run-with-plugin.ps1 and its
     check-game-windows.ps1/sc-canonical-path.ps1/sc-audio-mute.ps1 dependencies, into
     <DeployRoot>\plugin -- so the deployed install does not depend on this repo (or
     this worktree, which is disposable) still existing on disk later. See "Design:
     self-contained, not a thin repo pointer" below.
  7. Writes <DeployRoot>\Launch-StarCraft-Modded.ps1, a launcher with zero parameters
     that calls the deployed copy of run-with-plugin.ps1 with the feature set baked in:
     -Mode fanout -InjectWindowedHelper WMode -Circles 1 -HudRow 1 -Sound (fanout +
     selection circles + HUD row paging, windowed, audible). This is run-with-plugin.ps1's
     real working windowed recipe, not its deprecated/broken -Windowed switch -- see
     tools/plugin/README.md "Windowed mode: injected, not proxied". -Sound matters here
     specifically: run-with-plugin.ps1 mutes by default (unattended test suites), and
     this is the one launcher that must stay audible -- the user plays through it.
  8. Creates/updates the desktop shortcut "StarCraft Modded.lnk", target
     "pwsh -WindowStyle Hidden -File <launcher>" so double-clicking shows the game and
     nothing else -- no console window.
  9. Verifies: deployed StarCraft.exe sha256 == source's, plugin DLL/EXE are newer than
     this run's start (proof they were actually rebuilt, not stale leftovers), the
     shortcut resolves to an existing target and launcher. Prints a one-line receipt.

What survives a redeploy, and what does not.
Early versions of this script mirrored -SourceGameDir into <DeployRoot>\game with a plain
/MIR, which is a TRUE mirror: anything the destination has that the source does not gets
DELETED. That is correct for the shipped game files (an old build should not linger) and
wrong for player state, which exists ONLY in the deploy dir (the working copy is a dev
scratch area, nobody plays from it) -- a plain /MIR silently deleted it on every single
redeploy after the one that created it. Caught in review before "deployed" meant anything,
in two passes: the first covered characters\ (profiles) and Maps\Replays\ (replays); it
missed save\ (single-player saved games, a SIBLING of characters\, not something it
already covered) until a live save-then-redeploy test caught it.

PRESERVED (excluded from the mirror entirely, in both directions):
  - characters\   -- player profiles
  - save\         -- single-player saved games
  - Maps\Replays\ -- replays

PURGED (still a true mirror of -SourceGameDir, same as everything else):
  - Maps\ itself, outside \Replays\ -- a custom map dropped straight into
    <DeployRoot>\game\Maps\ does NOT survive a redeploy.
  - Errors\ -- crash logs, same reasoning.
  - anything else not in the three preserved directories above.

Custom maps were deliberately left out of the preserved set, not overlooked: the honest
fix would mean the same diff-based "keep destination-only extras" logic
tools/make-working-copy.ps1 already uses for the working copy (its
-PreservedExtraPrefixes covers characters\ and all of Maps\) -- /XD cannot do it, because
/XD-ing all of Maps\ would also skip copying the SHIPPED stock maps under it on a fresh
deploy, breaking Single Player/Skirmish map lists entirely. That is a real feature, not
a rejected idea, but it is more code than this fix round and nothing in the task's Goal
asks for custom-map support in the deployed copy -- worth a follow-up task if that
changes.

Why the running-game check is name-based.
The natural check for step 2 above is "is StarCraft running FROM -DeployRoot specifically"
-- but that needs the process's image path, and on this machine Get-Process's
.Path/.MainModule, Get-CimInstance Win32_Process's ExecutablePath, and even a raw
OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION) against the game's own pid all come back
empty or access-denied for this specific process (verified live; not root-caused -- looks
like a session/token boundary between the shell driving these checks and the desktop the
game runs on, not something specific to StarCraft). A guard that silently no-ops when path
access fails is worse than a broader one that always fires, so this checks by process name
alone, same as tools/plugin/close-game.ps1's own precedent: refuse whenever ANY StarCraft
process is running, not only one launched from -DeployRoot. Conservative, but never
silently wrong.

Design: self-contained, not a thin repo pointer.
tools/plugin/run-with-plugin.ps1 already does everything the launcher needs (pristine-
install guard, injection, windowed helper, dialog health check) -- reimplementing that
here would be pure duplication risk for zero benefit. The question was only whether the
deployed launcher should call this repo's copy in place, or its own copy. A thin pointer
into the repo is fragile for this project specifically: worker worktrees (including the
one this task was built in) are disposable and get pruned after merge (AGENTS.md
"Conventions"), so a launcher baked with a worktree path would break the day its worktree
is cleaned up. Copying run-with-plugin.ps1 + check-game-windows.ps1 into the deploy tree
avoids that: the deployed install has everything it needs under one root and keeps
working even if every git worktree on the machine is deleted. The cost is that a deployed
install goes stale until the next ./tools/deploy.ps1 -- identical to how the plugin
binaries themselves already work, so it is not a new kind of staleness.

.PARAMETER DeployRoot
Where the self-contained install is assembled. Must not be inside this repo, under
C:\git, under C:\sc-work, under -SourceGameDir, or under C:\sc-install. Checked against
the canonical (device-prefix/8.3/junction-resolved) form of both the argument and every
protected root, not the literal spelling.

.PARAMETER SourceGameDir
The pristine-verified working copy to deploy from. Never C:\sc-install (hard rule 1).

.PARAMETER ShortcutName
File name of the desktop shortcut.

.EXAMPLE
./tools/deploy.ps1
#>
[CmdletBinding()]
param(
    [string]$DeployRoot = 'C:\sc-deploy\starcraft-modded',
    [string]$SourceGameDir = 'C:\sc-work\1161-base',
    [string]$ShortcutName = 'StarCraft Modded.lnk'
)

$ErrorActionPreference = 'Stop'
$deployStart = Get-Date

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..')).Path
$pluginDir = Join-Path $scriptDir 'plugin'

# Junction/8.3/device-prefix-proof canonicalisation (Get-CanonicalPath, Test-PathUnder) --
# shared with run-with-plugin.ps1's pristine-install guard. A plain GetFullPath comparison
# is spellable around: '-DeployRoot \\?\C:\sc-install\Starcraft' passes a naive prefix
# check unchanged, and /MIR would then purge inside the pristine install.
. (Join-Path $pluginDir 'sc-canonical-path.ps1')

# --- guard: refuse a dangerous -DeployRoot ----------------------------------
$deployRootFull = Get-CanonicalPath $DeployRoot
foreach ($devicePrefix in @('\\?\', '\\.\')) {
    if ($deployRootFull.StartsWith($devicePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        # Get-CanonicalPath strips exactly one such prefix; a canonical result that still
        # carries one is a spelling this guard does not understand. Refuse outright rather
        # than trust it.
        throw "deploy: refusing -DeployRoot '$DeployRoot' -- canonicalised to '$deployRootFull', which still carries a device prefix."
    }
}
foreach ($protected in @(
    @{ Path = $repoRoot;       Label = 'this repo' }
    @{ Path = 'C:\git';        Label = 'every repo/worktree root' }
    @{ Path = 'C:\sc-work';    Label = 'the working-copy scratch root' }
    @{ Path = $SourceGameDir;  Label = '-SourceGameDir itself' }
    @{ Path = 'C:\sc-install'; Label = 'the pristine install (hard rule 1)' }
)) {
    $protectedFull = Get-CanonicalPath $protected.Path
    if (Test-PathUnder -Candidate $deployRootFull -Root $protectedFull) {
        throw "deploy: refusing -DeployRoot '$DeployRoot' (resolves to '$deployRootFull') -- it is inside/under $($protected.Label) ('$protectedFull')."
    }
}

if (-not (Test-Path -LiteralPath $SourceGameDir)) {
    throw "deploy: -SourceGameDir not found: $SourceGameDir (create it with tools/make-working-copy.ps1)"
}
$sourceExe = Join-Path $SourceGameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw "deploy: $sourceExe not found -- is -SourceGameDir a real working copy?"
}
$gameDeployDir = Join-Path $deployRootFull 'game'

# --- guard: refuse if StarCraft is currently running --------------------------
# /MIR purges then re-copies. A process holding scplugin.dll open from a previous deploy
# would abort the copy AFTER the purge already ran, leaving a stale build behind a
# working-looking shortcut -- reproduced live. The natural check is "running FROM
# DeployRoot specifically", but that needs the process's image path, and on this machine
# Get-Process's Path/MainModule, Get-CimInstance's ExecutablePath, and even a raw
# OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION) on the game's pid all come back empty/
# access-denied for this specific process (verified live, cause not root-caused -- some
# session/token boundary between this shell and the desktop the game runs on). A guard
# that silently no-ops when path access fails is worse than a broader one that always
# fires, so this checks by name alone, same as tools/plugin/close-game.ps1's own
# precedent: refuse whenever ANY StarCraft process is running, not just one from inside
# -DeployRoot. Conservative, but never silently wrong.
$runningGame = Get-Process StarCraft -ErrorAction SilentlyContinue
if ($runningGame) {
    $pidList = ($runningGame | Select-Object -ExpandProperty Id) -join ', '
    throw "deploy: StarCraft is running (pid $pidList) -- close it first (tools/plugin/close-game.ps1), then redeploy."
}

# --- guard: refuse to mirror over a reparse point in the deployed game dir ---
# /XJ (exclude junctions) does NOT stop /MIR purging through a junction's target on the
# robocopy build this was verified against -- a junction placed under <DeployRoot>\game
# (e.g. as a workaround to relocate saves) turns the next deploy into a wipe of wherever
# it points. The only safe fix is to never attempt the mirror if one is present.
if (Test-Path -LiteralPath $gameDeployDir) {
    $reparsePoints = @(Get-ChildItem -LiteralPath $gameDeployDir -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($reparsePoints.Count -gt 0) {
        $list = ($reparsePoints | ForEach-Object { "  $($_.FullName)" }) -join "`n"
        throw "deploy: refusing to mirror -- $($reparsePoints.Count) reparse point(s) (symlink/junction) found under $gameDeployDir :`n$list`nA /MIR purge follows a junction into its target and deletes files there. Remove it by hand and re-run."
    }
}

# --- version receipt ---------------------------------------------------------
$gitSha = (& git -C $repoRoot rev-parse --short HEAD).Trim()
$dirty  = [bool](& git -C $repoRoot status --porcelain)
if ($dirty) {
    Write-Warning 'deploy: working tree has uncommitted changes -- deploying whatever is on disk, not a clean HEAD checkout.'
}
$version = "$gitSha$(if ($dirty) { '+dirty' })"
$dateStamp = $deployStart.ToString('yyyy-MM-dd')

Write-Host "deploy: version=$version date=$dateStamp"
Write-Host "deploy: source game dir  $SourceGameDir"
Write-Host "deploy: deploy root      $deployRootFull"

# --- 1. build the plugin from HEAD -------------------------------------------
Write-Host ''
Write-Host '== Building plugin from current checkout =='
& (Join-Path $scriptDir 'plugin\build.ps1') | Write-Host
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "deploy: plugin build failed (exit $LASTEXITCODE)" }

$builtDll = Join-Path $repoRoot 'work\scratch\plugin-build\scplugin.dll'
$builtExe = Join-Path $repoRoot 'work\scratch\plugin-build\scinject.exe'
foreach ($f in @($builtDll, $builtExe)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "deploy: expected build output missing: $f" }
    if ((Get-Item -LiteralPath $f).LastWriteTime -lt $deployStart) {
        throw "deploy: $f is older than this deploy run -- build did not actually refresh it."
    }
}
Write-Host 'build: OK, both artifacts newer than this deploy run'

# --- 2. mirror the game tree, preserving player saves/replays ----------------
Write-Host ''
Write-Host "== Mirroring $SourceGameDir -> $deployRootFull\game =="
New-Item -ItemType Directory -Path $deployRootFull -Force | Out-Null
# characters\ (player profiles), save\ (single-player saved games) and Maps\Replays\
# (replays) are USER DATA the deployed game itself writes, not part of the shipped source
# -- /XD skips them entirely on both the copy and the purge side of /MIR, so anything
# written there after one deploy survives every deploy after it. See .DESCRIPTION
# "What survives a redeploy, and what does not".
#
# save\ is a SIBLING of characters\, not something characters\ already covers -- easy to
# miss (this deploy's own first fix round did, and shipped believing it was complete).
# Evidence it exists and where: StarCraft.exe's own strings carry a bare "save\" fragment
# next to "** Single Player Save Format ver %d.%d" and source names saveload.cpp /
# sai_LoadSave.cpp / CUnitSave.cpp. It never appears in the source tree (0 occurrences --
# checked live), so it is purely a deploy-dir-only, destination-side directory, exactly
# the shape /MIR purges without an exclusion.
#
# /XD 'Maps\Replays' (a multi-segment relative path) does NOT match on this robocopy
# build -- verified live: it still descended into Maps\replays, overwrote LastReplay.rep
# from source and purged a destination-only file. A bare directory NAME does work (also
# verified live) and matches at any depth, which is fine for 'Replays' and 'save': each
# occurs at most once in the whole source tree (once under Maps\, and zero times,
# respectively).
$robocopyArgs = @(
    $SourceGameDir, $gameDeployDir,
    '/MIR',
    '/XD', 'characters', 'Replays', 'save',
    '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP'
)
& robocopy @robocopyArgs | Out-Host
if ($LASTEXITCODE -ge 8) { throw "deploy: robocopy failed with exit code $LASTEXITCODE" }
Write-Host "robocopy exit code $LASTEXITCODE (success)"
Write-Host 'robocopy: characters\, save\ and Maps\Replays\ excluded -- player profiles/saves/replays in the deploy dir are never touched'

# --- 3. copy the plugin runtime (self-contained, see .DESCRIPTION) -----------
Write-Host ''
Write-Host "== Assembling plugin runtime -> $deployRootFull\plugin =="
$pluginDeployDir = Join-Path $deployRootFull 'plugin'
New-Item -ItemType Directory -Path $pluginDeployDir -Force | Out-Null
Copy-Item -LiteralPath $builtDll -Destination (Join-Path $pluginDeployDir 'scplugin.dll') -Force
Copy-Item -LiteralPath $builtExe -Destination (Join-Path $pluginDeployDir 'scinject.exe') -Force
Copy-Item -LiteralPath (Join-Path $pluginDir 'run-with-plugin.ps1')     -Destination (Join-Path $pluginDeployDir 'run-with-plugin.ps1')     -Force
Copy-Item -LiteralPath (Join-Path $pluginDir 'check-game-windows.ps1') -Destination (Join-Path $pluginDeployDir 'check-game-windows.ps1') -Force
Copy-Item -LiteralPath (Join-Path $pluginDir 'sc-canonical-path.ps1')  -Destination (Join-Path $pluginDeployDir 'sc-canonical-path.ps1')  -Force
Copy-Item -LiteralPath (Join-Path $pluginDir 'sc-audio-mute.ps1')      -Destination (Join-Path $pluginDeployDir 'sc-audio-mute.ps1')      -Force
Write-Host 'plugin runtime copied: scplugin.dll, scinject.exe, run-with-plugin.ps1, check-game-windows.ps1, sc-canonical-path.ps1, sc-audio-mute.ps1'

# --- 4. write the zero-argument launcher --------------------------------------
$launcherPath = Join-Path $deployRootFull 'Launch-StarCraft-Modded.ps1'
$launcherBody = @'
#Requires -Version 7
<#
Deployed launcher -- no arguments. Generated by tools/deploy.ps1; re-run that to refresh
this file rather than editing it by hand. Baked feature set: fan-out + selection circles
+ HUD row paging, windowed, sound ON (run-with-plugin.ps1 mutes by default for unattended
test suites -- -Sound here is what keeps the user's own play audible; see
tools/README-deploy.md "Sound").
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
& (Join-Path $here 'plugin\run-with-plugin.ps1') `
    -GameDir  (Join-Path $here 'game') `
    -BuildDir (Join-Path $here 'plugin') `
    -LogPath  (Join-Path $here 'logs\sc-plugin.log') `
    -Mode fanout `
    -InjectWindowedHelper WMode `
    -Sound `
    -Circles 1 `
    -HudRow 1
'@
Set-Content -LiteralPath $launcherPath -Value $launcherBody -Encoding utf8NoBOM
Write-Host ''
Write-Host "launcher written: $launcherPath"

# --- 5. desktop shortcut -------------------------------------------------------
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop $ShortcutName
$pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = Join-Path $PSHOME 'pwsh.exe' }
if (-not (Test-Path -LiteralPath $pwshExe)) { throw "deploy: could not resolve pwsh.exe (looked at $pwshExe)" }

$deployedExe = Join-Path $gameDeployDir 'StarCraft.exe'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath = $pwshExe
$lnk.Arguments = "-WindowStyle Hidden -File `"$launcherPath`""
$lnk.WorkingDirectory = $deployRootFull
$lnk.IconLocation = "$deployedExe,0"
$lnk.Description = 'StarCraft 1.16.1, modded (fan-out select-past-12 + circles + HUD row), windowed'
$lnk.Save()
Write-Host "shortcut written: $shortcutPath"

# --- 6. verify -------------------------------------------------------------
Write-Host ''
Write-Host '== Verifying =='

$srcHash = (Get-FileHash -LiteralPath $sourceExe -Algorithm SHA256).Hash
$dstHash = (Get-FileHash -LiteralPath $deployedExe -Algorithm SHA256).Hash
if ($srcHash -ne $dstHash) {
    throw "deploy: deployed StarCraft.exe hash MISMATCH`n  source:   $srcHash`n  deployed: $dstHash"
}
Write-Host "verify: StarCraft.exe sha256 OK ($dstHash)"

foreach ($f in @((Join-Path $pluginDeployDir 'scplugin.dll'), (Join-Path $pluginDeployDir 'scinject.exe'))) {
    if ((Get-Item -LiteralPath $f).LastWriteTime -lt $deployStart) {
        throw "deploy: $f predates this deploy run -- not freshly built."
    }
}
Write-Host 'verify: plugin binaries are freshly built from this run'

if (-not (Test-Path -LiteralPath $shortcutPath)) { throw "deploy: shortcut was not written: $shortcutPath" }
$resolved = $shell.CreateShortcut($shortcutPath)
if ($resolved.TargetPath -ne $pwshExe) { throw "deploy: shortcut target mismatch: $($resolved.TargetPath)" }
if ($resolved.Arguments -notmatch [Regex]::Escape($launcherPath)) { throw "deploy: shortcut arguments do not reference the launcher: $($resolved.Arguments)" }
if (-not (Test-Path -LiteralPath $launcherPath)) { throw "deploy: shortcut points at a launcher that does not exist: $launcherPath" }
Write-Host "verify: shortcut resolves ($shortcutPath -> $pwshExe $($resolved.Arguments))"

Write-Host ''
Write-Host "deploy: OK  version=$version  date=$dateStamp  -> $deployRootFull"
Write-Host "deploy: shortcut -> $shortcutPath"
exit 0
