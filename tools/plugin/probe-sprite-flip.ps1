#Requires -Version 7
<#
.SYNOPSIS
Does the partial redraw flip overlapping sprites in cells nothing marked? The
engine repaints every sprite that touches a dirty 16x16 cell over its WHOLE rect
(0x00497CE0 after 0x00497000 finds one set cell), so a lower-order sprite lands
on top of a higher one wherever the two overlap outside the dirty cells -- the
mineral line under a passing cursor. The dirty-marker and image-mark traces (MARK and IMRK lines) say
which cells the engine marked; the buffer dump says which pixels changed; any
change outside every mark is the flip, and its bbox is the finding.

The posted cursor sweeps four horizontal lines across the base; the buffer is
dumped settled before the sweep and after each line, and each consecutive pair
is judged with frame-capture.py unmarked-diff over the marks logged between them.

.PARAMETER FullRedraw
Passed through as %SCPLUGIN_FULLREDRAW%: 1 arms the plugin's whole-frame
recompose (the fix), 0 leaves the stock partial redraw so the oracle can be
watched failing first.

.EXAMPLE
$env:AGENT_TASK = '157'; ./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-sprite-flip.ps1
.EXAMPLE
./tools/plugin/probe-sprite-flip.ps1 -FullRedraw 0   # the negative control: expect FINDINGS
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\157',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\157-frames',
    [string]$WindowedHelperDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    [int]$FullRedraw = 1,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot; $repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
foreach ($f in 'drive-game', 'sc-launch-lock', 'sc-suite', 'sc-wsprobe', 'sc-oracle-guard') { . (Join-Path $scriptDir "$f.ps1") }

$ws = Get-ScWideGeometry
$SCREEN_W = $ws.W; $SCREEN_H = $ws.H; $STOCK_H = $ws.StockH
$PF_H = $STOCK_H - 80 + $ws.ConsoleShiftY

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t157' -Suite 'spriteflip' }
$mapName = 'spriteflip.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$log = Join-Path $LogDir '157-spriteflip.log'
Initialize-ScWsProbe -LogDir $LogDir -FrameDir $FrameDir

$NEXUS_TYPE = 0x9A
# The sweep: x from 20 to 1100 in 40 px steps, four lines relative to the Nexus. The
# fixture's mineral clusters sit above and left of the Nexus, so the lines start high
# and the sweep starts at the left edge.
$SWEEP_X = 20..1100 | Where-Object { ($_ - 20) % 40 -eq 0 }
$LINE_DY = @(-180, -110, -50, 10)
$MARK_PAD = 2
# An animated image's show/hide mark is its rect at that moment; a geyser's smoke puff
# then rises a further ~20 px through frames the full redraw never marks, so the
# run-wide image marks are grown by this much before they mask a pair.
$ANIM_PAD = 24
# Far from the base and from every sweep line, so the parked cursor marks nothing there.
$AWAY = [pscustomobject]@{ X = 40; Y = 40 }

# A dump that must come back with both halves, or a pair cannot be judged.
function Get-Dump {
    param([string]$Tag)
    $d = Get-ScBufferDump -LogPath $log -MarkerPath $markerPath -Tag $Tag
    if (-not ($d.Path -and $d.Cam)) { throw "probe-flip: dump '$Tag' came back without a path or a camera (path=$($d.Path))." }
    $d
}

# Every rect the engine marked between two dumps, as `x1,y1,x2,y2` lines: the MARK
# (dirty marker) and IMRK (image-rect mark: animation, movement) lines logged between
# the two FRAMEDUMP lines.
function Get-MarksBetween {
    param([string]$TagA, [string]$TagB)
    $lines = @(Get-Content -LiteralPath $log)
    $ia = ($lines | Select-String -Pattern "FRAMEDUMP \[$([regex]::Escape($TagA))\] " | Select-Object -Last 1).LineNumber
    $ib = ($lines | Select-String -Pattern "FRAMEDUMP \[$([regex]::Escape($TagB))\] " | Select-Object -Last 1).LineNumber
    if (-not $ia -or -not $ib -or $ib -le $ia) { throw "probe-flip: no FRAMEDUMP span $TagA -> $TagB in the log ($ia, $ib)." }
    @($lines[$ia..($ib - 1)] | ForEach-Object {
        if ($_ -match '(?:MARK|IMRK) rect=\((-?\d+),(-?\d+)\)-\((-?\d+),(-?\d+)\)') { "$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4])" }
    })
}

