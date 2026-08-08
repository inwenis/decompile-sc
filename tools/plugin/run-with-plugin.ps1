#Requires -Version 7
<#
.SYNOPSIS
Launch StarCraft 1.16.1 from the disposable working copy with the task-008
read-only observer plugin injected.

.DESCRIPTION
The plugin is injected by scinject.exe (CreateProcess + CreateRemoteThread ->
LoadLibraryA). NOTHING is copied into the game directory by the plugin itself,
so "uninstall" is simply "launch StarCraft.exe directly instead of through this
script" -- see tools/plugin/README.md.

-Windowed is the separate, pre-existing windowed-mode recipe from
research/launch-baseline.md (WMode.dll copied in as ddraw.dll). It is the ONE
thing that does write into the game directory; -RemoveWindowed undoes it, and
tools/make-working-copy.ps1 -Force also purges it.

Hard rules this script respects: it only ever touches the working copy
(default C:\sc-work\1161-base), never C:\sc-install\Starcraft -- $GameDir is
canonicalised (device prefix, slash direction, 8.3 names, links) before the
guard runs and everything downstream uses that canonical form; and the log goes
to a path outside the repo (C:/sc-work/ is gitignored).

.EXAMPLE
./tools/plugin/run-with-plugin.ps1 -Build -Windowed

.EXAMPLE
./tools/plugin/run-with-plugin.ps1 -RemoveWindowed -NoLaunch
#>
[CmdletBinding()]
param(
    [string]$GameDir  = 'C:\sc-work\1161-base',
    [string]$BuildDir,
    [string]$LogPath  = 'C:\sc-work\logs\sc-plugin.log',
    [int]$PollMs      = 250,
    [int]$SettleMs    = 4000,
    [switch]$Build,
    [switch]$Windowed,
    [ValidateSet('none', 'WMode', 'WMode_Fix', 'both')]
    [string]$InjectWindowedHelper = 'none',
    [switch]$RemoveWindowed,
    [switch]$NoLaunch,
    [switch]$WaitForExit,
    # A/B control: launch through exactly this path with our observer NOT injected.
    # Used to prove a symptom is (or is not) ours, and to demonstrate the uninstalled game.
    [switch]$NoPlugin,
    # What the plugin is allowed to do (task 011). 'observe' is the DEFAULT and the
    # off switch: read-only, no hooks, nothing written to game memory -- exactly the
    # task-008 observer. See tools/plugin/README.md "Modes".
    [ValidateSet('observe', 'hooktest', 'shadow', 'fanout')]
    [string]$Mode = 'observe',
    # Log every outgoing command id (default on; noisy but it is what makes a single
    # hand-driven test run diagnosable without a second run).
    [ValidateSet('0', '1')][string]$LogCommands = '1',
    # Per-turn byte budget for fan-out. The replay format length-prefixes each
    # frame's command block with ONE byte, so 255 is the hard ceiling for everything
    # every player does in a frame; 200 leaves room. selection-cap.md 6.2.
    [int]$FanoutBudget = 200,
    # Override the set of command ids that get fanned out (hex, space separated).
    [string]$FanoutCmds,
    # Task 014: draw a selection circle under the units the 12-cap threw away.
    # Only meaningful in -Mode fanout; '0' is the feature's own off switch, which is
    # how a run with and without the visuals can be compared without rebuilding.
    [ValidateSet('0', '1')][string]$Circles = '1',
    # Task 017: page the bottom-HUD wireframe row through the whole shadow
    # selection (right-click on the row flips pages). Only meaningful in
    # -Mode fanout; '0' is its own off switch, same pattern as -Circles.
    [ValidateSet('0', '1')][string]$HudRow = '1'
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path

# --- pristine-install guard (hard rule 1) -----------------------------------
# C:\sc-install\Starcraft is the user's playable install and is never touched.
# A literal prefix match is NOT enough: 'C:/sc-install/...' and
# '\\?\C:\sc-install\...' are both valid Windows paths that Test-Path, Join-Path
# and CreateProcess all accept, and -Windowed COPIES into $GameDir\ddraw.dll
# while -RemoveWindowed DELETES it. So canonicalise first -- device prefix,
# slash direction, . and .., 8.3 short names, symlinks and junctions -- then
# test containment on the canonical form, and use that canonical form for
# everything downstream so the guard cannot check one path and the file
# operations act on another.

# Junction/8.3/device-prefix-proof canonicalisation -- shared with tools/deploy.ps1 so the
# two guards (this file's pristine-install check, deploy.ps1's DeployRoot check) cannot
# drift apart. See tools/plugin/sc-canonical-path.ps1 for why a plain string/GetFullPath
# comparison is not enough.
. (Join-Path $scriptDir 'sc-canonical-path.ps1')

$PRISTINE_ROOT = 'C:\sc-install'
$givenGameDir  = $GameDir
$GameDir       = Get-CanonicalPath $GameDir

# Compare against both the literal root and its canonical form, so the guard
# still holds if C:\sc-install is itself a junction (or does not exist yet).
$guardRoots = @($PRISTINE_ROOT, (Get-CanonicalPath $PRISTINE_ROOT)) |
              Where-Object { $_ } | Select-Object -Unique
foreach ($root in $guardRoots) {
    if (Test-PathUnder -Candidate $GameDir -Root $root) {
        throw "run-with-plugin: refusing to touch the pristine install. '$givenGameDir' resolves to '$GameDir', which is under '$root'. Use the working copy (C:\sc-work\1161-base)."
    }
}

if (-not (Test-Path -LiteralPath $GameDir)) {
    throw "run-with-plugin: game dir not found: $GameDir (create it with tools/make-working-copy.ps1)"
}

$ddraw = Join-Path $GameDir 'ddraw.dll'

if ($RemoveWindowed) {
    if (Test-Path -LiteralPath $ddraw) {
        Remove-Item -LiteralPath $ddraw -Force
        Write-Host "run-with-plugin: removed $ddraw (windowed-mode shim)"
    }
    else { Write-Host "run-with-plugin: no $ddraw present, nothing to remove" }
}

if ($Build) { & (Join-Path $scriptDir 'build.ps1') | Write-Host }

if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot 'work/scratch/plugin-build' }
$dll = Join-Path $BuildDir 'scplugin.dll'
$inj = Join-Path $BuildDir 'scinject.exe'
foreach ($f in @($dll, $inj)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "run-with-plugin: missing $f -- run ./tools/plugin/build.ps1 first (or pass -Build)." }
}

