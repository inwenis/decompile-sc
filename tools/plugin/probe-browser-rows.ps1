#Requires -Version 7
<#
.SYNOPSIS
Prove in the live game that the map browser opens a row computed from the filesystem, and
that the harness can tell WHICH folder it opened, with a decoy fixture folder present.

.DESCRIPTION
The decoy sorts FIRST and holds a map of a DIFFERENT unit type, so a fixed row-1 click
lands on it and the run boxes somebody else's units while reporting internally consistent
nonsense. The claim that cannot be argued with is the world scan: it holds this fixture's
unit type and none of the decoy's. The maps are game content, generated for the run and
deleted afterwards, never committed (AGENTS.md § "Hard rules").

.EXAMPLE
./tools/plugin/probe-browser-rows.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs\023',
    # This run's own folder, and the decoy that sorts before it.
    [string]$MyFolder = '00-t023',
    [string]$DecoyFolder = '00-t000',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

$LURKER_TYPE = 0x67
$MARINE_TYPE = 0x00

$mapsRoot  = Join-Path $GameDir 'Maps'
$broodWar  = Join-Path $mapsRoot 'BroodWar'
$myDir     = Join-Path $broodWar $MyFolder
$decoyDir  = Join-Path $broodWar $DecoyFolder
$myName    = 'browser-probe.scx'
$decoyName = 'decoy.scx'
$myPath    = Join-Path $myDir $myName
$decoyPath = Join-Path $decoyDir $decoyName
$logPath   = Join-Path $LogDir 'browser-probe.log'
$shotDir   = Join-Path $LogDir 'browser-probe-frames'
$markerPath = Join-Path $LogDir 'marker.txt'

$mine  = New-ScFixtureRun -Dir $myDir -Names @($myName)
$decoy = New-ScFixtureRun -Dir $decoyDir -Names @($decoyName)

New-Item -ItemType Directory -Path $LogDir, $shotDir -Force | Out-Null
if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

