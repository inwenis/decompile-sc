#Requires -Version 7
<#
.SYNOPSIS
Launch StarCraft 1.16.1 from the disposable working copy with the read-only
observer plugin injected.

.DESCRIPTION
scinject.exe injects the plugin (CreateProcess + CreateRemoteThread -> LoadLibraryA).
The plugin copies nothing into the game directory, so "uninstall" is "launch
StarCraft.exe directly" -- see tools/plugin/README.md. -Windowed (WMode.dll copied in
as ddraw.dll, research/launch-baseline.md) is the ONE thing that writes into the game
directory; -RemoveWindowed undoes it, tools/make-working-copy.ps1 -Force purges it.

Touches only the working copy (default C:\sc-work\1161-base), never
C:\sc-install\Starcraft; the log goes outside the repo (C:/sc-work/ is gitignored).

Worker launches ($env:AGENT_TASK set) take the launch lock, hand the foreground back
and run muted; the deployed shortcut passes -NoLaunchLock -NoForegroundRestore -Sound.
The DLL's build stamp is checked against src/ before launch and against the ATTACH
banner after it. Each mechanism's why sits at its code site below.

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
    # The stale-DLL gate below REBUILDS by default when the DLL in $BuildDir was not
    # built from the source next to this script. -NoAutoBuild makes it refuse instead:
    # same detection, no compile -- for a machine with no toolchain, or a deliberate
    # run against a specific old DLL, which is then an explicit choice, not an oversight.
    [switch]$NoAutoBuild,
    [switch]$Windowed,
    # Which DLL -Windowed copies in as $GameDir\ddraw.dll. Empty (default) keeps the
    # WMode.dll recipe. Point it at a cnc-ddraw ddraw.dll (fetch-cnc-ddraw.ps1) to run
    # the SAME vector through the non-cropping helper; tools/plugin/cnc-ddraw.ini then
    # travels with it as $GameDir\ddraw.ini, because cnc-ddraw reads its config from
    # the directory the game runs in.
    [string]$WindowedHelperDll = '',
    # Which ini travels in as $GameDir\ddraw.ini when -WindowedHelperDll is a cnc-ddraw
    # build. Empty (default) keeps probes, suites and the wide launcher on
    # $scriptDir\cnc-ddraw.ini, whose width=0/height=0/adjmouse=false is what
    # drive-game.ps1's posted client-area clicks depend on (1:1). Exists so deploy.ps1's
    # normal (non-wide) launcher can point cnc-ddraw at tools/plugin/cnc-ddraw-2x.ini
    # (2x scale + cursor lock) without that offscreen-harness ini ever changing.
    [string]$WindowedHelperIni = '',
    [ValidateSet('none', 'WMode', 'WMode_Fix', 'both')]
    [string]$InjectWindowedHelper = 'none',
    [switch]$RemoveWindowed,
    [switch]$NoLaunch,
    [switch]$WaitForExit,
    # A/B control: launch through exactly this path with our observer NOT injected, to
    # prove a symptom is (or is not) ours and to demonstrate the uninstalled game.
    [switch]$NoPlugin,
    # What the plugin is allowed to do. 'observe' is the DEFAULT and the off switch:
    # read-only, no hooks, nothing written to game memory. See tools/plugin/README.md "Modes".
    [ValidateSet('observe', 'hooktest', 'fanout')]
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
    # Draw a selection circle under the units the 12-cap threw away. Only meaningful
    # in -Mode fanout; '0' is the feature's own off switch, which is how a run with
    # and without the visuals can be compared without rebuilding.
    [ValidateSet('0', '1')][string]$Circles = '1',
    # Page the bottom-HUD wireframe row through the whole shadow selection
    # (right-click on the row flips pages). Only meaningful in -Mode fanout; '0' is
    # its own off switch, same pattern as -Circles.
    [ValidateSet('0', '1')][string]$HudRow = '1',
    # Unattended runs are SILENT by default; every test suite launches through this
    # script, so muting here covers all of them. Pass -Sound for a normal, audible
    # launch; the deployed desktop shortcut always passes it, since that one is for playing.
    [switch]$Sound,
    # The launch lock is a worker-serialisation mechanism and must never affect the
    # user's own deployed play: it is taken only when $env:AGENT_TASK is set (never for
    # a human double-clicking the desktop shortcut), AND this switch skips it as a
    # second, independent guard. deploy.ps1's generated launcher bakes it in even though
    # the env-var check alone covers the user's path, because a held or wedged lock on
    # the shared dev lock file must never turn into the user double-clicking their game
    # and silently getting nothing for the whole wait budget.
    [switch]$NoLaunchLock,
    # Hand the foreground back to whatever window had it before this launch, once the
    # game's window exists. On by default for WORKERS ONLY -- the same $env:AGENT_TASK
    # gate the launch lock uses -- and this switch is the second, independent guard,
    # baked into the deployed launcher: the user double-clicked their shortcut in order
    # to play, and pushing the game behind their editor would be a worse bug than the
    # focus theft this fixes. $env:SCDRIVE_RAISE=1 (drive-game.ps1's "a human is
    # watching this run" knob) also turns it off.
    [switch]$NoForegroundRestore,
    # Launch the game onto a named Windows DESKTOP OBJECT rather than the one on the
    # monitor (scinject.exe --desktop -> STARTUPINFO.lpDesktop). Normally NOBODY PASSES
    # THIS: run-offscreen.ps1 starts the whole run in a process born on the invisible
    # desktop, and this script finds itself already there and follows suit on its own
    # (see $effectiveDesktop below). A launcher that had to be TOLD could be forgotten,
    # and the failure mode of forgetting is the game appearing on the user's screen --
    # exactly what this is for. Pass it explicitly only to launch onto a desktop this
    # process is not itself on.
    [string]$Desktop,
    # The emit-side liveness gate. '1' (the default) refuses to put a dead /
    # removed-from-play unit's tag into a replayed Select. '0' is a KNOWN-BAD
    # configuration that restores the uniqueness-only test the fan-out shipped with, so
    # the defect can be reproduced on demand -- it is how the in-game regression
    # assertion was shown to be capable of failing (research/fanout-liveness.md). Never
    # use it for a real run.
    [ValidateSet('0', '1')][string]$Liveness = '1',
    # The read-only WORLD scan. On each marker the observer walks the engine's own
    # per-player unit lists and logs one line per unit (type, hp, order, position). It
    # installs NO hook and writes nothing, so unlike the fan-out's UNITSTATE line it also
    # exists in -Mode observe -- the stock arm of a plugin-vs-stock comparison needs an
    # oracle too, and it must be the SAME oracle. Off by default because the existing
    # suites parse this log and a 36-unit fixture would add 36 lines per marker.
    [ValidateSet('0', '1')][string]$WorldScan = '0',
    # Let a production building hold more than the engine's five queued items. Off by
    # default -- it installs three detours of its own and it MOVES A PLAYER'S RESOURCES,
    # so it is opt-in per run. Ignored outright in -Mode observe, which stays read-only
    # whatever this says.
    [ValidateSet('0', '1')][string]$ProdQueue = '0',
    # Total logical queue length per building, the engine's five included. Clamped by
    # the plugin to [5, 24].
    [int]$ProdQueueMax = 16,
    # Same-type building groups. '1' (the default) lets a drag box over N buildings of
    # one type select all N, by relaxing the client half of the unit_IsStandardAndMovable
    # gate for exactly that case. '0' is the feature's own off switch and restores stock
    # "one building per box" -- the control arm test-building-groups.ps1 measures the
    # feature against, in the same binary. Only meaningful in -Mode fanout.
    [ValidateSet('0', '1')][string]$BuildingGroups = '1',
    # The read-only COMMAND-CARD scan. On each marker the observer walks the card dialog
    # (0x0068C148) and logs one `CARD` line per slot -- the control's visible/greyed
    # flags plus the Button record behind it (slot, icon, condition, action, params,
    # strings). Like -WorldScan it installs no hook and writes nothing, so it exists in
    # -Mode observe too. Off by default: the existing suites parse this log and this
    # adds eleven lines per marker.
    [ValidateSet('0', '1')][string]$CardScan = '0',
    # One Train click queues a unit at EVERY selected production building. Off by
    # default and opt-in per run for the same reason -ProdQueue is: it MOVES A PLAYER'S
    # RESOURCES -- N buildings means N units paid for, by the engine, from one click. It
    # only ever fans command 0x1F out across a same-type BUILDING group (simSlots == 1),
    # so it is meaningful only in -Mode fanout, and ignored outright in -Mode observe.
    # Its read-only oracle (the `PRODFAN` lines) runs whatever this says, because the
    # stock arm is measured with it too.
    [ValidateSet('0', '1')][string]$ProdFan = '0',
    # The QUEUE-OVERFLOW INDICATOR. When a building's logical queue is longer than the
    # five icons of the production strip can draw, the plugin draws the icons the engine
    # left empty from its OWN overflow and puts a "+N" over the last one; with several
    # producing buildings selected it says how many of them are queueing. All of it is
    # ENGINE-DRAWN TEXT through a spliced static-text control -- no art is added
    # (research/status-pane-text.md). Off by default because it DRAWS: '0' leaves the
    # status dialog's child list byte-for-byte stock. Only meaningful in -Mode fanout,
    # and worth little without -ProdQueue 1, which creates the overflow it reports.
    [ValidateSet('0', '1')][string]$QueueIndicator = '0',
    # Queue more than one upgrade or research at one building. Off by default -- it
    # installs eight detours of its own and it moves a player's resources (indirectly:
    # the ENGINE pays for every item, at the moment it starts, and the plugin never
    # touches a resource global), so it is opt-in per run. Ignored outright in -Mode
    # observe, which stays read-only whatever this says. The deployed launcher turns it on.
    [ValidateSet('0', '1')][string]$UpgradeQueue = '0',
    # Total logical queue length per building, the engine's ONE included. Clamped by the
    # plugin to [1, 16].
    [int]$UpgradeQueueMax = 8,
    # The read-only RENDERER/VIEWPORT read-back. On each marker the observer logs the
    # screen Bitmap descriptor (0x006CEFF0), all eight graphic layers (0x006CEF50) in
    # draw order with their rectangles and draw callbacks, and the viewport origin plus
    # the scroll maxima. Installs no hook and writes nothing, so it exists in -Mode
    # observe too. Off by default: ten lines per marker, and the existing suites parse this log.
    [ValidateSet('0', '1')][string]$ScreenScan = '0',
    # The read-only FRAMEBUFFER DUMP. On each marker the observer copies the engine's
    # own composed frame out of the screen Bitmap's buffer (0x006CEFF0) into
    # fd-<marker>.bin under this directory -- the one oracle that sees the columns the
    # presented window discards (research/renderer-viewport.md 12.6/12.10). Installs no
    # hook and writes nothing to game memory, so it exists in -Mode observe too. Empty =
    # off. THE DUMP REPRODUCES GAME ARTWORK (AGENTS.md § Project hard rules, 1): point
    # this at the gitignored diagnostic path (C:\sc-work\...), never inside the repo.
    [string]$FrameDump = '',
    # The WIDER PLAYFIELD: rewrites the operands that carry the screen's geometry so the
    # engine composes a bigger frame (research/renderer-viewport.md 9.3). Off by default,
    # ignored in -Mode observe like every writer. Two constraints, enforced here:
    #   * injected EARLY (scinject --early): every pitch it patches describes a buffer the
    #     game allocates during startup, so a patch after the video init is a promise the
    #     allocation cannot keep. The plugin ALSO refuses on its own if the framebuffer
    #     already exists, so the two guards are independent.
    #   * windowed only (-InjectWindowedHelper WMode or -Windowed): it changes what
    #     DirectDraw is asked for.
    [ValidateSet('0', '1')][string]$Widescreen = '0',

    # Which stage of research/renderer-viewport.md 9.3 to apply. 0 = the display mode
    # alone (expect a small image in the corner of a bigger one); 1 = + the screen
    # surface; 2 = + the playfield geometry; 3 = + input reaches the full width (the
    # window-proc mouse clamps widen so clicks can reach x=640..799, renderer-viewport.md
    # 18). Meaningless unless -Widescreen 1.
    [ValidateSet('0', '1', '2', '3')][string]$WidescreenStage = '1',
    # Which geometry PRESET the widescreen table targets, by name (sc_screen_presets.h:
    # 1280x880 by default, 1280x720, 1536x864). Empty leaves %SCPLUGIN_WS_GEOMETRY% as
    # inherited, so a suite can set the variable once for a whole run. The DLL refuses
    # the whole widescreen install on an unknown name and logs the list.
    [string]$Geometry = '',
    # Centre the menus on the wider screen and draw a starfield around them (sc_menu.h).
    # Off by default: it moves the glue roots, so a suite's fixed menu coordinates would
    # miss. The deployed launcher turns it on. Needs -Widescreen 1 -WidescreenStage 3.
    [ValidateSet('0', '1')][string]$MenuCentre = '0',

    # Wrap every root dialog's interact with a logging shim (CTRACE lines: dialog name,
    # event type, dwUser, x/y, return value). The dispatcher stops at the first non-zero
    # return, so the trace names the dialog that claims any click. Read-only in effect
    # but it writes dialog records, so it is ignored in -Mode observe too.
    [ValidateSet('0', '1')][string]$ConsoleTrace = '0',

    # The storm-side buffer->glass present (renderer-viewport.md 19.8). 'probe' =
    # READ-ONLY: log storm's virtual-screen geometry, the flip clip, the fallback lock
    # pointer and the present region on the marker channel (any mode, writes nothing).
    # 'widen' = coerce storm's virtual screen to the widescreen width so the present
    # carries all 800 columns (writes game memory, ignored in -Mode observe). '0' = off.
    # 'auto' (default) leaves %SCPLUGIN_STORM_PRESENT% UNSET so the DLL decides: WIDEN
    # at widescreen stage >= 2, off otherwise. The default must be 'auto', not '0': an
    # exported '0' disarms the DLL's auto-arm, the deployed (Wide) shortcut then plays
    # with the present copy OFF and a black right band, and every offscreen proof passes
    # -StormPresent widen explicitly, so none of them can catch it.
    [ValidateSet('auto', '0', 'probe', 'widen')][string]$StormPresent = 'auto'
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path

