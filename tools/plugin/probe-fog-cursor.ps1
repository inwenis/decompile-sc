#Requires -Version 7
<#
.SYNOPSIS
Does a resting cursor over UNEXPLORED map paint terrain into the buffer? Three
parks; around each the dirty-marker trace is armed (MARK/FOGR/TERR lines: every
rect the engine marks, every fog run it renders, every terrain run it blits),
the buffer is dumped while parked and at 0 s, 1 s and 3 s after the cursor
leaves, and each dump is compared with the baseline in MAP space over the
cursor's footprint.

The edge-scroll reads the PHYSICAL mouse (GetCursorPos at 0x004D12A0), so a real
mouse resting near the monitor's bottom or right edge scrolls this off-screen
game; comparing in map space (each dump carries its camera) makes that drift
harmless to the numbers.

.EXAMPLE
$env:AGENT_TASK = '145'; ./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-fog-cursor.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\145',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\145-frames',
    [string]$WindowedHelperDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
. (Join-Path $scriptDir 'sc-suite.ps1')
. (Join-Path $scriptDir 'sc-wsprobe.ps1')

$ws = Get-ScWideGeometry
$SCREEN_W = $ws.W; $SCREEN_H = $ws.H; $STOCK_H = $ws.StockH
$PF_H = $STOCK_H - 80 + $ws.ConsoleShiftY

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t145' -Suite 'fogcursor' }
$mapName = 'fogcursor.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$log = Join-Path $LogDir '145-fogcursor.log'
Initialize-ScWsProbe -LogDir $LogDir -FrameDir $FrameDir

function Get-DumpBand {
    param([string]$Dump, [int]$X0, [int]$X1, [int]$Y0, [int]$Y1)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') band --dump $Dump --x0 $X0 --x1 $X1 --y0 $Y0 --y1 $Y1 2>&1
    $r = [ordered]@{ Frac = -1.0; Nonzero = -1 }
    foreach ($l in $out) {
        if ("$l" -match '^band_nonzero_frac=(.+)$') { $r.Frac = [double]$Matches[1] }
        if ("$l" -match '^band_nonzero=(\d+)$') { $r.Nonzero = [int]$Matches[1] }
    }
    [pscustomobject]$r
}
# A's screen rect compared against B in MAP space (each dump's camera shifts it),
# widened by the camera drift so a footprint laid down mid-drift is still inside.
function Get-MapDiff {
    param($A, $B, [int]$X0, [int]$Y0, [int]$X1, [int]$Y1)
    $ddx = [Math]::Abs($B.Cam.X - $A.Cam.X); $ddy = [Math]::Abs($B.Cam.Y - $A.Cam.Y)
    $x0 = [Math]::Max(0, $X0 - $ddx); $y0 = [Math]::Max(0, $Y0 - $ddy)
    $x1 = [Math]::Min($SCREEN_W, $X1 + $ddx); $y1 = [Math]::Min($PF_H, $Y1 + $ddy)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') mapdiff --a $A.Path --ax $A.Cam.X --ay $A.Cam.Y `
        --b $B.Path --bx $B.Cam.X --by $B.Cam.Y --x0 $x0 --y0 $y0 --x1 $x1 --y1 $y1 2>&1
    $r = [ordered]@{ Overlap = -1; Changed = -1; Gained = -1; Lost = -1; Drift = "$($B.Cam.X - $A.Cam.X),$($B.Cam.Y - $A.Cam.Y)" }
    foreach ($l in $out) {
        if ("$l" -match '^mapdiff_overlap=(\d+)$') { $r.Overlap = [int]$Matches[1] }
        if ("$l" -match '^mapdiff_changed=(\d+)$') { $r.Changed = [int]$Matches[1] }
        if ("$l" -match '^mapdiff_gained=(\d+)$') { $r.Gained = [int]$Matches[1] }
        if ("$l" -match '^mapdiff_lost=(\d+)$') { $r.Lost = [int]$Matches[1] }
    }
    [pscustomobject]$r
}
# A dump that must come back with both halves, or the probe cannot judge it.
function Get-Dump {
    param([string]$Tag)
    $d = Get-ScBufferDump -LogPath $log -MarkerPath $markerPath -Tag $Tag
    if (-not $d.Path -or -not $d.Cam) { throw "probe-fog: dump '$Tag' came back without a path or a camera (path=$($d.Path))." }
    $d
}

# The cursor's footprint plus room: three cell columns right of the hotspot's
# and a column left, two rows above to four below.
function Get-ParkRect {
    param([int]$X, [int]$Y)
    [pscustomobject]@{ X0 = [Math]::Max(0, $X - 24); Y0 = [Math]::Max(0, $Y - 40); X1 = [Math]::Min($SCREEN_W, $X + 64); Y1 = [Math]::Min($PF_H, $Y + 72) }
}

# Explored map near the Nexus, far from every park.
$AWAY = [pscustomobject]@{ X = 400; Y = 120 }

