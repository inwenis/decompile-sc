#Requires -Version 7
<#
.SYNOPSIS
Reads the renderer's own layout out of a running StarCraft, so research/renderer-viewport.md
rests on a measurement and not only on a disassembly.
.DESCRIPTION
The renderer has no public prior art a static map could be checked against
(research/prior-art.md 9), so this probe reads the live screen Bitmap 0x006CEFF0, the eight
graphic layers 0x006CEF50 in draw order as static VAs comparable against sc_addresses.h, and
the viewport origin and scroll maxima beside what the document's reading of 0x0049BB90
predicts, so a wrong reading is a mismatch here rather than surviving into research/.
It reads twice because one in-game reading cannot tell "layer 5 is the playfield" from
"layer 5 is always like that", and the menu/in-game pair can. -Mode observe keeps the whole
probe read-only: no hooks, no writes to game memory, no patch to StarCraft.exe on disk.

.EXAMPLE
./tools/plugin/probe-screen-layout.ps1

.EXAMPLE
./tools/plugin/probe-screen-layout.ps1 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    # This run's own fixture folder, one folder per run (AGENTS.md § "Test fixtures").
    [string]$FixtureDir,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
. (Join-Path $scriptDir 'sc-wsprobe.ps1')

if (-not $FixtureDir) { $FixtureDir = Join-Path $GameDir 'Maps\BroodWar\00-t032' }
# Named for the suite: two suites generating the same filename make "delete only your own
# file" undecidable.
$mapName = 'screen-layout.scx'
$mapPath = Join-Path $FixtureDir $mapName
$logPath = Join-Path $LogDir '032-screen-layout.log'
$markerPath = Join-Path $LogDir 'marker.txt'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
foreach ($p in @($logPath, $markerPath)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}

$failures = 0
$gamePid = 0
$launchLock = $null
$fixtures = $null
$readings = @{}

# What sc_addresses.h says each layer's draw callback is, from the writer of its +0x10 slot.
# Printed beside the live value so agreement or disagreement is visible without a lookup.
$EXPECTED_DRAW = @{
    0 = '0x004BDFA0'; 1 = '0x004810F0'; 2 = '0x0041CB50'; 3 = '0x0048D5C0'
    4 = '0x0048D5C0'; 5 = '0x004BD580'; 6 = '(none)';     7 = '(none)'
}

# The marker is how a reading is synchronised: the driver says "look now" and waits for the
# log line carrying its own tag, so there is no polling race.
function Read-ScreenLayout {
    param([Parameter(Mandatory)][string]$Tag)

    $from = Get-ScLogLineCount -LogPath $logPath
    # Set-ScMarker, not Set-Content: Set-Content opens the marker with FileShare.None and
    # therefore throws whenever the plugin's observer has it open.
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    # Ten lines land per marker (bitmap + 8 layers + viewport); wait for the LAST of them,
    # the viewport line, so a partially-written set is never parsed.
    Wait-ScLogMatch -LogPath $logPath -Pattern "SCREEN \[$Tag\] origin=" -TimeoutSec 30 -FromLine $from | Out-Null
    $lines = @(Get-Content -LiteralPath $logPath | Select-Object -Skip $from |
               Where-Object { $_ -match "SCREEN \[$Tag\]" })

    $r = @{ Tag = $Tag; Layers = @(); Bitmap = $null; Viewport = $null; Lines = $lines }
    foreach ($l in $lines) {
        if ($l -match 'bitmap@(0x[0-9A-Fa-f]+) w=(\d+) h=(\d+) data=(0x[0-9A-Fa-f]+) bytes=(\d+)') {
            $r.Bitmap = @{ At = $Matches[1]; W = [int]$Matches[2]; H = [int]$Matches[3]
                           Data = $Matches[4]; Bytes = [int]$Matches[5] }
        }
        elseif ($l -match 'layer=(\d+) used=(\d+) flags=(0x[0-9A-Fa-f]+) rect=\((-?\d+),(-?\d+) (\d+)x(\d+)\) param=(0x[0-9A-Fa-f]+) draw=(0x[0-9A-Fa-f]+) drawStatic=(0x[0-9A-Fa-f]+)') {
            $r.Layers += [pscustomobject]@{
                Index = [int]$Matches[1]; Used = [int]$Matches[2]; Flags = $Matches[3]
                Left = [int]$Matches[4]; Top = [int]$Matches[5]
                Width = [int]$Matches[6]; Height = [int]$Matches[7]
                Param = $Matches[8]; Draw = $Matches[9]; DrawStatic = $Matches[10]
            }
        }
        elseif ($l -match 'origin=\((\d+),(\d+)\) tile=\((\d+),(\d+)\) map=(\d+)x(\d+) tiles \((\d+)x(\d+) px\) scrollMax=\((-?\d+),(-?\d+)\) predicted=\((-?\d+),(-?\d+)\) match=(\d)') {
            $r.Viewport = @{
                OriginX = [int]$Matches[1]; OriginY = [int]$Matches[2]
                TileX = [int]$Matches[3]; TileY = [int]$Matches[4]
                MapTileW = [int]$Matches[5]; MapTileH = [int]$Matches[6]
                MapPxW = [int]$Matches[7]; MapPxH = [int]$Matches[8]
                MaxX = [int]$Matches[9]; MaxY = [int]$Matches[10]
                PredX = [int]$Matches[11]; PredY = [int]$Matches[12]
                Match = ([int]$Matches[13] -eq 1)
            }
        }
    }
    $r
}