if ($Windowed) {
    $wmode = Join-Path $GameDir 'WMode.dll'
    if (-not (Test-Path -LiteralPath $wmode)) { throw "run-with-plugin: $wmode not found; cannot enable windowed mode." }
    Copy-Item -LiteralPath $wmode -Destination $ddraw -Force
    Write-Host "run-with-plugin: windowed shim installed ($ddraw <- WMode.dll)"
}

if ($NoLaunch) { Write-Host 'run-with-plugin: -NoLaunch given, done.'; return }

$exe = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "run-with-plugin: $exe not found" }

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
$env:SCPLUGIN_LOG     = $LogPath
$env:SCPLUGIN_POLL_MS = "$PollMs"

# The plugin defaults to 'observe' when this is unset, so setting it explicitly on
# every launch keeps "which mode was that run?" answerable from the command alone.
$env:SCPLUGIN_MODE           = $Mode
$env:SCPLUGIN_LOG_COMMANDS   = $LogCommands
$env:SCPLUGIN_FANOUT_BUDGET  = "$FanoutBudget"
$env:SCPLUGIN_CIRCLES        = $Circles
$env:SCPLUGIN_HUDROW         = $HudRow
if ($FanoutCmds) { $env:SCPLUGIN_FANOUT_CMDS = $FanoutCmds }
else { $env:SCPLUGIN_FANOUT_CMDS = '' }

Write-Host "run-with-plugin: log -> $LogPath (poll ${PollMs}ms, mode=$Mode)"
if ($Mode -eq 'observe') {
    Write-Host 'run-with-plugin: mode=observe — read-only, the plugin writes NOTHING to game memory'
} else {
    Write-Host "run-with-plugin: mode=$Mode — the plugin will patch game memory IN THIS PROCESS ONLY (never on disk)"
}

$injArgs = @($exe, $dll, '--wait-ms', "$SettleMs")

# The windowed-mode helpers have no export table, so they cannot be a ddraw proxy;
# they are injectable hook DLLs and must be in place before DirectDraw initialises.
# Hence --early-dll (injected while the process is still suspended).
if ($InjectWindowedHelper -ne 'none') {
    $helpers = switch ($InjectWindowedHelper) {
        'WMode'     { @('WMode.dll') }
        'WMode_Fix' { @('WMode_Fix.dll') }
        'both'      { @('WMode.dll', 'WMode_Fix.dll') }
    }
    foreach ($h in $helpers) {
        $hp = Join-Path $GameDir $h
        if (-not (Test-Path -LiteralPath $hp)) { throw "run-with-plugin: $hp not found" }
        $injArgs += @('--early-dll', $hp)
        Write-Host "run-with-plugin: will early-inject $hp"
    }
}

if ($NoPlugin) {
    $injArgs += '--no-plugin'
    Write-Host 'run-with-plugin: -NoPlugin — control run, our observer will NOT be injected'
}
if (-not $WaitForExit) { $injArgs += '--no-wait-exit' }

# Stream scinject's output live AND keep it, so the pid it prints can be handed
# to the health check below. Resolving the game by process name instead would
# throw whenever any other StarCraft is running on the machine -- after a launch
# that actually succeeded.
$injOut = [System.Collections.Generic.List[string]]::new()
& $inj @injArgs 2>&1 | ForEach-Object { Write-Host $_; $injOut.Add("$_") }
$rc = $LASTEXITCODE
Write-Host "run-with-plugin: scinject exit=$rc"
if ($rc -ne 0) { throw "run-with-plugin: injection failed (exit $rc)" }

$gamePid = 0
foreach ($line in $injOut) {
    if ($line -match 'scinject:\s*PID=(\d+)\b') { $gamePid = [int]$Matches[1] }
}

if (-not $WaitForExit) {
    # A launch can fail with the process still alive and a modal DirectDraw error
    # box on screen -- invisible to exit codes. Check from outside the process.
    Start-Sleep -Seconds 2
    if ($gamePid -gt 0) {
        & (Join-Path $scriptDir 'check-game-windows.ps1') -ProcessId $gamePid
    }
    else {
        Write-Warning 'run-with-plugin: could not parse the pid from scinject output; falling back to resolving the game by process name.'
        & (Join-Path $scriptDir 'check-game-windows.ps1')
    }
    if ($LASTEXITCODE -eq 1) {
        throw 'run-with-plugin: the game has an error dialog open — the launch is NOT healthy.'
    }
}
