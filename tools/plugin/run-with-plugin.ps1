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

Foreground (issue #30). The game activates its own window when it creates it, and on an
idle desktop nothing ever takes it back -- task 029 measured 72 seconds of stolen
foreground on a 72-second run. Task 027 fixed the per-CLICK raise; this is the LAUNCH,
which it never covered. So a worker launch records the foreground window before
CreateProcess and hands it back once the game's window exists. Gated exactly like the
launch lock: $env:AGENT_TASK (never set for the user's own shortcut) plus
-NoForegroundRestore as an independent second guard, because a human who double-clicked
their game wants to SEE it. See tools/plugin/sc-foreground.ps1.

Launch lock (task018). Two workers launching concurrently is not hypothetical -- it
happened live during task018's own development: a second worker's StarCraft process
shared this one's plugin/geometry closely enough that its own cleanup logic mistook one
launch for its leftover and closed it mid-test. Every WORKER launch through this script
now takes an exclusive OS file lock at C:\sc-work\logs\sc-launch.lock
(`[IO.File]::Open(..., FileShare.None)`, held open for the duration -- not a
check-then-write on file contents, which a verifier showed has a real two-winner race
window) before anything that touches the shared working copy (the CreateProcess sequence,
but also -RemoveWindowed's delete and -Windowed's copy of ddraw.dll -- both act on the
same shared $GameDir, so both race exactly the way launches do) and releases it once the
post-launch health check completes. Deliberately scoped to the LAUNCH SEQUENCE, not the
whole play session: -WaitForExit releases the lock BEFORE blocking on the game's exit,
not after, so a long/foreground play session does not hold the lock for its whole
duration -- a lock held that long would need a background watcher tied to the game's
lifetime rather than this script's own, a bigger mechanism than the launch race needs.
An exclusive OS handle needs no separate staleness logic: if the holder crashes or is
killed, Windows releases the handle itself the instant the process dies, so a "stale
lock" cannot exist by construction (the previous check-then-write design tracked pid
liveness by hand for exactly this reason; the handle design deletes the whole problem
instead of fixing it). Waits up to 5 minutes for a live holder before failing loudly;
never silently launches a second game into a live collision. Deliberately NOT under
work/scratch/ -- that is worktree-local (each worker's own worktree has its own, unshared
copy), which would not serialise anything between workers at all; C:\sc-work\logs\ is the
one location every launch already treats as the shared scratch root (see -LogPath).

**This lock is for workers only and must never affect the user's own play.** It is taken
only when $env:AGENT_TASK is set (true for every worker, never true for a human
double-clicking the desktop shortcut) -- and -NoLaunchLock skips it unconditionally as a
second, independent guard. deploy.ps1's generated launcher bakes -NoLaunchLock in
explicitly, even though the env-var check alone already covers the user's path, because a
held or wedged lock on the shared dev lock file must never turn into the user
double-clicking their game and silently getting nothing for however long the wait budget
is -- that exact regression shipped in an earlier round of this task and was caught before
merge, not after. deploy.ps1 itself also takes this same lock for its own build+mirror
window, closing a TOCTOU in its own running-game preflight check.

Sound. Every unattended test suite (test-selection-circles.ps1,
test-fanout-orders.ps1, test-burrow-fanout.ps1, test-hud-row.ps1) launches
through this script, so a launch is SILENT by default -- pass -Sound for a
normal, audible one (this also actively clears any mute rather than merely
skipping muting -- see below). Mechanism: tools/plugin/sc-audio-mute.ps1 mutes
the game's own Windows Core Audio (WASAPI) session directly -- the same
per-application volume the Windows Volume Mixer controls -- across EVERY
ACTIVE RENDER ENDPOINT, once the process id is known.

Scope, stated exactly: Set-ScProcessMuted polls for up to its -TimeoutSec at
launch and then stops -- there is no ongoing re-check after that window. An
earlier version of this claimed a background timer kept re-affirming the mute
for the whole game session; measured live, that timer did not fire while the
calling script was inside a Start-Sleep call (0 ticks across a 3s sleep) and
died with the calling pwsh process regardless, so it did not do what it
claimed and was removed rather than left in place as a false guarantee -- see
sc-audio-mute.ps1's own .DESCRIPTION for the full account.

Why StarCraft's session was not found in three earlier attempts, resolved: the
mute code checked the DEFAULT render endpoint only. Windows' own per-app audio
policy store on the machine this was tested on shows StarCraft with sessions
on THREE distinct render endpoints (onboard line-out, an HDMI output, a USB
device) -- the session was almost certainly live the whole time, on an
endpoint this code never looked at. sc-audio-mute.ps1 now enumerates every
active render endpoint, not just the default one.

Persistence, checked rather than assumed: searched both
HKCU:\...\MMDevices\Audio\Render\*\Applications\* and the modern per-app
policy store at HKCU:\...\Internet Explorer\LowRegistry\Audio\PolicyConfig\
PropertyStore for anything referencing StarCraft after muting/unmuting a real
session -- found nothing in either. Not an exhaustive proof, so -Sound calls
Set-ScProcessMuted -Mute $false explicitly (see below) rather than just
skipping the mute call, as cheap insurance against a persistence path this
search did not find.

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
    [switch]$Sound,
    # Task018: the launch lock (see "Launch lock" below) is a worker-serialisation
    # mechanism and must never affect the user's own deployed play -- it is taken only
    # when $env:AGENT_TASK is set (true for every worker, never true for a human
    # double-clicking the desktop shortcut) as the primary guard, AND skippable
    # explicitly with this switch as a second, independent one. The deployed launcher
    # deploy.ps1 generates bakes this in even though the env-var check alone would
    # already cover it, specifically so a held/wedged lock can never turn into the user
    # double-clicking their game and silently getting nothing.
    [switch]$NoLaunchLock,
    # Issue #30: hand the foreground back to whatever window had it before this launch,
    # once the game's window exists. On by default for WORKERS ONLY -- the same
    # $env:AGENT_TASK gate the launch lock uses -- and this switch is the second,
    # independent guard, baked into the deployed launcher: the user double-clicked their
    # shortcut in order to play, and pushing the game behind their editor would be a
    # worse bug than the focus theft this fixes. $env:SCDRIVE_RAISE=1 (drive-game.ps1's
    # existing "a human is watching this run" knob) also turns it off.
    [switch]$NoForegroundRestore,
    # Task 043: launch the game onto a named Windows DESKTOP OBJECT rather than the one on
    # the monitor (scinject.exe --desktop, task 040 / PR #49 -> STARTUPINFO.lpDesktop).
    #
    # Normally NOBODY PASSES THIS. run-offscreen.ps1 starts the whole run in a process born
    # on the invisible desktop, and this script then finds itself already there and follows
    # suit on its own (see $effectiveDesktop below). That auto-detection is the point: a
    # launcher that had to be TOLD would be a launcher somebody could forget to tell, and
    # the failure mode of forgetting is the game appearing on the user's screen -- exactly
    # what this is for.
    #
    # Pass it explicitly only to launch onto a desktop this process is not itself on.
    [string]$Desktop,
    # Task 020: the emit-side liveness gate. '1' (the default, and the shipped
    # behaviour) refuses to put a dead / removed-from-play unit's tag into a
    # replayed Select. '0' is a KNOWN-BAD configuration that restores the
    # uniqueness-only test the fan-out shipped with, so the defect can be
    # reproduced on demand -- it is how the in-game regression assertion was shown
    # to be capable of failing (research/fanout-liveness.md). Never use it for a
    # real run.
    [ValidateSet('0', '1')][string]$Liveness = '1',
    # Task 022: the read-only WORLD scan. On each marker the observer walks the
    # engine's own per-player unit lists and logs one line per unit (type, hp, order,
    # position). It installs NO hook and writes nothing, so unlike the fan-out's
    # UNITSTATE line it also exists in -Mode observe -- which is the whole point:
    # the stock arm of a plugin-vs-stock comparison needs an oracle too, and it must
    # be the SAME oracle. Off by default because the existing suites parse this log
    # and a 36-unit fixture would add 36 lines per marker to every one of their runs.
    [ValidateSet('0', '1')][string]$WorldScan = '0',
    # Task 025: let a production building hold more than the engine's five queued items.
    # Off by default -- it installs three detours of its own and it is the only feature
    # here that MOVES A PLAYER'S RESOURCES, so it is opt-in per run. It is also ignored
    # outright in -Mode observe, which stays read-only whatever this says.
    [ValidateSet('0', '1')][string]$ProdQueue = '0',
    # Total logical queue length per building, the engine's five included. Clamped by
    # the plugin to [5, 24].
    [int]$ProdQueueMax = 16,
    # Task 024: same-type building groups. '1' (the default) lets a drag box over N
    # buildings of one type select all N, by relaxing the client half of the
    # unit_IsStandardAndMovable gate for exactly that case. '0' is the feature's own off
    # switch and restores stock "one building per box" -- which is the control arm
    # test-building-groups.ps1 measures the feature against, in the same binary.
    # Only meaningful in -Mode fanout, same as -Circles and -HudRow.
    [ValidateSet('0', '1')][string]$BuildingGroups = '1',
    # Task 026: the read-only COMMAND-CARD scan. On each marker the observer walks the
    # card dialog (0x0068C148) and logs one `CARD` line per slot -- the control's
    # visible/greyed flags plus the Button record behind it (slot, icon, condition,
    # action, params, strings). Like -WorldScan it installs no hook and writes nothing,
    # so it exists in -Mode observe too. Off by default: the existing suites parse this
    # log and this adds eleven lines per marker.
    [ValidateSet('0', '1')][string]$CardScan = '0',
    # Task 030: one Train click queues a unit at EVERY selected production building.
    # Off by default and opt-in per run for the same reason -ProdQueue is: it is the
    # second feature here that MOVES A PLAYER'S RESOURCES -- N buildings means N units
    # paid for, by the engine, from one click. It only ever fans command 0x1F out across
    # a same-type BUILDING group (simSlots == 1), so it is meaningful only in
    # -Mode fanout, and it is ignored outright in -Mode observe. Its read-only oracle
    # (the `PRODFAN` lines) runs whatever this says, because the stock arm is measured
    # with it too.
    [ValidateSet('0', '1')][string]$ProdFan = '0',
    # Task 033: the QUEUE-OVERFLOW INDICATOR. When a building's logical queue is longer
    # than the five icons of the production strip can draw, the plugin draws the icons the
    # engine left empty from its OWN overflow and puts a "+N" over the last one; with
    # several producing buildings selected it says how many of them are queueing. All of it
    # is ENGINE-DRAWN TEXT through a spliced static-text control -- no art is added
    # (research/status-pane-text.md). Off by default because it DRAWS: '0' leaves the
    # status dialog's child list byte-for-byte stock. Only meaningful in -Mode fanout,
    # same as -Circles and -HudRow, and worth little without -ProdQueue 1, which is what
    # creates the overflow it reports.
    [ValidateSet('0', '1')][string]$QueueIndicator = '0',
    # Task 029: queue more than one upgrade or research at one building. Off by default --
    # it installs eight detours of its own and it moves a player's resources (indirectly:
    # the ENGINE pays for every item, at the moment it starts, and the plugin never touches
    # a resource global), so it is opt-in per run. Ignored outright in -Mode observe, which
    # stays read-only whatever this says. This is the flag the deployed launcher turns on.
    [ValidateSet('0', '1')][string]$UpgradeQueue = '0',
    # Total logical queue length per building, the engine's ONE included. Clamped by the
    # plugin to [1, 16].
    [int]$UpgradeQueueMax = 8,
    # Task 032: the read-only RENDERER/VIEWPORT read-back. On each marker the observer logs
    # the screen Bitmap descriptor (0x006CEFF0), all eight graphic layers (0x006CEF50) in
    # draw order with their rectangles and draw callbacks, and the viewport origin plus the
    # scroll maxima. Installs no hook and writes nothing, so it exists in -Mode observe too.
    # Off by default: ten lines per marker, and the existing suites parse this log.
    [ValidateSet('0', '1')][string]$ScreenScan = '0',
    # Task 034: the WIDER PLAYFIELD. Rewrites the operands that carry the screen's
    # geometry so the engine composes a bigger frame (research/renderer-viewport.md 9.3).
    # Off by default and ignored outright in -Mode observe, like every other feature that
    # writes game memory. Two things make it different from the others and both are
    # enforced here rather than left to the caller:
    #   * it must be injected EARLY. Every pitch it patches describes a buffer the game
    #     allocates during startup, so a patch that lands after the video init would be a
    #     promise the allocation cannot keep. Passing this switch adds scinject --early;
    #     the plugin ALSO refuses on its own if it finds the framebuffer already there,
    #     so the two guards are independent.
    #   * it changes what DirectDraw is asked for, so it is only sane windowed --
    #     -InjectWindowedHelper WMode (or -Windowed) is what the runs use.
    [ValidateSet('0', '1')][string]$Widescreen = '0',
    # Which stage of research/renderer-viewport.md 9.3 to apply. 0 = the display mode
    # alone (expect a small image in the corner of a bigger one); 1 = + the screen
    # surface; 2 = + the playfield geometry. Meaningless unless -Widescreen 1.
    [ValidateSet('0', '1', '2')][string]$WidescreenStage = '1'
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
# Cross-worker launch serialisation -- see "Launch lock" below and
# tools/plugin/sc-launch-lock.ps1.
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
# Record-and-restore of the pre-launch foreground window -- see "Foreground" below and
# tools/plugin/sc-foreground.ps1.
. (Join-Path $scriptDir 'sc-foreground.ps1')
# Which desktop this process is on -- see "-Desktop" below and tools/plugin/sc-desktop.ps1.
. (Join-Path $scriptDir 'sc-desktop.ps1')

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

# --- launch lock (task018) ----------------------------------------------------
# See .DESCRIPTION "Launch lock" for the full design/incident. Acquired here, BEFORE
# -RemoveWindowed's delete and -Windowed's copy -- both act on the shared $GameDir's
# ddraw.dll, so both race exactly the way the launch itself does, not just CreateProcess.
# Gated on $env:AGENT_TASK (true for every worker, never for the user's desktop shortcut)
# and -NoLaunchLock, independently -- this lock must never be reachable from the user's
# own play. See tools/plugin/sc-launch-lock.ps1 for the mechanism itself.
$takeLock = (-not $NoLaunchLock) -and [bool]$env:AGENT_TASK
$lock = $null
if ($takeLock) { $lock = Enter-ScLaunchLock -TimeoutMinutes 5 }

# --- foreground restore (issue #30) -------------------------------------------
# Same gate as the lock, for the same reason and with the same second guard: this must
# be unreachable from the user's own play path. SCDRIVE_RAISE=1 is the existing "a human
# is watching this run" knob (drive-game.ps1 Set-ScWindowActive) and turns it off too.
# $preLaunchFg stays Zero until the moment before CreateProcess, so the finally below
# cannot restore anything on a -NoLaunch/-RemoveWindowed run that never launched.
$restoreForeground = (-not $NoForegroundRestore) -and [bool]$env:AGENT_TASK -and ($env:SCDRIVE_RAISE -ne '1')
$preLaunchFg = [IntPtr]::Zero

try {
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
    $env:SCPLUGIN_FANOUT_LIVENESS = $Liveness
    $env:SCPLUGIN_WORLDSCAN      = $WorldScan
    $env:SCPLUGIN_PRODQ          = $ProdQueue
    $env:SCPLUGIN_PRODQ_MAX      = "$ProdQueueMax"
    $env:SCPLUGIN_BUILDING_GROUPS = $BuildingGroups
    $env:SCPLUGIN_CARDSCAN       = $CardScan
    $env:SCPLUGIN_PRODFAN        = $ProdFan
    $env:SCPLUGIN_QUEUEIND       = $QueueIndicator
    $env:SCPLUGIN_UPGQ           = $UpgradeQueue
    $env:SCPLUGIN_UPGQ_MAX       = "$UpgradeQueueMax"
    $env:SCPLUGIN_SCREENSCAN     = $ScreenScan
    $env:SCPLUGIN_WIDESCREEN     = $Widescreen
    $env:SCPLUGIN_WS_STAGE       = $WidescreenStage
    if ($Liveness -eq '0') {
        Write-Warning 'run-with-plugin: -Liveness 0 — the fan-out emit gate is back to the pre-task-020 uniqueness test ALONE. A unit killed by damage will be replayed into a Select. This is a deliberate defect-reproduction run.'
    }
    if ($FanoutCmds) { $env:SCPLUGIN_FANOUT_CMDS = $FanoutCmds }
    else { $env:SCPLUGIN_FANOUT_CMDS = '' }

    Write-Host "run-with-plugin: log -> $LogPath (poll ${PollMs}ms, mode=$Mode)"
    if ($Mode -eq 'observe') {
        Write-Host 'run-with-plugin: mode=observe — read-only, the plugin writes NOTHING to game memory'
    } else {
        Write-Host "run-with-plugin: mode=$Mode — the plugin will patch game memory IN THIS PROCESS ONLY (never on disk)"
    }

    # --no-wait-exit ALWAYS: -WaitForExit's blocking wait happens in THIS script, after
    # the lock below is released, not inside scinject.exe holding the lock for the
    # whole play session (see .DESCRIPTION "Launch lock" on -WaitForExit).
    $injArgs = @($exe, $dll, '--wait-ms', "$SettleMs", '--no-wait-exit')

    # --- which desktop the game is born on (task 043) --------------------------
    # Explicit -Desktop wins. Otherwise: if THIS process is not on the desktop the monitor
    # is showing, it was started by run-offscreen.ps1 onto an invisible one, and the game
    # belongs there too.
    #
    # Why name it rather than let CreateProcess inherit it: task 040 measured that the
    # inheritance chain does not reliably hold through PowerShell's own process-launch path
    # (the game came up on no discoverable desktop at all), which is why scinject.exe grew
    # --desktop in the first place. Naming it costs nothing and removes the question.
    $effectiveDesktop = $Desktop
    if (-not $effectiveDesktop) {
        $here = Get-ScThreadDesktopName
        $shown = Get-ScInputDesktopName
        # $shown is $null on a locked workstation. "I could not find out what is on the
        # monitor" is not a reason to assume this process is off-screen, so that case
        # deliberately falls through to the ordinary visible launch.
        if ($here -and $shown -and ($here -ne $shown)) { $effectiveDesktop = $here }
    }
    if ($effectiveDesktop) {
        $injArgs += @('--desktop', $effectiveDesktop)
        Write-Host "run-with-plugin: launching onto the desktop '$effectiveDesktop' — nothing from this run reaches the monitor (task 043)."
    }

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

    # Task 034. --early puts our DllMain in front of the game's entry point, which is
    # the only place the geometry patches are correct (see -Widescreen above). It is
    # attached to THIS switch alone so no other run's injection point changes.
    if ($Widescreen -eq '1') {
        $injArgs += '--early'
        Write-Host "run-with-plugin: -Widescreen 1 (stage $WidescreenStage) — the plugin is injected EARLY so the geometry patches land before the video init"
        if ($Mode -eq 'observe') {
            Write-Warning 'run-with-plugin: -Widescreen 1 with -Mode observe — the plugin will IGNORE it. Observe writes nothing to game memory; use -Mode hooktest or higher.'
        }
        if (-not $Windowed -and $InjectWindowedHelper -eq 'none') {
            Write-Warning 'run-with-plugin: -Widescreen 1 without a windowed-mode helper — the game will ask DirectDraw for a non-stock display mode fullscreen. Use -Windowed or -InjectWindowedHelper WMode.'
        }
    }

    if ($NoPlugin) {
        $injArgs += '--no-plugin'
        Write-Host 'run-with-plugin: -NoPlugin — control run, our observer will NOT be injected'
    }

    # Stream scinject's output live AND keep it, so the pid it prints can be handed
    # to the health check below. Resolving the game by process name instead would
    # throw whenever any other StarCraft is running on the machine -- after a launch
    # that actually succeeded.
    # WHOSE WINDOW THIS IS ABOUT TO BE TAKEN FROM (issue #30). Recorded here, the last
    # moment before CreateProcess, because the game activates its window the instant it
    # creates one -- roughly four seconds before its own log opens, so there is no
    # in-game signal to record against. Skipped if a StarCraft window already holds the
    # foreground: that is another worker's run, and raising it back would be worse than
    # doing nothing.
    if ($restoreForeground) {
        $fg = Get-ScForegroundWindow
        if ($fg -eq [IntPtr]::Zero) {
            Write-Host 'run-with-plugin: no foreground window to record; the game will keep the foreground it takes.'
        }
        elseif (Test-ScForegroundIsGame -Hwnd $fg) {
            Write-Host 'run-with-plugin: a StarCraft window already holds the foreground (another run); not recording it.'
        }
        else {
            $preLaunchFg = $fg
            Write-Host "run-with-plugin: foreground before launch -- $(Get-ScForegroundLabel -Hwnd $preLaunchFg); it will be handed back once the game window exists."
        }
    }

    $injOut = [System.Collections.Generic.List[string]]::new()
    & $inj @injArgs 2>&1 | ForEach-Object { Write-Host $_; $injOut.Add("$_") }
    $rc = $LASTEXITCODE
    Write-Host "run-with-plugin: scinject exit=$rc"
    if ($rc -ne 0) { throw "run-with-plugin: injection failed (exit $rc)" }

    $gamePid = 0
    foreach ($line in $injOut) {
        if ($line -match 'scinject:\s*PID=(\d+)\b') { $gamePid = [int]$Matches[1] }
    }

    # --- hand the foreground back, at the FIRST moment this script can (issue #30) ---
    # Timed on one launch, with the launch stages stamped against an in-process foreground
    # sampler:
    #     T+5.28  scinject starts the game
    #     T+5.53  the game's window creation takes the foreground
    #     T+9.60  scinject returns -- the first instant this script runs again
    #     T+12.19 check-game-windows
    # So ~4.1 s of the hold is structural: scinject blocks for its own settle and nothing
    # here executes during it. What was NOT structural was the 2.5 s after it -- the mute
    # and the health-check sleep -- which the restore used to sit behind. Doing it here
    # cuts the hold from ~6.8 s to ~4.2 s.
    #
    # The window exists by now: scinject has already returned from WaitForInputIdle, which
    # is what "once the game window exists" means in practice. The finally below repeats
    # this as the safety net, for the case where the game activates itself again while the
    # health check runs.
    if ($preLaunchFg -ne [IntPtr]::Zero) {
        if (Restore-ScForeground -Hwnd $preLaunchFg -Tries 2) {
            Write-Host "run-with-plugin: foreground handed back -- $(Get-ScForegroundLabel -Hwnd $preLaunchFg)"
        }
    }

    # --- sound (task018) -------------------------------------------------------
    # Muted by default (see .DESCRIPTION "Sound"); -Sound actively CLEARS the mute
    # rather than merely skipping it (cheap insurance -- see "Sound" for what that
    # guards against). Process-scoped, every active render endpoint checked -- see
    # tools/plugin/sc-audio-mute.ps1.
    # Wrapped: audio bookkeeping must never fail a launch that has already succeeded.
    # -Sound runs on EVERY USER launch (the deployed shortcut always passes it), unguarded
    # against $ErrorActionPreference='Stop' -- a verifier flagged that a COM hiccup here
    # would otherwise report "failed to launch" to a user over a game that is running
    # fine. The -Sound branch also calls the interop directly rather than through
    # Set-ScProcessMuted's poll loop -- this is pure insurance (see "Sound" .DESCRIPTION),
    # not something worth costing the user up to 5s of polling on every launch for.
    if ($gamePid -gt 0) {
        try {
            if ($Sound) {
                [ScAudio.Interop]::TryMuteProcess([uint32]$gamePid, $false) | Out-Null
                Write-Host 'run-with-plugin: -Sound — ensured the game''s audio session is not muted'
            }
            elseif (Set-ScProcessMuted -ProcessId $gamePid -Mute $true) {
                Write-Host 'run-with-plugin: sound muted for this launch (process-scoped WASAPI session mute, every active render endpoint) -- pass -Sound to keep audio on'
            }
            else {
                Write-Warning 'run-with-plugin: could not find an audio session to mute within the timeout -- launch continues audible. Pass -Sound to silence this warning if that is expected.'
            }
        }
        catch {
            Write-Warning "run-with-plugin: sound mute/unmute failed unexpectedly ($($_.Exception.Message)) -- the launch itself is unaffected."
        }
    }

    # A launch can fail with the process still alive and a modal DirectDraw error box on
    # screen -- invisible to exit codes. Check from outside the process. Always run this
    # (not just when -WaitForExit is absent) since scinject.exe itself no longer waits.
    Start-Sleep -Seconds 2
    if ($gamePid -gt 0) {
        & (Join-Path $scriptDir 'check-game-windows.ps1') -ProcessId $gamePid
    }
    else {
        Write-Warning 'run-with-plugin: could not parse the pid from scinject output; falling back to resolving the game by process name.'
        & (Join-Path $scriptDir 'check-game-windows.ps1')
    }
    # Any non-zero is unhealthy, not just exit 1 (error dialog). check-game-windows.ps1
    # exits 3 when the pid is not running at all -- reachable here because scinject
    # returns as soon as injection succeeds, and the game then has the ~2s settle sleep
    # above to die on its own (partially-mirrored deploy tree, a locked MPQ, a
    # second-instance self-exit). A verifier found this falls through silently on the
    # deployed launcher's play path: exit 3 was not 1, so nothing threw, the hidden pwsh
    # exited 0, and the user got no window and no error -- the exact symptom the
    # -NoLaunchLock fix above exists to prevent, from a different cause. Throwing on any
    # non-zero closes that regardless of which check-game-windows.ps1 exit code it is.
    if ($LASTEXITCODE -ne 0) {
        throw "run-with-plugin: the game is NOT healthy after launch (check-game-windows.ps1 exit=$LASTEXITCODE -- 1=error dialog open, 3=process not running/died immediately)."
    }
}
finally {
    # --- hand the foreground back (issue #30) ---------------------------------
    # In the finally, not after the health check, so a launch that throws with the game
    # already on screen (a modal DirectDraw error box is exactly that case) still gives
    # the user their window back before the failure propagates.
    #
    # By here check-game-windows.ps1 has enumerated the game's top-level windows, so the
    # window whose creation stole the foreground exists -- which is the condition the fix
    # is specified against ("restore it once the game window exists").
    #
    # NEVER FATAL, on the same reasoning as Send-ScDropdownPick's hand-back: the launch
    # has already happened, and a shell that will not give the foreground up is a
    # cosmetic loss, not a failed launch.
    if ($preLaunchFg -ne [IntPtr]::Zero) {
        # Whether the early restore above still holds. If it does this is a no-op and says
        # nothing -- printing "handed back" twice would read as two borrows, not one.
        $alreadyBack = (Get-ScForegroundWindow) -eq $preLaunchFg
        if (Restore-ScForeground -Hwnd $preLaunchFg) {
            if (-not $alreadyBack) {
                Write-Host "run-with-plugin: foreground handed back -- $(Get-ScForegroundLabel -Hwnd $preLaunchFg)"
            }
        }
        else {
            Write-Warning ('run-with-plugin: could not hand the foreground back after launch; the game may be left in front. ' +
                           "It now belongs to $(Get-ScForegroundLabel -Hwnd (Get-ScForegroundWindow)). The launch itself is unaffected.")
        }
    }
    if ($lock) { Exit-ScLaunchLock -Lock $lock }
}

if ($WaitForExit -and $gamePid -gt 0) {
    # Deliberately OUTSIDE the lock (see .DESCRIPTION "Launch lock") -- this can block
    # for a whole play session, and the lock above only ever covers the launch sequence.
    Write-Host "run-with-plugin: -WaitForExit — waiting for pid $gamePid to exit (Ctrl-C to stop waiting)"
    Wait-Process -Id $gamePid -ErrorAction SilentlyContinue
    Write-Host "run-with-plugin: pid $gamePid exited"
}