function Show-ScreenLayout {
    param($R)
    Write-Host ""
    Write-Host "  ---- $($R.Tag) ----"
    if ($R.Bitmap) {
        Write-Host ("       screen Bitmap @{0}: {1}x{2}, data={3}, {4} bytes" -f
                    $R.Bitmap.At, $R.Bitmap.W, $R.Bitmap.H, $R.Bitmap.Data, $R.Bitmap.Bytes)
    } else { Write-Host '       screen Bitmap: NOT READ' }
    foreach ($l in $R.Layers) {
        $exp = $EXPECTED_DRAW[$l.Index]
        # A null callback is a MISMATCH only where the layer is in use: at the main menu the
        # playfield and placement layers are legitimately absent, so that must not print as
        # a failure.
        $agree = if ($l.Draw -eq '0x00000000') {
                     if ($exp -eq '(none)') { 'unused, as documented' }
                     elseif ($l.Used -eq 0) { "not installed in this state (doc $exp)" }
                     else { "MISMATCH -- in use but no callback (doc $exp)" }
                 }
                 elseif ($l.DrawStatic -ieq $exp) { 'matches doc' }
                 else { "MISMATCH (doc $exp)" }
        Write-Host ("       layer {0} used={1} flags={2} rect=({3},{4} {5}x{6}) draw={7} [{8}]" -f
                    $l.Index, $l.Used, $l.Flags, $l.Left, $l.Top, $l.Width, $l.Height,
                    $l.DrawStatic, $agree)
    }
    if ($R.Viewport) {
        $v = $R.Viewport
        Write-Host ("       viewport origin=({0},{1}) tile=({2},{3}) map={4}x{5} tiles ({6}x{7} px)" -f
                    $v.OriginX, $v.OriginY, $v.TileX, $v.TileY, $v.MapTileW, $v.MapTileH, $v.MapPxW, $v.MapPxH)
        Write-Host ("       scrollMax=({0},{1}) predicted (mapTiles-20/-12)*32=({2},{3}) match={4}" -f
                    $v.MaxX, $v.MaxY, $v.PredX, $v.PredY, $v.Match)
    }
}

$step = 0

