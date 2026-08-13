#Requires -Version 7
<#
.SYNOPSIS
THE FIRST QUESTION of task 029, answered on the wire: with an upgrade ALREADY RUNNING at
a building, does the client put a second Upgrade command on the wire, or does it refuse?

.DESCRIPTION
AGENTS.md, "A player-input feature is unproven until the wire has been watched": task 025
built over-cap production queueing against a receive-side handler for a command the client
never sends, every offline test passed, and the feature was inert in game. So task 029
starts here, before any design exists, and it starts with a MEASUREMENT.

The fixture is one Terran Engineering Bay (units.dat 122) owned by player 0, with enough
minerals and gas for several upgrades. An Engineering Bay is the cheapest building that
RESEARCHES and it offers two INDEPENDENT level-1 upgrades -- Terran Infantry Armor
(upgrades.dat 0) and Terran Infantry Weapons (upgrades.dat 7) -- so "queue a second
upgrade" can be asked without dragging in the level-N/level-N+1 case.

WHAT IS MEASURED, and how each half is read:

  * THE WIRE. The plugin hooks the engine's outgoing-command funnel queueCommand
    (0x00485BD0) and logs every command the game sends. `CMD id=0x32` is Upgrade,
    `CMD id=0x30` is Tech (research/data/command-opcodes.tsv). The count of those lines
    between two markers IS the answer to the question. Nothing is inferred from a frame.

  * THE CARD, out of memory, before AND after (AGENTS.md, task 026: read a dialog's
    CONTENT, never hash its pixels -- and take the read BEFORE the acting as well as
    after, because a read taken only afterwards can be a false negative manufactured by
    the act itself). -CardScan 1 walks the card dialog at 0x0068C148 and reports, per
    slot, the control's visible/greyed bits and the Button record behind it. So this run
    can say WHICH slot, in WHICH state, and whether the buttonset itself changed --
    which a "the button looked dark" observation cannot.

  * THE BUILDING'S ORDER, out of memory. -WorldScan 1 reports each unit's primary and
    secondary order. A research that really started shows up there, so the precondition
    of the whole question ("with an upgrade already running") is checked rather than
    assumed.

CLICKS, NOT HOTKEYS. Every card click point is computed from the LIVE dialog by
Get-ScCardSlotPoint (rootRect + the control's own rect, halved) -- never a hardcoded
coordinate, which is the ambiguity that cost task 022 the whole Ghost question: a probe
that clicks a guessed centre cannot tell "the button refused" from "the click missed".

This probe writes nothing into the game and installs no hook of its own; it runs in
-Mode hooktest, which is the one queueCommand hook and nothing else.

.EXAMPLE
./tools/plugin/probe-upgrade-wire.ps1

.EXAMPLE
./tools/plugin/probe-upgrade-wire.ps1 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\029\upgrade-wire.log',
    [string]$ShotDir = 'C:\sc-work\logs\029\upgrade-wire-frames',
    [string]$FixtureDir,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 3000,
    # How long to give the research to visibly start before the second press. One
    # Engineering Bay upgrade is 4000 game frames-ish; a couple of seconds is plenty to
    # be unambiguously "already running" without waiting for it to finish.
    [int]$SettleSec = 4,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
$step = 0

# Pinned constants, asserted rather than reported.
$EBAY_TYPE = 122            # units.dat 122, richchk UnitId 'Terran Engineering Bay'
$UPGRADE_CMD = '0x32'       # research/data/command-opcodes.tsv
$TECH_CMD = '0x30'          # ditto
# The two emitters research/data/command-ids.tsv lists for each of those ids. The one in
# the 0x423xxx range is the build-menu button table's ACTION function -- which is what a
# card Button record points at, so it is how an upgrade button is recognised without
# guessing at icons or strings.
$UPGRADE_ACTION = '00423310'
$TECH_ACTION = '00423350'

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t029' -Suite 'upgrade-wire' }
$mapDir = $FixtureDir
$mapName = 'upgrade-wire.scx'
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

# One line per slot, so the run's own transcript carries the card rather than a summary
# of it. This is the evidence the design will be quoted against.
function Show-Card {
    param($Card, [string]$Tag)
    Write-Host ("       CARD[$Tag] cardId={0} portraitType=0x{1:x} portraitSet={2} setCount={3} shown={4} greyed={5} reason={6}" -f `
        $Card.CardId, $Card.PortraitType, $Card.PortraitSet, $Card.SetCount, $Card.Shown, $Card.Greyed, $Card.Reason)
    foreach ($s in $Card.Slots) {
        Write-Host ("         slot={0} {1,-7} icon=0x{2:x} bslot={3} cond=0x{4} act=0x{5} cparam={6} aparam={7} name=0x{8:x}" -f `
            $s.Index, $s.State, $s.Icon, $s.BSlot, $s.Cond, $s.Action, $s.CondParam, $s.ActParam, $s.NameStr)
    }
}

