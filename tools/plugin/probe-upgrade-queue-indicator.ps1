#Requires -Version 7
<#
.SYNOPSIS
Queues 2+ upgrades at a real building and reads back whether the QUEUE INDICATOR
(sc_queueind.cpp, SC_QIND_UPGRADE) shows it -- from the in-process oracle AND a real frame.

.DESCRIPTION
QIND reports the module's own state, and that state can be entirely truthful about a string
no player can read: `mode=3 text="+2 upg" ink>0` says nothing about paint order or about the
art the text lands on, which is what decides whether it reaches the glass legibly. So the
frame `-CaptureFrames` captures is what settles this probe, not the log line
(AGENTS.md § "Oracles: what counts as a read-back").

.EXAMPLE
./tools/plugin/probe-upgrade-queue-indicator.ps1 -UnitType engineering-bay -CaptureFrames
.EXAMPLE
./tools/plugin/probe-upgrade-queue-indicator.ps1 -UnitType academy -CaptureFrames -BuildDir C:\sc-work\logs\037\build-fixed2
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    # Two interchangeable samples, not a required set: neither AnchorFor nor the mode it is
    # given looks at the unit's type, so the indicator behaves identically at every
    # upgrade-producing building.
    [ValidateSet('engineering-bay', 'academy')]
    [string]$UnitType = 'engineering-bay',
    [string]$BuildDir,
    [string]$LogPath = "C:\sc-work\logs\037\qind-$UnitType.log",
    [string]$FixtureDir,
    [int]$StartingMinerals = 5000,
    [int]$StartingGas = 5000,
    [int]$SettleSec = 4,
    [switch]$CaptureFrames,
    [string]$FrameDir = "C:\sc-work\logs\037-frames",
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
$step = 0

# units.dat ids, evidence: the UNIT_TYPE_IDS table in tools/make_test_map.py.
$UNIT_TYPE_ID = @{ 'engineering-bay' = 122; 'academy' = 112 }
$BUILDING_TYPE = $UNIT_TYPE_ID[$UnitType]
$UPGRADE_CMD = '0x32'
$TECH_CMD = '0x30'
$UPGRADE_ACTION = '00423310'
$TECH_ACTION = '00423350'

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t037' -Suite 'upgrade-queue-indicator' }
$mapDir = $FixtureDir
$mapName = "qind-$UnitType.scx"
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}
function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    & $Body
}

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-World { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScWorldState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }
function Get-Card { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScCardState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }

