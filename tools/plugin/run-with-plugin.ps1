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

Launch lock (task018). Two workers launching concurrently is not hypothetical -- it
happened live during task018's own development: a second worker's StarCraft process
shared this one's plugin/geometry closely enough that its own cleanup logic mistook one
launch for its leftover and closed it mid-test. Every launch through this script now
takes a file lock at C:\sc-work\logs\sc-launch.lock (task id + pid + timestamp) before
CreateProcess and releases it once the post-launch health check completes -- deliberately
scoped to the LAUNCH SEQUENCE, not the whole play session (this script usually returns
while the game keeps running, so holding the lock that long would need a background
watcher tied to the game's lifetime, a bigger mechanism than the launch race actually
needs). A lock whose recorded pid is no longer running is treated as stale and taken
immediately. Waits up to 3 minutes for a live holder before failing loudly; never
silently launches a second game into a live collision. Deliberately NOT under
work/scratch/ -- that is worktree-local (each worker's own worktree has its own, unshared
copy), which would not serialise anything between workers at all; C:\sc-work\logs\ is the
one location every launch already treats as the shared scratch root (see -LogPath).

Sound. Every unattended test suite (test-selection-circles.ps1,
test-fanout-orders.ps1, test-burrow-fanout.ps1, test-hud-row.ps1) launches
through this script, so a launch is SILENT by default -- pass -Sound for a
normal, audible one. Mechanism: tools/plugin/sc-audio-mute.ps1 mutes the game's
own Windows Core Audio (WASAPI) session directly -- the same per-application
volume the Windows Volume Mixer controls -- once the process id is known.
Nothing is written to the registry or disk, so there is nothing to restore and
nothing that can be left corrupted or stuck-muted by a crash, a kill, or two
overlapping runs: the mute is a property of the process's own audio session and
ends when the process does.

The game's own audio session is created LAZILY, not at launch -- verified live:
StarCraft sitting at its own main menu (visibly running, not stalled) shows
ZERO sessions in the Core Audio session enumerator until something actually
plays. Set-ScProcessMuted therefore polls briefly at launch AND keeps a
background timer re-affirming the mute for as long as the game process lives
(see sc-audio-mute.ps1), so whichever moment a session actually appears it
gets muted within about 1.5s of existing, not just in the first few seconds.

Verification status, stated plainly rather than overclaimed: the mute/unmute
call itself is proven correct against a REAL session on this machine (a
different process, `TryMuteProcess` round-tripped mute -> GetMute=true ->
unmute -> GetMute=false). What was NOT directly observed in this environment,
despite several attempts (menu clicks, several seconds of waiting) was
StarCraft's OWN session actually appearing in the enumerator -- it may need
longer than tested, or this machine may not have a real audio render device
for DirectSound to attach to at all (both remain open questions, not
confirmed either way). The mechanism is correct and will mute the session the
moment one exists; whether StarCraft ever creates one on this specific machine
is the part left unverified.

A first version of this used the game's registry volume settings instead
(HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft `music`/`sfx`, captured before
launch and restored after). That mutated live, per-user state that outlives the
process, and on its very first real run an unguarded `New-Item -Force` against
the already-existing key deleted and recreated it, wiping every other value
under it (Gamma, scroll speed, Recent Maps, ...) alongside the two it meant to
touch -- a real user's settings, corrected from a snapshot taken minutes
earlier in the same session, not from anything durable. Replaced with the
process-scoped mechanism above rather than just fixing the one line: per
AGENTS.md hard rule 5 (added because of this incident), a mechanism that
mutates live user state and depends on a restore step running is the wrong
shape here even when the specific bug is fixed, because "restore always runs"
is a claim a crash or a kill can still falsify.

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
    [ValidateSet('0', '1')][string]$HudRow = '1',
    # Task018: unattended runs are SILENT by default (every test suite launches
    # through this script, so muting here is the one place that covers all of
    # them -- see "Sound" below). Pass -Sound for a normal, audible launch; the
    # deployed desktop shortcut always passes it, since that one is for playing.
    [switch]$Sound
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
# Process-scoped audio mute for unattended launches -- see "Sound" below and
# tools/plugin/sc-audio-mute.ps1.
. (Join-Path $scriptDir 'sc-audio-mute.ps1')

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

