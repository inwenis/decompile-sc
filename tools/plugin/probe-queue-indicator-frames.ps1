#Requires -Version 7
<#
.SYNOPSIS
Task 039. Queues MORE THAN FIVE units at a real Terran building, one run per unit TYPE, and
captures a frame of the fifth queue slot for each -- the picture the user reported as garbage,
in the buildings they reported it from.

.DESCRIPTION
The user, 2026-08-11, on the deployed build:

  "when queuing more than 5 units to build in a single building something buggy happens with
   the 5th units placeholder: for command center it becomes the number '2' and stays regardless
   of queue length / for one barrack it blacked out / for another barrack somehting blue
   flashing appeard"

THREE RENDERINGS, ONE BUG, AND THE FRAME INDEX IS WHY. The plugin fills a queue slot the
engine has just laid out EMPTY. An empty slot's statUser record points at the button-BORDER
art (`*0x0068C1C0`, <race>cmdbtns.grp) and the draw at 0x00456C30 takes the GRP and the frame
index out of THE SAME record -- so writing the unit type as the frame index without writing
the GRP blits frame #unitType out of the borders. That is a different wrong picture per unit
TYPE and a constant one per type, which is exactly the shape of the report: an SCV is type 7,
a Marine is type 0, a Firebat 32, a Medic 34.

So this probe varies THE UNIT TYPE: one map holding a Command Center and a Barracks, every
Train button each card offers, a queue of more than five for each, a frame each. Both cases the
user could name precisely are in one run -- the SCV that became a stuck "2" and the Marine that
blacked out.

WHY BOTH BUILDINGS ARE IN ONE MAP, and it is not tidiness: the Command Center is the only
SUPPLY on it. A Terran player starts with no psi and the sim refuses a Train it cannot house
while the button stays lit -- the first version of this probe put a lone Barracks and an Academy
on the map, watched all eight Train commands reach the engine's own funnel (`trainSeen=8`) and
read back an empty queue. The generator has two placement groups, so a Command Center is the one
that pays for itself: 10 psi AND the user's first case.

WHAT IS THE ORACLE AND WHAT IS THE PICTURE (AGENTS.md, "Read a dialog's CONTENT from memory;
never hash its pixels"): the assertions read the live statUser records -- which GRP, which
frame, which label -- and `boxDiff`, the indicator's own box against a copy of itself taken
while it was hidden. The PNGs are for the human, never asserted on, and never enter the repo
(hard rule 1).

.EXAMPLE
./tools/plugin/probe-queue-indicator-frames.ps1 -Arm fixed
.EXAMPLE
./tools/plugin/probe-queue-indicator-frames.ps1 -Arm defect -BuildDir C:\git\decompile-sc\work\scratch\039\arms\defect
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    # DEFECT is the same tree with the three fixes reverted (work/scratch/039/defect-arm.patch).
    # It only labels the log, the frames and the assertions' expectations -- the build itself
    # comes from -BuildDir.
    [ValidateSet('defect', 'fixed')]
    [string]$Arm = 'fixed',
    [string]$BuildDir,
    [string]$LogPath = "C:\sc-work\logs\039\qind-frames-$Arm.log",
    [string]$FrameDir = 'C:\sc-work\logs\039-frames',
    [string]$FixtureDir,
    # More than five, so the plugin is holding at least one item the strip cannot draw and the
    # fifth icon is the plugin's rather than the engine's.
    [int]$Clicks = 8,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 1000,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
$step = 0

# units.dat ids, from tools/make_test_map.py's own table (task 029). BOTH buildings are in one
# map and both are walked, in this order: the Command Center is the user's own first case AND
# the only supply on the map, so nothing the Barracks trains would be accepted without it.
$BUILDINGS = @(
    [pscustomobject]@{ Name = 'command-center'; Type = 106 },
    [pscustomobject]@{ Name = 'barracks';       Type = 111 }
)
# Names for the frame files, so a path says WHICH unit's picture it holds. Anything not in the
# table is named by its id rather than guessed at -- an unnamed type is still a valid case.
$UNIT_NAMES = @{ 0 = 'marine'; 1 = 'ghost'; 7 = 'scv'; 32 = 'firebat'; 34 = 'medic'; 64 = 'probe' }
function Get-UnitName([int]$Type) {
    if ($UNIT_NAMES.ContainsKey($Type)) { return $UNIT_NAMES[$Type] }
    return "type$Type"
}
# The card's Train button, as the read-back reports actions: uppercase hex, no 0x. Its
# actionParam IS the unit type, which is what makes "one frame per type" drivable from the
# card rather than from a table of ids (research/production-queue.md 8).
$TRAIN_ACT = '004234B0'
$CANCEL_ACT = '00423490'
# The engine's own five: the ring is five slots and the plugin keeps it one below that, so
# the fifth ICON is always the one this plugin fills.
$STRIP_SLOTS = 5

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t039' }
$mapDir = $FixtureDir
$mapName = 'qind-frames.scx'
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
function Get-Strip { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScStatusQueue -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }

# The indicator's own line, parsed BY NAME. Positional parsing of this line has broken twice
# in one task; a named group cannot shift when a field is inserted.
function ConvertFrom-QIndLine {
    param($Hit)
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
        RefId = [int]$m.Groups['refId'].Value; SurfInk = [int]$m.Groups['surfInk'].Value
        SlotDiff = [int]$m.Groups['slotDiff'].Value; BoxDiff = [int]$m.Groups['boxDiff'].Value
        FontH = [int]$m.Groups['fontH'].Value
        Icons = @($m.Groups['icons'].Value -split ',' | Where-Object { $_ } | ForEach-Object {
            $p = $_ -split ':'
            [pscustomobject]@{ Icon = [Convert]::ToInt32(($p[0] -replace '^0x'), 16)
                               Mode = [int]$p[1]; State = $p[2]
                               Art = $p[3]; Label = ($p[4] -eq '1') } })
        EngineLen = [int]$m.Groups['engineLen'].Value
        Overflow = [int]$m.Groups['overflow'].Value
        Line = $Hit.Line
    }
}
$script:qindSeq = 0
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

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$launchLock = $null
# NAMED FOR THE STATE, NOT NUMBERED (the user's standing rule, 2026-08-12): the conductor
# hands these paths to the user, and "frame-007.png" tells them nothing about which case it is.
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $p = Join-Path $FrameDir ("{0}-{1}.png" -f $tag, $Arm)
    Save-ScWindowImage -Hwnd $script:hwnd -Path $p -FullWindow | Out-Null
    Write-Host "       frame: $p"
    return $p
}

