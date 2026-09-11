#Requires -Version 7
<#
.SYNOPSIS
One-click deployed install of the modded StarCraft 1.16.1: builds the plugin from HEAD,
assembles a self-contained copy of the game + plugin at -DeployRoot, and creates/updates
a desktop shortcut that launches it windowed with the full feature set on -- no terminal,
no arguments.

.DESCRIPTION
Idempotent: a re-run mirrors the game tree, overwrites the plugin binaries and the
launcher, and re-saves the shortcut. Two orderings are load-bearing: the mirror runs
before the plugin/launcher/shortcut assembly because /MIR purges the destination, and
the feature-test map is regenerated LAST, so a generator failure leaves the install
working with only the map missing. Player state (profiles, saves, replays, downloaded
maps, screenshots) exists ONLY in the deploy dir and is excluded from the mirror in both
directions -- see the robocopy call for exactly what survives and what does not; a custom
map dropped straight into <DeployRoot>\game\Maps\ does not.

.PARAMETER DeployRoot
Where the self-contained install is assembled. Must not be inside this repo, under
C:\git, under C:\sc-work, under -SourceGameDir, or under C:\sc-install. Checked against
the canonical (device-prefix/8.3/junction-resolved) form of both the argument and every
protected root, not the literal spelling.

.PARAMETER SourceGameDir
The pristine-verified working copy to deploy from. Never C:\sc-install -- nothing writes
to the pristine install (AGENTS.md § "Hard rules").

.PARAMETER ShortcutName
File name of the desktop shortcut.