$parks = @(
    [pscustomobject]@{ X = 1100; Y = 200 },
    [pscustomobject]@{ X = 700;  Y = 360 },
    [pscustomobject]@{ X = 252;  Y = 600 }
)

try {
    Write-Host 'probe-fog: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '145-fogcursor'

    Write-Host 'probe-fog: generating the fixture (one Nexus, explored start, black beyond its sight)'
    $fixtures = New-ScNexusFixture -RepoRoot $repoRoot -FixtureDir $FixtureDir -MapName $mapName -Noun 'probe-fog'

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    Write-Host 'probe-fog: launching (stage 3, cnc-ddraw, widen, marker trace armed)'
    $env:SCPLUGIN_MARKTRACE = '1'
    $gamePid = Start-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -LogPath $log -FrameDir $FrameDir `
        -WindowedHelperDll $WindowedHelperDll -Noun 'probe-fog'
    $h = Connect-ScWideGame -GamePid $gamePid -LogPath $log -ScreenW $SCREEN_W -ScreenH $SCREEN_H
    Assert-True 'the dirty-marker trace hook is armed' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'MARKTRACE: armed' }).Count -gt 0)

    Write-Host 'probe-fog: walking to a loaded game'
    Enter-ScCustomGame -Hwnd $h -LogPath $log -Fixtures $fixtures -MapPath $mapPath -GameDir $GameDir -ActivationNudge -Noun 'probe-fog'

    Send-ScMouseMove -Hwnd $h -X $AWAY.X -Y $AWAY.Y -DelayMs 300
    Start-Sleep -Milliseconds 700
    $base = Get-Dump -Tag 'fog-base'
    Assert-True 'baseline buffer dump with its camera position' ($null -ne $base.Path) "($($base.Path) cam=$($base.Cam.X),$($base.Cam.Y))"

    $i = 0
    $worst = 0
    foreach ($p in $parks) {
        $i++
        $r = Get-ParkRect -X $p.X -Y $p.Y
        $blackBefore = 1 - (Get-DumpBand -Dump $base.Path -X0 $r.X0 -X1 $r.X1 -Y0 $r.Y0 -Y1 $r.Y1).Frac
        Set-ScMarker -MarkerPath $markerPath -Label 'marktrace-on'
        Start-Sleep -Milliseconds 400
        Send-ScMouseMove -Hwnd $h -X $p.X -Y $p.Y -DelayMs 400
        $in = Get-Dump -Tag "p$i-in"
        Start-Sleep -Milliseconds 300
        Send-ScMouseMove -Hwnd $h -X $AWAY.X -Y $AWAY.Y -DelayMs 0
        $out0 = Get-Dump -Tag "p$i-out0"
        Start-Sleep -Milliseconds 1000
        $out1 = Get-Dump -Tag "p$i-out1"
        Start-Sleep -Milliseconds 3000
        $out3 = Get-Dump -Tag "p$i-out3"
        Set-ScMarker -MarkerPath $markerPath -Label 'marktrace-off'
        Start-Sleep -Milliseconds 400
        $line = "park $i at ($($p.X),$($p.Y)) black-before=${blackBefore}:"
        foreach ($d in @($in, $out0, $out1, $out3)) {
            $md = Get-MapDiff -A $base -B $d -X0 $r.X0 -Y0 $r.Y0 -X1 $r.X1 -Y1 $r.Y1
            $line += " $($d.Tag) gained=$($md.Gained) lost=$($md.Lost) drift=$($md.Drift) |"
            if ($blackBefore -gt 0.5 -and $md.Gained -gt $worst) { $worst = $md.Gained }
        }
        Report-Finding $line
        $marks = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'MARKTRACE off: marks=' }) | Select-Object -Last 1
        Report-Finding "park $i trace: $($marks -replace '^\[[^\]]+\]\s*','')"
    }
    Assert-True 'a resting cursor leaves the unexplored map black around it (gained <= 32 px in every dump, map space)' ($worst -le 32) "(worst gained=$worst)"

    $completed = $true
}
catch {
    Write-ScStepFailure -Err $_ -What 'a probe step'
}
finally {
    Remove-Item Env:SCPLUGIN_MARKTRACE -ErrorAction SilentlyContinue
    Stop-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -GamePid $gamePid -KeepOpen:$KeepOpen -Fixtures $fixtures -LaunchLock $launchLock
}

Write-Host ''
if ($script:findings.Count) { Write-Host 'probe-fog: FINDINGS:'; $script:findings | ForEach-Object { Write-Host "  - $_" } }
Write-Host ''
if (-not $completed) { Write-Host "probe-fog: INCOMPLETE -- the run did not reach its end; $script:failures failure(s) so far"; exit 1 }
elseif ($script:failures -gt 0) { Write-Host "probe-fog: FAIL ($script:failures failure(s)) -- a resting cursor changes the fogged buffer"; exit 1 }
else { Write-Host 'probe-fog: PASS (0 failures) -- a resting cursor leaves the unexplored map black'; exit 0 }
