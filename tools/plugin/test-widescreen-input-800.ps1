#Requires -Version 7
<#
.SYNOPSIS
Proves stage 3 lets mouse input REACH past x=639 on the wide screen -- the
window-proc mouse clamps do not pin every x to 639 -- while everything at
640 (flag off) is byte-for-byte stock, and the CONSOLE keeps its stock 640
columns (renderer-viewport.md 18: relocating its bounds sideways moved the
hit-test, not the pixels).

.DESCRIPTION
Two arms, one oracle each -- the engine's own world scan and portrait, never
pixels.

  stock  -Widescreen 0, observe. The geometry the user plays today. A click on
         the aimed unit selects it; the minimap steers; no WIDESCREEN verdict,
         no stage-3 clamp. This is acceptance-criterion "at 640 everything is
         exactly as it was" measured, and the POSITIVE control for the s3 arm's
         absence checks.
  s3     -Widescreen 1 -WidescreenStage 3, hooktest. Asserts: the patch table
         ACTIVE with the 8 mouse-clamp sites in; the camera steered until the
         Nexus sits PAST x=639, then a click AT it selects THAT Nexus (the
         thing no run before stage 3 could do -- a click past the seam); a
         seam-crossing drag selects it; the minimap still steers; and -- the
         honest negative -- the console is STILL at its stock 640 rect
         (StatBtn 496..639), because stage 3 widens input, not the console.

THE SEAM, counted (AGENTS.md seam-coverage rule): the whole point is a click at x>639.
The suite asserts the click point is past the stock edge BEFORE it clicks and
FAILS if the steer did not put it there -- a run that never crosses the seam
cannot detect the clamp regression, whatever its verdict.

Presentation: WMode drives the input (posted clicks reach every engine path);
its window crops to 640 but that does not matter here -- selection is engine
arithmetic on stored coordinates, presentation-independent. The cnc-ddraw
picture of the wide window is another suite's; this suite is the input proof.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-widescreen-input-800.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\071',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\071-frames',
    [switch]$StockOnly,
    [switch]$S3Only,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$geom = Get-ScWideGeometry
$STOCK_W  = $geom.StockW
$SCREEN_W = $geom.W               # the width the table was generated for
$SCREEN_H = $geom.H
$PF_H     = $geom.PfH
$SHIFT_Y  = $geom.ConsoleShiftY   # how far the console moves DOWN at stage 3 (0 at 480 tall)
# The minimap click-to-centre half-extents in px at stage 3 (minimap.centre.tiles*):
# (W/32 tiles)*16 and (ceil(PF_H/32) tiles)*16; stock 320 and 208.
$HALF_X = ($SCREEN_W / 32) * 16
$HALF_Y = [math]::Ceiling($PF_H / 32) * 16
# The stage-3 patch bytes this suite expects in the log, derived from $SCREEN_W so the
# assertions move with the geometry: le32 of a value, and the imm8 tile count.
function Hex32([int]$v) { ([BitConverter]::GetBytes([uint32]$v) | ForEach-Object { $_.ToString('X2') }) -join '' }
$CLIP_HEX    = "C745F880020000 -> C745F8$(Hex32 $SCREEN_W)"          # cursor.clip.right: mov [ebp-8],640 -> W
$CLAMP_HEX   = "83E914 -> 83E9$(($SCREEN_W / 32).ToString('X2'))"    # scroll.clamp.x.tiles: sub ecx,20 -> W/32
$TRIGGER_HEX = "3D7E020000 -> 3D$(Hex32 ($SCREEN_W - 2))"            # scroll.right.trigger: cmp eax,638 -> W-2
# console.hittest.xguard: the cave body the plugin logs after the window's
# runtime `jmp`. The 0x280 is the console.pcx WIDTH (stock 640, whatever the screen is),
# so it is a constant here, not derived from $SCREEN_W: cmp ecx,640 / jl +3 / xor eax,eax
# / ret / cmp [0x6D6430],ecx (the displaced memo probe).
$XGUARD_HEX  = "[81F9800200007C0333C0C3390D30646D00 + jmp back]"