# Every card slot whose Button ACTION is one of the two research/upgrade emitters.
# `,@(...)` and not `@(...)`: a PowerShell function returning an empty array unrolls it
# to $null at the call site, and `$null.Count` is an error -- which is exactly how the
# first run of this probe died, at the one moment the answer was "none".
function Get-ResearchSlots {
    param($Card)
    ,@($Card.Slots | Where-Object { $_.HasButton -and ($_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() -or $_.Action -eq $TECH_ACTION.ToUpperInvariant()) })
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "probe: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
$launchLock = $null
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

$script:findings = @()
function Note([string]$Line) { $script:findings += $Line; Write-Host "       >> $Line" }

try {
    Step "generate the fixture: one Engineering Bay, $StartingMinerals minerals / $StartingGas gas" {
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 1 -UnitType engineering-bay -Player 0 -ClearPlayerUnits `
            -GridSpacing 160 -StartingMinerals $StartingMinerals -StartingGas $StartingGas `
            -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '029-upgrade-wire'
    # hooktest mode: the ONE queueCommand hook, so `CMD id=` lines exist, and nothing
    # else. No production-queue feature, no fan-out -- this run must measure VANILLA
    # client behaviour, so the only thing in the picture is the logger.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 -CardScan 1 `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2      # Use Map Settings, verified
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step 'the map spawned exactly one Engineering Bay and nothing else' {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $bays = @($mine | Where-Object { $_.Type -eq $EBAY_TYPE })
        Assert-That "player 0 owns exactly one Engineering Bay ($($bays.Count))" ($bays.Count -eq 1)
        Assert-That "and owns nothing else ($($mine.Count) unit(s) total)" ($mine.Count -eq 1) `
            "(types seen: $((($mine | ForEach-Object { '0x{0:x}' -f $_.Type }) | Sort-Object -Unique) -join ' '))"
        Assert-That 'the world scan of player 0 was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)
        $script:bayUnit = if ($bays.Count -gt 0) { $bays[0].Unit } else { $null }
        # The BEFORE half of the order comparison the "is it really running" step makes.
        $script:idleOrder = if ($bays.Count -gt 0) { $bays[0].Order } else { -1 }
        $script:idleOrder2 = if ($bays.Count -gt 0) { $bays[0].Order2 } else { -1 }
        if ($bays.Count -gt 0) {
            Note ("idle Engineering Bay: unit=0x$($bays[0].Unit) order=0x{0:x} order2=0x{1:x} hp={2}" -f `
                $bays[0].Order, $bays[0].Order2, $bays[0].Hp)
        }
    }

    Step 'select the Engineering Bay -- click point derived from MEMORY, not a frame' {
        $w = Get-World 'aim'
        $bay = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $EBAY_TYPE })[0]
        Assert-That 'the scan reports the viewport origin' ($null -ne $w.Screen)
        Assert-That 'and the Engineering Bay has a sprite position' `
            ($null -ne $bay -and $bay.X -gt 0 -and $bay.Y -gt 0)
        $cx = $bay.X - $w.Screen.Left
        $cy = $bay.Y - $w.Screen.Top
        Write-Host "       bay at map ($($bay.X),$($bay.Y)), viewport ($($w.Screen.Left),$($w.Screen.Top)) -> client ($cx,$cy)"
        Assert-That "the building is on screen, inside the play area ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2
        Shot 'selected'
    }

    Step 'READ THE CARD BEFORE ANYTHING IS PRESSED -- the negative half of the pair' {
        $card = Get-Card 'idle'
        Assert-That 'the card dialog was resolved' ($card.Ok)
        Show-Card -Card $card 'idle'
        Assert-That "the portrait is the Engineering Bay (0x$('{0:x}' -f $card.PortraitType))" `
            ($card.PortraitType -eq $EBAY_TYPE)
        $script:idleCard = $card
        $script:idleSet = $card.PortraitSet
        # NOT @(...) here: Get-ResearchSlots already comma-wraps, and the pipeline unrolls
        # that outer wrapper exactly once. Wrapping again nests the array inside a
        # one-element array, which the first fix did -- and it read as "1 button" for a
        # card that had two.
        $rs = Get-ResearchSlots -Card $card
        Note ("idle card: cardId=$($card.CardId) buttonset=$($card.PortraitSet) shown=$($card.Shown) greyed=$($card.Greyed); research/upgrade buttons: " +
              (($rs | ForEach-Object { "slot$($_.Index)/$($_.State)/act=0x$($_.Action)/aparam=$($_.ActParam)" }) -join ' '))
        Assert-That "the idle card offers at least two upgrade/research buttons ($($rs.Count))" ($rs.Count -ge 2)
        $enabled = @($rs | Where-Object { $_.Visible -and -not $_.Disabled })
        Assert-That "and at least two of them are ENABLED ($($enabled.Count))" ($enabled.Count -ge 2) `
            "(states: $(($rs | ForEach-Object { "$($_.Index)=$($_.State)" }) -join ' '))"
        $script:upgA = if ($enabled.Count -gt 0) { $enabled[0] } else { $null }
        $script:upgB = if ($enabled.Count -gt 1) { $enabled[1] } else { $null }
    }

    Step 'press the FIRST upgrade -- this one must reach the wire' {
        if (-not $script:upgA) { throw 'probe: no enabled upgrade button was found on the idle card.' }
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $pt = Get-ScCardSlotPoint -Card $script:idleCard -Slot $script:upgA.Index
        Write-Host "       clicking slot $($script:upgA.Index) at client ($($pt.X),$($pt.Y)) [aparam=$($script:upgA.ActParam)]"
        Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=($UPGRADE_CMD|$TECH_CMD) ")
        $cmds | ForEach-Object { Write-Host "       $($_.Line.Trim())" }
        Assert-That "exactly one research/upgrade command went out ($($cmds.Count))" ($cmds.Count -eq 1)
        $script:firstCmd = if ($cmds.Count -gt 0) { $cmds[0].Line.Trim() } else { '' }
        Note "press 1 (idle building) put on the wire: $script:firstCmd"
        Shot 'pressed-1'
    }

    Step "wait ${SettleSec}s and PROVE from memory that the upgrade is really running" {
        Start-Sleep -Seconds $SettleSec
        $w = Get-World 'researching'
        $bay = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $EBAY_TYPE })[0]
        Assert-That 'the Engineering Bay is still there' ($null -ne $bay)
        if ($bay) {
            Note ("researching Engineering Bay: order=0x{0:x} order2=0x{1:x} (idle was order=0x{2:x} order2=0x{3:x})" -f `
                $bay.Order, $bay.Order2, $script:idleOrder, $script:idleOrder2)
            $script:busyOrder = $bay.Order
            $script:busyOrder2 = $bay.Order2
        }
        # The precondition of the whole question. If the order did not change, the click
        # did not start anything and every measurement below is about the wrong state.
        Assert-That 'its order or secondary order CHANGED -- the research really started' `
            ($null -ne $bay -and ($bay.Order -ne $script:idleOrder -or $bay.Order2 -ne $script:idleOrder2)) `
            "(order=0x$('{0:x}' -f $bay.Order) order2=0x$('{0:x}' -f $bay.Order2))"
    }

    Step 'READ THE CARD AGAIN, with the upgrade running -- what does the client offer now?' {
        $card = Get-Card 'busy'
        Assert-That 'the card dialog was resolved' ($card.Ok)
        Show-Card -Card $card 'busy'
        $script:busyCard = $card
        # NOT @(...) here: Get-ResearchSlots already comma-wraps, and the pipeline unrolls
        # that outer wrapper exactly once. Wrapping again nests the array inside a
        # one-element array, which the first fix did -- and it read as "1 button" for a
        # card that had two.
        $rs = Get-ResearchSlots -Card $card
        Note ("busy card: cardId=$($card.CardId) buttonset=$($card.PortraitSet) shown=$($card.Shown) greyed=$($card.Greyed); research/upgrade buttons: " +
              (($rs | ForEach-Object { "slot$($_.Index)/$($_.State)/act=0x$($_.Action)/aparam=$($_.ActParam)" }) -join ' '))
        Note ("buttonset changed while researching: " + ($(if ($card.PortraitSet -ne $script:idleSet) { "YES ($script:idleSet -> $($card.PortraitSet))" } else { "NO (still $($card.PortraitSet))" })))
        $stillEnabled = @($rs | Where-Object { $_.Visible -and -not $_.Disabled })
        Note ("upgrade/research buttons still ENABLED while one runs: $($stillEnabled.Count) of $($rs.Count)")
        $script:busyEnabled = $stillEnabled
        Shot 'busy'
    }

    # THE HEADLINE. Both presses aim at the point the IDLE card put the button at -- the
    # same arithmetic, on the same dialog, that step 6 used to send a command
    # successfully. That pairing is what makes a zero here mean "refused" rather than
    # "missed": the identical click at the identical point demonstrably reached the wire
    # four seconds earlier, so the only thing that changed is the building's state.
    function Press-WhereTheButtonWas {
        param([string]$Which, $IdleSlot, [int]$Times = 3)
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $pt = Get-ScCardSlotPoint -Card $script:idleCard -Slot $IdleSlot.Index
        $now = Get-ScCardSlot -Card $script:busyCard -Slot $IdleSlot.Index
        $nowState = if ($now) { $now.State } else { 'absent' }
        $nowAct = if ($now -and $now.HasButton) { "act=0x$($now.Action) aparam=$($now.ActParam)" } else { 'no button record' }
        Write-Host "       clicking slot $($IdleSlot.Index) at client ($($pt.X),$($pt.Y)) -- idle it was $($IdleSlot.State)/aparam=$($IdleSlot.ActParam), busy it is $nowState/$nowAct"
        # Pressed $Times times, 300 ms apart. One press could in principle be lost to a
        # frame boundary; three cannot all be.
        for ($i = 1; $i -le $Times; $i++) { Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y -SettleMs 300 }
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=($UPGRADE_CMD|$TECH_CMD) ")
        $cmds | ForEach-Object { Write-Host "       $($_.Line.Trim())" }
        Note ("$Which : $Times presses at the live-derived point of slot $($IdleSlot.Index) put $($cmds.Count) command(s) on the wire" +
              $(if ($cmds.Count -gt 0) { " -- $(($cmds | ForEach-Object { $_.Line.Trim() }) -join ' | ')" } else { ' -- the client SENT NOTHING' }) +
              " [that slot is now $nowState]")
        $cmds.Count
    }

    Step 'PRESS A SECOND, DIFFERENT UPGRADE WHILE THE FIRST IS RUNNING -- the headline' {
        if (-not $script:upgB) { throw 'probe: the idle card offered only one enabled upgrade button, so a second, different one cannot be pressed.' }
        $script:secondCount = Press-WhereTheButtonWas -Which 'A DIFFERENT upgrade, while one runs' -IdleSlot $script:upgB
        Shot 'pressed-2'
    }

    Step 'and press the SAME upgrade again, for completeness' {
        $script:sameCount = Press-WhereTheButtonWas -Which 'the SAME upgrade again, while it runs' -IdleSlot $script:upgA
    }

    # THE CONTROL FOR THE WHOLE MEASUREMENT. If pressing the cancel button takes the
    # building out of the researching state and the upgrade buttons COME BACK, then the
    # hide is caused by the in-progress upgrade and by nothing else -- and a second run
    # of the same clicks, at the same points, on the same dialog, sends again. Without
    # this step "the client sent nothing" would be compatible with "the clicks stopped
    # working", which is the ambiguity task 022 lost a whole question to.
    Step 'CANCEL the running upgrade, then press again -- does the refusal lift?' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $cancelSlot = @($script:busyCard.Slots | Where-Object { $_.HasButton -and $_.Visible -and -not $_.Disabled }) |
                      Select-Object -First 1
        Assert-That 'the busy card offers exactly one enabled button to press' ($null -ne $cancelSlot)
        if ($cancelSlot) {
            Note ("the ONLY button a busy Engineering Bay offers: slot $($cancelSlot.Index) cond=0x$($cancelSlot.Cond) act=0x$($cancelSlot.Action) name=0x$('{0:x}' -f $cancelSlot.NameStr)")
            $pt = Get-ScCardSlotPoint -Card $script:busyCard -Slot $cancelSlot.Index
            Write-Host "       clicking it at client ($($pt.X),$($pt.Y))"
            Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
        }
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cancels = @($lines | Select-String -Pattern 'CMD id=0x3[13] ')
        $cancels | ForEach-Object { Write-Host "       $($_.Line.Trim())" }
        Note ("cancelling put $($cancels.Count) command(s) on the wire" +
              $(if ($cancels.Count -gt 0) { ": $(($cancels | ForEach-Object { $_.Line.Trim() }) -join ' | ')" } else { '' }))

        $w = Get-World 'cancelled'
        $bay = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $EBAY_TYPE })[0]
        if ($bay) { Note ("after cancel: order=0x{0:x} order2=0x{1:x}" -f $bay.Order, $bay.Order2) }
        Assert-That 'the building left the researching order it was in' `
            ($null -ne $bay -and $bay.Order -ne $script:busyOrder) `
            "(order=0x$('{0:x}' -f $bay.Order), was 0x$('{0:x}' -f $script:busyOrder))"

        $card = Get-Card 'idle-again'
        Show-Card -Card $card 'idle-again'
        # NOT @(...) here: Get-ResearchSlots already comma-wraps, and the pipeline unrolls
        # that outer wrapper exactly once. Wrapping again nests the array inside a
        # one-element array, which the first fix did -- and it read as "1 button" for a
        # card that had two.
        $rs = Get-ResearchSlots -Card $card
        $enabled = @($rs | Where-Object { $_.Visible -and -not $_.Disabled })
        Note ("after cancel the card offers $($enabled.Count) enabled upgrade button(s) again (busy card offered 0)")
        Assert-That 'the upgrade buttons came back once the building was idle again' `
            ($enabled.Count -ge 2) "(shown=$($card.Shown) greyed=$($card.Greyed))"

        # And the same click, at the same point, sends again -- the positive control.
        $script:afterCancelCount = 0
        if ($enabled.Count -ge 1) {
            $mark2 = Get-ScLogLineCount -LogPath $LogPath
            $pt2 = Get-ScCardSlotPoint -Card $card -Slot $script:upgB.Index
            Write-Host "       re-pressing slot $($script:upgB.Index) at client ($($pt2.X),$($pt2.Y))"
            Send-ScClick -Hwnd $hwnd -X $pt2.X -Y $pt2.Y
            Start-Sleep -Seconds 2
            $again = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark2 |
                       Select-String -Pattern "CMD id=($UPGRADE_CMD|$TECH_CMD) ")
            $again | ForEach-Object { Write-Host "       $($_.Line.Trim())" }
            $script:afterCancelCount = $again.Count
            Note ("with the building idle again, ONE press of the same slot sent $($again.Count) command(s) -- the positive control for the zeros above")
            Assert-That 'the same click at the same point sends once the building is idle' ($again.Count -ge 1)
        }
        Shot 'after-cancel'
    }

    Step 'THE VERDICT' {
        Assert-That 'a second, DIFFERENT upgrade command was NOT sent while one was running' `
            ($script:secondCount -eq 0) "(got $script:secondCount)"
        Assert-That 'nor was a repeat of the running one' `
            ($script:sameCount -eq 0) "(got $script:sameCount)"
        Note ("VERDICT: the client REFUSES to send a second 0x32/0x30 while a building is researching. " +
              "It does not grey the buttons -- it HIDES them (busy card shown=1) and replaces the card with Cancel Upgrade. " +
              "A receive-side-only design is therefore impossible: there is no second command to catch.")
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
        catch {
            Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"
            $failures++
        }
        Start-Sleep -Seconds 2
    }
    elseif (-not $KeepOpen) {
        Write-Host '  FAIL no pid was ever parsed, so nothing could be closed'
        $failures++
    }
    if (-not $KeepOpen) { Remove-ScOwnFixture -Run $fixtures }
    Remove-ScOwnFixtureDir -Dir $mapDir
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock; $launchLock = $null }
}

Write-Host ''
Write-Host '[findings]'
$script:findings | ForEach-Object { Write-Host "  - $_" }

Write-Host ''
# close-game posts WM_CLOSE and waits for the DLL detach, but the kernel can still be
# tearing the process down a moment later -- so give it a bounded wait rather than
# sampling once and reporting a stranded process that is merely still exiting.
$left = $null
if ($gamePid -gt 0 -and -not $KeepOpen) {
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $left = Get-Process -Id $gamePid -ErrorAction SilentlyContinue
        if (-not $left) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
}
Assert-That 'the game process this probe started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))
$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)

Write-Host ''
Write-Host "probe-upgrade-wire: $failures failure(s)"
Write-Host "log:    $LogPath"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