# --- launch lock (task018) ----------------------------------------------------
# Two workers launching concurrently is not hypothetical -- it happened live during
# task018: a second worker's own StarCraft process shared this one's plugin+geometry
# closely enough that its cleanup logic mistook one launch for the other's leftover and
# closed it mid-test. This lock serialises the LAUNCH SEQUENCE specifically (CreateProcess
# through the post-launch health check below) across every worker on the machine, so two
# scinject/injection races can never overlap. It deliberately does NOT hold for the
# game's whole play session afterward -- once a launch is confirmed healthy, this script
# usually returns while the game keeps running (no -WaitForExit), so a lock held that long
# would need a background watcher tied to the game's lifetime rather than this script's
# own, which is a bigger mechanism than the actual race (the launch sequence) needs.
# Deliberately NOT under work/scratch/: that directory is worktree-local (each worker's
# worktree has its own, unshared), which would not serialise anything between workers at
# all. C:\sc-work\logs\ is the one location every worker's launch already treats as the
# shared scratch root (see -LogPath's own default), so the lock lives there instead.
$lockPath = 'C:\sc-work\logs\sc-launch.lock'
$lockTaskId = if ($env:AGENT_TASK) { $env:AGENT_TASK } else { "pid$PID" }
New-Item -ItemType Directory -Path (Split-Path $lockPath -Parent) -Force | Out-Null
$lockDeadline = (Get-Date).AddMinutes(3)
$lockHeld = $false
while (-not $lockHeld) {
    $holder = $null
    if (Test-Path -LiteralPath $lockPath) {
        try { $holder = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $holder = $null }
    }
    $holderAlive = $holder -and (Get-Process -Id $holder.pid -ErrorAction SilentlyContinue)
    if (-not $holder -or -not $holderAlive) {
        if ($holder -and -not $holderAlive) {
            Write-Host "run-with-plugin: launch lock held by dead pid $($holder.pid) (task=$($holder.task)) -- treating as stale, taking it"
        }
        # Not a true cross-process mutex (no atomic test-and-set on a plain file write) --
        # a second worker could in principle write in the same instant. The re-read below
        # catches that: only the writer whose own pid comes back out actually holds it: a
        # loser just loops back to the top and waits its turn, rather than proceeding
        # believing it has the lock when it does not.
        [pscustomobject]@{ task = $lockTaskId; pid = $PID; startedUtc = [DateTime]::UtcNow.ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $lockPath -Encoding utf8NoBOM
        Start-Sleep -Milliseconds 250
        $reread = Get-Content -LiteralPath $lockPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($reread -and $reread.pid -eq $PID) { $lockHeld = $true }
    }
    if (-not $lockHeld) {
        if ((Get-Date) -ge $lockDeadline) {
            $who = if ($holder) { "task=$($holder.task) pid=$($holder.pid)" } else { 'unknown' }
            throw "run-with-plugin: could not acquire the launch lock ($lockPath) within 3 minutes -- another launch ($who) is still using it."
        }
        Start-Sleep -Seconds 2
    }
}
Write-Host "run-with-plugin: launch lock acquired ($lockTaskId, pid $PID)"

try {
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

    # --- sound (task018) -------------------------------------------------------
    # Muted by default (see .DESCRIPTION "Sound"); -Sound skips this entirely, which is
    # what the deployed shortcut passes. Process-scoped (the game's own WASAPI audio
    # session, ISimpleAudioVolume::SetMute) -- no registry, no file, nothing that outlives
    # the process, so a crash/kill/overlapping run cannot leave anything muted or corrupted.
    # A first version of this used the game's registry volume settings instead; that wiped
    # a real user's HKCU StarCraft key via an unguarded New-Item -Force (2026-08-08
    # incident) and was replaced rather than merely fixed -- see tools/plugin/README.md
    # "Sound" and tools/plugin/sc-audio-mute.ps1.
    if (-not $Sound -and $gamePid -gt 0) {
        if (Set-ScProcessMuted -ProcessId $gamePid) {
            Write-Host 'run-with-plugin: sound muted for this launch (process-scoped WASAPI session mute) -- pass -Sound to keep audio on'
        }
        else {
            Write-Warning 'run-with-plugin: could not find an audio session to mute within the timeout -- launch continues audible. Pass -Sound to silence this warning if that is expected.'
        }
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
}
finally {
    # Release only if this is still our own lock -- defensive against the (already rare,
    # already narrowed by the re-read-after-write check above) case of somehow not
    # actually holding it when this runs.
    if ($lockHeld) {
        $current = $null
        try { $current = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
        if ($current -and $current.pid -eq $PID) {
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            Write-Host "run-with-plugin: launch lock released ($lockTaskId, pid $PID)"
        }
    }
}