# --- pristine-install guard ---------------------------------------------------
# C:\sc-install\Starcraft is the user's playable install and is never touched.
# A literal prefix match is NOT enough: 'C:/sc-install/...' and
# '\\?\C:\sc-install\...' are both valid Windows paths that Test-Path, Join-Path
# and CreateProcess all accept, and -Windowed COPIES into $GameDir\ddraw.dll
# while -RemoveWindowed DELETES it. So canonicalise first -- device prefix,
# slash direction, . and .., 8.3 short names, symlinks and junctions -- then
# test containment on the canonical form, and use that form for everything
# downstream so the guard cannot check one path and the file operations act on another.

# Junction/8.3/device-prefix-proof canonicalisation -- shared with tools/deploy.ps1 so the
# two guards (this file's pristine-install check, deploy.ps1's DeployRoot check) cannot
# drift apart. See tools/plugin/sc-canonical-path.ps1 for why a plain string/GetFullPath
# comparison is not enough.
. (Join-Path $scriptDir 'sc-canonical-path.ps1')
# Process-scoped audio mute for unattended launches -- see the sound block below.
. (Join-Path $scriptDir 'sc-audio-mute.ps1')
# Cross-worker launch serialisation -- see the launch lock below.
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
# Record-and-restore of the pre-launch foreground window -- see the foreground gate below.
. (Join-Path $scriptDir 'sc-foreground.ps1')
# Which desktop this process is on -- see -Desktop above and tools/plugin/sc-desktop.ps1.
. (Join-Path $scriptDir 'sc-desktop.ps1')
# What build the DLL about to be injected IS -- see the stale-DLL gate below. Every helper
# here is copied into the deployed plugin dir by deploy.ps1: this script runs from there too.
. (Join-Path $scriptDir 'sc-build-id.ps1')

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