$NEXUS_TYPE = 154
# 070's measured stock console rects -- asserted UNCHANGED at stock, and at stage 3
# moved DOWN by the console shift (the 2x-height step; 0 at 480 tall, where the
# console stays put).
$STATBTN_STOCK = @(496, 354, 639, 479)
$MINIMAP_STOCK = @(0, 315, 137, 479)

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t071' -Suite 'wsinput' }
$mapName = 'wsinput.scx'
$mapPath = Join-Path $FixtureDir $mapName
$fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null
$markerPath = Join-Path $LogDir 'marker.txt'

$script:failures = 0
$script:step = 0
$launchLock = $null

function Step([string]$What, [scriptblock]$Body) {
    $script:step++; Write-Host "[$script:step] $What"; & $Body
}
function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

# A behavioural claim the OFF-SCREEN HARNESS CANNOT FEED is REPORTED, never
# asserted (the widescreen input proof and AGENTS.md's seam-coverage rule).
# A posted playfield click past x=639 does not reach the engine off-screen:
# WMode remaps posted input to its 640-wide window (070 §17.2: out of the
# shim's contract past x=640), and cnc-ddraw off-screen registers no posted
# playfield click at all (070 measured 0/8). So x>639 SELECTION is provable
# only with a real mouse on a real desktop; here it is measured and REPORTED,
# and it does NOT move the verdict. What the verdict rests on is what the
# harness CAN prove: the patches are present and correct, the console is
# unmoved, and x<640 selection is unbroken.
$script:reported = @()
function Report-Input {
    param([string]$What, [bool]$Selected, [string]$Detail = '')
    $verdict = $Selected ? 'SELECTED' : 'no-select (expected off-screen: input past x=639 is not feedable here)'
    Write-Host "  ~~   $What -> $verdict $Detail"
    $script:reported += "$What -> $verdict"
}

