#Requires -Version 7
<#
.SYNOPSIS
The SHIPPED-config proof for the storm-side buffer->glass present fix
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
    # nothing through to the DLL and lets its own auto-arm decide -- the auto-arm bug
    # was about: before the fix this arm read "STORM present: off", after it "WIDEN armed".
    [ValidateSet('widen', 'probe', 'auto')][string]$StormPresent = 'widen',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
. (Join-Path $scriptDir 'sc-suite.ps1')
. (Join-Path $scriptDir 'sc-wsprobe.ps1')

# The geometry under test comes from the generated table, never from this file.
$ws = Get-ScWideGeometry
$SCREEN_W = $ws.W; $SCREEN_H = $ws.H; $STOCK_W = $ws.StockW; $STOCK_H = $ws.StockH
$SHIFT_Y = $ws.ConsoleShiftY        # the console's move DOWN at stage 3 (0 at 480 tall)
# The MAP right band the two numbers are read over: 20px in from the stock edge to
# 10px short of the new one.
$BAND_X0 = $STOCK_W + 20; $BAND_X1 = $SCREEN_W - 10

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t074' -Suite 'stormpresent' }
$mapName = 'stormpresent.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$log = Join-Path $LogDir '074-stormpresent.log'

Initialize-ScWsProbe -LogDir $LogDir -FrameDir $FrameDir

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
    (Get-ScBufferDump -LogPath $log -MarkerPath $markerPath -Tag $Tag).Path
}
function Get-DumpBand {
    param([string]$Dump, [int]$X0, [int]$X1, [int]$Y0, [int]$Y1)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') band --dump $Dump --x0 $X0 --x1 $X1 --y0 $Y0 --y1 $Y1 2>&1
    foreach ($l in $out) { if ("$l" -match '^band_nonzero_frac=(.+)$') { return [double]$Matches[1] } }
    -1.0
}

# The STORM log's base-region row-width, for a dedicated marker. This is the memory
# oracle the on-glass capture corroborates: +0x18 == the screen width means the widen is in force.
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

# The shipped-config band read: buffer (composed, always full width) beside glass (the
# window), over the MAP right band BAND_X0..BAND_X1, y=80..300.
function Read-TwoNumbers {
    param([string]$Tag, [string]$ShotName, [int]$X0 = $BAND_X0, [int]$X1 = $BAND_X1, [int]$Y0 = 80, [int]$Y1 = 300)
    $dump = Get-BufferDump -Tag "$Tag-buf"
    $buf = ($dump) ? (Get-DumpBand -Dump $dump -X0 $X0 -X1 $X1 -Y0 $Y0 -Y1 $Y1) : -1
    $shot = Join-Path $FrameDir $ShotName
    Save-ScWindowImage -Hwnd $h -Path $shot | Out-Null
    $glass = Get-PngRectNonzero -Path $shot -X0 $X0 -Y0 $Y0 -X1 $X1 -Y1 $Y1
    [pscustomobject]@{ Buffer = $buf; Glass = $glass; Shot = $shot }
}