# Every image-rect mark of the whole run, grown by $ANIM_PAD: the animated images'
# footprints (a geyser's smoke, a building's glow). With the full redraw pending the
# draw skips the per-frame animation marks, so a pair's own span may miss them; the
# show/hide marks over the run cover the same footprints, and the union masks every pair.
function Get-ImageMarksAll {
    @(Get-Content -LiteralPath $log | ForEach-Object {
        if ($_ -match 'IMRK rect=\((-?\d+),(-?\d+)\)-\((-?\d+),(-?\d+)\)') {
            "$([int]$Matches[1] - $ANIM_PAD),$([int]$Matches[2] - $ANIM_PAD),$([int]$Matches[3] + $ANIM_PAD),$([int]$Matches[4] + $ANIM_PAD)"
        }
    } | Sort-Object -Unique)
}

# Changed pixels of the playfield split by whether a padded mark covers them.
function Get-UnmarkedDiff {
    param($A, $B, [string]$MarksPath)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') unmarked-diff --a $A.Path --b $B.Path `
        --marks $MarksPath --pad $MARK_PAD --y1 $PF_H 2>&1
    $r = [ordered]@{ Total = -1; Marked = -1; Unmarked = -1; Bbox = '?'; MarksN = -1 }
    foreach ($l in $out) {
        if ("$l" -match '^changed_total=(\d+)$') { $r.Total = [int]$Matches[1] }
        if ("$l" -match '^marked_changed=(\d+)$') { $r.Marked = [int]$Matches[1] }
        if ("$l" -match '^unmarked_changed=(\d+)$') { $r.Unmarked = [int]$Matches[1] }
        if ("$l" -match '^unmarked_bbox=(.+)$') { $r.Bbox = $Matches[1] }
        if ("$l" -match '^marks_n=(\d+)$') { $r.MarksN = [int]$Matches[1] }
    }
    [pscustomobject]$r
}

# One consecutive pair: the marks between the dumps go to a marks file, and every
# changed playfield pixel must lie under one of them.
function Assert-PairUnmarked {
    param($A, $B)
    $marksPath = Join-Path $LogDir "marks-$($A.Tag)-$($B.Tag).txt"
    $marks = @(Get-MarksBetween -TagA $A.Tag -TagB $B.Tag)
    $anim = @(Get-ImageMarksAll)
    Set-Content -LiteralPath $marksPath -Value (@("# $($A.Tag) -> $($B.Tag) (+ $($anim.Count) run-wide image marks, grown by $ANIM_PAD)"; $marks; $anim) -join "`n")
    $u = Get-UnmarkedDiff -A $A -B $B -MarksPath $marksPath
    $pair = "$($A.Tag)->$($B.Tag)"
    $camA = "$($A.Cam.X),$($A.Cam.Y)"; $camB = "$($B.Cam.X),$($B.Cam.Y)"
    Assert-True "$pair camera unchanged (screen-space marks are comparable)" (-not (Test-ScChanged $camA $camB)) "($camA -> $camB)"
    Assert-True "$pair the engine marked cells in between" (Test-ScReached $marks.Count) "(marks=$($marks.Count))"
    # No "the dumps differ" guard: the buffer is cursor-free (save-under before the
    # present, restore after), so a sweep over a still scene may legitimately leave
    # two identical dumps; the marks count is what proves the sweep happened.
    Assert-True "$pair no pixel changed outside every padded mark" ($u.Unmarked -eq 0) "(unmarked=$($u.Unmarked) bbox=$($u.Bbox) total=$($u.Total))"
    if ($u.Unmarked -gt 0) { Report-Finding "$pair $($u.Unmarked) px changed in cells no mark covers, bbox=$($u.Bbox) (marks=$($marks.Count), marked=$($u.Marked))" }
}