try {
    # Take the lock BEFORE generating anything: a fixture folder of mine, even an empty one,
    # pushes every entry below it down a row in every other worker's map browser, so it must
    # exist for as little of the run as possible (AGENTS.md § "Test fixtures").
    Write-Host 'probe-screen-layout: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '032-screen-layout'

    Write-Host 'probe-screen-layout: generating the fixture'
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $genArgs = @{ UnitCount = 1; UnitType = 'marine'; Player = 0; Race = 'terran'; OutputPath = $mapPath }
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }

    Write-Host 'probe-screen-layout: launching (observe mode, read-only, ScreenScan on)'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode observe -ScreenScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $logPath 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe-screen-layout: could not parse the game pid from scinject output.' }
    $h = Get-ScGameWindow -ProcessId $gamePid
    Start-Sleep -Seconds 3

    # At the main menu the video init has run, so the screen Bitmap and the layer block
    # exist, but the playfield layer is not installed.
    $readings['menu'] = Read-ScreenLayout -Tag 'menu'
    Show-ScreenLayout $readings['menu']

    # The clicks below are menu buttons; the map-browser row itself is computed from the
    # filesystem by Select-ScBrowserMap, never a fixed row (AGENTS.md § "Map browser").
    Write-Host ''
    Write-Host 'probe-screen-layout: walking to a loaded game'
    Send-ScClick -Hwnd $h -X 215 -Y 119
    Send-ScClick -Hwnd $h -X 373 -Y 300
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $h -X 75  -Y 111
    Send-ScClick -Hwnd $h -X 516 -Y 392
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $h -X 327 -Y 415
    Start-Sleep -Seconds 2
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $mapPath | Out-Null
    Assert-ScGameType -LogPath $logPath
    Send-ScClick -Hwnd $h -X 516 -Y 393
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $h -X 544 -Y 387
    Start-Sleep -Seconds 10
    Dismiss-ScTipsDialog -Hwnd $h -LogPath $logPath | Out-Null
    Start-Sleep -Seconds 3

    $readings['ingame'] = Read-ScreenLayout -Tag 'ingame'
    Show-ScreenLayout $readings['ingame']

    Write-Host ''
    Write-Host 'probe-screen-layout: assertions'
    $m = $readings['menu']; $g = $readings['ingame']

    Assert-True 'screen Bitmap reads 640x480' `
        ($null -ne $g.Bitmap -and $g.Bitmap.W -eq 640 -and $g.Bitmap.H -eq 480) `
        "(got $($g.Bitmap.W)x$($g.Bitmap.H))"
    Assert-True 'screen Bitmap data pointer is non-null (the SMemAlloc from 0x004DB060)' `
        ($null -ne $g.Bitmap -and $g.Bitmap.Data -ne '0x00000000') "(got $($g.Bitmap.Data))"
    Assert-True 'buffer is width*height bytes = 307200' `
        ($null -ne $g.Bitmap -and $g.Bitmap.Bytes -eq 307200) "(got $($g.Bitmap.Bytes))"
    Assert-True 'all eight layer records were readable' ($g.Layers.Count -eq 8) "(got $($g.Layers.Count))"

    $l5 = $g.Layers | Where-Object Index -eq 5
    Assert-True 'layer 5 is 640x400 at (0,0) -- the playfield/HUD seam' `
        ($null -ne $l5 -and $l5.Width -eq 640 -and $l5.Height -eq 400 -and $l5.Left -eq 0 -and $l5.Top -eq 0) `
        "(got ($($l5.Left),$($l5.Top) $($l5.Width)x$($l5.Height)))"
    Assert-True 'layer 5 draw callback is 0x004BD580' ($null -ne $l5 -and $l5.DrawStatic -ieq '0x004BD580') `
        "(got $($l5.DrawStatic))"

    $l2 = $g.Layers | Where-Object Index -eq 2
    Assert-True 'layer 2 (dialogs) is 640x480' `
        ($null -ne $l2 -and $l2.Width -eq 640 -and $l2.Height -eq 480) `
        "(got $($l2.Width)x$($l2.Height))"

    # The positive half of the menu/in-game pair: the claim is not just "layer 5 is the
    # playfield in game", it is "layer 5 is the playfield BECAUSE it appears when a game
    # loads". An absence is only worth something next to the presence it contrasts with
    # (AGENTS.md § "Oracles: absence and defect-era checks").
    $m5 = $m.Layers | Where-Object Index -eq 5
    Assert-True 'layer 5 is NOT installed at the main menu, and IS in game' `
        ($null -ne $m5 -and $null -ne $l5 -and $m5.Used -eq 0 -and $l5.Used -ne 0) `
        "(menu used=$($m5.Used), in-game used=$($l5.Used))"

    Assert-True 'layers 6 and 7 carry no draw callback in either reading' `
        (@($m.Layers + $g.Layers | Where-Object { $_.Index -ge 6 -and $_.Draw -ne '0x00000000' }).Count -eq 0)

    $v = $g.Viewport
    Assert-True 'the scroll maxima match (mapTiles - viewportTiles) * 32 (+8 on y)' `
        ($null -ne $v -and $v.Match) `
        "(max=($($v.MaxX),$($v.MaxY)) predicted=($($v.PredX),$($v.PredY)) on a $($v.MapTileW)x$($v.MapTileH)-tile map)"
    Assert-True 'the tile-granular origin is the pixel origin >> 5' `
        ($null -ne $v -and $v.TileX -eq [math]::Floor($v.OriginX / 32) -and $v.TileY -eq [math]::Floor($v.OriginY / 32)) `
        "(origin=($($v.OriginX),$($v.OriginY)) tile=($($v.TileX),$($v.TileY)))"

    # Observe mode installing a hook would invalidate every "read-only" claim in the
    # document. Proved POSITIVE first -- the log must show the mode line at all -- then
    # absent.
    $modeLines = @(Get-Content -LiteralPath $logPath | Where-Object { $_ -match 'mode\s+:\s+observe' })
    Assert-True 'the log positively reports observe mode' ($modeLines.Count -gt 0)
    $hookLines = @(Get-Content -LiteralPath $logPath | Where-Object { $_ -match 'HOOK .*installed' })
    Assert-True 'no hook was installed' ($hookLines.Count -eq 0) "(found $($hookLines.Count))"
}
catch {
    Write-Host "  FAIL probe: $($_.Exception.Message)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game: $($_.Exception.Message)"; $failures++ }
        Start-Sleep -Seconds 2
    }
    # Only this run's own declared fixture, on every path (AGENTS.md § "Test fixtures").
    if ($fixtures) {
        try { Remove-ScOwnFixture -Run $fixtures | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
        # -Dir, not -Run: it deletes the folder only if it is EMPTY, which is why it takes a
        # path rather than the run record.
        try { Remove-ScOwnFixtureDir -Dir $fixtures.Dir | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
    }
    if ($launchLock) { try { Exit-ScLaunchLock -Lock $launchLock } catch { } }
}

Write-Host ''
if ($failures -eq 0) { Write-Host 'probe-screen-layout: PASS (0 failures)' }
else { Write-Host "probe-screen-layout: FAIL ($failures failures)" }
exit ($failures -gt 0 ? 1 : 0)