$script:framesWritten = @()

try {
    Step 'generate the fixture: a Command Center and a Barracks, both the player''s' {
        Wait-ScFixtureFolderFree -Run $fixtures
        # WHY THE COMMAND CENTER IS IN EVERY RUN AND NOT ONLY IN ITS OWN CASE: it is the
        # SUPPLY. The generator has two placement groups, a Terran player starts with no psi,
        # and the sim refuses a Train it cannot house -- the first run of this probe queued
        # eight Marines at a lone Barracks, watched all eight reach the command funnel
        # (`trainSeen=8`), and read back an empty queue, because a Barracks and an Academy
        # between them supply nothing. A Command Center supplies 10 and trains the SCV, which
        # is the user's own first case, so it earns its place twice.
        #
        # And the build times are pushed out on purpose: a unit that COMPLETES inside the
        # measurement window frees a queue slot and takes a supply point with it, which is the
        # confound AGENTS.md says to design out rather than tolerate (task 026). At 180 game
        # seconds nothing finishes while this probe is looking.
        $genArgs = @{
            UnitCount = 1; UnitType = 'command-center'; Player = 0; ClearPlayerUnits = $true
            GridSpacing = 160
            StartingMinerals = $StartingMinerals; StartingGas = $StartingGas
            UnitBuildTime = @('scv=180', 'marine=180')
            EnemyCount = 1; EnemyType = 'barracks'; EnemyOwner = 'player'
            EnemyOffsetX = 288; EnemyOffsetY = 0
            OutputPath = $mapPath
        }
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId "039-frames-$Arm"
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 -CardScan 1 `
        -ProdQueue 1 -ProdQueueMax 16 -QueueIndicator 1 `
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
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415
        Start-Sleep -Seconds 2
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
    }

    foreach ($building in $BUILDINGS) {
        $bName = $building.Name
        $bType = $building.Type

        Step "select the $bName -- click point derived from MEMORY, not from a frame" {
            $w = Get-World "aim-$bName"
            $b = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $bType }) |
                 Select-Object -First 1
            Assert-That "the map spawned the $bName" ($null -ne $b)
            if ($b) {
                $cx = $b.X - $w.Screen.Left
                $cy = $b.Y - $w.Screen.Top
                Assert-That "it is on screen ($cx,$cy)" `
                    ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
                Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
                Start-Sleep -Seconds 2
            }
            $script:framesWritten += (Shot "$bName-idle-empty-queue")
        }

        # THE NEGATIVE HALF, and it is what makes every reading below a measurement: with an
        # empty queue the indicator must be showing NOTHING, and the probe must still be able to
        # read the surface. surfInk answers that in this state and refInk cannot -- neither the
        # strip nor the wireframe row is up when one building sits idle, which is exactly why
        # refInk is -1 here and why it is not allowed to fall back to a hidden control.
        Step "the indicator says nothing at the $bName before anything is queued" {
            $q = Get-QInd "idle-$bName"
            Write-Host "       $($q.Line)"
            Assert-That "it is showing nothing (mode=$($q.Mode))" ($q.Mode -eq 0)
            Assert-That "and the probe can still read this surface (surfInk=$($q.SurfInk))" `
                ($q.SurfInk -gt 0)
        }

        $script:trainSlots = @()
        Step "read the $bName's card and take every Train button it offers" {
            $card = Get-Card "idle-$bName"
            Assert-That 'the card dialog was resolved' ($card.Ok)
            $script:trainSlots = @($card.Slots | Where-Object {
                $_.HasButton -and $_.Action -eq $TRAIN_ACT -and $_.Visible -and -not $_.Disabled })
            foreach ($ts in $script:trainSlots) {
                Write-Host ("       slot {0}: Train unit type {1} ({2})" -f `
                            $ts.Index, $ts.ActParam, (Get-UnitName $ts.ActParam))
            }
            Assert-That "at least one Train button is enabled ($($script:trainSlots.Count))" `
                ($script:trainSlots.Count -ge 1)
            $script:idleCard = $card
        }

        foreach ($t in $script:trainSlots) {
            $type = [int]$t.ActParam
            # NOT $name: `Step` takes a -Name parameter and the scriptblock runs in a scope that
            # can see it, so a variable called $name inside one silently becomes the step's own
            # title. The first run of this probe wrote its frames to
            # "barracks-fifth-slot-QUEUE 8 x unit type 0 and look at the FIFTH slot-defect.png".
            $typeTag = Get-UnitName $type
            $caseTag = "$bName-$typeTag"

            Step "QUEUE $Clicks x $typeTag (type $type) at the $bName and look at the FIFTH slot" {
                $pt = Get-ScCardSlotPoint -Card $script:idleCard -Slot $t.Index
                for ($i = 1; $i -le $Clicks; $i++) {
                    Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y -SettleMs 150
                }
                Start-Sleep -Seconds 3

                $q = Get-QInd "queued-$caseTag"
                Write-Host "       $($q.Line)"
                $strip = Get-Strip "queued-$caseTag"

                Assert-That "more than five are queued (engine $($q.EngineLen) + plugin $($q.Overflow))" `
                    (($q.EngineLen + $q.Overflow) -gt $STRIP_SLOTS) `
                    '(a Terran player with no psi has every Train refused by the SIM while the button stays lit -- check supply before blaming the click)'
                Assert-That "the strip is full: $($strip.Shown) icon(s) shown, $($strip.Clickable) clickable" `
                    ($strip.Shown -eq $STRIP_SLOTS)

                # THE DEFECT ITSELF, read out of the live record rather than off the picture:
                # which GRP the fifth slot draws from. I = the engine's icon art (a unit
                # portrait), B = the button-BORDER art, in which frame #unitType is not a unit.
                $fifth = if ($q.Icons.Count -ge $STRIP_SLOTS) { $q.Icons[$STRIP_SLOTS - 1] } else { $null }
                Assert-That 'the read-back reported all five icons' ($null -ne $fifth) `
                    "(got $($q.Icons.Count))"
                if ($fifth) {
                    $want = ($Arm -eq 'fixed')
                    $wantArt = $want ? 'I' : 'B'
                    Assert-That "the fifth icon draws from the $(if ($want) { 'ICON' } else { 'BUTTON-BORDER' }) grp (art=$($fifth.Art))" `
                        ($fifth.Art -eq $wantArt) `
                        "(arm=${Arm}: B means the frame index is aimed at the button borders)"
                    Assert-That "and $(if ($want) { 'carries' } else { 'carries NO' }) slot label (label=$($fifth.Label))" `
                        ($fifth.Label -eq $want)
                    Assert-That "and its frame index is the unit type ($($fifth.Icon) vs $type)" `
                        ($fifth.Icon -eq $type)
                }
                # EACH ARM ASSERTS ITS OWN SIGNATURE, so both runs are expected to come out at
                # ZERO failures and any failure means the world is not as this task claims. A
                # probe that only knows what "fixed" looks like reports the defect arm as a
                # mess of failures, and a mess is not a measurement.
                #
                # slotDiff: slots 0 and 4 hold the same unit type and the same border graphic,
                # so once the strip has settled every differing byte is this plugin's --
                #   fixed   tens: the same picture with our "+N" drawn on it;
                #   defect  hundreds: a different picture entirely (measured: 470).
                # boxDiff: the indicator's box against the same box with none of our line in it --
                #   fixed   > 0: the line is on the screen;
                #   defect  0: spliced at the HEAD, the engine's own controls paint over it in
                #           the same frame, so truthful fields (mode=1 visible=1 text="+3") sit
                #           behind a picture the player sees instead. That zero IS the z-order
                #           defect, measured.
                Write-Host "       slotDiff=$($q.SlotDiff) boxDiff=$($q.BoxDiff) ink=$($q.Ink) surfInk=$($q.SurfInk)"
                if ($Arm -eq 'fixed') {
                    Assert-That "the indicator's line is ON the screen (boxDiff=$($q.BoxDiff) bytes are ours)" `
                        ($q.BoxDiff -gt 0)
                    Assert-That "and the fifth icon is the same picture as the first, plus our text (slotDiff=$($q.SlotDiff))" `
                        ($q.SlotDiff -gt 0 -and $q.SlotDiff -lt 200)
                } else {
                    Assert-That "the head splice puts NOTHING of ours on the screen (boxDiff=$($q.BoxDiff))" `
                        ($q.BoxDiff -eq 0) `
                        '(this is the z-order defect: the control is visible and holds the right string)'
                    Assert-That "and the fifth icon is a DIFFERENT picture from the first (slotDiff=$($q.SlotDiff) bytes)" `
                        ($q.SlotDiff -ge 200) `
                        '(the frame index is being read out of the button-border art)'
                }

                $script:framesWritten += (Shot "fifth-slot-$caseTag")
                Start-Sleep -Seconds 2
                $script:framesWritten += (Shot "fifth-slot-$caseTag-settled")
            }

            Step "cancel the $typeTag queue back to empty before the next case" {
                # SLOT 9 IS SHARED, AND THAT IS WHY THIS LOOP RE-READS BEFORE EVERY CLICK.
                # The control carries Cancel while the building is training and Lift Off while
                # it is idle -- complementary conditions on ONE control
                # (research/production-queue.md 8.3). A loop that reads the card once and then
                # clicks a fixed number of times is therefore clicking Lift Off the moment the
                # queue runs out, and that is not theory: the run before this one drained eight
                # items, clicked four more times, and PUT THE COMMAND CENTER IN THE AIR. Every
                # later step then read a flying building's card (`cardId=230`, one button) and
                # reported "no Train button", which looks nothing like the actual cause.
                #
                # So: ask the queue first, stop the moment it is empty, and never press a
                # button whose meaning has changed since it was read.
                $left = -1
                for ($i = 1; $i -le ($Clicks + 6); $i++) {
                    $q = Get-QInd "draining-$caseTag"
                    $left = $q.EngineLen + $q.Overflow
                    if ($left -le 0) { break }
                    $card = Get-Card "busy-$caseTag"
                    $cancel = @($card.Slots | Where-Object {
                        $_.HasButton -and $_.Action -eq $CANCEL_ACT -and $_.Visible -and
                        -not $_.Disabled }) | Select-Object -First 1
                    if (-not $cancel) {
                        Assert-That "the card offers a Cancel button while $left item(s) are queued" $false
                        break
                    }
                    $pt = Get-ScCardSlotPoint -Card $card -Slot $cancel.Index
                    Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y -SettleMs 250
                }
                Assert-That "the queue is empty again ($left left)" ($left -eq 0) `
                    '(a leftover item would make the NEXT case read against a stale strip)'

                # AND THE BUILDING IS STILL THE ONE WE ARE MEASURING. A lift-off, a lost
                # selection or a click that landed on the terrain all produce readings that are
                # internally consistent and about the wrong unit -- the failure mode this
                # project keeps meeting. One read, named, before the next case starts.
                $strip = Get-Strip "still-selected-$caseTag"
                Assert-That "the pane still holds the $bName (portrait type $($strip.PortraitType))" `
                    ([int]$strip.PortraitType -eq $bType)
            }
        }
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
Write-Host "probe (Command Center + Barracks, $Arm arm): $failures failure(s)"
Write-Host "log:    $LogPath"
Write-Host 'frames (diagnostic, NOT committable -- AGENTS.md hard rule 1):'
foreach ($f in $script:framesWritten) { if ($f) { Write-Host "  $f" } }
exit ($failures -eq 0 ? 0 : 1)