$stepError = $null
try {
    Write-Host 'probe-flip: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '157-spriteflip'

    Write-Host 'probe-flip: generating the fixture (one Nexus at a stock start location with its mineral line)'
    $fixtures = New-ScNexusFixture -RepoRoot $repoRoot -FixtureDir $FixtureDir -MapName $mapName -Noun 'probe-flip' -ClearCritters

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    Write-Host "probe-flip: launching (stage 3, cnc-ddraw, widen, marker trace armed, full redraw=$FullRedraw)"
    $env:SCPLUGIN_MARKTRACE = '1'
    $env:SCPLUGIN_FULLREDRAW = "$FullRedraw"
    $gamePid = Start-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -LogPath $log -FrameDir $FrameDir `
        -WindowedHelperDll $WindowedHelperDll -Noun 'probe-flip'
    $h = Connect-ScWideGame -GamePid $gamePid -LogPath $log -ScreenW $SCREEN_W -ScreenH $SCREEN_H
    Assert-True 'the dirty-marker trace hook is armed' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'MARKTRACE: armed' }).Count -gt 0)
    @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'FULLREDRAW' }) | ForEach-Object { Write-Host "       $_" }

    Write-Host 'probe-flip: walking to a loaded game'
    Walk-ToScGame -Hwnd $h -LogPath $log -Fixtures $fixtures -MapPath $mapPath -GameDir $GameDir -Noun 'probe-flip'

    $world = Get-ScWorldState -LogPath $log -Tag 'aim' -MarkerPath $markerPath
    $nexus = @($world.Units | Where-Object { $_.Owner -eq 0 -and $_.Type -eq $NEXUS_TYPE }) | Select-Object -First 1
    Assert-True 'the fixture Nexus and the viewport are in the WORLD scan' ($null -ne $nexus -and $null -ne $world.Screen)
    $nx = $nexus.X - $world.Screen.Left; $ny = $nexus.Y - $world.Screen.Top
    Assert-True 'the Nexus is on the playfield' ($nx -ge 0 -and $nx -lt $SCREEN_W -and $ny -ge 0 -and $ny -lt $PF_H) "(screen $nx,$ny)"
    $lineYs = @($LINE_DY | ForEach-Object { [Math]::Min($PF_H - 8, [Math]::Max(8, $ny + $_)) })
    Write-Host "probe-flip: Nexus at screen ($nx,$ny); sweep lines y=$($lineYs -join ',')"

    Send-ScMouseMove -Hwnd $h -X $AWAY.X -Y $AWAY.Y -DelayMs 300
    Set-ScMarker -MarkerPath $markerPath -Label 'marktrace-on'
    Start-Sleep -Milliseconds 700
    $dumps = @(Get-Dump -Tag 'flip-base')
    # An idle second first: the only changes must be animation, under the image marks.
    Start-Sleep -Milliseconds 1000
    $dumps += Get-Dump -Tag 'flip-idle'

    $i = 0
    foreach ($y in $lineYs) {
        $i++
        foreach ($x in $SWEEP_X) { Send-ScMouseMove -Hwnd $h -X $x -Y $y -DelayMs 120 }
        # Settle before the dump so no mark of the sweep races the FRAMEDUMP line.
        Start-Sleep -Milliseconds 700
        $dumps += Get-Dump -Tag "flip-line$i"
    }
    Set-ScMarker -MarkerPath $markerPath -Label 'marktrace-off'
    Start-Sleep -Milliseconds 400
    # Judged after the trace closed, so every pair sees the run-wide image marks.
    for ($k = 1; $k -lt $dumps.Count; $k++) { Assert-PairUnmarked -A $dumps[$k - 1] -B $dumps[$k] }
}
catch { $stepError = $_ }
finally {
    Remove-Item Env:SCPLUGIN_MARKTRACE, Env:SCPLUGIN_FULLREDRAW -ErrorAction SilentlyContinue
    Stop-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -GamePid $gamePid -KeepOpen:$KeepOpen -Fixtures $fixtures -LaunchLock $launchLock
}
if ($stepError) { Write-ScStepFailure -Err $stepError -What 'a probe step' }
# The trace totals survive the close-down in the log: the per-caller MARK counts.
$trace = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'MARKTRACE off: marks=' }) | Select-Object -Last 1
Write-Host "       trace: $($trace -replace '^\[[^\]]+\]\s*','')"

Write-Host ''
$script:findings | ForEach-Object { Write-Host "  - FINDING: $_" }
$verdict = if ($stepError) { "INCOMPLETE -- the run did not reach its end; $script:failures failure(s) so far" }
    elseif ($script:failures -gt 0) { "FAIL ($script:failures failure(s)) -- sprites changed in cells the engine never marked" }
    else { 'PASS (0 failures) -- every buffer change lies under a marked cell' }
Write-Host "`nprobe-flip: $verdict"
exit [int]($verdict -notmatch '^PASS')