# --- launch lock --------------------------------------------------------------
# Concurrent worker launches collide: one worker's cleanup mistakes the other's game
# (same plugin, same geometry) for its own leftover and closes it mid-test. Taken here,
# BEFORE -RemoveWindowed's delete and -Windowed's copy -- both act on the shared
# $GameDir's ddraw.dll and race exactly the way CreateProcess does. Workers only, on
# two independent guards ($env:AGENT_TASK is never set for the user's shortcut;
# -NoLaunchLock), because the lock must never be reachable from the user's own play.
# Mechanism, lock path and why an OS handle: tools/plugin/sc-launch-lock.ps1.
$takeLock = (-not $NoLaunchLock) -and [bool]$env:AGENT_TASK
$lock = $null
if ($takeLock) { $lock = Enter-ScLaunchLock -TimeoutMinutes 5 }

# --- foreground restore ---------------------------------------------------------
# The game activates its own window when it creates it, and on an idle desktop nothing
# ever takes it back; a worker launch records the foreground before CreateProcess and
# hands it back once the game's window exists (tools/plugin/sc-foreground.ps1). Same
# gate as the lock, same second guard: unreachable from the user's own play path.
# SCDRIVE_RAISE=1 (drive-game.ps1 Set-ScWindowActive, "a human is watching this run")
# turns it off too. $preLaunchFg stays Zero until the moment before CreateProcess, so
# the finally below cannot restore anything on a -NoLaunch/-RemoveWindowed run.
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
        # The cnc-ddraw config a -WindowedHelperDll install placed next to the DLL.
        # Inert without a ddraw.dll, but the shared game dir stays as found.
        $ddrawIni = Join-Path $GameDir 'ddraw.ini'
        if (Test-Path -LiteralPath $ddrawIni) {
            Remove-Item -LiteralPath $ddrawIni -Force
            Write-Host "run-with-plugin: removed $ddrawIni (windowed-helper config)"
        }
    }

    if ($Build) { & (Join-Path $scriptDir 'build.ps1') | Write-Host }

    # Whether the caller NAMED a build directory, decided before the default is filled in.
    # It changes what the stale-DLL gate below is allowed to do.
    $explicitBuildDir = $PSBoundParameters.ContainsKey('BuildDir') -and $BuildDir
    if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot 'work/scratch/plugin-build' }
    $dll = Join-Path $BuildDir 'scplugin.dll'
    $inj = Join-Path $BuildDir 'scinject.exe'
    foreach ($f in @($dll, $inj)) {
        if (-not (Test-Path -LiteralPath $f)) { throw "run-with-plugin: missing $f -- run ./tools/plugin/build.ps1 first (or pass -Build)." }
    }

    # --- stale-DLL gate --------------------------------------------------------
    # Test-Path above answers "is there a file"; a DLL left over from an earlier build
    # passes it as readily as a current one, and a suite run against it is green for
    # code that never ran -- silently, since nothing in the run says which build was
    # injected. The DLL carries its own identity (build.ps1 stamps it, sc-build-id.ps1
    # compares it against the CONTENT of src/* plus build.ps1) so the mismatch is loud.
    $gateSrcDir = Join-Path $scriptDir 'src'
    if (Test-Path -LiteralPath $gateSrcDir) {
        $verdict = Test-ScPluginCurrent -DllPath $dll -SrcDir $gateSrcDir `
                                        -BuildScript (Join-Path $scriptDir 'build.ps1')
        if ($verdict.Current) {
            Write-Host "run-with-plugin: plugin $($verdict.Reason)"
        }
        elseif ($explicitBuildDir) {
            # A NAMED -BuildDir is a deliberate choice of build, and real callers depend on
            # it being honoured: test-random-conformance.ps1 points at C:\sc-work\builds\<sha>
            # to reproduce a bug against the commit BEFORE its fix, probe-queue-indicator-frames.ps1
            # keeps a 'defect' arm, and README-deploy.md points this script at the user's
            # DEPLOYED plugin dir. Rebuilding into any of those destroys what the caller asked
            # for -- in the deploy case it overwrites the user's installed binary from a test
            # run. So never rebuild here; say loudly what is being injected instead, because
            # "deliberate" and "forgotten" look identical in a transcript unless one says so.
            Write-Warning ("run-with-plugin: the plugin in the -BuildDir you named is NOT this worktree's source -- " +
                           "$($verdict.Reason) Nothing was rebuilt: that directory is yours, and a named build dir is " +
                           'treated as a deliberate choice of build. If this run was meant to test your edits, drop -BuildDir.')
        }
        elseif ($NoAutoBuild) {
            throw ("run-with-plugin: STALE PLUGIN -- $($verdict.Reason)`n" +
                   "Every assertion in this run would have been made against code that is not in this worktree. " +
                   'Re-run without -NoAutoBuild to rebuild, or run ./tools/plugin/build.ps1 yourself.')
        }
        else {
            Write-Host "run-with-plugin: STALE PLUGIN -- $($verdict.Reason)"
            Write-Host 'run-with-plugin: rebuilding before launch (this used to run the old DLL and say nothing).'
            & (Join-Path $scriptDir 'build.ps1') -OutDir $BuildDir | Write-Host
            # Re-check rather than assume the rebuild fixed it. A build that
            # wrote somewhere else, or produced an unstamped DLL, must not be
            # able to satisfy this gate by having exited 0.
            $verdict = Test-ScPluginCurrent -DllPath $dll -SrcDir $gateSrcDir `
                                            -BuildScript (Join-Path $scriptDir 'build.ps1')
            if (-not $verdict.Current) {
                throw "run-with-plugin: rebuilt and the DLL is STILL not this tree -- $($verdict.Reason)"
            }
            Write-Host "run-with-plugin: rebuilt -- $($verdict.Reason)"
        }
        $expectedStamp = $verdict.Stamp
    }
    else {
        # The deployed runtime copy: plugin\ next to the game, no src/, no toolchain,
        # nothing to be stale against. Say what the DLL is and say WHY the comparison
        # did not run -- a gate that quietly no-ops in one deployment is how "green"
        # stops meaning anything; a skipped gate is not a passed gate.
        $deployedStamp = Get-ScDllBuildStamp -Path $dll
        $expectedStamp = $deployedStamp
        if ($deployedStamp) {
            Write-Host "run-with-plugin: plugin build $($deployedStamp.BuildId) src=$($deployedStamp.SrcDigest) (read from the DLL itself)"
        } else {
            Write-Warning "run-with-plugin: $dll carries NO build stamp -- it cannot say what source it came from (pre-task-056 build, or not built by build.ps1)."
        }
        Write-Host "run-with-plugin: no src/ beside this script (deployed runtime copy) -- the staleness comparison did NOT run here; there is nothing on this machine to compare against."
    }

    if ($Windowed) {
        if ($WindowedHelperDll) {
            if (-not (Test-Path -LiteralPath $WindowedHelperDll)) { throw "run-with-plugin: $WindowedHelperDll not found; run fetch-cnc-ddraw.ps1 first." }
            Copy-Item -LiteralPath $WindowedHelperDll -Destination $ddraw -Force
            $iniSrc = if ($WindowedHelperIni) { $WindowedHelperIni } else { Join-Path $scriptDir 'cnc-ddraw.ini' }
            if (-not (Test-Path -LiteralPath $iniSrc)) { throw "run-with-plugin: $iniSrc not found (-WindowedHelperIni)." }
            Copy-Item -LiteralPath $iniSrc -Destination (Join-Path $GameDir 'ddraw.ini') -Force
            Write-Host "run-with-plugin: windowed shim installed ($ddraw <- $WindowedHelperDll, ddraw.ini <- $iniSrc)"
        }
        else {
            $wmode = Join-Path $GameDir 'WMode.dll'
            if (-not (Test-Path -LiteralPath $wmode)) { throw "run-with-plugin: $wmode not found; cannot enable windowed mode." }
            Copy-Item -LiteralPath $wmode -Destination $ddraw -Force
            Write-Host "run-with-plugin: windowed shim installed ($ddraw <- WMode.dll)"
        }
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
    # A frame dump is raw game output and stays outside the repo -- the same guard
    # Save-ScWindowImage enforces for PNGs, applied to the raw container before the path
    # crosses into the plugin.
    if ($FrameDump) {
        $fdFull = [IO.Path]::GetFullPath($FrameDump)
        if ($fdFull.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase) -and
            $fdFull -notmatch '\\work\\scratch\\') {
            throw "run-with-plugin: refusing -FrameDump '$FrameDump' inside the repo -- frame dumps go under C:\sc-work\ or work/scratch/ (AGENTS.md hard rule 1)."
        }
        $env:SCPLUGIN_FRAMEDUMP = $fdFull
    } else { $env:SCPLUGIN_FRAMEDUMP = '' }
    $env:SCPLUGIN_WIDESCREEN     = $Widescreen
    $env:SCPLUGIN_WS_STAGE       = $WidescreenStage
    if ($Geometry) { $env:SCPLUGIN_WS_GEOMETRY = $Geometry }
    $env:SCPLUGIN_MENU_CENTRE    = $MenuCentre
    $env:SCPLUGIN_CONSOLE_TRACE  = $ConsoleTrace
    # 'auto' must reach the DLL as UNSET. Remove-Item, not `$env:X = ''`: measured on
    # pwsh 7.6, the empty assignment leaves the variable present-but-empty in a child's
    # environment block; the DLL happens to treat length 0 as unset, but the launcher
    # should not lean on that.
    if ($StormPresent -eq 'auto') { Remove-Item Env:SCPLUGIN_STORM_PRESENT -ErrorAction SilentlyContinue }
    else { $env:SCPLUGIN_STORM_PRESENT = $StormPresent }
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
    # the launch lock is released, not inside scinject.exe with the lock held for the
    # whole play session.
    $injArgs = @($exe, $dll, '--wait-ms', "$SettleMs", '--no-wait-exit')

    # --- which desktop the game is born on ---------------------------------------
    # Explicit -Desktop wins. Otherwise: if THIS process is not on the desktop the monitor
    # is showing, it was started by run-offscreen.ps1 onto an invisible one, and the game
    # belongs there too. Named rather than left to CreateProcess inheritance: measured,
    # the inheritance chain does not reliably hold through PowerShell's own process-launch
    # path (the game came up on no discoverable desktop at all) -- that is what
    # scinject.exe --desktop is for. Naming it costs nothing and removes the question.
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

    # --early puts our DllMain in front of the game's entry point, which is the only
    # place the geometry patches are correct (see -Widescreen above). Attached to THIS
    # switch alone so no other run's injection point changes.
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
    # WHOSE WINDOW THIS IS ABOUT TO BE TAKEN FROM. Recorded here, the last moment
    # before CreateProcess, because the game activates its window the instant it
    # creates one -- roughly four seconds before its own log opens, so there is no
    # in-game signal to record against. Skipped if a StarCraft window already holds
    # the foreground: that is another worker's run, and raising it back would be
    # worse than doing nothing.
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

    # Where THIS run's log output starts. The plugin opens its log with
    # FILE_APPEND_DATA (sc_log.cpp), so every run appends to whatever is already
    # there -- and the banner check below must not be able to pass on the banner
    # of a PREVIOUS run. That is not hypothetical: a plugin that fails to load
    # leaves the log untouched, and in this worktree the previous run's banner
    # carries the identity this run is looking for.
    $logStartOffset = 0L
    if (Test-Path -LiteralPath $LogPath) { $logStartOffset = (Get-Item -LiteralPath $LogPath).Length }

    $injOut = [System.Collections.Generic.List[string]]::new()
    & $inj @injArgs 2>&1 | ForEach-Object { Write-Host $_; $injOut.Add("$_") }
    $rc = $LASTEXITCODE
    Write-Host "run-with-plugin: scinject exit=$rc"
    if ($rc -ne 0) { throw "run-with-plugin: injection failed (exit $rc)" }

    $gamePid = 0
    foreach ($line in $injOut) {
        if ($line -match 'scinject:\s*PID=(\d+)\b') { $gamePid = [int]$Matches[1] }
    }

    # --- hand the foreground back, at the FIRST moment this script can ----------------
    # scinject's return is the first instant this script runs after the window exists
    # (it has already returned from WaitForInputIdle, which is what "once the game
    # window exists" means in practice). Restoring here rather than behind the mute and
    # the health-check sleep cuts the measured foreground hold from ~6.8 s to ~4.2 s;
    # the remaining ~4.1 s is scinject's own settle, during which nothing here executes.
    # The finally below repeats this as the safety net, for the case where the game
    # activates itself again while the health check runs.
    if ($preLaunchFg -ne [IntPtr]::Zero) {
        if (Restore-ScForeground -Hwnd $preLaunchFg -Tries 2) {
            Write-Host "run-with-plugin: foreground handed back -- $(Get-ScForegroundLabel -Hwnd $preLaunchFg)"
        }
    }

    # --- sound ------------------------------------------------------------------
    # Muted by default: every unattended suite launches through this script, so this is
    # the one place that covers them all. Process-scoped WASAPI session mute
    # (tools/plugin/sc-audio-mute.ps1), never the game's HKCU volume keys: live user
    # state that depends on a restore step running (AGENTS.md § Project hard rules, 5).
    # -Sound CLEARS the mute rather than skipping it -- cheap insurance against a mute
    # persistence path the registry search in sc-audio-mute.ps1 did not find. Wrapped,
    # and calling the interop directly rather than Set-ScProcessMuted's poll loop: -Sound
    # runs on EVERY user launch, where a COM hiccup must not report "failed to launch"
    # over a game that is running fine, and insurance is not worth up to 5 s of polling.
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
    # screen -- invisible to exit codes. Check from outside the process, regardless of
    # -WaitForExit: scinject.exe returns as soon as injection succeeds and waits for nothing.
    Start-Sleep -Seconds 2
    if ($gamePid -gt 0) {
        & (Join-Path $scriptDir 'check-game-windows.ps1') -ProcessId $gamePid
    }
    else {
        Write-Warning 'run-with-plugin: could not parse the pid from scinject output; falling back to resolving the game by process name.'
        & (Join-Path $scriptDir 'check-game-windows.ps1')
    }
    # Any non-zero is unhealthy, not just exit 1 (error dialog). check-game-windows.ps1
    # exits 3 when the pid is not running at all -- reachable because scinject returns as
    # soon as injection succeeds and the game has the ~2 s settle above to die on its own
    # (partially-mirrored deploy tree, a locked MPQ, a second-instance self-exit). Do not
    # test -eq 1: exit 3 then falls through, the deployed launcher's hidden pwsh exits 0,
    # and the user gets no window and no error -- the same silent failure -NoLaunchLock
    # exists to prevent, from a different cause.
    if ($LASTEXITCODE -ne 0) {
        throw "run-with-plugin: the game is NOT healthy after launch (check-game-windows.ps1 exit=$LASTEXITCODE -- 1=error dialog open, 3=process not running/died immediately)."
    }

    # --- did the DLL we vetted actually LOAD? ---------------------------------------
    # The gate above checked a FILE. scinject was then handed a PATH, and a path is not
    # a promise: the injection can fail, the plugin can decline to initialise, or the
    # game can be a leftover process from another launch. This reads the identity out
    # of the ATTACH banner the running plugin wrote -- the only evidence that says what
    # is inside the process -- and requires it to be the build this script vetted.
    if (-not $NoPlugin -and $expectedStamp) {
        $wantLine = "$($expectedStamp.BuildId) SRC=$($expectedStamp.SrcDigest)"
        $seen = $null
        $deadline = (Get-Date).AddSeconds(10)
        do {
            if (Test-Path -LiteralPath $LogPath) {
                # Opened share-read/write: the game holds this file open for
                # append the whole run, so an exclusive open would fail here.
                $fs = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                try {
                    if ($fs.Length -gt $logStartOffset) {
                        $fs.Position = $logStartOffset
                        $sr = [IO.StreamReader]::new($fs)
                        try { $tail = $sr.ReadToEnd() } finally { $sr.Dispose() }
                        # Anchored on the log's own "[timestamp] " prefix so only a real
                        # banner line can match -- not the word "build" inside some other
                        # message. Last match wins: one launch writes one banner, but a
                        # log this run appended to may hold more than one.
                        foreach ($m in [regex]::Matches($tail, '(?m)^\[[^\]]+\]\s+build\s+:\s+(\S+ SRC=\S+)')) { $seen = $m.Groups[1].Value }
                    }
                } finally { $fs.Dispose() }
            }
            if (-not $seen) { Start-Sleep -Milliseconds 500 }
        } while (-not $seen -and (Get-Date) -lt $deadline)

        if (-not $seen) {
            throw ("run-with-plugin: the plugin logged NO ATTACH banner into $LogPath after the launch. " +
                   'The game is up but our DLL is not reporting itself -- it did not load, or it is writing somewhere else. ' +
                   'Nothing this run observes can be attributed to the plugin.')
        }
        if ($seen -ne $wantLine) {
            throw ("run-with-plugin: WRONG PLUGIN IS RUNNING. The DLL on disk is '$wantLine'; " +
                   "the plugin inside the game reports '$seen'. Every assertion this run makes would be about a different build.")
        }
        Write-Host "run-with-plugin: ATTACH banner confirms the running plugin is $seen"
    }
    elseif (-not $NoPlugin) {
        Write-Warning 'run-with-plugin: the DLL carries no build stamp, so the ATTACH banner cannot be checked against it -- what is running in the game is not established.'
    }
}
finally {
    # --- hand the foreground back -------------------------------------------------
    # In the finally, not after the health check, so a launch that throws with the game
    # already on screen (a modal DirectDraw error box is exactly that case) still gives
    # the user their window back before the failure propagates. By here
    # check-game-windows.ps1 has enumerated the game's top-level windows, so the window
    # whose creation stole the foreground exists. NEVER FATAL, on the same reasoning as
    # Send-ScDropdownPick's hand-back: the launch has already happened, and a shell that
    # will not give the foreground up is a cosmetic loss, not a failed launch.
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
    # Deliberately OUTSIDE the lock: this can block for a whole play session, and the
    # lock only covers the launch sequence -- a lock held that long would need a watcher
    # tied to the game's lifetime rather than this script's.
    Write-Host "run-with-plugin: -WaitForExit — waiting for pid $gamePid to exit (Ctrl-C to stop waiting)"
    Wait-Process -Id $gamePid -ErrorAction SilentlyContinue
    Write-Host "run-with-plugin: pid $gamePid exited"
}
