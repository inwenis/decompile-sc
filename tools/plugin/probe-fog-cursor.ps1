#Requires -Version 7
<#
.SYNOPSIS
Does a resting cursor over UNEXPLORED map paint terrain into the buffer? Three
parks; around each the dirty-marker trace is armed (MARK lines: every rect the
engine marks, with its caller), the buffer is dumped while parked and at 0 s,
1 s and 3 s after the cursor leaves, and each dump is compared with the
baseline in MAP space over the cursor's footprint.

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

$ws = Get-ScWideGeometry
$SCREEN_W = $ws.W; $SCREEN_H = $ws.H; $STOCK_W = $ws.StockW; $STOCK_H = $ws.StockH
$SHIFT_Y = $ws.ConsoleShiftY
$PF_H = $STOCK_H - 80 + $SHIFT_Y

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t145' -Suite 'fogcursor' }
$mapName = 'fogcursor.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$log = Join-Path $LogDir '145-fogcursor.log'

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

# One buffer dump plus the camera position the same marker's WORLD scan reports.
function Get-BufferDump {
    param([string]$Tag)
    $from = Get-ScLogLineCount -LogPath $log
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    $lines = Wait-ScLogMatch -LogPath $log -Pattern "FRAMEDUMP \[$([regex]::Escape($Tag))\] " -TimeoutSec 20 -FromLine $from
    $path = $null
    foreach ($l in $lines) {
        if ($l -match 'FRAMEDUMP \[[^\]]+\] w=\d+ h=\d+ bytes=\d+ reads=\d+ stable=\d path=(.+)$') { $path = $Matches[1].Trim() }
    }
    $cam = $null
    $w = @(Get-Content -LiteralPath $log | Select-Object -Skip $from | Where-Object { $_ -match "WORLD \[$([regex]::Escape($Tag))\] screen=\((-?\d+),(-?\d+)\)" }) | Select-Object -First 1
    if ($w -and $w -match 'screen=\((-?\d+),(-?\d+)\)') { $cam = [pscustomobject]@{ X = [int]$Matches[1]; Y = [int]$Matches[2] } }
    if (-not $path -or -not $cam) { throw "probe-fog: dump '$Tag' came back without a path or a camera (path=$path)." }
    [pscustomobject]@{ Tag = $Tag; Path = $path; Cam = $cam }
}
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

function Walk-ToGame {
    $env:SCDRIVE_POST_ACTIVATE = '1'
    if (-not (Wait-ScDialog -LogPath $log -Name 'MainMenu' -TimeoutSec 30)) { throw 'probe-fog: main menu never appeared.' }
    Start-Sleep -Seconds 3
    if (-not (Click-UntilDialog -X 215 -Y 119 -Name 'Delete')) { throw 'probe-fog: Original/Expansion chooser never appeared.' }
    Send-ScClick -Hwnd $h -X 373 -Y 300; Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $h -X 75 -Y 111
    if (-not (Click-UntilDialog -X 516 -Y 392 -Name 'RaceSelection' -WaitSec 15)) { throw 'probe-fog: RaceSelection never appeared.' }
    if (-not (Click-UntilDialog -X 327 -Y 415 -Name 'Create' -WaitSec 15)) { throw 'probe-fog: map browser never appeared.' }
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
    if (-not (Test-Path -LiteralPath $WindowedHelperDll)) { throw "probe-fog: $WindowedHelperDll not found; run fetch-cnc-ddraw.ps1." }

    Write-Host 'probe-fog: generating the fixture (one Nexus, explored start, black beyond its sight)'
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount 1 -UnitType 'nexus' -Player 0 -ClearPlayerUnits -Race 'protoss' `
        -StartingMinerals 500 -StartingGas 0 -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }
    if (-not (Test-Path -LiteralPath $mapPath)) { throw 'probe-fog: the fixture was never generated.' }

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    Write-Host 'probe-fog: launching (stage 3, cnc-ddraw, widen, marker trace armed)'
    $env:SCPLUGIN_MARKTRACE = '1'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -WorldScan 1 -NoLaunchLock `
        -Widescreen 1 -WidescreenStage 3 -StormPresent widen `
        -FrameDump $FrameDir `
        -Windowed -WindowedHelperDll $WindowedHelperDll `
        -GameDir $GameDir -LogPath $log 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe-fog: could not parse the game pid.' }
    $h = Get-ScGameWindow -ProcessId $gamePid
    Start-Sleep -Seconds 3

    Assert-True 'the widescreen table is ACTIVE with 0 refused' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'WIDESCREEN ACTIVE' -and $_ -match ', 0 refused' }).Count -gt 0)
    Assert-True 'the dirty-marker trace hook is armed' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'MARKTRACE: armed' }).Count -gt 0)
    $client = Get-ScClientSize -Hwnd $h
    Assert-True "cnc-ddraw presents a $($SCREEN_W)x$($SCREEN_H) client area" ($client.Width -eq $SCREEN_W -and $client.Height -eq $SCREEN_H) "(got $($client.Width)x$($client.Height))"

    Write-Host 'probe-fog: walking to a loaded game'
    Walk-ToGame

    Send-ScMouseMove -Hwnd $h -X $AWAY.X -Y $AWAY.Y -DelayMs 300
    Start-Sleep -Milliseconds 700
    $base = Get-BufferDump -Tag 'fog-base'
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
        $in = Get-BufferDump -Tag "p$i-in"
        Start-Sleep -Milliseconds 300
        Send-ScMouseMove -Hwnd $h -X $AWAY.X -Y $AWAY.Y -DelayMs 0
        $out0 = Get-BufferDump -Tag "p$i-out0"
        Start-Sleep -Milliseconds 1000
        $out1 = Get-BufferDump -Tag "p$i-out1"
        Start-Sleep -Milliseconds 3000
        $out3 = Get-BufferDump -Tag "p$i-out3"
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
    $script:failures++
    Write-Host "  FAIL a step threw: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
}
finally {
    Remove-Item Env:SCDRIVE_POST_ACTIVATE -ErrorAction SilentlyContinue
    Remove-Item Env:SCPLUGIN_MARKTRACE -ErrorAction SilentlyContinue
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  warn close-game: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
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
if ($script:findings.Count) { Write-Host 'probe-fog: FINDINGS:'; $script:findings | ForEach-Object { Write-Host "  - $_" } }
Write-Host ''
if (-not $completed) { Write-Host "probe-fog: INCOMPLETE -- the run did not reach its end; $script:failures failure(s) so far"; exit 1 }
elseif ($script:failures -gt 0) { Write-Host "probe-fog: FAIL ($script:failures failure(s)) -- a resting cursor changes the fogged buffer"; exit 1 }
else { Write-Host 'probe-fog: PASS (0 failures) -- a resting cursor leaves the unexplored map black'; exit 0 }
