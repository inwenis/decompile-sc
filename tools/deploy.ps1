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
  2. Takes the same cross-worker launch lock run-with-plugin.ps1 does (see its
     "Launch lock" .DESCRIPTION and tools/plugin/sc-launch-lock.ps1) for the rest of
     this run -- guard checks through verify -- so a game cannot start in the window
     between the running-game check below and the mirror actually running.
  3. Refuses if StarCraft is currently running -- ANY StarCraft process, not only one
     running from -DeployRoot (redeploying over a locked scplugin.dll would abort
     mid-copy, after /MIR had already purged; see "Why the running-game check is
     name-based" below for why it is not scoped tighter).
  4. Refuses if <DeployRoot>\game contains a reparse point (symlink/junction): /MIR
     purging through one deletes files in whatever it points at, and /XJ does not
     stop that on the robocopy build this was verified against.
  5. Builds scplugin.dll + scinject.exe from the current checkout (tools/plugin/build.ps1
     -- already asserts both are PE32/x86 and fails the build otherwise).
  6. Mirrors -SourceGameDir (default the working copy, C:\sc-work\1161-base) into
     <DeployRoot>\game -- the same StarCraft.exe bytes, not a rebuild of anything.
     characters\, save\, Maps\Replays\, maps\download\ and SCScrnShot_*.pcx are excluded
     from the mirror in both directions, so anything the deployed game itself writes
     there survives every future redeploy. A tripwire hashes those directories before
     and after the mirror and throws if anything preserved actually changed. See "What
     survives a redeploy, and what does not" below.
  7. Copies the freshly built plugin binaries, plus run-with-plugin.ps1 and its
     check-game-windows.ps1/sc-canonical-path.ps1/sc-audio-mute.ps1/sc-launch-lock.ps1/
     sc-foreground.ps1 dependencies, into <DeployRoot>\plugin -- so the deployed install
     does not depend
     on this repo (or this worktree, which is disposable) still existing on disk later.
     See "Design: self-contained, not a thin repo pointer" below.
  8. Writes <DeployRoot>\Launch-StarCraft-Modded.ps1, a launcher with zero parameters
     that calls the deployed copy of run-with-plugin.ps1 with the feature set baked in:
     -Mode fanout -InjectWindowedHelper WMode -Circles 1 -HudRow 1 -ProdQueue 1
     -ProdFan 1 -UpgradeQueue 1 -QueueIndicator 1 -Sound -NoLaunchLock -NoForegroundRestore
     (fanout + selection circles + HUD row paging + over-cap production queue +
     group production fan-out — -ProdQueue and -ProdFan both default to 0 in
     run-with-plugin.ps1 so suites opt in, but the PLAY build turns them on; building
     groups are already on by default. -ProdFan is the task-030 feature: with several
     production buildings selected, one Train click queues a unit at every one of them,
     and it is the second flag here that moves the player's resources, which is why it is
     opt-in per run everywhere else. -QueueIndicator is the task-033 feature and the
     only one here that DRAWS: it fills the production strip's icons past the engine's
     ring from the plugin's own queue and puts a "+N" on the rest, so the two flags above
     it stop being invisible. It draws with the engine's own text routine and adds no art.
     Windowed, audible, and structurally
     unable to take the worker launch lock). This is run-with-plugin.ps1's real working
     windowed recipe, not its deprecated/broken -Windowed switch -- see
     tools/plugin/README.md "Windowed mode: injected, not proxied". -Sound and
     -NoLaunchLock both matter here specifically because this is the ONE launcher the
     user's own play goes through -- see run-with-plugin.ps1's "Launch lock" .DESCRIPTION
     for the regression that shipped once from getting this wrong. The launcher also
     wraps the call in try/catch: on failure it logs to <DeployRoot>\logs\launch-error.log
     and shows a message box, because this runs `pwsh -WindowStyle Hidden` with no
     console -- without that, any failure here is silently invisible to the user.
  9. Creates/updates the desktop shortcut "StarCraft Modded.lnk", target
     "pwsh -WindowStyle Hidden -File <launcher>" so double-clicking shows the game and
     nothing else -- no console window.
  10. Regenerates the feature-test map (tools/make-feature-test-map.ps1, task 062) into
      <DeployRoot>\game\Maps\BroodWar\!feature-test.scx (task 067). It has to run AFTER
      the mirror: the map is a destination-only file (never in -SourceGameDir, never in
      the repo -- hard rule 1), so /MIR correctly purges it every redeploy, and this
      step puts a fresh copy back that matches the build just deployed. Regenerate
      rather than /XF-preserve, deliberately: an exclusion only protects a file that
      already exists (a fresh deploy would still have no map), and a preserved stale
      map silently mismatches the build it rides along with. Cost: the checkout a
      deploy runs from needs the map toolchain (./setup.ps1 for .venv/richchk; issue
      #97 for worktrees) -- the same class of dependency as the C++ toolchain step 5
      already requires. It runs LAST in assembly on purpose: a generator failure
      throws AFTER game+plugin+launcher+shortcut are fully assembled, so the install
      still works and only the map is missing, loudly.
  11. Verifies: deployed StarCraft.exe sha256 == source's, plugin DLL/EXE are newer than
      this run's start (proof they were actually rebuilt, not stale leftovers), the
      feature-test map exists and was written by this run, the
      shortcut resolves to an existing target and launcher. Prints a one-line receipt.
  12. Verifies the deployed plugin's IDENTITY and writes <DeployRoot>\BUILD-ID.txt
      (issue #73, task 056). Step 11's freshness check is a timestamp, and a redeploy of
      an old checkout passes it -- which is exactly the gap that made a deployed build
      untraceable to a commit twice (2026-08-11, 2026-08-12). The DLL now carries its own
      "<short sha>[+dirty] SRC=<digest>" stamp; this step reads it back OUT of the
      deployed file and refuses if it is not the version this run says it deployed.

      So the user's install answers "what am I running" three ways, none of them
      involving hashing a file or comparing mtimes: BUILD-ID.txt beside the game, the
      stamp inside plugin\scplugin.dll (Get-ScDllBuildStamp in
      plugin\sc-build-id.ps1), and the ATTACH banner every launch writes into
      C:\sc-work\logs\sc-plugin.log.

What survives a redeploy, and what does not.
Early versions of this script mirrored -SourceGameDir into <DeployRoot>\game with a plain
/MIR, which is a TRUE mirror: anything the destination has that the source does not gets
DELETED. That is correct for the shipped game files (an old build should not linger) and
wrong for player state, which exists ONLY in the deploy dir (the working copy is a dev
scratch area, nobody plays from it) -- a plain /MIR silently deleted it on every single
redeploy after the one that created it. Caught in review across THREE rounds, each one
finding another sibling of the same bug class: the first covered characters\ (profiles)
and Maps\Replays\ (replays); the second missed save\ (single-player saved games, a
SIBLING of characters\, not something it already covered) until a live save-then-redeploy
test caught it; the third added maps\download\ and SCScrnShot_*.pcx pre-emptively and a
post-mirror tripwire (hash every preserved file before and after, throw on any change) so
a FOURTH instance of this class fails loudly instead of shipping quietly.

PRESERVED (excluded from the mirror entirely, in both directions):
  - characters\        -- player profiles
  - save\               -- single-player saved games
  - Maps\Replays\       -- replays
  - maps\download\      -- Battle.net map-download cache (0 occurrences in source, same
                            shape as save\ -- excluded pre-emptively, not yet caught live)
  - SCScrnShot_*.pcx    -- in-game screenshots (F12), which land in the game dir ROOT

PURGED (still a true mirror of -SourceGameDir, same as everything else):
  - Maps\ itself, outside \Replays\ -- a custom map dropped straight into
    <DeployRoot>\game\Maps\ does NOT survive a redeploy. (!feature-test.scx is the
    one deliberate exception, by RECREATION rather than preservation: step 10
    regenerates it after every mirror, so it is always present and always matches
    the deployed build. Nothing else under Maps\ gets that treatment.)
  - Errors\ -- crash logs, same reasoning.
  - anything else not in the preserved set above.

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
# Cross-worker/deploy serialisation -- deploy.ps1 takes the same lock run-with-plugin.ps1
# does, for its whole run (guard check through the mirror), closing a TOCTOU a verifier
# found: without it, StarCraft could start between the running-game preflight check below
# and the mirror actually running. See tools/plugin/sc-launch-lock.ps1.
. (Join-Path $pluginDir 'sc-launch-lock.ps1')
# Build identity (issue #73, task 056) -- the version string this script prints is now
# also stamped inside the DLL, so the deployed build can say what it is on its own.
. (Join-Path $pluginDir 'sc-build-id.ps1')

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

# --- launch/deploy lock (task018) --------------------------------------------
# Taken for the WHOLE rest of this run (guard through verify), not just the mirror --
# without it, StarCraft could start between the running-game check right below and the
# mirror actually running, the exact TOCTOU a verifier found. Unlike run-with-plugin.ps1,
# this is not gated on $env:AGENT_TASK: deploy.ps1 is never in the user's own play path
# (the deployed launcher calls run-with-plugin.ps1 directly, never this script), so there
# is no user-facing regression risk in always taking it here.
$deployLock = Enter-ScLaunchLock -TimeoutMinutes 5
try {

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
# maps\download\ (Battle.net map-download cache) is the same shape again -- also 0
# occurrences in the source tree, also purely destination-side if the deployed game ever
# creates it. Excluded pre-emptively rather than waiting for a fourth round to find it.
#
# SCScrnShot_*.pcx (in-game screenshots, F12) land in the game dir ROOT, not a
# subdirectory -- /XD cannot express that, so it is a /XF file-pattern exclusion instead,
# same "excluded from both sides of /MIR" treatment.
#
# /XD 'Maps\Replays' (a multi-segment relative path) does NOT match on this robocopy
# build -- verified live: it still descended into Maps\replays, overwrote LastReplay.rep
# from source and purged a destination-only file. A bare directory NAME does work (also
# verified live) and matches at any depth, which is fine for 'Replays'/'save'/'download':
# each occurs at most once in the whole source tree (once under Maps\, and zero times for
# the other two).
$robocopyArgs = @(
    $SourceGameDir, $gameDeployDir,
    '/MIR',
    '/XD', 'characters', 'Replays', 'save', 'download',
    '/XF', 'SCScrnShot_*.pcx',
    '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP'
)

# --- preserved-data tripwire (task018, round 4/5): snapshot before, assert after -------
# Three review rounds have now found a class of bug in this exact mirror step (a
# preserved directory silently purged). A verifier catching it by hand every time does
# not scale -- this makes a future regression a loud thrown error instead of something
# that has to be noticed. Hashes, not just presence: a byte-for-byte survival claim
# deserves a byte-for-byte check, and these directories are small (profiles/saves/
# replays), so hashing everything in them costs nothing meaningful.
#
# Covers all FIVE preserved classes, not just three -- round 4 shipped with the tripwire
# watching characters\/save\/Maps\Replays\ only while the doc and the robocopy exclusion
# list both already claimed all five; a verifier caught the mismatch. SCScrnShot_*.pcx is
# a root-level FILE pattern, not a directory, so it is snapshotted separately
# (-RootFilePatterns) rather than forced into the directory-shaped $RelativeDirs list.
$preservedDirs = @('characters', 'save', 'Maps\Replays', 'maps\download')
$preservedRootFilePatterns = @('SCScrnShot_*.pcx')
function Get-ScPreservedSnapshot {
    param([string]$Root, [string[]]$RelativeDirs, [string[]]$RootFilePatterns = @())
    $snap = @{}
    foreach ($rel in $RelativeDirs) {
        $full = Join-Path $Root $rel
        $snap[$rel] = if (Test-Path -LiteralPath $full) {
            Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{
                    Rel  = $_.FullName.Substring($full.Length).TrimStart('\')
                    Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
            }
        } else { @() }
    }
    if ($RootFilePatterns.Count -gt 0 -and (Test-Path -LiteralPath $Root)) {
        $snap['<root patterns>'] = Get-ChildItem -LiteralPath $Root -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $name = $_.Name; @($RootFilePatterns | Where-Object { $name -like $_ }).Count -gt 0 } |
            ForEach-Object {
                [pscustomobject]@{
                    Rel  = $_.Name
                    Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
            }
    }
    return $snap
}
$preSnapshot = Get-ScPreservedSnapshot -Root $gameDeployDir -RelativeDirs $preservedDirs -RootFilePatterns $preservedRootFilePatterns

& robocopy @robocopyArgs | Out-Host
if ($LASTEXITCODE -ge 8) { throw "deploy: robocopy failed with exit code $LASTEXITCODE" }
Write-Host "robocopy exit code $LASTEXITCODE (success)"
Write-Host 'robocopy: characters\, save\, Maps\Replays\, maps\download\ and SCScrnShot_*.pcx excluded -- player data in the deploy dir is never touched'

$postSnapshot = Get-ScPreservedSnapshot -Root $gameDeployDir -RelativeDirs $preservedDirs -RootFilePatterns $preservedRootFilePatterns
$lost = @()
foreach ($rel in $preSnapshot.Keys) {
    $before = @{}; foreach ($f in $preSnapshot[$rel]) { $before[$f.Rel] = $f.Hash }
    $after  = @{};  foreach ($f in $postSnapshot[$rel]) { $after[$f.Rel] = $f.Hash }
    foreach ($path in $before.Keys) {
        if (-not $after.ContainsKey($path)) { $lost += "MISSING  $rel\$path" }
        elseif ($after[$path] -ne $before[$path]) { $lost += "CHANGED  $rel\$path" }
    }
}
if ($lost.Count -gt 0) {
    throw "deploy: preserved-data tripwire FAILED -- the mirror step above touched files it must not have:`n$($lost -join "`n")"
}
Write-Host "verify: preserved-data tripwire OK ($(($preSnapshot.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) file(s) checked across all five preserved classes)"

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
Copy-Item -LiteralPath (Join-Path $pluginDir 'sc-launch-lock.ps1')     -Destination (Join-Path $pluginDeployDir 'sc-launch-lock.ps1')     -Force
Copy-Item -LiteralPath (Join-Path $pluginDir 'sc-foreground.ps1')      -Destination (Join-Path $pluginDeployDir 'sc-foreground.ps1')      -Force
# Task 043: run-with-plugin.ps1 asks it "am I on the desktop the monitor is showing?" before
# every launch, so the deployed launcher needs it even though the answer is always yes for a
# user who double-clicked their game -- the file has to be THERE for the question to be asked.
Copy-Item -LiteralPath (Join-Path $pluginDir 'sc-desktop.ps1')         -Destination (Join-Path $pluginDeployDir 'sc-desktop.ps1')         -Force
# Task 056: run-with-plugin.ps1 dot-sources it on EVERY launch, the user's included, to
# read the build identity out of the DLL it is about to inject. Missing here would break
# the deployed launcher outright, not degrade it.
Copy-Item -LiteralPath (Join-Path $pluginDir 'sc-build-id.ps1')        -Destination (Join-Path $pluginDeployDir 'sc-build-id.ps1')        -Force
Write-Host 'plugin runtime copied: scplugin.dll, scinject.exe, run-with-plugin.ps1, check-game-windows.ps1, sc-canonical-path.ps1, sc-audio-mute.ps1, sc-launch-lock.ps1, sc-foreground.ps1, sc-desktop.ps1, sc-build-id.ps1'

# --- 4. write the zero-argument launcher --------------------------------------
$launcherPath = Join-Path $deployRootFull 'Launch-StarCraft-Modded.ps1'
$launcherBody = @'
#Requires -Version 7
<#
Deployed launcher -- no arguments. Generated by tools/deploy.ps1; re-run that to refresh
this file rather than editing it by hand. Baked feature set: fan-out + selection circles
+ HUD row paging + over-cap production queue + group production fan-out, windowed,
sound ON (run-with-plugin.ps1 mutes by default for unattended
test suites -- -Sound here is what keeps the user's own play audible; see
tools/README-deploy.md "Sound").

-NoForegroundRestore is baked in for the same class of reason (issue #30): a worker
launch hands the foreground back to whatever window had it before, because an unattended
suite must not own the user's screen. THIS launcher is the user asking for the game, so
the game keeps the foreground it takes. run-with-plugin.ps1's own $env:AGENT_TASK check
would already cover it; this makes it structural.

-NoLaunchLock is baked in deliberately, on top of run-with-plugin.ps1's own
$env:AGENT_TASK check (never true here, since nothing sets that variable for the user's
own desktop shortcut): the worker launch lock must be structurally unreachable from this
path, not just conditionally skipped, because this launcher runs
`pwsh -WindowStyle Hidden` with no console -- a held or wedged lock would otherwise mean
double-clicking the game produces nothing on screen for however long the wait budget is,
with no error visible anywhere. That regression shipped once during this task's own
review and was caught before merge; this comment (and the try/catch below) are why it
should not need catching twice.

The try/catch below exists for the same reason, generalised: ANY failure in a hidden
process is otherwise invisible. On failure this writes the error to
<here>\logs\launch-error.log and shows a message box -- something on screen, rather than
a double-click that silently does nothing.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
try {
    & (Join-Path $here 'plugin\run-with-plugin.ps1') `
        -GameDir  (Join-Path $here 'game') `
        -BuildDir (Join-Path $here 'plugin') `
        -LogPath  (Join-Path $here 'logs\sc-plugin.log') `
        -Mode fanout `
        -InjectWindowedHelper WMode `
        -Sound `
        -NoLaunchLock `
        -NoForegroundRestore `
        -Circles 1 `
        -HudRow 1 `
        -ProdQueue 1 `
        -ProdFan 1 `
        -UpgradeQueue 1 `
        -QueueIndicator 1
}
catch {
    $errLog = Join-Path $here 'logs\launch-error.log'
    New-Item -ItemType Directory -Path (Split-Path $errLog -Parent) -Force | Out-Null
    "$([DateTime]::Now.ToString('o'))`r`n$($_ | Out-String)" | Out-File -LiteralPath $errLog -Append -Encoding utf8
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "StarCraft Modded failed to launch:`r`n`r`n$($_.Exception.Message)`r`n`r`nDetails logged to:`r`n$errLog",
        'StarCraft Modded', 'OK', 'Error') | Out-Null
}
'@
Set-Content -LiteralPath $launcherPath -Value $launcherBody -Encoding utf8NoBOM
Write-Host ''
Write-Host "launcher written: $launcherPath"

# --- 5. desktop shortcut -------------------------------------------------------
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop $ShortcutName
# A .lnk stores an ABSOLUTE path, so it must be a VERSION-STABLE one. The Store build of
# PowerShell lives at C:\Program Files\WindowsApps\Microsoft.PowerShell_<version>_x64__...\,
# and that directory is renamed on every update -- baking it produced a shortcut that died
# the moment the user reinstalled PowerShell (2026-08-10: "the desktop shortcut stopped
# working"). Prefer paths that survive an upgrade, and refuse the versioned one outright.
$pwshCandidates = @(
    (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')                    # MSI install, stable
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')           # Store alias, stable
    (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source              # whatever is on PATH
    (Join-Path $PSHOME 'pwsh.exe')                                           # this session's host
)
$pwshExe = $null
foreach ($cand in $pwshCandidates) {
    if (-not $cand) { continue }
    if ($cand -like '*\WindowsApps\Microsoft.PowerShell_*') { continue }  # version-pinned, dies on update
    if (Test-Path -LiteralPath $cand) { $pwshExe = $cand; break }
}
if (-not $pwshExe) {
    throw ("deploy: could not resolve a version-stable pwsh.exe. Tried: {0}" -f ($pwshCandidates -join '; '))
}

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

# --- 6. regenerate the feature-test map (task 067) ----------------------------
# The mirror in step 2 correctly purged Maps\BroodWar\!feature-test.scx: it is a
# destination-only file (never in -SourceGameDir, never in the repo -- hard rule 1)
# and /MIR is a true mirror. Task 062's card told the user to re-run the generator by
# hand after every redeploy; this step is what makes that instruction obsolete.
# Regenerate rather than /XF-preserve, deliberately: an exclusion only protects a file
# that already exists (a fresh deploy would still ship without the map), and a
# preserved stale map silently mismatches the build it rides along with -- there is no
# staleness signal a player would ever see. Regeneration keeps the map matched to the
# build this run just deployed, at the cost of needing the map toolchain on the
# checkout the deploy runs from (.venv/richchk -- ./setup.ps1; issue #97 for
# worktrees). This step runs LAST in assembly on purpose: if the generator throws,
# game + plugin + launcher + shortcut are already fully assembled, so the install
# still works and only the map is missing -- and the failure is loud, never a silent
# skip. Writes exactly ONE file, ours by name; it never touches anything else under
# the user's Maps\ tree.
Write-Host ''
Write-Host '== Regenerating the feature-test map =='
$featureMapPath = Join-Path $gameDeployDir 'Maps\BroodWar\!feature-test.scx'
& (Join-Path $scriptDir 'make-feature-test-map.ps1') -OutputPath $featureMapPath | Write-Host
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "deploy: feature-test map generation failed (exit $LASTEXITCODE) -- the deployed game works, but $featureMapPath is missing. Fix the toolchain (./setup.ps1) and re-run the deploy, or run tools/make-feature-test-map.ps1 -OutputPath '$featureMapPath' by hand." }

# --- 7. verify -------------------------------------------------------------
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

# The feature-test map is regenerated by step 6 every run (see that step for why it is
# recreated, not preserved). Presence alone is not enough -- a leftover from a previous
# deploy would pass a bare Test-Path -- so this also requires the file to be newer than
# this run's start, same shape as the plugin-binary freshness check above.
if (-not (Test-Path -LiteralPath $featureMapPath)) {
    throw "deploy: feature-test map missing after deploy: $featureMapPath"
}
if ((Get-Item -LiteralPath $featureMapPath).LastWriteTime -lt $deployStart) {
    throw "deploy: $featureMapPath predates this deploy run -- the regeneration step did not actually write it."
}
Write-Host "verify: feature-test map regenerated this run ($featureMapPath)"

# --- 7b. the deployed plugin's IDENTITY, not its freshness (issue #73, task 056) ---
# The check above is a TIMESTAMP: it says a file was written during this run, which is
# what a redeploy of an old checkout also looks like. It was the only thing standing
# between "merged" and "deployed", and on 2026-08-12 that gap cost twenty minutes of
# hashing three scplugin.dll files and comparing their mtimes against commit timestamps
# to work out that the user's build came from main four minutes AFTER the fix landed on
# a branch. So read the identity out of the deployed file and require it to be the
# version this run says it deployed.
$deployedDll = Join-Path $pluginDeployDir 'scplugin.dll'
$deployedStamp = Get-ScDllBuildStamp -Path $deployedDll
if (-not $deployedStamp) {
    throw ("deploy: the deployed scplugin.dll carries NO build stamp. It cannot say what commit it came " +
           'from, which is the whole problem issue #73 exists for. Rebuild with tools/plugin/build.ps1.')
}
if ($deployedStamp.BuildId -ne $version) {
    throw ("deploy: the deployed scplugin.dll says it is build '$($deployedStamp.BuildId)' but this run " +
           "reports version=$version. The copy did not take, or it copied a different build.")
}
$deployedDllHash = (Get-FileHash -LiteralPath $deployedDll -Algorithm SHA256).Hash
Write-Host "verify: deployed scplugin.dll is build $($deployedStamp.BuildId) src=$($deployedStamp.SrcDigest) (read from the file, not from this script's own variables)"

# And a receipt beside the game, for a human who has a running install and a question.
# The DLL is the authority -- this file is the convenience -- so it records the DLL's own
# stamp and hash rather than a separately-computed version string.
$buildIdPath = Join-Path $deployRootFull 'BUILD-ID.txt'
@(
    "version      : $version"
    "commit       : $gitSha$(if ($dirty) { '   (DIRTY: built from a tree with uncommitted changes -- the commit id alone does not describe this build)' })"
    "deployed     : $($deployStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    "plugin stamp : $($deployedStamp.Stamp)"
    "plugin sha256: $deployedDllHash"
    ''
    'The DLL is the authority, not this file. To ask the binary itself:'
    '    . <thisdir>\plugin\sc-build-id.ps1'
    '    Get-ScDllBuildStamp -Path <thisdir>\plugin\scplugin.dll'
    'Every game launched through the shortcut also logs this in its ATTACH banner'
    '(C:\sc-work\logs\sc-plugin.log, line "  build         : ...").'
) | Set-Content -LiteralPath $buildIdPath -Encoding utf8
Write-Host "verify: build receipt written -> $buildIdPath"

if (-not (Test-Path -LiteralPath $shortcutPath)) { throw "deploy: shortcut was not written: $shortcutPath" }
$resolved = $shell.CreateShortcut($shortcutPath)
if ($resolved.TargetPath -ne $pwshExe) { throw "deploy: shortcut target mismatch: $($resolved.TargetPath)" }
if ($resolved.Arguments -notmatch [Regex]::Escape($launcherPath)) { throw "deploy: shortcut arguments do not reference the launcher: $($resolved.Arguments)" }
if (-not (Test-Path -LiteralPath $launcherPath)) { throw "deploy: shortcut points at a launcher that does not exist: $launcherPath" }
Write-Host "verify: shortcut resolves ($shortcutPath -> $pwshExe $($resolved.Arguments))"

} finally {
    Exit-ScLaunchLock -Lock $deployLock
}

Write-Host ''
Write-Host "deploy: OK  version=$version  date=$dateStamp  -> $deployRootFull"
Write-Host "deploy: the deployed plugin reports itself as $($deployedStamp.Stamp) -- see $deployRootFull\BUILD-ID.txt"
Write-Host "deploy: shortcut -> $shortcutPath"
exit 0