# The indicator, read back OUT OF THE LIVE DIALOG. Same parser as test-production-queue.ps1,
# duplicated because the two suites share no file.
$script:qindSeq = 0
function ConvertFrom-QIndLine {
    param($Hit)
    # Match BY NAME: fields get inserted into the QIND line, and each insertion shifts every
    # positional group after it -- a positional parser throws "unparseable" and takes the
    # whole probe down with it. Named groups survive the next field.
    $m = [regex]::Match($Hit.Line,
                'QIND \[[^\]]+\] mode=(?<mode>\d+) linked=(?<linked>\d+) visible=(?<visible>\d+) ' +
                'text="(?<text>[^"]*)" ' +
                'bounds=\((?<left>-?\d+),(?<top>-?\d+),(?<right>-?\d+),(?<bottom>-?\d+)\) ' +
                'ink=(?<ink>-?\d+) refInk=(?<refInk>-?\d+) refId=(?<refId>-?\d+) ' +
                'surfInk=(?<surfInk>-?\d+) slotDiff=(?<slotDiff>-?\d+) boxDiff=(?<boxDiff>-?\d+) ' +
                'fontH=(?<fontH>\d+) icons=\[(?<icons>[^\]]*)\] ' +
                'sel=(?<sel>\d+) engineLen=(?<engineLen>\d+) overflow=(?<overflow>\d+) ' +
                'upg=(?<upg>\d+) bldgs=(?<bldgs>\d+) queued=(?<queued>\d+)')
    if (-not $m.Success) { throw "probe: unparseable QIND line: $($Hit.Line)" }
    return [pscustomobject]@{
        Mode = [int]$m.Groups['mode'].Value; Linked = $m.Groups['linked'].Value -eq '1'
        Visible = $m.Groups['visible'].Value -eq '1'; Text = $m.Groups['text'].Value
        Left = [int]$m.Groups['left'].Value; Top = [int]$m.Groups['top'].Value
        Right = [int]$m.Groups['right'].Value; Bottom = [int]$m.Groups['bottom'].Value
        Ink = [int]$m.Groups['ink'].Value; RefInk = [int]$m.Groups['refInk'].Value
        SurfInk = [int]$m.Groups['surfInk'].Value; BoxDiff = [int]$m.Groups['boxDiff'].Value
        Upg = [int]$m.Groups['upg'].Value
        Line = $Hit.Line
    }
}
function Get-QInd {
    param([string]$Tag, [int]$TimeoutSec = 20)
    $script:qindSeq++
    $label = "qi-$Tag-$script:qindSeq"
    Set-ScMarker -MarkerPath $markerPath -Label $label
    $esc = [regex]::Escape($label)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $hit = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                 Select-String -Pattern "QIND \[$esc\]") | Select-Object -Last 1
        if ($hit) { return ConvertFrom-QIndLine $hit }
        Start-Sleep -Milliseconds 250
    }
    throw "probe: no QIND answer for marker '$label' within ${TimeoutSec}s (log: $LogPath)."
}

