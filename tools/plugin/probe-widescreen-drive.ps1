#Requires -Version 7
<#
.SYNOPSIS
Task 070. Drives a REAL game for minutes on the assembled widescreen build --
stage 2 + fog (renderer_patch_sites.py, 068's table) presented through cnc-ddraw
(065's FOLLOW vector) -- and measures the things a frozen frame cannot:
scrolling across sub-tile origins, clicks past x=640, selection, commands,
minimap navigation, HUD placement, and stability over time.

.DESCRIPTION
Every capture this project took before this suite was a frozen frame, and the
presentation joint (cnc-ddraw) had only ever been measured at the MENU (065).
This suite is the first time the assembled combination -- engine patched to
800x480 with correct fog, cnc-ddraw presenting all 800 columns -- is driven
in game.

What it asserts, and with which oracle (never pixels -- AGENTS.md "Read a
dialog's CONTENT from memory"):

  - WIDESCREEN ACTIVE, 0 refused, whole stage (plugin's own install verdict;
    a refused table runs stock and everything below passes vacuously).
  - The in-game client area is 800x480 THROUGH cnc-ddraw (GetClientRect).
  - Frame dumps read 800x480, settled, at every camera stop (FRAMEDUMP header).
  - CLICK-SELECT: a posted click at screen x>640 selects exactly the unit whose
    engine position (WORLD scan) predicted that screen point -- the engine's own
    clientSelectionGroup (SELSNAP) is the oracle, cross-referenced by CUnit
    pointer. A control click at x<640 proves the instrument first.
  - DRAG-SELECT across the 640 seam: the box's selection contains the aimed
    units on BOTH sides of x=640.
  - COMMAND at x>640: a right-click move order moves the selected units' own
    engine positions toward the point (position delta, not bookkeeping).
  - SCROLL: held arrow keys stop the camera at several sub-tile origins
    (x%32 != 0); at every stop the fog seam tooth holds (no zero-column run
    intersecting x=660..700 unless the map-anchored exploration edge sits
    there, which is computed and excluded per capture).
  - MINIMAP: a minimap click moves the camera to the commanded origin (SCREEN
    scan), with the stock 640-era minimap geometry (Get-ScMinimapPoint).
  - HUD PLACEMENT: the engine's own dialog list (DIALOGS) is logged in game at
    800 wide; the console dialog's rect IS the verdict on where the HUD sits.
  - STABILITY: the session runs at least -MinSessionMinutes of in-game driving;
    the process stays alive, WORLD scans stay complete, and the final capture
    still reads 800x480 with the seam tooth holding.

The right MAP EDGE is visited and REPORTED, not asserted: the scroll clamp is
stock (stage 3 unbuilt, renderer-viewport.md 15.5), so the camera stops 20
tiles short and the right band there shows whatever the terrain cache holds --
a KNOWN, documented imperfection this suite records for the user card.

Window PNGs are saved beside every dump for the human (gitignored; paths
travel, images never -- hard rule 1). No window-vouched consistency check runs
here: the cnc-ddraw window's caption geometry differs from WMode's (065 14.3)
and probe-framebuffer-capture already owns that instrument under WMode. The
dump-internal oracles (geometry, seam, band, cross-capture diff) carry this
suite.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-widescreen-drive.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\070-frames',
    # The pinned cnc-ddraw (fetch-cnc-ddraw.ps1, sha256-verified at fetch).
    [string]$WindowedHelperDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    # Which helper PRESENTS. The engine build is identical either way (stage 2 +
    # fog, in-process); what differs is the window. 'cnc' is the user's wide
    # presentation (window 800, and the harness's posted playfield mouse does
    # NOT register there -- measured, attempts 8-10, see the PR); 'wmode' crops
    # the window to 640 but posts reach every engine path, so it is the arm
    # that PROVES the engine's input mapping past x=640 (hit-testing is engine
    # arithmetic on its own stored coordinates; the presenter never sees it).
    [ValidateSet('cnc', 'wmode')][string]$Presenter = 'cnc',
    # The stability floor: in-game driving keeps going until this much wall
    # clock has passed since the game loaded. The click/scroll/command tests
    # above run inside it, so a passing run IS a driven session of this length.
    [int]$MinSessionMinutes = 3,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

if (-not $FixtureDir) {
    $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t070-wsdrive' -Suite 'wsdrive'
}
$mapName = 'wsdrive.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$py = 'python'
$tool = Join-Path $scriptDir 'frame-capture.py'
$log = Join-Path $LogDir '070-wsdrive.log'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null

$script:failures = 0
$script:step = 0
$script:findings = @()
$script:completedPhases = @()
$script:stripSamples = @()
$launchLock = $null
$fixtures = $null
$gamePid = 0
$completedDrive = $false

# The map the fixture generator writes: 128x96 tiles, start location centred by
# the engine at origin (544,416); the marine grid explores to map x ~1332
# (measured, renderer-viewport.md 16.4). Used to compute the exploration edge
# per origin so a map-anchored shroud run is never mistaken for the seam.
$MAP_TILES_W = 128
$MAP_TILES_H = 96
$EXPLORED_EDGE_X = 1332

function Assert-True {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    $script:step++
    if ($Ok) { Write-Host "  [$script:step] OK   $What $Detail" }
    else { Write-Host "  [$script:step] FAIL $What $Detail"; $script:failures++ }
}

function Report-Finding {
    param([string]$What)
    $script:findings += $What
    Write-Host "  ---- FINDING: $What"
}

# Playfield-input steps assert only where posted input REACHES the playfield.
# Under cnc-ddraw on the invisible desktop it does not (measured 0/8 across
# three mechanisms -- a harness limit, AGENTS.md "Glue-screen input is
# ACTIVATION-GATED"), so there the same steps run and REPORT; under WMode
# posted coordinates reach every engine path and the steps assert. The
# readings themselves are identical either way.
function Assert-Input {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok -or $Presenter -eq 'wmode') { Assert-True $What $Ok $Detail }
    else { Report-Finding "input step, NOT asserted under cnc-ddraw (posted playfield input is a measured harness limit there): $What $Detail" }
}

function Invoke-FrameTool {
    param([Parameter(Mandatory)][string[]]$ToolArgs)
    $out = & $py $tool @ToolArgs 2>&1
    $m = @{}
    foreach ($line in $out) {
        Write-Host "         $line"
        if ("$line" -match '^([a-z_]+)=(.*)$') { $m[$Matches[1]] = $Matches[2] }
    }
    $m
}

# One captured point: window PNG, marker-driven dump + SCREEN origin, window
# PNG again. Same shape as probe-framebuffer-capture's, minus the window-vouch.
function Get-CapturePoint {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Tag
    )
    $before = Join-Path $FrameDir "$Tag-before.png"
    $after = Join-Path $FrameDir "$Tag-after.png"
    $from = Get-ScLogLineCount -LogPath $log
    Save-ScWindowImage -Hwnd $Hwnd -Path $before | Out-Null
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    $lines = Wait-ScLogMatch -LogPath $log -Pattern "FRAMEDUMP \[$Tag\] " -TimeoutSec 30 -FromLine $from
    Save-ScWindowImage -Hwnd $Hwnd -Path $after | Out-Null
    $r = @{ Tag = $Tag; Before = $before; After = $after
            Dump = $null; W = 0; H = 0; Reads = 0; Stable = 0; Refused = $null; Origin = $null
            OriginX = -1; OriginY = -1 }
    foreach ($l in $lines) {
        if ($l -match 'FRAMEDUMP \[[^\]]+\] w=(\d+) h=(\d+) bytes=\d+ reads=(\d+) stable=(\d) path=(.+)$') {
            $r.W = [int]$Matches[1]; $r.H = [int]$Matches[2]
            $r.Reads = [int]$Matches[3]; $r.Stable = [int]$Matches[4]
            $r.Dump = $Matches[5].Trim()
        }
        elseif ($l -match 'FRAMEDUMP \[[^\]]+\] refused: (.+)$') { $r.Refused = $Matches[1] }
    }
    $originHit = @(Get-Content -LiteralPath $log | Select-Object -Skip $from |
                   Where-Object { $_ -match "SCREEN \[$Tag\] origin=\((\d+),(\d+)\)" })
    if ($originHit.Count -and $originHit[0] -match 'origin=\((\d+),(\d+)\)') {
        $r.Origin = "$($Matches[1]),$($Matches[2])"
        $r.OriginX = [int]$Matches[1]; $r.OriginY = [int]$Matches[2]
    }
    Write-Host ("       $Tag : dump=$(if ($r.Dump) { Split-Path $r.Dump -Leaf } else { 'NONE' }) " +
                "w=$($r.W) h=$($r.H) stable=$($r.Stable) origin=$($r.Origin)")
    $r
}

# The engine's twelve, tagged: set a marker, wait for the SELSNAP line carrying
# that label, return the clientSelectionGroup pointers (upper-case hex, no 0x).
function Get-ScSelectionTagged {
    param([Parameter(Mandatory)][string]$Tag, [int]$TimeoutSec = 10)
    $from = Get-ScLogLineCount -LogPath $log
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    [void](Wait-ScLogMatch -LogPath $log -Pattern ("SELSNAP \[" + [regex]::Escape($Tag) + "\] ") -TimeoutSec $TimeoutSec -FromLine $from)
    $line = @(Get-Content -LiteralPath $log | Select-Object -Skip $from |
              Where-Object { $_ -match 'SELSNAP clientSelectionGroup' }) | Select-Object -First 1
    if (-not $line) { return @() }
    [regex]::Matches($line, '=0x([0-9A-Fa-f]+)') |
        ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } |
        Where-Object { $_ -ne '00000000' }
}