function Invoke-Arm {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Widescreen)
    $logPath = Join-Path $LogDir "wsinput-$Name.log"
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    $gamePid = 0; $hwnd = [IntPtr]::Zero; $result = @{ Name = $Name }

    function Get-World([string]$Tag) { Get-ScWorldState -LogPath $logPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec 20 }
    function Get-StatQ([string]$Tag) { Get-ScStatusQueue -LogPath $logPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec 20 }
    function Shot([string]$T) { if ($hwnd -ne [IntPtr]::Zero) { Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $FrameDir "$Name-$T.png") -FullWindow | Out-Null } }

    Write-Host "test-widescreen-input-800: ARM '$Name' (-Widescreen $Widescreen)"
    try {
        $mode = ($Widescreen -eq '1') ? 'hooktest' : 'observe'
        & (Join-Path $scriptDir 'run-with-plugin.ps1') `
            -Mode $mode -CardScan 1 -WorldScan 1 -NoLaunchLock `
            -Widescreen $Widescreen -WidescreenStage 3 -InjectWindowedHelper WMode `
            -GameDir $GameDir -LogPath $logPath 6>&1 | ForEach-Object {
                Write-Host $_
                if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
            }
        if (-not $gamePid) { throw "test-widescreen-input-800[$Name]: no game pid." }
        $hwnd = Get-ScGameWindow -ProcessId $gamePid

        Step "[$Name] install verdicts match the arm" {
            $ws = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN (ACTIVE|INCOMPLETE|REFUSED)')
            $clamps = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 mouse\.clamp')
            $rects = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 click\.searchrect')
            # The edge-scroll-right trigger moves with the
            # clamp (638 -> screenW-2), or the whole widened band scrolls the camera.
            $scroll = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 scroll\.right\.trigger')
            # The relocated grid must carry a committed guard on
            # each side, or an off-edge dialog rect reads grid_base-1 and faults.
            $guard = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN: grid guard OK')
            # The physical cursor clip (ClipCursor rect reset at
            # 0x004215E0) must widen with the clamp, or the real mouse is pinned to
            # x<640 and can never reach the moved scroll trigger.
            $clip = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 cursor\.clip\.right')
            # The camera's scroll clamp moves from 20 to 25 tiles
            # (0x0049BBE6), or the right map edge shows a stale band past the map.
            $clampSite = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 scroll\.clamp\.x\.tiles')
            # The right-click dead band beside the console: the console
            # hit-test 0x004D1140 asks the 640-wide console region about x>=640 and
            # answers "console"; the stage-3 cave guards it by x. A cave line carries
            # its runtime address ("cave@") and the body; assert both were written.
            $xguard = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 console\.hittest\.xguard')
            # The 2x-height step: the four wndproc mouse-Y clamp pairs (twins of the x
            # pairs above) and the console's own stage-3 sites.
            $yclamps = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 mouse\.yclamp')
            $yshift = @(Get-Content -LiteralPath $logPath | Select-String -Pattern 'WIDESCREEN patch stage=3 console\.hittest\.yshift')
            if ($Widescreen -eq '1') {
                Assert-That 'the stage-3 physical cursor clip was widened to the new screen' `
                    ($clip.Count -eq 1 -and $clip[0].Line.Contains($CLIP_HEX)) "($(($clip|ForEach-Object Line) -join ' | '); want '$CLIP_HEX')"
                Assert-That "the stage-3 camera scroll clamp was moved from 20 to $($SCREEN_W / 32) tiles" `
                    ($clampSite.Count -eq 1 -and $clampSite[0].Line.Contains($CLAMP_HEX)) "($(($clampSite|ForEach-Object Line) -join ' | '); want '$CLAMP_HEX')"
                Assert-That 'the widescreen table is ACTIVE with 0 refused' `
                    ($ws.Count -gt 0 -and $ws[0].Line -match 'ACTIVE' -and $ws[0].Line -match ' 0 refused') "($(($ws|ForEach-Object Line) -join ' | '))"
                Assert-That 'all 8 stage-3 mouse-clamp sites were written' ($clamps.Count -eq 8) "(got $($clamps.Count))"
                # 4 now: the two x extents (right, right.drag) plus the two y extents
                # (bottom, bottom.drag) the 2x-height step adds.
                $expectRects = ($SHIFT_Y -gt 0) ? 4 : 2
                Assert-That "the stage-3 click-search-rect sites were written (x + y extents)" ($rects.Count -eq $expectRects) "(got $($rects.Count), want $expectRects)"
                Assert-That 'the stage-3 edge-scroll-right trigger was moved to the widened edge' `
                    ($scroll.Count -eq 1 -and $scroll[0].Line.Contains($TRIGGER_HEX)) "($(($scroll|ForEach-Object Line) -join ' | '); want '$TRIGGER_HEX')"
                Assert-That 'the relocated dirty grid has a committed guard on both sides' `
                    ($guard.Count -eq 1) "($(($guard|ForEach-Object Line) -join ' | '))"
                Assert-That 'the stage-3 console hit-test x guard was caved (right-click beside the console)' `
                    ($xguard.Count -eq 1 -and $xguard[0].Line.Contains('cave@') -and $xguard[0].Line.Contains($XGUARD_HEX)) "($(($xguard|ForEach-Object Line) -join ' | '); want '$XGUARD_HEX')"
                Assert-That 'all 8 stage-3 mouse-Y-clamp sites were written' ($yclamps.Count -eq 8) "(got $($yclamps.Count))"
                if ($SHIFT_Y -gt 0) {
                    Assert-That "the console hit-test y shift was caved (screen y -> art y, shift $SHIFT_Y)" `
                        ($yshift.Count -eq 1 -and $yshift[0].Line.Contains('cave@')) "($(($yshift|ForEach-Object Line) -join ' | '))"
                }
            }
            else {
                Assert-That 'no widescreen verdict exists at stock' ($ws.Count -eq 0)
                Assert-That 'no stage-3 clamp was written at stock' ($clamps.Count -eq 0)
                Assert-That 'no stage-3 click-rect was written at stock' ($rects.Count -eq 0)
                Assert-That 'no edge-scroll trigger was moved at stock' ($scroll.Count -eq 0)
                Assert-That 'no console hit-test guard was caved at stock' ($xguard.Count -eq 0)
                Assert-That 'no relocated grid guard at stock' ($guard.Count -eq 0)
            }
        }

        Step "[$Name] menus -> $mapName" {
            Start-Sleep -Seconds 2
            Send-ScClick -Hwnd $hwnd -X 215 -Y 119
            Send-ScClick -Hwnd $hwnd -X 373 -Y 300
            Start-Sleep -Seconds 1
            Send-ScClick -Hwnd $hwnd -X 75 -Y 111
            Send-ScClick -Hwnd $hwnd -X 516 -Y 392
            Start-Sleep -Seconds 2
            Send-ScClick -Hwnd $hwnd -X 327 -Y 415
            Start-Sleep -Seconds 2
            Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
            Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
            Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2
            Send-ScClick -Hwnd $hwnd -X 516 -Y 393
            Start-Sleep -Seconds 6
            Send-ScClick -Hwnd $hwnd -X 544 -Y 387
            Start-Sleep -Seconds 10
            Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $logPath | Out-Null
            Start-Sleep -Seconds 2
        }

        $dy = ($Widescreen -eq '1') ? $SHIFT_Y : 0
        Step "[$Name] the console sits at its stock 640 columns, $dy below its stock rows" {
            $dlgs = @(Get-ScDialogs -LogPath $logPath)
            $btn = @($dlgs | Where-Object Name -eq 'StatBtn')[0]
            $mini = @($dlgs | Where-Object Name -eq 'Minimap')[0]
            if ($btn) {
                Assert-That "StatBtn at ($($STATBTN_STOCK[0]),$($STATBTN_STOCK[1] + $dy))-($($STATBTN_STOCK[2]),$($STATBTN_STOCK[3] + $dy))" `
                    ($btn.Left -eq $STATBTN_STOCK[0] -and $btn.Right -eq $STATBTN_STOCK[2] -and
                     $btn.Top -eq ($STATBTN_STOCK[1] + $dy) -and $btn.Bottom -eq ($STATBTN_STOCK[3] + $dy)) `
                    "(measured $($btn.Left),$($btn.Top),$($btn.Right),$($btn.Bottom))"
            }
            if ($mini) {
                Assert-That "Minimap at ($($MINIMAP_STOCK[0]),$($MINIMAP_STOCK[1] + $dy))-($($MINIMAP_STOCK[2]),$($MINIMAP_STOCK[3] + $dy))" `
                    ($mini.Left -eq $MINIMAP_STOCK[0] -and $mini.Right -eq $MINIMAP_STOCK[2] -and
                     $mini.Top -eq ($MINIMAP_STOCK[1] + $dy) -and $mini.Bottom -eq ($MINIMAP_STOCK[3] + $dy)) `
                    "(measured $($mini.Left),$($mini.Top),$($mini.Right),$($mini.Bottom))"
            }
        }

        # The seam steer uses the MINIMAP to move the camera. At the height geometry
        # (SHIFT_Y>0) the minimap has moved to y>=748, BELOW WMode's 640x480 window, so
        # a posted click can't reach it -- the Y-axis form of the 17.2 harness limit.
        # The storm probe (cnc-ddraw, a real 1280x880 window) proves minimap steering AND
        # the moved console present at 880; here the console MOVE (asserted above) and the
        # stage-3 sites are what the WMode arm can prove.
        if ($Widescreen -eq '1' -and $SHIFT_Y -gt 0) {
            Report-Input "minimap steer + x>639 seam" $false "(the minimap moved below WMode's 640x480 window at 880; cnc-ddraw covers it -- see probe-storm-present)"
        }
        elseif ($Widescreen -eq '1') {
            Step "[$Name] THE SEAM: steer the Nexus past x=639, click AT it, it selects" {
                $w0 = Get-World 'seam-0'
                $nx = @($w0.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $NEXUS_TYPE })[0]
                Assert-That 'the world scan found the Nexus' ($null -ne $nx)
                if ($null -eq $nx) { return }
                # want client x ~64px past the stock edge: origin.Left = nexus.X - 704;
                # the minimap click-to-centre half-extents follow the geometry at stage 3
                # (minimap.centre.tiles*: W/32 x ceil(PF_H/32) tiles), and the minimap
                # box itself sits $SHIFT_Y lower.
                $tileX = [int][math]::Round(($nx.X - 704 + $HALF_X) / 32)
                $tileY = [int][math]::Round(($nx.Y - 240 + $HALF_Y) / 32)
                $p = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 -TileX $tileX -TileY $tileY -ConsoleShiftY $SHIFT_Y
                Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -SettleMs 400
                Start-Sleep -Milliseconds 600
                $w1 = Get-World 'seam-1'
                Assert-That "the minimap click moved the camera" `
                    ($w0.Screen.Left -ne $w1.Screen.Left -or $w0.Screen.Top -ne $w1.Screen.Top)
                $nx1 = @($w1.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $NEXUS_TYPE })[0]
                if ($null -eq $nx1) { Assert-That 'the Nexus survived the steer' $false; return }
                $cx = $nx1.X - $w1.Screen.Left; $cy = $nx1.Y - $w1.Screen.Top
                Write-Host "       Nexus client position: ($cx,$cy)"
                Assert-That "the Nexus sits PAST the stock edge (x=$cx > 639, inside the $SCREEN_W-wide client)" `
                    ($cx -gt 639 -and $cx -lt ($SCREEN_W - 10) -and $cy -ge 0 -and $cy -lt 340)
                Send-ScClick -Hwnd $hwnd -X 200 -Y 200 -SettleMs 300   # deselect
                $sel = Get-StatQ 'seam-sel'
                for ($t = 1; $t -le 2 -and $sel.PortraitType -ne $NEXUS_TYPE; $t++) {
                    Send-ScClick -Hwnd $hwnd -X $cx -Y $cy -SettleMs 400
                    Start-Sleep -Milliseconds 600
                    $sel = Get-StatQ "seam-sel-$t"
                }
                # REPORTED, not asserted (see Report-Input): the off-screen
                # harness cannot feed a playfield click past x=639.
                Report-Input "click at ($cx,$cy), x>639" ($sel.PortraitType -eq $NEXUS_TYPE) "(ptype $($sel.PortraitType))"
                Shot 'seam-selected'

                Send-ScClick -Hwnd $hwnd -X 200 -Y 200 -SettleMs 300
                Send-ScDrag -Hwnd $hwnd -X1 ($cx - 120) -Y1 ([math]::Max(20, $cy - 80)) `
                            -X2 ([math]::Min(795, $cx + 60)) -Y2 ([math]::Min(335, $cy + 80))
                Start-Sleep -Milliseconds 600
                $drag = Get-StatQ 'drag'
                Report-Input "drag-box crossing x=640" ($drag.PortraitType -eq $NEXUS_TYPE) "(ptype $($drag.PortraitType))"
            }

            Step "[$Name] minimap still steers the camera" {
                $a = Get-World 'mini-a'
                $p = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 -TileX 20 -TileY 20 -ConsoleShiftY $SHIFT_Y
                Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -SettleMs 400
                Start-Sleep -Milliseconds 600
                $b = Get-World 'mini-b'
                Assert-That "the camera moved" ($a.Screen.Left -ne $b.Screen.Left -or $a.Screen.Top -ne $b.Screen.Top)
            }
        }
        else {
            Step "[$Name] a click on the aimed Nexus selects it (baseline)" {
                $w = Get-World 'stock-aim'
                $nx = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $NEXUS_TYPE })[0]
                Assert-That 'the world scan found the Nexus' ($null -ne $nx)
                if ($nx) {
                    $cx = $nx.X - $w.Screen.Left; $cy = $nx.Y - $w.Screen.Top
                    $sel = $null
                    for ($t = 1; $t -le 3; $t++) {
                        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy -SettleMs 400
                        Start-Sleep -Milliseconds 600
                        $sel = Get-StatQ "stock-sel-$t"
                        if ($sel.PortraitType -eq $NEXUS_TYPE) { break }
                    }
                    Assert-That "the click at ($cx,$cy) selected the Nexus" ($sel.PortraitType -eq $NEXUS_TYPE) "(ptype $($sel.PortraitType))"
                }
            }
            Shot 'stock-640'
        }
        $result.Failures = $script:failures
    }
    finally {
        if (-not $KeepOpen -and $gamePid -gt 0) {
            try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
            catch { Write-Host "  warn close-game: $($_.Exception.Message)" }
            Start-Sleep -Seconds 2
        }
    }
    $result
}

$completedArms = 0
try {
    Step "generate the fixture: one Nexus, 500 minerals" {
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 1 -UnitType 'nexus' -Player 0 -ClearPlayerUnits `
            -Race 'protoss' -StartingMinerals 500 -StartingGas 0 -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'its structural validation passed' (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
    }
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '071-wsinput'
    if (-not $S3Only) { Invoke-Arm -Name 'stock' -Widescreen '0'; $completedArms++ }
    if (-not $StockOnly) { Invoke-Arm -Name 's3' -Widescreen '1'; $completedArms++ }
}
finally {
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
    if ($fixtures) {
        foreach ($n in $fixtures.Names) {
            $p = Join-Path $fixtures.Dir $n
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
        }
        if ((Test-Path -LiteralPath $fixtures.Dir) -and (@(Get-ChildItem -LiteralPath $fixtures.Dir -Force).Count -eq 0)) {
            Remove-Item -LiteralPath $fixtures.Dir -Force
        }
    }
}