$gamePid = 0
$launchLock = $null
try {
    Write-Host ''
    Write-Host '[1] two fixture folders at once: a decoy that sorts first, and ours'
    Wait-ScFixtureFolderFree -Run $decoy
    Wait-ScFixtureFolderFree -Run $mine
    # DIFFERENT unit types on purpose: that is what makes "which map loaded" answerable
    # from inside the process rather than from a click that appeared to work.
    & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount 6 -UnitType marine -Player 0 -OutputPath $decoyPath 2>&1 |
        Where-Object { "$_" -notmatch 'WARNING:StormLib' } | ForEach-Object { Write-Host "       $_" }
    & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount 36 -UnitType lurker -Player 0 -OutputPath $myPath 2>&1 |
        Where-Object { "$_" -notmatch 'WARNING:StormLib' } | ForEach-Object { Write-Host "       $_" }
    Assert-That 'the decoy fixture was written' (Test-Path -LiteralPath $decoyPath)
    Assert-That 'our own fixture was written' (Test-Path -LiteralPath $myPath)

    Write-Host ''
    Write-Host '[2] the computed row is not the row the old harness clicked'
    # The world scan in [4] is the conclusive check; these row checks earn their keep by
    # making a wrong row fail here and loudly, not as a wrong-unit-type mystery in-game.
    $bwListing = Get-ScBrowserListing -Dir $broodWar -MapsRoot $mapsRoot
    Write-Host "       Maps\BroodWar: $($bwListing.Text)"
    $myEntry = Get-ScBrowserEntry -Listing $bwListing -Name $MyFolder
    $row1 = $bwListing.Entries[0]
    Write-Host ("       old harness clicked row 1 (y=140) = [{0}]; computed row for {1} is {2} (y={3})" -f `
        $row1.Name, $MyFolder, $myEntry.Row, $myEntry.Y)
    Assert-That 'the old fixed row-1 click would have opened the decoy, not ours' `
        ($row1.Name -eq $DecoyFolder)
    Assert-That 'the computed row is ours and is not row 1' `
        ($myEntry.Row -gt 1)
    # [Up One Level] is no fixed row either: it sorts alphabetically AMONG the folders, so
    # any folder that sorts before it pushes it down a row.
    $up = @($bwListing.Entries | Where-Object Kind -eq 'up')[0]
    Write-Host ("       [Up One Level] is row {0} (y={1}); the campaign suites used to click y=178 (row 3)" -f $up.Row, $up.Y)
    Assert-That 'the two extra folders moved [Up One Level] off row 3 as well' ($up.Row -ne 3)

    Write-Host ''
    Write-Host '[3] launch, and walk the browser with every row computed'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '023-browser-probe'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode observe -WorldScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $logPath 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
    Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
    Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
    Start-Sleep -Seconds 2
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '01-broodwar-listing.png') -FullWindow | Out-Null

    # THE OPENING LIST IS SCROLLED, which is why no row is read before the list is put
    # somewhere known: the rows before and after the scroll-to-top are different rows.
    $fpOpen = @(Get-ScBrowserRowOccupancy -Hwnd $hwnd)
    Sync-ScBrowserToTop -Hwnd $hwnd
    $fpTop = @(Get-ScBrowserRowOccupancy -Hwnd $hwnd)
    for ($i = 0; $i -lt 6; $i++) {
        Write-Host ("         row {0}: as opened {1} | at the top {2}" -f ($i + 1), $fpOpen[$i], $fpTop[$i])
    }
    Assert-That 'the browser did not open at the top of its own list' `
        (@(0..5 | Where-Object { $fpOpen[$_] -ne $fpTop[$_] }).Count -gt 0)

    # The negative half, measured rather than assumed: EVERY folder row leaves the SAME
    # blank map-information panel, which is what makes "the panel changed" mean "the row
    # I clicked was a map" when Select-ScBrowserMap checks it below -- the positive-first
    # half of the absence claim (AGENTS.md § "Oracles: absence and defect-era checks").
    Send-ScClick -Hwnd $hwnd -X 117 -Y 140          # row 1 at the top == the decoy, a folder
    Start-Sleep -Milliseconds 400
    $panelOnFolder = Get-ScBrowserInfoPanel -Hwnd $hwnd
    Send-ScClick -Hwnd $hwnd -X 117 -Y 178          # row 3 == [Allied], a different folder
    Start-Sleep -Milliseconds 400
    Assert-That 'any FOLDER row leaves the same blank map-information panel' `
        ((Get-ScBrowserInfoPanel -Hwnd $hwnd) -eq $panelOnFolder) "(blank=$panelOnFolder)"

    # THE WALK. Throws if the row it clicked did not select a map.
    Assert-ScFixtureStillMine -Run $mine -MapPath $myPath
    Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $myPath | Out-Null
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '02-our-folder.png') -FullWindow | Out-Null
    Assert-That 'and the map row DID change it' `
        ((Get-ScBrowserInfoPanel -Hwnd $hwnd) -ne $panelOnFolder)

    Write-Host ''
    Write-Host '[4] start the map, and ask the PROCESS which one loaded'
    Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2           # Use Map Settings, verified
    Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
    Start-Sleep -Seconds 10
    # Found in the engine's own dialog list and dismissed by ITS OWN OK button, then
    # asserted gone: never a fixed point, never the registry (AGENTS.md § "Tips dialog").
    Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $logPath | Out-Null
    Start-Sleep -Seconds 3
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '03-in-game.png') -FullWindow | Out-Null

    $world = Get-ScWorldState -LogPath $logPath -Tag 'probe' -MarkerPath $markerPath
    $mineUnits  = @($world.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $LURKER_TYPE })
    $decoyUnits = @($world.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $MARINE_TYPE })
    Write-Host ("       world scan: player 0 holds {0} Lurker(s) (ours) and {1} Marine(s) (the decoy's)" -f `
        $mineUnits.Count, $decoyUnits.Count)
    # Positive first, then negative: an absence claim alone is worth nothing, so the same
    # scan must show our units present (AGENTS.md § "Oracles: absence and defect-era checks").
    Assert-That 'our own map loaded -- its 36 Lurkers are in the world' ($mineUnits.Count -eq 36)
    Assert-That "and the decoy's Marines are not" ($decoyUnits.Count -eq 0)
}
catch {
    Write-Host "  FAIL the probe threw: $($_.Exception.Message)"
    Write-Host "       $($_.InvocationInfo.PositionMessage)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game: $($_.Exception.Message)"; $failures++ }
        Start-Sleep -Seconds 2
    }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
    if (-not $KeepOpen) {
        Remove-ScOwnFixture -Run $mine
        Remove-ScOwnFixture -Run $decoy
        Remove-ScOwnFixtureDir -Dir $myDir
        Remove-ScOwnFixtureDir -Dir $decoyDir
    }
}

Write-Host ''
if ($failures -eq 0) { Write-Host 'probe-browser-rows: 0 failures' }
else { Write-Host "probe-browser-rows: $failures failure(s)" }
exit ($failures -gt 0 ? 1 : 0)