# Assert the dump geometry + the fog seam tooth for one captured point. The
# tooth excludes the map-anchored exploration edge: at origin O the fixture's
# explored boundary sits at screen x = EXPLORED_EDGE_X - O, and a zero run
# there is legitimate shroud, not the 068 seam class (renderer-viewport.md
# 16.4 measured that edge at three origins and scrollmid).
function Assert-WideCapture {
    param([Parameter(Mandatory)]$Pt, [switch]$SkipSeam)
    Assert-True "[$($Pt.Tag)] a dump was written" ($null -ne $Pt.Dump) `
        ($Pt.Refused ? "(refused: $($Pt.Refused))" : '')
    if ($null -eq $Pt.Dump) { return }
    Assert-True "[$($Pt.Tag)] the dump is the full 800x480" `
        ($Pt.W -eq 800 -and $Pt.H -eq 480) "(got $($Pt.W)x$($Pt.H))"
    Assert-True "[$($Pt.Tag)] the copy settled" ($Pt.Stable -eq 1) "(reads=$($Pt.Reads))"
    if ($SkipSeam -or $Pt.OriginX -lt 0) { return }
    $zr = Invoke-FrameTool -ToolArgs @('zeroruns', '--dump', $Pt.Dump,
            '--x0', '0', '--x1', '800', '--y0', '20', '--y1', '320')
    $edge = $EXPLORED_EDGE_X - $Pt.OriginX
    if ($edge -ge 560 -and $edge -le 800) {
        Report-Finding "[$($Pt.Tag)] exploration edge at screen x=$edge overlaps the seam test band; seam tooth reported, not asserted (runs: $($zr['zeroruns']))"
        return
    }
    $seam = @()
    foreach ($run in ("$($zr['zeroruns'])" -split ';')) {
        if ($run -match '^(\d+)-(\d+)$' -and [int]$Matches[1] -le 700 -and [int]$Matches[2] -ge 660) { $seam += $run }
    }
    Assert-True "[$($Pt.Tag)] no zero-column run intersects the old seam band x=660..700" `
        ($seam.Count -eq 0) "(origin=$($Pt.Origin), intersecting: $($seam -join ','); all runs: $($zr['zeroruns']))"
}

try {
    Write-Host 'probe-wsdrive: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '070-wsdrive'

    if (-not (Test-Path -LiteralPath $WindowedHelperDll)) {
        throw "probe-wsdrive: $WindowedHelperDll not found; run fetch-cnc-ddraw.ps1 first."
    }

    Write-Host 'probe-wsdrive: generating the fixture (36-marine grid, the 064/068 shape)'
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 36 -GridSpacing 64 -UnitType 'marine' `
            -Player 0 -Race 'terran' -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }
    if (-not (Test-Path -LiteralPath $mapPath)) {
        throw "probe-wsdrive: the fixture was never generated ($mapPath does not exist) -- read the generator output above; nothing was launched."
    }

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    # The launch: the USER's feature set (deploy.ps1's launcher flags) plus the
    # assembled widescreen -- stage 2 + fog in-process, cnc-ddraw presenting.
    # This exact flag combination is what the wide launcher ships.
    # Task 070: the engine's glue-screen input is ACTIVATION-GATED, and on the
    # invisible desktop a cnc-ddraw window is never told it is active -- a
    # posted click at a fully interactive menu registers 0/4 runs without this,
    # and in 0.4s with it (probe-cnc-clickdelay, arm B). The flag makes every
    # drive-game input primitive post the activation triple first; real
    # foreground/focus are untouched. Cleared in finally. WMode needs none of
    # this (its runs never gate).
    if ($Presenter -eq 'cnc') { $env:SCDRIVE_POST_ACTIVATE = '1' }

    Write-Host "probe-wsdrive: launching (fanout features + stage 2, presenter=$Presenter)"
    $launchArgs = @{
        Mode = 'fanout'; Circles = '1'; HudRow = '1'; ProdQueue = '1'; ProdFan = '1'
        UpgradeQueue = '1'; QueueIndicator = '1'; WorldScan = '1'; ScreenScan = '1'
        FrameDump = $FrameDir; NoLaunchLock = $true
        Widescreen = '1'; WidescreenStage = '2'
        GameDir = $GameDir; LogPath = $log
    }
    if ($Presenter -eq 'cnc') { $launchArgs.Windowed = $true; $launchArgs.WindowedHelperDll = $WindowedHelperDll }
    else { $launchArgs.InjectWindowedHelper = 'WMode' }
    & (Join-Path $scriptDir 'run-with-plugin.ps1') @launchArgs 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe-wsdrive: could not parse the game pid.' }
    $h = Get-ScGameWindow -ProcessId $gamePid
    Start-Sleep -Seconds 3

    # ---- install verdicts, before anything is driven ----------------------
    $wsLines = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'WIDESCREEN (ACTIVE|INCOMPLETE|REFUSED)' })
    Assert-True 'the widescreen table is ACTIVE with 0 refused' `
        ($wsLines.Count -gt 0 -and $wsLines[0] -match 'WIDESCREEN ACTIVE' -and $wsLines[0] -match ', 0 refused') `
        "($($wsLines | Select-Object -First 1))"
    $fLines = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'WIDESCREEN filter:' })
    Assert-True 'the whole stage applied (no leftover %SCPLUGIN_WS_ONLY%)' `
        ($fLines.Count -gt 0 -and $fLines[0] -match 'unset, whole stage applied') "($($fLines | Select-Object -First 1))"

    $client = Get-ScClientSize -Hwnd $h
    if ($Presenter -eq 'cnc') {
        Assert-True 'cnc-ddraw presents an 800x480 client area (FOLLOW, in the launched window)' `
            ($client.Width -eq 800 -and $client.Height -eq 480) "(got $($client.Width)x$($client.Height))"
    }
    else {
        Assert-True 'WMode presents its 640x480 window (the crop arm; the engine is still 800 wide underneath)' `
            ($client.Width -eq 640 -and $client.Height -eq 480) "(got $($client.Width)x$($client.Height))"
    }

    # A marker round-trip proving the plugin's observer is ALIVE. The cnc-ddraw
    # attempts before this gate existed produced a DETACH mid-menu and every
    # log-based oracle after it silently read a frozen log; this turns "the log
    # stopped" into a named failure at the step where it happened.
    function Assert-PluginAlive {
        param([Parameter(Mandatory)][string]$Stage)
        $from = Get-ScLogLineCount -LogPath $log
        Set-ScMarker -MarkerPath $markerPath -Label "alive-$Stage"
        try { [void](Wait-ScLogMatch -LogPath $log -Pattern ("MARK: alive-" + [regex]::Escape($Stage)) -TimeoutSec 8 -FromLine $from) }
        catch {
            $det = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'DETACH pid=' })
            throw ("probe-wsdrive: the plugin stopped answering markers at stage '$Stage'" +
                   $(if ($det.Count) { " -- the log carries '$($det[-1])' with the game still running: the DLL was unloaded out of the live process" } else { ' (no DETACH line; observer wedged?)' }))
        }
    }

    # ---- menu walk to a loaded game -- every step gated on the ENGINE's own
    # dialog list, never on sleep guesswork. The first cnc-ddraw attempt clicked
    # into a menu that was not up yet and every later click landed on the wrong
    # screen; the fingerprints then "confirmed" a browser walk that never
    # happened (this run's own lesson).
    # A menu click that must produce a dialog, retried: the activation gate can
    # swallow the first click even nudged (measured -- the probe's arm B was
    # itself a retry after a dead click), so "click, wait for the ENGINE to show
    # the dialog, click again if it did not" is the resilient form.
    function Click-UntilDialog {
        param([int]$X, [int]$Y, [string]$Name, [int]$Tries = 3, [int]$WaitSec = 10)
        for ($i = 1; $i -le $Tries; $i++) {
            Send-ScClick -Hwnd $h -X $X -Y $Y
            $d = Wait-ScDialog -LogPath $log -Name $Name -TimeoutSec $WaitSec
            if ($d) { return $d }
            Write-Host "       walk: '$Name' not up after click $i/$Tries at ($X,$Y); retrying with a fresh nudge"
        }
        $null
    }

    Write-Host 'probe-wsdrive: walking to a loaded game (dialog-gated)'
    if (-not (Wait-ScDialog -LogPath $log -Name 'MainMenu' -TimeoutSec 30)) {
        throw 'probe-wsdrive: the main menu never appeared in the DIALOGS oracle.'
    }
    Assert-PluginAlive -Stage 'mainmenu'
    Start-Sleep -Seconds 3
    if (-not (Click-UntilDialog -X 215 -Y 119 -Name 'Delete')) {              # Single Player
        throw 'probe-wsdrive: the Original/Expansion chooser never appeared (3 nudged clicks).'
    }
    Send-ScClick -Hwnd $h -X 373 -Y 300                       # Expansion
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $h -X 75  -Y 111                       # login-profile row
    # (516,392) OK leaves the Login screen for the campaign RaceSelection
    # screen; Create (the map browser) only appears after Play Custom
    # (327,415) THERE. Attempt 7 waited for Create one screen early and
    # concluded "walk lost" with a perfectly healthy walk.
    if (-not (Click-UntilDialog -X 516 -Y 392 -Name 'RaceSelection' -WaitSec 15)) {
        Assert-PluginAlive -Stage 'post-login'     # names WHICH failed: plugin or walk
        throw 'probe-wsdrive: the campaign (RaceSelection) screen never appeared, with the plugin alive -- the walk is lost.'
    }
    if (-not (Click-UntilDialog -X 327 -Y 415 -Name 'Create' -WaitSec 15)) {
        Assert-PluginAlive -Stage 'post-race'
        throw 'probe-wsdrive: the map-browser (Create) screen never appeared, with the plugin alive -- the walk is lost.'
    }
    Assert-PluginAlive -Stage 'create-screen'
    Start-Sleep -Seconds 2
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $mapPath | Out-Null
    Assert-PluginAlive -Stage 'map-selected'
    Set-ScGameType -Hwnd $h -LogPath $log -Index 2
    Send-ScClick -Hwnd $h -X 516 -Y 393
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $h -X 544 -Y 387
    Start-Sleep -Seconds 10
    Dismiss-ScTipsDialog -Hwnd $h -LogPath $log | Out-Null
    Start-Sleep -Seconds 3
    Assert-PluginAlive -Stage 'in-game'

    # In game, the activation nudge comes OFF for playfield input: attempt 8 ran
    # the whole session with it on and every playfield click-select returned an
    # EMPTY selection -- including the x<640 control -- while the minimap
    # (console dialog) and the scroll keys worked. The activation handler
    # re-syncs the engine's cursor (the "Foreground" section's measured
    # raise-destroys-the-posted-position effect), which is a fine price before
    # a GLUE click and fatal immediately before a playfield button-down. The
    # glue gate does not exist in-game for WMode and the hypothesis under test
    # here is that it does not exist for cnc-ddraw either; minimap clicks keep
    # a nudged RETRY (Click-MinimapVerified) in case the console dialog path
    # still wants it.
    $env:SCDRIVE_POST_ACTIVATE = '0'

    # A minimap click whose effect is VERIFIED against the engine's own origin,
    # with one nudged retry: attempt 8 saw one minimap click take and another
    # (same run, same shape) not take.
    function Click-MinimapVerified {
        param([Parameter(Mandatory)]$Point, [Parameter(Mandatory)][int]$ExpectedOriginX, [Parameter(Mandatory)][string]$Tag)
        Send-ScClick -Hwnd $h -X $Point.X -Y $Point.Y
        Start-Sleep -Seconds 2
        $w = Get-ScWorldState -LogPath $log -Tag "$Tag-a" -MarkerPath $markerPath
        if ($null -ne $w.Screen -and [Math]::Abs($w.Screen.Left - $ExpectedOriginX) -le 32) { return $w }
        Write-Host "       [$Tag] minimap click did not take (origin $($w.Screen.Left) vs expected ~$ExpectedOriginX); retrying with an activation nudge"
        $env:SCDRIVE_POST_ACTIVATE = '1'
        try { Send-ScClick -Hwnd $h -X $Point.X -Y $Point.Y }
        finally { $env:SCDRIVE_POST_ACTIVATE = '0' }
        Start-Sleep -Seconds 2
        Get-ScWorldState -LogPath $log -Tag "$Tag-b" -MarkerPath $markerPath
    }

    $sessionStart = Get-Date

    # ---- capture 1: the loaded game at the start origin -------------------
    $ptIngame = Get-CapturePoint -Hwnd $h -Tag 'drive-ingame'
    Assert-WideCapture -Pt $ptIngame
    if ($ptIngame.Dump) {
        $b = Invoke-FrameTool -ToolArgs @('band', '--dump', $ptIngame.Dump,
                '--x0', '640', '--x1', '800', '--y0', '20', '--y1', '320')
        Assert-True 'the right band holds MAP at the start origin (explored; nonzero >= 0.30)' `
            ([double]($b['band_nonzero_frac'] ?? 0) -ge 0.30) "(got $($b['band_nonzero_frac']))"
        # The console-right strip: 160x80 at the bottom right that no console
        # art exists for (15.5 item 3). Reported so the card can say what the
        # user will actually see there.
        $strip = Invoke-FrameTool -ToolArgs @('band', '--dump', $ptIngame.Dump,
                '--x0', '640', '--x1', '800', '--y0', '400', '--y1', '480')
        Report-Finding "console-right strip x=640..799 y=400..479: nonzero_frac=$($strip['band_nonzero_frac']) distinct=$($strip['band_distinct']) (blank-by-design region; this is what fills it)"
        $script:stripSamples += "ingame: nonzero=$($strip['band_nonzero_frac']) distinct=$($strip['band_distinct'])"
    }

    # ---- the HUD/minimap placement verdict, from the engine's dialog list -
    Write-Host 'probe-wsdrive: reading the in-game dialog list (HUD placement)'
    [void](Get-ScWorldState -LogPath $log -Tag 'dlgpump' -MarkerPath $markerPath)
    $dialogs = @(Get-ScDialogs -LogPath $log)
    Assert-True 'the engine reports in-game dialogs (DIALOGS line present)' ($dialogs.Count -gt 0) `
        "(n=$($dialogs.Count))"
    foreach ($d in $dialogs) {
        Write-Host ("       dlg '$($d.Name)' rect=($($d.Left),$($d.Top))-($($d.Right),$($d.Bottom)) ctrls=$($d.Controls.Count)")
    }
    # The console is the dialog whose rect contains the minimap box (7,348).
    $console = $dialogs | Where-Object { $_.Left -le 7 -and $_.Top -le 348 -and $_.Right -ge 135 -and $_.Bottom -ge 476 } | Select-Object -First 1
    if ($console) {
        Report-Finding "HUD VERDICT: console dialog '$($console.Name)' sits at ($($console.Left),$($console.Top))-($($console.Right),$($console.Bottom)) in the 800-wide client -- $(if ($console.Left -eq 0 -and $console.Right -le 640) { 'LEFT-ANCHORED at its stock 640 geometry; the strip x=640..799 below y=400 has no console art' } elseif ($console.Right -gt 640) { 'WIDER THAN 640 -- not the stock anchor; read the rect' } else { 'not at the stock origin -- read the rect' })"
    }
    else {
        Report-Finding "HUD VERDICT: no dialog rect contains the stock minimap box (7,348) -- dialog rects logged above; the minimap click test below decides whether the minimap still works"
    }

    # ---- position the camera so the marine block straddles x=640 ----------
    $w0 = Get-ScWorldState -LogPath $log -Tag 'aim0' -MarkerPath $markerPath
    Assert-True 'the WORLD scan is complete and sees the 36 marines' `
        ($null -ne $w0.Screen -and @($w0.Units | Where-Object { $_.Owner -eq 0 }).Count -ge 36) `
        "(units=$(@($w0.Units).Count), screen=$($w0.Screen))"
    $marines = @($w0.Units | Where-Object { $_.Owner -eq 0 -and $_.Type -eq 0 })
    if (-not $marines.Count) { $marines = @($w0.Units | Where-Object { $_.Owner -eq 0 }) }
    $maxX = ($marines | Measure-Object -Property X -Maximum).Maximum
    $meanY = [int](($marines | Measure-Object -Property Y -Average).Average)
    # Aim the camera so the rightmost marine columns land near screen x ~736
    # and ~672 -- the 64px fixture grid then puts one column in each of the
    # first two >640 click bands. The minimap centres a click's tile:
    # origin = (tile - 10) * 32 horizontally.
    $targetOriginX = [Math]::Max(0, $maxX - 736)
    $tileX = [int][Math]::Round($targetOriginX / 32) + 10
    $tileY = [Math]::Min(($MAP_TILES_H - 7), [Math]::Max(6, [int]($meanY / 32)))
    $mm = Get-ScMinimapPoint -MapTilesW $MAP_TILES_W -MapTilesH $MAP_TILES_H -TileX $tileX -TileY $tileY
    $expectedOriginX = ($tileX - 10) * 32
    $w1 = Click-MinimapVerified -Point $mm -ExpectedOriginX $expectedOriginX -Tag 'aim1'
    Assert-True 'the minimap click moved the camera to the commanded origin (stock minimap geometry works at 800)' `
        ($null -ne $w1.Screen -and [Math]::Abs($w1.Screen.Left - $expectedOriginX) -le 32) `
        "(commanded x=$expectedOriginX, got $($w1.Screen.Left),$($w1.Screen.Top))"

    # ---- click-select: control at x<640, then the question at x>640 -------
    function Select-MarineAt {
        param([int]$MinSx, [int]$MaxSx, [string]$Tag)
        $w = Get-ScWorldState -LogPath $log -Tag "$Tag-scan" -MarkerPath $markerPath
        $cand = @($w.Units | Where-Object {
            $_.Owner -eq 0 -and
            ($_.X - $w.Screen.Left) -ge $MinSx -and ($_.X - $w.Screen.Left) -le $MaxSx -and
            ($_.Y - $w.Screen.Top) -ge 40 -and ($_.Y - $w.Screen.Top) -le 300
        })
        # Prefer a unit with no close neighbour, so the click cannot land on two.
        $pick = $null
        foreach ($u in $cand) {
            $near = @($w.Units | Where-Object { $_ -ne $u -and [Math]::Abs($_.X - $u.X) -lt 24 -and [Math]::Abs($_.Y - $u.Y) -lt 24 })
            if ($near.Count -eq 0) { $pick = $u; break }
        }
        if (-not $pick -and $cand.Count) { $pick = $cand[0] }
        if (-not $pick) { return $null }
        $sx = $pick.X - $w.Screen.Left; $sy = $pick.Y - $w.Screen.Top
        Write-Host "       [$Tag] aiming at unit 0x$($pick.Unit) map=($($pick.X),$($pick.Y)) screen=($sx,$sy)"
        Send-ScClick -Hwnd $h -X $sx -Y $sy
        Start-Sleep -Milliseconds 600
        $sel = @(Get-ScSelectionTagged -Tag "$Tag-sel")
        [pscustomobject]@{ Aimed = $pick.Unit.ToUpperInvariant(); ScreenX = $sx; ScreenY = $sy; Selected = $sel }
    }

    $ctl = Select-MarineAt -MinSx 60 -MaxSx 600 -Tag 'click-ctl'
    Assert-Input 'CONTROL: a click at x<640 selects exactly the aimed unit (instrument positive)' `
        ($null -ne $ctl -and $ctl.Selected.Count -eq 1 -and $ctl.Selected[0] -eq $ctl.Aimed) `
        "(aimed=$($ctl.Aimed) at x=$($ctl.ScreenX), selected=[$($ctl.Selected -join ',')])"

    $wideHits = 0
    $wideTried = 0
    foreach ($range in @(@(645, 700), @(700, 755), @(755, 795))) {
        $r = Select-MarineAt -MinSx $range[0] -MaxSx $range[1] -Tag "click-wide$($range[0])"
        if ($null -eq $r) {
            Report-Finding "no isolated marine offered a target at screen x $($range[0])..$($range[1]) from this origin; band skipped"
            continue
        }
        $wideTried++
        $ok = ($r.Selected.Count -eq 1 -and $r.Selected[0] -eq $r.Aimed)
        Assert-Input "a click at screen x=$($r.ScreenX) (>640) selects exactly the aimed unit" $ok `
            "(aimed=$($r.Aimed), selected=[$($r.Selected -join ',')])"
        if ($ok) { $wideHits++ }
    }
    Assert-Input 'clicks past x=640 were actually exercised (>= 2 bands reached)' ($wideTried -ge 2) "(tried=$wideTried, hit=$wideHits)"

    # ---- drag-select across the 640 seam ----------------------------------
    $w2 = Get-ScWorldState -LogPath $log -Tag 'box-scan' -MarkerPath $markerPath
    $inBox = @($w2.Units | Where-Object {
        $_.Owner -eq 0 -and
        ($_.X - $w2.Screen.Left) -ge 560 -and ($_.X - $w2.Screen.Left) -le 780 -and
        ($_.Y - $w2.Screen.Top) -ge 60 -and ($_.Y - $w2.Screen.Top) -le 280
    })
    $leftOfSeam = @($inBox | Where-Object { ($_.X - $w2.Screen.Left) -lt 640 })
    $rightOfSeam = @($inBox | Where-Object { ($_.X - $w2.Screen.Left) -ge 640 })
    Send-ScDrag -Hwnd $h -X1 555 -Y1 55 -X2 785 -Y2 285
    Start-Sleep -Milliseconds 600
    $boxSel = @(Get-ScSelectionTagged -Tag 'box-sel')
    $boxExpected = @($inBox | ForEach-Object { $_.Unit.ToUpperInvariant() })
    $missing = @($boxExpected | Where-Object { $boxSel -notcontains $_ })
    Assert-Input 'the drag box spans the seam and selects units on BOTH sides of x=640' `
        ($leftOfSeam.Count -ge 1 -and $rightOfSeam.Count -ge 1 -and $missing.Count -eq 0 -and $boxSel.Count -ge $boxExpected.Count) `
        "(expected n=$($boxExpected.Count) [left $($leftOfSeam.Count) / right $($rightOfSeam.Count)], selected n=$($boxSel.Count), missing=[$($missing -join ',')])"

    # ---- command at x>640: move order, engine positions are the oracle ----
    if ($boxSel.Count -gt 0) {
        $before = Get-ScWorldState -LogPath $log -Tag 'move-before' -MarkerPath $markerPath
        $selSet = $boxSel
        $selBefore = @($before.Units | Where-Object { $selSet -contains $_.Unit.ToUpperInvariant() })
        $meanXBefore = ($selBefore | Measure-Object -Property X -Average).Average
        # Right-click ground at screen (760, 150): a move order to a point past
        # the old edge. The engine's mouse->world is origin + screen.
        Send-ScClick -Hwnd $h -X 760 -Y 150 -Right
        Start-Sleep -Seconds 4
        $after = Get-ScWorldState -LogPath $log -Tag 'move-after' -MarkerPath $markerPath
        $selAfter = @($after.Units | Where-Object { $selSet -contains $_.Unit.ToUpperInvariant() })
        $meanXAfter = ($selAfter | Measure-Object -Property X -Average).Average
        $targetMapX = $before.Screen.Left + 760
        $movedRight = ($meanXAfter - $meanXBefore)
        Assert-Input 'a right-click at screen x=760 moved the selected units toward that map point (engine positions moved)' `
            ($selAfter.Count -ge 1 -and (($movedRight -gt 16) -or ([Math]::Abs($meanXAfter - $targetMapX) -lt [Math]::Abs($meanXBefore - $targetMapX) - 16))) `
            "(meanX $([int]$meanXBefore) -> $([int]$meanXAfter), target map x=$targetMapX)"
    }
    $script:completedPhases += 'input'

    # ---- scroll: several sub-tile origins, seam tooth at each -------------
    $phases = @{}
    $stops = @()
    foreach ($hold in @(60, 90, 120)) {
        Send-ScKey -Hwnd $h -VirtualKey 0x27 -HoldMs $hold -SettleMs 600   # VK_RIGHT
        $pt = Get-CapturePoint -Hwnd $h -Tag "drive-scroll-h$hold"
        Assert-WideCapture -Pt $pt
        if ($pt.OriginX -ge 0) { $phases[($pt.OriginX % 32)] = $true; $stops += $pt.Origin }
    }
    Send-ScKey -Hwnd $h -VirtualKey 0x28 -HoldMs 70 -SettleMs 600          # VK_DOWN: vertical too
    $ptv = Get-CapturePoint -Hwnd $h -Tag 'drive-scroll-v'
    Assert-WideCapture -Pt $ptv
    # The keyboard stepper lands on 16px multiples -- every held-arrow stop
    # measured at 800 sits at x%32 in {0,16} (068's scrollmid and this suite's
    # runs, 5 of 5), so ">= 2 distinct nonzero phases" is unsatisfiable and a
    # single sub-tile (x%32=16) stop is what exercises the fog alignment terms.
    Assert-True 'the held-key scrolls stopped at a sub-tile origin (x%32 != 0)' `
        (@($phases.Keys | Where-Object { $_ -ne 0 }).Count -ge 1) `
        "(phases=[$(($phases.Keys | Sort-Object) -join ',')] stops=[$($stops -join ' | ')])"
    $script:completedPhases += 'scroll'

    # ---- the right MAP EDGE: the stock clamp, reported for the card -------
    $mmEdge = Get-ScMinimapPoint -MapTilesW $MAP_TILES_W -MapTilesH $MAP_TILES_H -TileX ($MAP_TILES_W - 1) -TileY $tileY
    $stockClampOriginX = ($MAP_TILES_W - 20) * 32
    [void](Click-MinimapVerified -Point $mmEdge -ExpectedOriginX $stockClampOriginX -Tag 'mapedge')
    $ptEdge = Get-CapturePoint -Hwnd $h -Tag 'drive-mapedge'
    Assert-WideCapture -Pt $ptEdge -SkipSeam
    if ($ptEdge.Dump -and $ptEdge.OriginX -ge 0) {
        $stockClampX = ($MAP_TILES_W - 20) * 32
        Report-Finding "right map edge: camera clamped at origin x=$($ptEdge.OriginX) (stock 20-tile clamp predicts $stockClampX; stage 3 unbuilt) -- screen x=$([Math]::Max(0, 4096 - $ptEdge.OriginX))..799 lies past the map's own edge there"
        $eb = Invoke-FrameTool -ToolArgs @('band', '--dump', $ptEdge.Dump,
                '--x0', '640', '--x1', '800', '--y0', '20', '--y1', '320')
        Report-Finding "right-band content at the clamped edge: nonzero_frac=$($eb['band_nonzero_frac']) distinct=$($eb['band_distinct']) (what the user sees if they scroll all the way right)"
    }
    # back toward the fixture
    $mmBack = Get-ScMinimapPoint -MapTilesW $MAP_TILES_W -MapTilesH $MAP_TILES_H -TileX $tileX -TileY $tileY
    [void](Click-MinimapVerified -Point $mmBack -ExpectedOriginX $expectedOriginX -Tag 'mapback')
    $script:completedPhases += 'mapedge'

    # ---- stability: keep driving until the session floor is met -----------
    Write-Host "probe-wsdrive: stability loop (floor $MinSessionMinutes min from game load)"
    $iter = 0
    while (((Get-Date) - $sessionStart).TotalMinutes -lt $MinSessionMinutes) {
        $iter++
        $vk = if ($iter % 2 -eq 0) { 0x25 } else { 0x27 }   # alternate left/right
        Send-ScKey -Hwnd $h -VirtualKey $vk -HoldMs 80 -SettleMs 400
        $w = Get-ScWorldState -LogPath $log -Tag "stab$iter" -MarkerPath $markerPath
        if ($null -eq $w.Screen -or @($w.Units).Count -lt 36) {
            Assert-True "stability iteration $iter kept a complete WORLD scan" $false "(units=$(@($w.Units).Count))"
            break
        }
        if ($iter % 4 -eq 0) {
            $pt = Get-CapturePoint -Hwnd $h -Tag "drive-stab$iter"
            Assert-WideCapture -Pt $pt
            if ($pt.Dump) {
                # The dead strip, WATCHED, not sampled once (conductor,
                # 2026-08-13): 640..799 x 400..479 -- beside the console,
                # below the map. Screen-anchored, so it is comparable across
                # camera moves. A clean black strip is a footnote; flickering
                # garbage there is what would make the feature feel broken.
                $ss = Invoke-FrameTool -ToolArgs @('band', '--dump', $pt.Dump,
                        '--x0', '640', '--x1', '800', '--y0', '400', '--y1', '480')
                $script:stripSamples += "iter${iter}: nonzero=$($ss['band_nonzero_frac']) distinct=$($ss['band_distinct'])"
            }
        }
        Start-Sleep -Seconds 8
    }
    $elapsedMin = [Math]::Round(((Get-Date) - $sessionStart).TotalMinutes, 1)
    $procAlive = $null -ne (Get-Process -Id $gamePid -ErrorAction SilentlyContinue)
    Assert-True "the game survived a $elapsedMin-minute driven session ($iter stability iterations)" `
        ($procAlive -and $elapsedMin -ge $MinSessionMinutes) "(alive=$procAlive)"

    # ---- final: input still maps, frame still wide ------------------------
    $fin = Select-MarineAt -MinSx 645 -MaxSx 795 -Tag 'click-final'
    if ($null -eq $fin) { $fin = Select-MarineAt -MinSx 60 -MaxSx 600 -Tag 'click-final-left' }
    Assert-Input 'after the session a click still selects exactly the aimed unit' `
        ($null -ne $fin -and $fin.Selected.Count -eq 1 -and $fin.Selected[0] -eq $fin.Aimed) `
        "($(if ($fin) { "aimed=$($fin.Aimed) at x=$($fin.ScreenX), selected=[$($fin.Selected -join ',')]" } else { 'no target found' }))"
    $ptFinal = Get-CapturePoint -Hwnd $h -Tag 'drive-final'
    Assert-WideCapture -Pt $ptFinal
    if ($ptIngame.Dump -and $ptFinal.Dump) {
        # The strip across the WHOLE session, first in-game dump vs last:
        # screen-anchored region, so any difference is content changing in
        # the strip itself, not the camera moving under it.
        $sf = Invoke-FrameTool -ToolArgs @('band', '--dump', $ptFinal.Dump,
                '--x0', '640', '--x1', '800', '--y0', '400', '--y1', '480')
        $script:stripSamples += "final: nonzero=$($sf['band_nonzero_frac']) distinct=$($sf['band_distinct'])"
        $sd = Invoke-FrameTool -ToolArgs @('diff', '--a', $ptIngame.Dump, '--b', $ptFinal.Dump,
                '--x0', '640', '--x1', '800', '--y0', '400', '--y1', '480')
        Report-Finding "DEAD STRIP watched over the session (640..799 x 400..479): samples [$($script:stripSamples -join ' | ')]; first-vs-last diff_px=$($sd['diff_px']) of 12800 -- $(if ([int]($sd['diff_px'] ?? 12800) -eq 0) { 'STABLE: whatever is there at load never changes' } else { 'the strip CHANGES during play; describe what the PNGs show' })"
    }
    [void](Get-ScWorldState -LogPath $log -Tag 'dlgpump2' -MarkerPath $markerPath)
    $dialogsEnd = @(Get-ScDialogs -LogPath $log)
    Assert-True 'the dialog list still answers after the session' ($dialogsEnd.Count -gt 0) "(n=$($dialogsEnd.Count))"
    $completedDrive = $true
}
catch {
    $script:failures++
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
}
finally {
    Remove-Item Env:SCDRIVE_POST_ACTIVATE -ErrorAction SilentlyContinue
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  warn close-game: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
    }
    # Leave the shared game dir as found: -Windowed copied ddraw.dll/.ini in.
    # -NoLaunchLock is REQUIRED here: this suite still holds the launch lock, and
    # run-with-plugin takes the same lock for -RemoveWindowed (it mutates the shared
    # game dir) -- without the flag this finally deadlocks on its own suite's lock
    # for the lock's whole 5-minute timeout (measured, this task's diag run).
    try {
        & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch -NoLaunchLock -GameDir $GameDir | Write-Host
    }
    catch { Write-Host "  warn RemoveWindowed: $($_.Exception.Message)" }
    if ($fixtures) {
        try { Remove-ScOwnFixture -Run $fixtures | Out-Null } catch { Write-Host "  warn fixture cleanup: $($_.Exception.Message)" }
        try { Remove-ScOwnFixtureDir -Dir $fixtures.Dir | Out-Null } catch { Write-Host "  warn fixture cleanup: $($_.Exception.Message)" }
    }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
}

Write-Host ''
Write-Host 'probe-wsdrive: window PNGs + dumps (gitignored diagnostic path, never committed):'
Get-ChildItem $FrameDir -Filter 'drive-*' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "       $($_.FullName)" }
if ($script:findings.Count) {
    Write-Host ''
    Write-Host 'probe-wsdrive: FINDINGS (the honest list, ranked in the report):'
    $script:findings | ForEach-Object { Write-Host "  - $_" }
}
Write-Host ''
# 041's structural rule: a verdict that does not depend on reaching the end of
# the work is not a verdict. PASS requires the drive to have COMPLETED.
if (-not $completedDrive) {
    Write-Host "probe-wsdrive: INCOMPLETE -- the driven session did not run to its end (phases done: $($script:completedPhases -join ', ')); $script:failures failure(s) so far"
    exit 1
}
elseif ($script:failures -gt 0) {
    Write-Host "probe-wsdrive: FAIL ($script:failures failure(s))"
    exit 1
}
else {
    Write-Host 'probe-wsdrive: PASS (0 failures) -- the assembled build was driven, not captured'
    exit 0
}
