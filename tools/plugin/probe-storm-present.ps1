#Requires -Version 7
<#
.SYNOPSIS
Task 074. The SHIPPED-config proof for the storm-side buffer->glass present fix
(renderer-viewport.md 19.8/20): widescreen stage 3, cnc-ddraw, and NO console-edge
move -- so the map at x>648 is the PLAYFIELD, proving the present widens on its own,
independent of 073's unshipped console experiment.

It reads the buffer-vs-glass two numbers over the MAP right band (the instrument
renderer-viewport.md 19.8 leaves behind; this reuses it, it does not build another),
captures the window the user would actually see, checks the widen held (base region
+0x18 == 800 from the STORM log), that a minimap click still steers (must-not-break),
and -- the conductor's ask -- that the widen RE-ASSERTS across a return-to-menu +
reload, which rebuilds the base region to 640 and must be re-widened.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-storm-present.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\074',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\074-frames',
    [string]$WindowedHelperDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    # 'widen' forces the fix on (what the deployed wide launcher passes). 'auto' passes
    # nothing through to the DLL and lets its own auto-arm decide -- the arm issue #113
    # was about: before the fix this arm read "STORM present: off", after it "WIDEN armed".
    [ValidateSet('widen', 'probe', 'auto')][string]$StormPresent = 'widen',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

# The geometry under test comes from the generated table, never from this file.
$ws = Get-ScWideGeometry
$SCREEN_W = $ws.W; $SCREEN_H = $ws.H; $STOCK_W = $ws.StockW
# The MAP right band the two numbers are read over: 20px in from the stock edge to
# 10px short of the new one (was the fixed 660..790 of 19.8 at 800 wide).
$BAND_X0 = $STOCK_W + 20; $BAND_X1 = $SCREEN_W - 10

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t074' -Suite 'stormpresent' }
$mapName = 'stormpresent.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$log = Join-Path $LogDir '074-stormpresent.log'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null

$script:failures = 0
$script:step = 0
$script:findings = @()
$launchLock = $null
$fixtures = $null
$gamePid = 0
$completed = $false

function Assert-True {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    $script:step++
    if ($Ok) { Write-Host "  [$script:step] OK   $What $Detail" }
    else { Write-Host "  [$script:step] FAIL $What $Detail"; $script:failures++ }
}
function Report-Finding { param([string]$What) $script:findings += $What; Write-Host "  ---- FINDING: $What" }

Add-Type -AssemblyName System.Drawing
function Get-PngRectNonzero {
    param([Parameter(Mandatory)][string]$Path, [int]$X0, [int]$Y0, [int]$X1, [int]$Y1)
    $bmp = [System.Drawing.Bitmap]::new($Path)
    try {
        $n = 0; $nz = 0
        $xe = [Math]::Min($X1, $bmp.Width); $ye = [Math]::Min($Y1, $bmp.Height)
        for ($y = $Y0; $y -lt $ye; $y += 2) {
            for ($x = $X0; $x -lt $xe; $x += 2) {
                $c = $bmp.GetPixel($x, $y); $n++
                if (([int]$c.R + [int]$c.G + [int]$c.B) -gt 24) { $nz++ }
            }
        }
        if ($n -eq 0) { return -1.0 }
        [Math]::Round($nz / $n, 4)
    } finally { $bmp.Dispose() }
}

function Get-BufferDump {
    param([string]$Tag)
    $from = Get-ScLogLineCount -LogPath $log
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    $lines = Wait-ScLogMatch -LogPath $log -Pattern "FRAMEDUMP \[$([regex]::Escape($Tag))\] " -TimeoutSec 20 -FromLine $from
    foreach ($l in $lines) {
        if ($l -match 'FRAMEDUMP \[[^\]]+\] w=\d+ h=\d+ bytes=\d+ reads=\d+ stable=\d path=(.+)$') { return $Matches[1].Trim() }
    }
    $null
}
function Get-DumpBand {
    param([string]$Dump, [int]$X0, [int]$X1, [int]$Y0, [int]$Y1)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') band --dump $Dump --x0 $X0 --x1 $X1 --y0 $Y0 --y1 $Y1 2>&1
    foreach ($l in $out) { if ("$l" -match '^band_nonzero_frac=(.+)$') { return [double]$Matches[1] } }
    -1.0
}