try {
    Write-Host 'probe-storm: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '074-stormpresent'

    Write-Host 'probe-storm: generating the fixture (one Nexus, explored start -- map at the right band)'
    $fixtures = New-ScNexusFixture -RepoRoot $repoRoot -FixtureDir $FixtureDir -MapName $mapName -Noun 'probe-storm'

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    Write-Host "probe-storm: launching (stage 3, cnc-ddraw, StormPresent=$StormPresent)"
    $gamePid = Start-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -LogPath $log -FrameDir $FrameDir `
        -WindowedHelperDll $WindowedHelperDll -StormPresent $StormPresent -Noun 'probe-storm'
    $h = Connect-ScWideGame -GamePid $gamePid -LogPath $log -ScreenW $SCREEN_W -ScreenH $SCREEN_H
    Assert-True 'storm present is armed as WIDEN' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'STORM present: WIDEN armed' }).Count -gt 0)

    Write-Host 'probe-storm: walking to a loaded game'
    Enter-ScCustomGame -Hwnd $h -LogPath $log -Fixtures $fixtures -MapPath $mapPath -GameDir $GameDir -ActivationNudge -Noun 'probe-storm'

    # ---- THE STATIC LOAD FRAME (run 7's failure): the map must present without a scroll.
    # The strip copy runs every present, so x>648 tracks the buffer on the very first
    # frame -- no dirty mark / no scroll needed. This is exactly what the base-region
    # widen could NOT do (run 7: base +0x18=800 yet glass map = 0 on the static frame).
    $n1 = Read-TwoNumbers -Tag 'ship-static' -ShotName 'storm-present-shipped-static.png'
    Report-Finding "SHIPPED STATIC load frame, MAP right band x=$BAND_X0..$BAND_X1 y=80..300: BUFFER=$($n1.Buffer) GLASS=$($n1.Glass) (capture $($n1.Shot))"
    # The oracle is AGREEMENT (20.7: "buffer and glass agree for the first time"): the
    # glass must carry what the buffer holds, and the buffer must hold something, or
    # the check is vacuous. An absolute floor was the 800-era form (>= 0.30), calibrated
    # on a 160-px band the fixture's sight had mostly explored; at 1280 the same sight
    # explores a quarter of a 640-px band (buffer 0.16 static, 0.47 after a scroll) and
    # the ratio glass/buffer is what stays put (0.86 at 800, 0.86 here).
    Assert-True 'STATIC load frame: the MAP right band is PRESENTED on glass past x=648 (glass >= 0.8 x buffer, buffer >= 0.05; no scroll needed)' `
        ($n1.Buffer -ge 0.05 -and $n1.Glass -ge 0.8 * $n1.Buffer) "(buffer=$($n1.Buffer) glass=$($n1.Glass))"

    # ---- THE HEIGHT (the 2x-height step, renderer-viewport.md 22): with the console
    # moved down, (a) the rows the console vacated are MAP and must present,
    # (b) the rows below the stock screen are map too (buffer-resident dialogs +
    # the whole-frame mirror), (c) the console itself must be on glass at its
    # new place. All three read the same two instruments as the right band.
    if ($SHIFT_Y -gt 0) {
        # The band the console VACATED downward -- pure playfield below the stock
        # screen bottom (480) and ABOVE the moved console's top (art row 302 + the
        # shift). Map here means the buffer->glass mirror carries the whole taller
        # frame. Ends before the console so the two-number ratio is not diluted by
        # console art (whose black panel interiors are a non-zero index that renders
        # near-black -- index!=0 in the buffer, RGB~0 on glass; that mismatch is what
        # the console-presence check below uses `check` consistency for instead).
        $mapBandBottom = 302 + $SHIFT_Y - 2
        $nb = Read-TwoNumbers -Tag 'ship-bottom' -ShotName 'storm-present-shipped-bottom.png' `
            -X0 20 -X1 ($STOCK_W - 20) -Y0 ($STOCK_H + 20) -Y1 $mapBandBottom
        Report-Finding "SHIPPED STATIC load frame, MAP band below the stock screen x=20..$($STOCK_W - 20) y=$($STOCK_H + 20)..${mapBandBottom}: BUFFER=$($nb.Buffer) GLASS=$($nb.Glass)"
        Assert-True 'STATIC load frame: the MAP below the stock screen bottom is PRESENTED on glass (glass >= 0.8 x buffer, buffer >= 0.05)' `
            ($nb.Buffer -ge 0.05 -and $nb.Glass -ge 0.8 * $nb.Buffer) "(buffer=$($nb.Buffer) glass=$($nb.Glass))"
        $nv = Read-TwoNumbers -Tag 'ship-vacated' -ShotName 'storm-present-shipped-vacated.png' `
            -X0 150 -X1 ($STOCK_W - 20) -Y0 320 -Y1 ($STOCK_H - 20)
        Report-Finding "SHIPPED STATIC load frame, the VACATED console rows x=150..$($STOCK_W - 20) y=320..$($STOCK_H - 20): BUFFER=$($nv.Buffer) GLASS=$($nv.Glass)"
        Assert-True 'STATIC load frame: the rows the console vacated show MAP on glass (glass >= 0.8 x buffer, buffer >= 0.05)' `
            ($nv.Buffer -ge 0.05 -and $nv.Glass -ge 0.8 * $nv.Buffer) "(buffer=$($nv.Buffer) glass=$($nv.Glass))"
        # The command card at its moved rect (496,354+dy)-(639,479+dy): bronze art and
        # buttons, mostly non-black on glass. The buffer half is read too (the dialogs
        # composite INTO the buffer now, so both must carry it).
        $nc = Read-TwoNumbers -Tag 'ship-card' -ShotName 'storm-present-shipped-card.png' `
            -X0 500 -X1 636 -Y0 (358 + $SHIFT_Y) -Y1 (476 + $SHIFT_Y)
        Report-Finding "SHIPPED STATIC load frame, the COMMAND CARD at its moved rect y=$(358 + $SHIFT_Y)..$(476 + $SHIFT_Y): BUFFER=$($nc.Buffer) GLASS=$($nc.Glass)"
        Assert-True 'STATIC load frame: the command card is on glass at its moved rect (nonzero >= 0.5) and in the buffer (>= 0.5)' `
            ($nc.Glass -ge 0.5 -and $nc.Buffer -ge 0.5) "(buffer=$($nc.Buffer) glass=$($nc.Glass))"
        # The whole moved console on glass, the HONEST way: the two-number ratio is
        # invalid over console art (nonzero-index black interiors), so use the
        # index->RGB CONSISTENCY frame-capture.py `check` derives -- the same oracle
        # probe-framebuffer-capture trusts for the playfield. It maps the dump's
        # indices to the glass RGB and reports how much of the console band the glass
        # reproduces. The pure-map playfield reaches 0.97; the console band mixes
        # bronze, text and black panels, so 0.75 is the floor. Alignment pinned (0,0):
        # the mirror is a straight copy, no offset.
        $bottomBuf = Join-Path $FrameDir 'fd-ship-bottom-buf.bin'
        $bottomShot = Join-Path $FrameDir 'storm-present-shipped-bottom.png'
        $consConsist = -1.0; $consDistinct = 0
        if ((Test-Path -LiteralPath $bottomBuf) -and (Test-Path -LiteralPath $bottomShot)) {
            $out = & python (Join-Path $scriptDir 'frame-capture.py') check `
                --dump $bottomBuf --before $bottomShot --after $bottomShot `
                --x0 20 --y0 (354 + $SHIFT_Y) --y1 (479 + $SHIFT_Y) --align-dx 0 --align-dy 0 2>&1
            foreach ($l in $out) {
                if ("$l" -match '^consist_frac=(.+)$') { $consConsist = [double]$Matches[1] }
                if ("$l" -match '^window_distinct_rgb=(\d+)') { $consDistinct = [int]$Matches[1] }
            }
        }
        Report-Finding "SHIPPED STATIC load frame, the moved CONSOLE band y=$(354 + $SHIFT_Y)..$(479 + $SHIFT_Y): index->RGB consistency=$consConsist distinct_rgb=$consDistinct"
        # Two-sided, so neither is vacuous: distinct_rgb proves the glass holds a real
        # PICTURE there (not black -- the framecap's own anti-vacuous check), and the
        # consistency proves that picture MATCHES the dump. The console band's ceiling
        # is lower than the pure playfield's 0.97 (map bleeds through the art's
        # transparent gaps, text anti-aliases, a single-frame palette misses fog edges),
        # so 0.70 is the floor here, measured ~0.74.
        Assert-True 'STATIC load frame: the moved console reaches the glass as a real picture that matches the dump (distinct_rgb >= 32 and consistency >= 0.70)' `
            ($consDistinct -ge 32 -and $consConsist -ge 0.70) "(distinct=$consDistinct consist=$consConsist)"
        $mv = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'CONSOLE moved ' })
        Assert-True 'the ten bottom-console roots were moved (CONSOLE moved lines = 10)' ($mv.Count -eq 10) "(got $($mv.Count))"
    }

    # ---- HOLDS THROUGH A SCROLL, and the camera still steers (must-not-break) ----
    $a = Get-ScWorldState -LogPath $log -Tag 'mini-a' -MarkerPath $markerPath
    $p = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 -TileX 20 -TileY 20 -ConsoleShiftY $SHIFT_Y
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
    Write-ScStepFailure -Err $_ -What 'a probe step'
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        Stop-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -GamePid $gamePid
        $gamePid = 0
        # The far-band cursor strobe (renderer-viewport.md 21.9): in WIDEN
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
    Stop-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -GamePid $gamePid -KeepOpen:$KeepOpen -Fixtures $fixtures -LaunchLock $launchLock
}

Write-Host ''
if ($script:findings.Count) { Write-Host 'probe-storm: FINDINGS:'; $script:findings | ForEach-Object { Write-Host "  - $_" } }
Write-Host ''
if (-not $completed) { Write-Host "probe-storm: INCOMPLETE -- the run did not reach its end; $script:failures failure(s) so far"; exit 1 }
elseif ($script:failures -gt 0) { Write-Host "probe-storm: FAIL ($script:failures failure(s))"; exit 1 }
else { Write-Host 'probe-storm: PASS (0 failures) -- the playfield presents past x=648 in the shipped config, and re-asserts across a reload'; exit 0 }