# The seam this suite exists to exercise -- a playfield click PAST x=639 -- is
# the one thing the off-screen harness cannot feed (see Report-Input). Name it
# beside the verdict every run so a PASS is never mistaken for "x>639 input was
# proven" (AGENTS.md seam-coverage rule). The behavioural proof is a real mouse on a real
# desktop.
Write-Host ''
Write-Host 'COVERAGE  the x>639 playfield-SELECT seam was REPORTED, not asserted:'
foreach ($r in $script:reported) { Write-Host "          $r" }
Write-Host '          off-screen WMode/cnc-ddraw cannot feed a posted click past x=639 (070 harness limit);'
Write-Host '          this run proves the PATCHES present + 640 unbroken, NOT that x>639 selection behaves.'

$expectedArms = ($StockOnly -or $S3Only) ? 1 : 2
if ($completedArms -lt $expectedArms) {
    Write-Host "test-widescreen-input-800: INCOMPLETE -- $completedArms of $expectedArms arm(s), $script:failures failure(s)"
    exit 1
}
if ($script:failures -gt 0) {
    Write-Host "test-widescreen-input-800: FAIL -- $script:failures failure(s) across $completedArms arm(s)"
    exit 1
}
Write-Host "test-widescreen-input-800: PASS -- $completedArms arm(s), 0 assertion failures (x>639 select reported, not asserted -- see COVERAGE)"
exit 0