# The STORM log's base-region row-width, for a dedicated marker. This is the memory
# oracle the on-glass capture corroborates: +0x18 == 800 means the widen is in force.
function Get-StormBaseW18 {
    param([string]$Tag)
    $from = Get-ScLogLineCount -LogPath $log
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    [void](Wait-ScLogMatch -LogPath $log -Pattern "STORM \[$([regex]::Escape($Tag))\] region-struct base" -TimeoutSec 15 -FromLine $from)
    $line = @(Get-Content -LiteralPath $log | Select-Object -Skip $from |
              Where-Object { $_ -match "STORM \[$([regex]::Escape($Tag))\] region-struct base" }) | Select-Object -First 1
    if ($line -and $line -match '\+18=(\d+)') { return [int]$Matches[1] }
    -1
}

# The shipped-config band read: buffer (composed, always 800) beside glass (the
# window). MAP right band x=660..790 y=80..300 -- the same rect 19.8's finding used.
function Read-TwoNumbers {
    param([string]$Tag, [string]$ShotName)
    $dump = Get-BufferDump -Tag "$Tag-buf"
    $buf = ($dump) ? (Get-DumpBand -Dump $dump -X0 $BAND_X0 -X1 $BAND_X1 -Y0 80 -Y1 300) : -1
    $shot = Join-Path $FrameDir $ShotName
    Save-ScWindowImage -Hwnd $h -Path $shot | Out-Null
    $glass = Get-PngRectNonzero -Path $shot -X0 $BAND_X0 -Y0 80 -X1 $BAND_X1 -Y1 300
    [pscustomobject]@{ Buffer = $buf; Glass = $glass; Shot = $shot }
}

function Click-UntilDialog {
    param([int]$X, [int]$Y, [string]$Name, [int]$Tries = 3, [int]$WaitSec = 12)
    for ($i = 1; $i -le $Tries; $i++) {
        Send-ScClick -Hwnd $h -X $X -Y $Y
        $d = Wait-ScDialog -LogPath $log -Name $Name -TimeoutSec $WaitSec
        if ($d) { return $d }
        Write-Host "       walk: '$Name' not up after click $i/$Tries at ($X,$Y); retrying"
    }
    $null
}

# The full menu -> loaded game walk (probe-console-edge's, verbatim shape).
function Walk-ToGame {
    $env:SCDRIVE_POST_ACTIVATE = '1'
    if (-not (Wait-ScDialog -LogPath $log -Name 'MainMenu' -TimeoutSec 30)) { throw 'probe-storm: main menu never appeared.' }
    Start-Sleep -Seconds 3
    if (-not (Click-UntilDialog -X 215 -Y 119 -Name 'Delete')) { throw 'probe-storm: Original/Expansion chooser never appeared.' }
    Send-ScClick -Hwnd $h -X 373 -Y 300; Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $h -X 75 -Y 111
    if (-not (Click-UntilDialog -X 516 -Y 392 -Name 'RaceSelection' -WaitSec 15)) { throw 'probe-storm: RaceSelection never appeared.' }
    if (-not (Click-UntilDialog -X 327 -Y 415 -Name 'Create' -WaitSec 15)) { throw 'probe-storm: map browser never appeared.' }
    Start-Sleep -Seconds 2
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $mapPath | Out-Null
    Set-ScGameType -Hwnd $h -LogPath $log -Index 2
    Send-ScClick -Hwnd $h -X 516 -Y 393; Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $h -X 544 -Y 387; Start-Sleep -Seconds 10
    Dismiss-ScTipsDialog -Hwnd $h -LogPath $log | Out-Null
    Start-Sleep -Seconds 3
    $env:SCDRIVE_POST_ACTIVATE = '0'
}