function Get-ResearchSlots {
    param($Card)
    ,@($Card.Slots | Where-Object { $_.HasButton -and ($_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() -or $_.Action -eq $TECH_ACTION.ToUpperInvariant()) })
}

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
if ($CaptureFrames) { New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null }

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
$launchLock = $null
function Shot([string]$tag) {
    if (-not $CaptureFrames -or $script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    $p = Join-Path $FrameDir ("{0:d2}-{1}-{2}.png" -f $script:shotN, $UnitType, $tag)
    Save-ScWindowImage -Hwnd $script:hwnd -Path $p -FullWindow | Out-Null
    Write-Host "       frame: $p"
}

try {
    Step "generate the fixture: one $UnitType, $StartingMinerals minerals / $StartingGas gas" {
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 1 -UnitType $UnitType -Player 0 -ClearPlayerUnits `
            -GridSpacing 160 -StartingMinerals $StartingMinerals -StartingGas $StartingGas `
            -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId "037-qind-$UnitType"
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 -CardScan 1 `
        -UpgradeQueue 1 -UpgradeQueueMax 8 -QueueIndicator 1 `
        -InjectWindowedHelper WMode -NoLaunchLock -BuildDir $BuildDir `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
        Write-Host $_
        if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
    }
    if (-not $gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
    }

    Step "the map spawned exactly one $UnitType and nothing else" {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $bldgs = @($mine | Where-Object { $_.Type -eq $BUILDING_TYPE })
        Assert-That "player 0 owns exactly one ($($bldgs.Count))" ($bldgs.Count -eq 1)
    }

    Step 'select the building -- click point derived from MEMORY, not a frame' {
        $w = Get-World 'aim'
        $b = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $BUILDING_TYPE })[0]
        $cx = $b.X - $w.Screen.Left
        $cy = $b.Y - $w.Screen.Top
        Assert-That "the building is on screen ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2
        Shot 'selected-idle'
    }

    Step 'READ THE QUEUE INDICATOR BEFORE ANYTHING IS QUEUED -- the negative half' {
        $q = Get-QInd 'idle'
        Write-Host "       QIND idle: mode=$($q.Mode) linked=$($q.Linked) visible=$($q.Visible) text=`"$($q.Text)`" ink=$($q.Ink) upg=$($q.Upg)"
        Assert-That 'nothing is shown yet (mode=NONE)' ($q.Mode -eq 0) "(mode=$($q.Mode))"
    }

    $script:idleCard = $null
    $script:upgA = $null
    $script:upgB = $null
    Step 'read the idle card and pick two enabled research buttons' {
        $card = Get-Card 'idle'
        Assert-That 'the card dialog was resolved' ($card.Ok)
        $rs = Get-ResearchSlots -Card $card
        $enabled = @($rs | Where-Object { $_.Visible -and -not $_.Disabled })
        Assert-That "at least two research buttons are enabled ($($enabled.Count))" ($enabled.Count -ge 2)
        $script:idleCard = $card
        $script:upgA = if ($enabled.Count -gt 0) { $enabled[0] } else { $null }
        $script:upgB = if ($enabled.Count -gt 1) { $enabled[1] } else { $null }
    }

    Step 'press the FIRST research -- starts in the engine''s own slot' {
        $pt = Get-ScCardSlotPoint -Card $script:idleCard -Slot $script:upgA.Index
        Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
        Start-Sleep -Seconds $SettleSec
    }

    Step 'press the SECOND, different research -- must be QUEUED, not refused' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $card = Get-Card 'busy'
        $pt = Get-ScCardSlotPoint -Card $script:idleCard -Slot $script:upgB.Index
        for ($i = 1; $i -le 3; $i++) { Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y -SettleMs 300 }
        Start-Sleep -Seconds 2
        Shot 'queued-2'
    }

    Step 'READ THE QUEUE INDICATOR WITH 2 UPGRADES QUEUED -- the headline' {
        $q = Get-QInd 'queued'
        Write-Host "       QIND queued: mode=$($q.Mode) linked=$($q.Linked) visible=$($q.Visible) text=`"$($q.Text)`" bounds=($($q.Left),$($q.Top),$($q.Right),$($q.Bottom)) ink=$($q.Ink) refInk=$($q.RefInk) upg=$($q.Upg)"
        Assert-That "the plugin is holding at least one ($($q.Upg))" ($q.Upg -ge 1)
        Assert-That 'the indicator picked UPGRADE mode (mode=3)' ($q.Mode -eq 3) "(mode=$($q.Mode))"
        Assert-That 'it is linked into the dialog' ($q.Linked)
        Assert-That 'the engine''s own visible bit is set' ($q.Visible)
        Assert-That "text says +N upg (got `"$($q.Text)`")" ($q.Text -match '^\+\d+ upg$')
        # Do not assert `ink > 0`: the pane draws its own art into the surface this probe
        # counts, so every rect in it is saturated (ink=608 here) before one pixel of ours
        # exists. boxDiff is that same box against a copy taken while the indicator was
        # hidden -- the only bytes this plugin is responsible for.
        Assert-That "the box holds bytes this plugin put there (boxDiff=$($q.BoxDiff), ink=$($q.Ink) is saturated by the pane's own art)" `
            ($q.BoxDiff -gt 0)
        Assert-That "and the probe can read this surface at all (surfInk=$($q.SurfInk))" `
            ($q.SurfInk -gt 0)
    }

    Step 'one more frame, a couple seconds later, for a human to open' {
        Start-Sleep -Seconds 2
        Shot 'queued-2-settled'
    }

}
catch {
    Write-Host "  FAIL a probe step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"; $failures++ }
        Start-Sleep -Seconds 2
    }
    if (-not $KeepOpen) { Remove-ScOwnFixture -Run $fixtures }
    Remove-ScOwnFixtureDir -Dir $mapDir
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock; $launchLock = $null }
}

Write-Host ''
Write-Host "probe ($UnitType): $failures failure(s)"
Write-Host "log:    $LogPath"
if ($CaptureFrames) { Write-Host "frames: $FrameDir (diagnostic, NOT committable -- AGENTS.md hard rule 1)" }
exit ($failures -eq 0 ? 0 : 1)