.PARAMETER CncDdrawDir
Where the pinned cnc-ddraw release lives (fetch-cnc-ddraw.ps1's output). The
ddraw.dll found there is sha256-verified against the pin recorded in
tools/plugin/sc-stage-runtime.ps1 before it is staged into the deploy tree.

.PARAMETER NoShortcut
Skip writing (and verifying) the desktop shortcut. A deploy to a throwaway root must not
touch live user state such as the desktop (AGENTS.md § "Hard rules").

.EXAMPLE
./tools/deploy.ps1
#>
[CmdletBinding()]
param(
    [string]$DeployRoot = 'C:\sc-deploy\starcraft-modded',
    [string]$SourceGameDir = 'C:\sc-work\1161-base',
    [string]$ShortcutName = 'StarCraft Modded.lnk',
    [string]$CncDdrawDir = 'C:\sc-work\cnc-ddraw\v7.1.0.0',
    [switch]$NoShortcut
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
. (Join-Path $pluginDir 'sc-launch-lock.ps1')
. (Join-Path $pluginDir 'sc-build-id.ps1')
# What the deploy tree and the release zip both get: the plugin runtime, the pinned
# cnc-ddraw, the launcher and its shim, staged by one function so the two cannot drift.
. (Join-Path $pluginDir 'sc-stage-runtime.ps1')

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

# --- launch/deploy lock ------------------------------------------------------
# Held for the WHOLE rest of this run (guard through verify), not just the mirror:
# otherwise StarCraft can start in the TOCTOU window between the running-game check right
# below and the mirror actually running. Unlike run-with-plugin.ps1 this is not gated on
# $env:AGENT_TASK -- deploy.ps1 is never in the user's own play path (the deployed
# launcher calls run-with-plugin.ps1 directly), so always taking it costs the user nothing.
$deployLock = Enter-ScLaunchLock -TimeoutMinutes 5
try {

# --- guard: refuse if StarCraft is currently running --------------------------
# /MIR purges then re-copies. A process holding scplugin.dll open aborts the copy AFTER
# the purge has run, leaving a stale build behind a working-looking shortcut (reproduced
# live). The tighter check -- "running FROM -DeployRoot" -- needs the process's image
# path, and on this machine Get-Process's Path/MainModule, Get-CimInstance's
# ExecutablePath and a raw OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION) on the game's
# pid all come back empty or access-denied for this process (some session/token boundary
# between this shell and the desktop the game runs on). A guard that silently no-ops when
# path access fails is worse than a broad one that always fires, so match by name alone,
# as tools/plugin/close-game.ps1 does: refuse whenever ANY StarCraft process is running.
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
# build.ps1 already refuses any artifact that is not Machine=0x014C/PE32 -- a non-x86
# binary cannot load into the 32-bit StarCraft.exe -- so this step only has to prove the
# outputs belong to this run rather than being stale leftovers.
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
# characters\ (profiles), save\ (single-player saves), Maps\Replays\ and maps\download\
# (Battle.net map cache) are USER DATA the deployed game writes and the source tree never
# has -- /XD skips them on both the copy and the purge side of /MIR, so they survive every
# redeploy. SCScrnShot_*.pcx (F12 screenshots) land in the game dir ROOT, which /XD cannot
# express, hence the /XF file pattern with the same both-sides treatment.
#
# /XD with a multi-segment path ('Maps\Replays') does NOT match on this robocopy build --
# verified live: it still descended into Maps\replays, overwrote LastReplay.rep from
# source and purged a destination-only file. A bare directory NAME does match, at any
# depth, which is safe here because 'Replays'/'save'/'download' each occur at most once in
# the whole source tree. Custom maps are deliberately NOT preserved: /XD-ing all of Maps\
# would also skip the SHIPPED stock maps on a fresh deploy and empty the Single
# Player/Skirmish map lists, and keeping only destination-only extras needs the diff-based
# approach tools/make-working-copy.ps1 uses, which an exclusion list cannot express.
$robocopyArgs = @(
    $SourceGameDir, $gameDeployDir,
    '/MIR',
    '/XD', 'characters', 'Replays', 'save', 'download',
    '/XF', 'SCScrnShot_*.pcx',
    '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP'
)

# --- preserved-data tripwire: snapshot before, assert after --------------------
# A wrong exclusion above silently purges profiles or saves, which are unrecoverable and
# which nobody notices until they are gone -- this turns that into a thrown error instead.
# Hashes, not just presence: a byte-for-byte survival claim deserves a byte-for-byte
# check, and these directories are small enough that hashing all of them costs nothing.
# It must cover all FIVE preserved classes the exclusion list claims; SCScrnShot_*.pcx is
# a root-level FILE pattern, not a directory, so it is snapshotted through
# -RootFilePatterns rather than forced into the directory-shaped $RelativeDirs list.
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

# --- 3. plugin runtime, cnc-ddraw, launcher, shim, card -----------------------
# The deploy tree gets its OWN copy of run-with-plugin.ps1 and its dependencies instead of
# a launcher pointing back into the repo: worktrees are disposable and get pruned, so a
# baked repo path breaks the day its worktree is cleaned up. Cost: a deployed install goes
# stale until the next deploy -- the same staleness the plugin binaries already have.
# What is copied, and how the 2x ini is generated, lives in tools/plugin/sc-stage-runtime.ps1,
# shared with tools/package-release.ps1 so the release zip and this install cannot drift.
#
# A 2x window only if it FITS the primary screen -- 1280x880 x2 = 2560x1760 does not fit a
# 1920x1080 monitor. Otherwise borderless (fullscreen=true + maintas), which the stage
# function writes. Decided here, not in the stage file: this machine is the one that plays.
Write-Host ''
Write-Host "== Assembling plugin runtime -> $deployRootFull =="
$geom = Get-ScWidescreenGeometry
$wsW = $geom.Width
$wsH = $geom.Height
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$fits2x = ($wsW * 2 -le $screen.Width) -and ($wsH * 2 -le $screen.Height - 48)
$staged = Publish-ScPluginRuntime -Dest $deployRootFull -BuiltDll $builtDll -BuiltExe $builtExe -CncDdrawDir $CncDdrawDir -Borderless (-not $fits2x)
$pluginDeployDir = $staged.PluginDir
$launcherPath    = $staged.LauncherPath
if (-not $fits2x) { Write-Host "presenter: borderless full screen on the $($screen.Width)x$($screen.Height) monitor, aspect kept (2x = $($wsW * 2)x$($wsH * 2) does not fit)" }

# --- 4. desktop shortcut -------------------------------------------------------
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop $ShortcutName
# A .lnk stores an ABSOLUTE path, so it must be a VERSION-STABLE one. The Store build of
# PowerShell lives at C:\Program Files\WindowsApps\Microsoft.PowerShell_<version>_x64__...\,
# a directory renamed on every update: a shortcut baked with it stops working the next
# time PowerShell is updated or reinstalled. Prefer paths that survive an upgrade, and
# refuse the versioned one outright.
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
# Exactly one launcher and one shortcut are deployed. A separate "Wide" pair left behind
# by an older deploy is removed: it would run a stale ini/argument set against the
# current plugin.
$staleWideLauncher = Join-Path $deployRootFull 'Launch-StarCraft-Modded-Wide.ps1'
if (Test-Path -LiteralPath $staleWideLauncher) { Remove-Item -LiteralPath $staleWideLauncher -Force; Write-Host "removed the stale wide launcher: $staleWideLauncher" }
if ($NoShortcut) {
    Write-Host 'shortcuts SKIPPED (-NoShortcut): a scratch/test deploy must not touch the desktop'
}
else {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($shortcutPath)
    $lnk.TargetPath = $pwshExe
    $lnk.Arguments = "-WindowStyle Hidden -File `"$launcherPath`""
    $lnk.WorkingDirectory = $deployRootFull
    $lnk.IconLocation = "$deployedExe,0"
    $lnk.Description = "StarCraft 1.16.1, modded (fan-out select-past-12 + circles + HUD row), WIDESCREEN ${wsW}x${wsH} shown at 2x, mouse locked -- see widescreen-card.md"
    $lnk.Save()
    Write-Host "shortcut written: $shortcutPath"
    $staleWideShortcut = Join-Path $desktop 'StarCraft Modded (Wide).lnk'
    if (Test-Path -LiteralPath $staleWideShortcut) { Remove-Item -LiteralPath $staleWideShortcut -Force; Write-Host "removed the stale wide shortcut: $staleWideShortcut (one shortcut carries the wide geometry now)" }
}

# --- 5. regenerate the feature-test map ---------------------------------------
# Maps\BroodWar\!feature-test.scx is a destination-only file (never in -SourceGameDir,
# never in the repo -- AGENTS.md § "Hard rules"), so the true mirror in step 2 correctly
# purges it every run. Regenerate rather than /XF-preserve: an exclusion only protects a
# file that already exists (a fresh deploy would ship without the map), and a preserved
# stale map silently mismatches the build it rides along with, with no staleness signal a
# player would ever see. Cost: the checkout deploying needs the map toolchain (.venv/
# richchk -- ./setup.ps1). This runs LAST in assembly so a generator failure throws with
# game + plugin + launcher + shortcut already assembled: the install still works, only the
# map is missing, loudly. It writes exactly ONE file, ours by name, and never touches
# anything else under the user's Maps\ tree.
Write-Host ''
Write-Host '== Regenerating the feature-test map =='
$featureMapPath = Join-Path $gameDeployDir 'Maps\BroodWar\!feature-test.scx'
& (Join-Path $scriptDir 'make-feature-test-map.ps1') -OutputPath $featureMapPath | Write-Host
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "deploy: feature-test map generation failed (exit $LASTEXITCODE) -- the deployed game works, but $featureMapPath is missing. Fix the toolchain (./setup.ps1) and re-run the deploy, or run tools/make-feature-test-map.ps1 -OutputPath '$featureMapPath' by hand." }

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

# Presence alone is not enough -- a leftover from an earlier deploy passes a bare
# Test-Path -- so the map must also be newer than this run's start, same shape as the
# plugin-binary freshness check above.
if (-not (Test-Path -LiteralPath $featureMapPath)) {
    throw "deploy: feature-test map missing after deploy: $featureMapPath"
}
if ((Get-Item -LiteralPath $featureMapPath).LastWriteTime -lt $deployStart) {
    throw "deploy: $featureMapPath predates this deploy run -- the regeneration step did not actually write it."
}
Write-Host "verify: feature-test map regenerated this run ($featureMapPath)"

# --- 6b. the deployed plugin's IDENTITY, not its freshness --------------------
# The check above is a TIMESTAMP: it says a file was written during this run, which is
# exactly what a redeploy of an old checkout also looks like. That gap leaves a deployed
# build untraceable to a commit, answerable only by hashing DLLs and comparing mtimes
# against commit times. So read the identity back OUT of the deployed file and require it
# to be the version this run says it deployed.
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

# A receipt beside the game, for a human who has a running install and a question. The
# DLL is the authority and this file the convenience, so it records the DLL's own stamp
# and hash rather than a separately-computed version string.
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

# Launcher, shim, staged helper, both inis and the card must exist, shortcut or not, and
# the staged DLL must still match the pin -- re-read from what shipped, by the stage file.
Test-ScPluginRuntime -Dest $deployRootFull -Borderless (-not $fits2x)

if ($NoShortcut) {
    Write-Host 'verify: shortcuts skipped (-NoShortcut)'
}
else {
    if (-not (Test-Path -LiteralPath $shortcutPath)) { throw "deploy: shortcut was not written: $shortcutPath" }
    $resolved = $shell.CreateShortcut($shortcutPath)
    if ($resolved.TargetPath -ne $pwshExe) { throw "deploy: shortcut target mismatch: $($resolved.TargetPath)" }
    if ($resolved.Arguments -notmatch [Regex]::Escape($launcherPath)) { throw "deploy: shortcut arguments do not reference the launcher: $($resolved.Arguments)" }
    if (-not (Test-Path -LiteralPath $launcherPath)) { throw "deploy: shortcut points at a launcher that does not exist: $launcherPath" }
    Write-Host "verify: shortcut resolves ($shortcutPath -> $pwshExe $($resolved.Arguments))"
}

} finally {
    Exit-ScLaunchLock -Lock $deployLock
}

Write-Host ''
Write-Host "deploy: OK  version=$version  date=$dateStamp  -> $deployRootFull"
Write-Host "deploy: the deployed plugin reports itself as $($deployedStamp.Stamp) -- see $deployRootFull\BUILD-ID.txt"
if ($NoShortcut) {
    Write-Host 'deploy: shortcuts skipped (-NoShortcut)'
}
else {
    Write-Host "deploy: shortcut -> $shortcutPath"
}
exit 0