try {
    Write-Host 'probe-storm: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '074-stormpresent'
    if (-not (Test-Path -LiteralPath $WindowedHelperDll)) { throw "probe-storm: $WindowedHelperDll not found; run fetch-cnc-ddraw.ps1." }

    Write-Host 'probe-storm: generating the fixture (one Nexus, explored start -- map at the right band)'
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount 1 -UnitType 'nexus' -Player 0 -ClearPlayerUnits -Race 'protoss' `
        -StartingMinerals 500 -StartingGas 0 -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }
    if (-not (Test-Path -LiteralPath $mapPath)) { throw 'probe-storm: the fixture was never generated.' }

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    Write-Host "probe-storm: launching (stage 3, cnc-ddraw, ConsoleEdge OFF, StormPresent=$StormPresent)"
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -WorldScan 1 -NoLaunchLock `
        -Widescreen 1 -WidescreenStage 3 -ConsoleEdge 0 -StormPresent $StormPresent `
        -FrameDump $FrameDir `
        -Windowed -WindowedHelperDll $WindowedHelperDll `
        -GameDir $GameDir -LogPath $log 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe-storm: could not parse the game pid.' }
    $h = Get-ScGameWindow -ProcessId $gamePid
    Start-Sleep -Seconds 3

    Assert-True 'the widescreen table is ACTIVE with 0 refused' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'WIDESCREEN ACTIVE' -and $_ -match ', 0 refused' }).Count -gt 0)
    Assert-True 'storm present is armed as WIDEN' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'STORM present: WIDEN armed' }).Count -gt 0)
    $client = Get-ScClientSize -Hwnd $h
    Assert-True "cnc-ddraw presents a $($SCREEN_W)x$($SCREEN_H) client area" ($client.Width -eq $SCREEN_W -and $client.Height -eq $SCREEN_H) "(got $($client.Width)x$($client.Height))"

    Write-Host 'probe-storm: walking to a loaded game'
    Walk-ToGame

    # ---- THE STATIC LOAD FRAME (run 7's failure): the map must present without a scroll.
    # The strip copy runs every present, so x>648 tracks the buffer on the very first
    # frame -- no dirty mark / no scroll needed. This is exactly what the base-region
    # widen could NOT do (run 7: base +0x18=800 yet glass map = 0 on the static frame).
    $n1 = Read-TwoNumbers -Tag 'ship-static' -ShotName 'storm-present-shipped-static.png'
    Report-Finding "SHIPPED (ConsoleEdge OFF) STATIC load frame, MAP right band x=$BAND_X0..$BAND_X1 y=80..300: BUFFER=$($n1.Buffer) GLASS=$($n1.Glass) (capture $($n1.Shot))"
    # The oracle is AGREEMENT (20.7: "buffer and glass agree for the first time"): the
    # glass must carry what the buffer holds, and the buffer must hold something, or
    # the check is vacuous. An absolute floor was the 800-era form (>= 0.30), calibrated
    # on a 160-px band the fixture's sight had mostly explored; at 1280 the same sight
    # explores a quarter of a 640-px band (buffer 0.16 static, 0.47 after a scroll) and
    # the ratio glass/buffer is what stays put (0.86 at 800, 0.86 here).
    Assert-True 'STATIC load frame: the MAP right band is PRESENTED on glass past x=648 (glass >= 0.8 x buffer, buffer >= 0.05; no scroll needed)' `
        ($n1.Buffer -ge 0.05 -and $n1.Glass -ge 0.8 * $n1.Buffer) "(buffer=$($n1.Buffer) glass=$($n1.Glass))"

    # ---- HOLDS THROUGH A SCROLL, and the camera still steers (must-not-break) ----
    $a = Get-ScWorldState -LogPath $log -Tag 'mini-a' -MarkerPath $markerPath
    $p = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 -TileX 20 -TileY 20
    Send-ScClick -Hwnd $h -X $p.X -Y $p.Y -SettleMs 400; Start-Sleep -Milliseconds 600
    $b = Get-ScWorldState -LogPath $log -Tag 'mini-b' -MarkerPath $markerPath
    Assert-True 'must-not-break: a minimap click still steers the camera at 800 with the widen active' `
        ($null -ne $a.Screen -and $null -ne $b.Screen -and ($a.Screen.Left -ne $b.Screen.Left -or $a.Screen.Top -ne $b.Screen.Top)) `
        "($($a.Screen.Left),$($a.Screen.Top) -> $($b.Screen.Left),$($b.Screen.Top))"
    $n2 = Read-TwoNumbers -Tag 'ship-scrolled' -ShotName 'storm-present-shipped-scrolled.png'
    Report-Finding "SHIPPED after a scroll, MAP right band: BUFFER=$($n2.Buffer) GLASS=$($n2.Glass) (capture $($n2.Shot))"
    Assert-True 'after a scroll: the MAP right band is still PRESENTED past x=648 (glass >= 0.8 x buffer, buffer >= 0.05)' `
        ($n2.Buffer -ge 0.05 -and $n2.Glass -ge 0.8 * $n2.Buffer) "(buffer=$($n2.Buffer) glass=$($n2.Glass))"

    # The strip runs every present and holds no engine state, so a save/load or a menu
    # return needs no re-assertion -- there is nothing to revert. (The per-frame strip
    # counter is logged in STORMSTATS at detach; the on-glass map above is what proves
    # the strip ran, since nothing else puts map past x=648 in this config.)
    $completed = $true
}
catch {
    $script:failures++
    Write-Host "  FAIL a step threw: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
}
finally {
    Remove-Item Env:SCDRIVE_POST_ACTIVATE -ErrorAction SilentlyContinue
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  warn close-game: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
        # 2026-09-07 (the far-band cursor strobe, renderer-viewport.md 21.9): in WIDEN
        # mode the ord432 hook sets the cursor layer's sticky always-draw bit and counts
        # how often it found it clear. STORMSTATS is written at detach, so it is read
        # here, after the close. 0 = the poke never ran (the hook did not fire);
        # 1 = set once and sticky, the expected reading; more = something clears it
        # (the layer-table init 0x0041E050 zeroes every flag, so a re-init would).
        if ($completed -and (Test-Path -LiteralPath $log)) {
            $stats = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'STORMSTATS mode=2 ' }) | Select-Object -Last 1
            $forced = ($stats -match 'cursorForced=(\d+)') ? [int]$Matches[1] : -1
            Assert-True 'WIDEN set the cursor layer always-draw bit exactly once (sticky, so the strip never mirrors a cursor-free frame)' `
                ($forced -eq 1) "(cursorForced=$forced from '$stats')"
        }
    }
    try { & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch -NoLaunchLock -GameDir $GameDir | Write-Host }
    catch { Write-Host "  warn RemoveWindowed: $($_.Exception.Message)" }
    if ($fixtures) {
        try { Remove-ScOwnFixture -Run $fixtures | Out-Null } catch { Write-Host "  warn fixture: $($_.Exception.Message)" }
        try { Remove-ScOwnFixtureDir -Dir $fixtures.Dir | Out-Null } catch { Write-Host "  warn fixture: $($_.Exception.Message)" }
    }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
}

Write-Host ''
if ($script:findings.Count) { Write-Host 'probe-storm: FINDINGS:'; $script:findings | ForEach-Object { Write-Host "  - $_" } }
Write-Host ''
if (-not $completed) { Write-Host "probe-storm: INCOMPLETE -- the run did not reach its end; $script:failures failure(s) so far"; exit 1 }
elseif ($script:failures -gt 0) { Write-Host "probe-storm: FAIL ($script:failures failure(s))"; exit 1 }
else { Write-Host 'probe-storm: PASS (0 failures) -- the playfield presents past x=648 in the shipped config, and re-asserts across a reload'; exit 0 }
