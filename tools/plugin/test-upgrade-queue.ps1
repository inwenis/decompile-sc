#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that a building can hold MORE THAN ONE queued research -- with
the queue read out of the building's own memory, the completions read out of the engine's
own level and researched-tech arrays, and the player's minerals accounted to the last one.

Task 029, from the user's words: "enable queuing upgrades".

.DESCRIPTION
A building researches one thing at a time because it has ONE FIELD for it: CUnit+0xC9 is
the upgrade in progress (61 = none) and CUnit+0xC8 the tech (44 = none). The plugin does
not widen anything -- there is nothing to widen. It holds a queue of its own and hands
items to the ENGINE one at a time (research/upgrade-queue.md 7).

THE FIXTURE IS AN ACADEMY (units.dat 112), and deliberately so. It offers FIVE independent
items across BOTH opcodes -- Stim Packs (tech 0), Restoration (tech 24), Optical Flare
(tech 29), U-238 Shells (upgrade 16) and Caduceus Reactor (upgrade 51) -- none of which
needs a second building, and all of which research in about a minute rather than three. So
one building can prove a MIXED queue, which an Engineering Bay (two upgrades, both slow)
cannot.

The suite does not hardcode WHICH three: it reads the card, takes the enabled research and
upgrade buttons in the order the engine laid them out, and presses those. That keeps it
honest about the tech tree instead of asserting a prerequisite it has not checked.

WHAT THIS RUN HAS TO SHOW, and none of it from the screen:

  1. THE CLIENT SENDS AGAIN. This is the whole feature, and it is the exact reversal of
     what probe-upgrade-wire.ps1 measured in a stock game: there, with a research running,
     six presses put ZERO commands on the wire and the card had shown=1. Here the same
     presses must reach `queueCommand` (0x00485BD0).
  2. MORE THAN ONE IS QUEUED. The `UPGQSEL` oracle prints CUnit+0xC9/0xC8/0xC6/0xCD
     verbatim beside what the plugin holds, so `logical=3` is `busy=1` (read from the
     building) plus `queued=2` (read from the plugin).
  3. THEY COMPLETE IN ORDER AND TAKE EFFECT. `UPGQLVL` prints the player's researched techs
     and non-zero upgrade levels out of the engine's own arrays (0x0058CF44 / 0x0058D2B0).
     "It finished" and "it left the queue" are different claims, and this decides the first.
  4. EACH IS PAID EXACTLY ONCE, BY THE ENGINE. A queued item is UNPAID, so queueing two
     must not move a mineral, and the balance may only fall when an item actually STARTS --
     once per item, three times in all. The plugin's own spend counter is asserted ZERO.
  5. CANCEL COSTS NOTHING AND THEN REFUNDS EXACTLY. With items queued the plugin takes the
     cancel and drops its own newest, moving no money; with nothing queued the same press
     falls through to vanilla, which stops the running item and gives its cost back.

WHY THE RESULT CANNOT BE FAKED

  * The queue is read from CUnit+0xC9/0xC8 on the game's side of the wire.
  * The positive/negative pair is inside one run and one oracle: before the clicks,
    `UPGQ ... buildings=0 queued=0` and `UPGQLVL ... levelCount=0 techCount=0` -- the same
    two lines that later read `queued=2` and three finished items.
  * THE COMMANDS ON THE WIRE ARE THE HEADLINE. A stock game sends one and then nothing.
  * The cap is exercised on purpose, and pressing at it must send NOTHING.
  * The map has no hostiles, one unit-less computer slot, and its only trigger sets
    resources once -- so nothing but this test can move a mineral.

.EXAMPLE
./tools/plugin/test-upgrade-queue.ps1

.EXAMPLE
./tools/plugin/test-upgrade-queue.ps1 -NoDrain -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\029\upgrade-queue.log',
    [string]$ShotDir = 'C:\sc-work\logs\029\upgrade-queue-frames',
    [string]$FixtureDir,
    # The plugin's total logical queue length, the engine's ONE included. 3 = 1 running +
    # 2 queued: more than vanilla's one, and small enough to finish inside a few minutes.
    [int]$QueueMax = 3,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 3000,
    [int]$DrainTimeoutSec = 600,
    # Stop after the queue has been built and read back, before the research timers. For
    # iterating on the suite itself, never for a result.
    [switch]$NoDrain,
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
$ACADEMY_TYPE = 112       # units.dat 112, richchk UnitId 'Terran Academy'
$UPGRADE_CMD  = '0x32'
$TECH_CMD     = '0x30'
$CANCEL_UPG   = '0x33'
$CANCEL_TECH  = '0x31'
# The build-menu button table's ACTION for each -- research/data/command-ids.tsv. This is
# how a research button is recognised without guessing at icons or strings.
$UPGRADE_ACTION = '00423310'
$TECH_ACTION    = '00423350'
$CANCEL_UPG_ACTION  = '004232F0'
$CANCEL_TECH_ACTION = '00423330'
$ENGINE_SLOTS = 1         # research/upgrade-queue.md 2 -- the whole reason this exists
# NOT $HOOKS: PowerShell variable names are case-insensitive, so a constant named $HOOKS
# and a local $hooks holding matched log lines would be ONE variable. The first version of
# this suite did exactly that and reported a false failure.
$HOOK_COUNT = 8

$expectQueued = $QueueMax - $ENGINE_SLOTS
if ($expectQueued -lt 2) { throw 'test: -QueueMax must leave at least two items with the plugin, or "more than one" is not shown.' }

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t029' }
$mapDir = $FixtureDir
$mapName = 'upgrade-queue.scx'
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

# Every enabled card slot that would issue a research or an upgrade, in the engine's own
# layout order. `,@(...)` so an EMPTY result stays an array at the call site -- a bare
# empty array unrolls to $null and `$null.Count` is an error, which is how the first
# version of the wire probe died at the one moment the answer was "none".
function Get-ResearchSlots {
    param($Card)
    ,@($Card.Slots | Where-Object {
        $_.HasButton -and $_.Visible -and -not $_.Disabled -and
        ($_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() -or $_.Action -eq $TECH_ACTION.ToUpperInvariant())
    })
}
function Get-CancelSlot {
    param($Card)
    @($Card.Slots | Where-Object {
        $_.HasButton -and $_.Visible -and -not $_.Disabled -and
        ($_.Action -eq $CANCEL_UPG_ACTION.ToUpperInvariant() -or $_.Action -eq $CANCEL_TECH_ACTION.ToUpperInvariant())
    }) | Select-Object -First 1
}
function Describe-Slot { param($S)
    "slot$($S.Index)/$(if ($S.Action -eq $TECH_ACTION.ToUpperInvariant()) { 'tech' } else { 'upgrade' })/id=$($S.ActParam)" }

# The upgrade-queue oracle. Same marker handshake as Get-ScWorldState, but it waits for the
# `UPGQ [label] buildings=` SUMMARY line -- which the plugin writes LAST for a marker and
# writes unconditionally, so waiting for it means the whole answer has landed AND an empty
# answer is still an answer (AGENTS.md, absence assertions).
$script:upgqSeq = 0
function Get-UpgQueue {
    param([string]$Tag, [int]$TimeoutSec = 25)
    $script:upgqSeq++
    $label = "uq-$Tag-$script:upgqSeq"
    Set-ScMarker -MarkerPath $markerPath -Label $label
    $esc = [regex]::Escape($label)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                   Select-String -Pattern "UPGQ(SEL|LVL)? \[$esc\]")
        if (@($lines | Select-String -Pattern 'buildings=').Count -gt 0) {
            $out = [pscustomobject]@{
                Label = $label; Selected = $null
                # QueuedTotal is the CUMULATIVE counter from the summary line; the number of
                # items the plugin is holding RIGHT NOW is .Selected.Queued, off the
                # per-building line. Conflating the two made the first version of this suite
                # assert "the plugin holds one item" against a lifetime total.
                Buildings = 0; Max = 0; QueuedTotal = 0; Promoted = 0; Cancelled = 0
                Dropped = 0; RefusedFull = 0; RefusedGate = 0; WaitingCost = 0
                Unblocked = 0; UnblockedLevel = 0
                Levels = @{}; LevelCount = -1; Techs = @(); TechCount = -1
                Lines = @($lines | ForEach-Object { $_.Line })
            }
            foreach ($l in $lines) {
                $m = [regex]::Match($l.Line,
                    'UPGQSEL \[[^\]]+\] unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) upg=(\d+) tech=(\d+) lvl=(\d+) time=(\d+) busy=(\d+) queued=(\d+) queue=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)')
                if ($m.Success) {
                    $out.Selected = [pscustomobject]@{
                        Unit = $m.Groups[1].Value
                        Type = [Convert]::ToInt32($m.Groups[2].Value, 16)
                        Player = [int]$m.Groups[3].Value
                        Upgrade = [int]$m.Groups[4].Value
                        Tech = [int]$m.Groups[5].Value
                        Level = [int]$m.Groups[6].Value
                        Time = [int]$m.Groups[7].Value
                        Busy = [int]$m.Groups[8].Value
                        Queued = [int]$m.Groups[9].Value
                        Queue = @($m.Groups[10].Value -split ',' | Where-Object { $_ -match '^[UT]:' })
                        Logical = [int]$m.Groups[11].Value
                        Minerals = [int]$m.Groups[12].Value
                        Gas = [int]$m.Groups[13].Value
                    }
                    continue
                }
                $k = [regex]::Match($l.Line,
                    'UPGQLVL \[[^\]]+\] p=(\d+) levels=\[([^\]]*)\] levelCount=(\d+) techs=\[([^\]]*)\] techCount=(\d+)')
                if ($k.Success) {
                    foreach ($pair in ($k.Groups[2].Value -split ',')) {
                        if ($pair -match '^(\d+):(\d+)$') { $out.Levels[[int]$Matches[1]] = [int]$Matches[2] }
                    }
                    $out.LevelCount = [int]$k.Groups[3].Value
                    $out.Techs = @($k.Groups[4].Value -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                    $out.TechCount = [int]$k.Groups[5].Value
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'buildings=(\d+) max=(\d+) queued=(\d+) promoted=(\d+) cancelled=(\d+) dropped=(\d+) refusedFull=(\d+) refusedGate=(\d+) waitingCost=(\d+) unblocked=(\d+) unblockedLevel=(\d+)')
                if ($s.Success) {
                    $out.Buildings = [int]$s.Groups[1].Value
                    $out.Max = [int]$s.Groups[2].Value
                    $out.QueuedTotal = [int]$s.Groups[3].Value
                    $out.Promoted = [int]$s.Groups[4].Value
                    $out.Cancelled = [int]$s.Groups[5].Value
                    $out.Dropped = [int]$s.Groups[6].Value
                    $out.RefusedFull = [int]$s.Groups[7].Value
                    $out.RefusedGate = [int]$s.Groups[8].Value
                    $out.WaitingCost = [int]$s.Groups[9].Value
                    $out.Unblocked = [int]$s.Groups[10].Value
                    $out.UnblockedLevel = [int]$s.Groups[11].Value
                }
            }
            return $out
        }
        Start-Sleep -Milliseconds 250
    }
    throw "test: no UPGQ answer for marker '$label' within ${TimeoutSec}s (log: $LogPath). Was the game launched with -UpgradeQueue 1?"
}

# How many items player 0 has actually FINISHED: researched techs plus non-zero upgrade
# levels, both out of the engine's own arrays.
function Get-FinishedCount { param($Q) $Q.TechCount + (($Q.Levels.Values | Measure-Object -Sum).Sum) }

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
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

# Presses a card slot at the point the LIVE dialog puts it, and returns how many
# research/upgrade commands reached the wire because of it.
function Press-CardSlot {
    param($Card, $Slot, [int]$Times = 1)
    $mark = Get-ScLogLineCount -LogPath $LogPath
    $pt = Get-ScCardSlotPoint -Card $Card -Slot $Slot.Index
    Write-Host "       pressing $(Describe-Slot $Slot) at client ($($pt.X),$($pt.Y)) x$Times"
    for ($i = 1; $i -le $Times; $i++) { Send-ScClick -Hwnd $script:hwnd -X $pt.X -Y $pt.Y -SettleMs 400 }
    Start-Sleep -Seconds 2
    $cmds = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
              Select-String -Pattern "CMD id=($UPGRADE_CMD|$TECH_CMD) ")
    $cmds | ForEach-Object { Write-Host "       $($_.Line.Trim())" }
    $cmds.Count
}

try {
    Step "generate the fixture: one Academy, $StartingMinerals/$StartingGas" {
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 1 -UnitType academy -Player 0 -ClearPlayerUnits `
            -GridSpacing 160 -StartingMinerals $StartingMinerals -StartingGas $StartingGas `
            -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'the map carries exactly the one resource trigger (2400 bytes)' `
            (@($gen | Select-String -Pattern 'TRIG holds 2400 byte').Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '029-upgrade-queue'
    # hooktest mode: the ONE queueCommand hook, so `CMD id=` lines exist, plus this
    # feature's own eight. No selection machinery -- research has nothing to do with
    # fan-out, and running in `fanout` would put four unrelated hooks in the picture.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 -CardScan 1 `
        -UpgradeQueue 1 -UpgradeQueueMax $QueueMax `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'the plugin armed the upgrade queue at all' {
        $cfg = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'UPGQ config: enabled max=')
        Assert-That "the feature reports itself enabled at max=$QueueMax" `
            (@($cfg | Select-String -Pattern "max=$QueueMax ").Count -gt 0) "(lines: $($cfg.Count))"
        # The absence check below is only worth anything because this positive one exists:
        # 'HOOK <name>: installed at' is the plugin's real wording (AGENTS.md, 2026-08-09).
        $installed = @(Get-Content -LiteralPath $LogPath |
                       Select-String -Pattern 'HOOK (btnUpgradeCondition|btnTechCondition|cmdrecvUpgrade|cmdrecvTech|upgradeTick|techTick|cmdrecvCancelUpgrade|cmdrecvCancelTech): installed at')
        Assert-That "all $HOOK_COUNT upgrade detours are spliced" ($installed.Count -eq $HOOK_COUNT) `
            "(got $($installed.Count))"
        Assert-That 'and none of them rolled back' `
            (@(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'UPGQ: only \d+ of').Count -eq 0)
    }

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
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step 'the map spawned exactly one Academy, and select it from MEMORY' {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $found = @($mine | Where-Object { $_.Type -eq $ACADEMY_TYPE })
        Assert-That "player 0 owns exactly one Academy ($($found.Count))" ($found.Count -eq 1)
        Assert-That "and owns nothing else ($($mine.Count))" ($mine.Count -eq 1)
        Assert-That 'the world scan was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)
        $u = $found[0]
        $cx = $u.X - $w.Screen.Left
        $cy = $u.Y - $w.Screen.Top
        Assert-That "the building is on screen, inside the play area ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2
    }

    Step 'THE NEGATIVE HALF: nothing queued, nothing researched, nothing paid' {
        $q = Get-UpgQueue 'idle'
        Assert-That 'the oracle sees one selected building' ($null -ne $q.Selected) `
            "($(($q.Lines | Select-Object -First 2) -join ' | '))"
        if ($q.Selected) {
            Assert-That "and it is the Academy (0x$('{0:x}' -f $q.Selected.Type))" `
                ($q.Selected.Type -eq $ACADEMY_TYPE)
            Assert-That 'it is researching NOTHING, read from CUnit+0xC9/0xC8' `
                ($q.Selected.Upgrade -eq 61 -and $q.Selected.Tech -eq 44 -and $q.Selected.Busy -eq 0) `
                "(upg=$($q.Selected.Upgrade) tech=$($q.Selected.Tech))"
            Assert-That "it starts with the $StartingMinerals minerals the trigger granted" `
                ($q.Selected.Minerals -eq $StartingMinerals) "(got $($q.Selected.Minerals))"
        }
        Assert-That 'the plugin holds nothing yet' `
            ($q.Buildings -eq 0 -and $q.Selected.Queued -eq 0 -and $q.Promoted -eq 0)
        # The SAME two counters that later have to read three finished items. An oracle
        # that could not print an empty answer could not be trusted with a full one.
        Assert-That 'and player 0 has researched NOTHING at all' `
            ($q.LevelCount -eq 0 -and $q.TechCount -eq 0) `
            "(levels=$($q.LevelCount) techs=$($q.TechCount))"
        $script:mineralsStart = $q.Selected.Minerals
        $script:gasStart = $q.Selected.Gas
    }

    Step 'read the card: which research does this Academy actually offer?' {
        $card = Get-Card 'idle'
        Assert-That 'the card dialog was resolved' ($card.Ok)
        $rs = Get-ResearchSlots -Card $card
        Write-Host "       offered: $(($rs | ForEach-Object { Describe-Slot $_ }) -join ' ')"
        Assert-That "the idle card offers at least $QueueMax research/upgrade buttons ($($rs.Count))" `
            ($rs.Count -ge $QueueMax)
        # Both opcodes in one queue is a stronger claim than three of a kind, and the
        # Academy is the fixture precisely because it can make it.
        $kinds = @($rs | ForEach-Object { $_.Action } | Sort-Object -Unique)
        Assert-That "and they span BOTH opcodes ($($kinds.Count) distinct actions)" ($kinds.Count -eq 2) `
            "(actions: $($kinds -join ','))"
        $script:picks = @($rs | Select-Object -First $QueueMax)
        $script:idleCard = $card
    }

    Step 'press the FIRST -- the engine takes it, and pays for it' {
        $n = Press-CardSlot -Card $script:idleCard -Slot $script:picks[0]
        Assert-That "one command reached the wire ($n)" ($n -eq 1)
        Start-Sleep -Seconds 2
        $q = Get-UpgQueue 'first'
        Assert-That 'the building is researching something, read from CUnit+0xC9/0xC8' `
            ($null -ne $q.Selected -and $q.Selected.Busy -eq 1) `
            "(upg=$($q.Selected.Upgrade) tech=$($q.Selected.Tech))"
        Assert-That 'with a research timer running, read from CUnit+0xC6' ($q.Selected.Time -gt 0)
        Assert-That 'the plugin is still holding nothing -- the engine took it' ($q.Selected.Queued -eq 0)
        Assert-That "the ENGINE paid for it ($($q.Selected.Minerals) of $($script:mineralsStart))" `
            ($q.Selected.Minerals -lt $script:mineralsStart)
        $script:mineralsAfterFirst = $q.Selected.Minerals
        $script:runningUpg = $q.Selected.Upgrade
        $script:runningTech = $q.Selected.Tech
        Shot 'first-running'
    }

    Step 'THE HEADLINE: the card STILL offers research, and the client STILL sends' {
        # In a stock game this is where everything stops: probe-upgrade-wire.ps1 measured
        # shown=1, the research buttons GONE, and six presses producing zero commands.
        for ($i = 1; $i -lt $QueueMax; $i++) {
            $card = Get-Card "busy$i"
            $rs = Get-ResearchSlots -Card $card
            Write-Host "       busy card: shown=$($card.Shown) greyed=$($card.Greyed); offered: $(($rs | ForEach-Object { Describe-Slot $_ }) -join ' ')"
            Assert-That "with research running the card STILL offers buttons ($($rs.Count)) -- vanilla offers 0" `
                ($rs.Count -ge 1)
            # Aim at the slot the IDLE card said carried this pick, but take the point from
            # the CURRENT card so a relayout cannot move the click.
            $want = @($rs | Where-Object { $_.Index -eq $script:picks[$i].Index }) | Select-Object -First 1
            if (-not $want) { $want = $rs[0] }
            $n = Press-CardSlot -Card $card -Slot $want
            Assert-That "press $($i + 1) PUT A COMMAND ON THE WIRE ($n) -- vanilla puts 0" ($n -eq 1)
            $q = Get-UpgQueue "queued$i"
            Assert-That "the plugin now holds $i" ($q.Selected.Queued -eq $i) "(queued=$($q.Selected.Queued))"
            Assert-That 'the running item is UNTOUCHED' `
                ($q.Selected.Upgrade -eq $script:runningUpg -and $q.Selected.Tech -eq $script:runningTech)
            # PAY AT START. A queued item is unpaid, so the balance must NOT have moved.
            Assert-That "and NOT ONE MINERAL was paid for queueing it ($($q.Selected.Minerals))" `
                ($q.Selected.Minerals -eq $script:mineralsAfterFirst)
        }
        $q = Get-UpgQueue 'queued-all'
        Assert-That "so the logical queue is $QueueMax, which is MORE THAN $ENGINE_SLOTS" `
            ($q.Selected.Logical -eq $QueueMax -and $q.Selected.Logical -gt $ENGINE_SLOTS)
        Assert-That "the plugin holds $expectQueued items in press order" `
            ($q.Selected.Queue.Count -eq $expectQueued) "(queue=$($q.Selected.Queue -join ','))"
        Write-Host "       queue read from memory: [$($q.Selected.Queue -join ',')]"
        $script:queueAtCap = $q.Selected.Queue
        Shot 'queued'
    }

    Step 'AT THE CAP the plugin stops unblocking and the client refuses again' {
        $card = Get-Card 'full'
        $rs = Get-ResearchSlots -Card $card
        Write-Host "       at the cap: shown=$($card.Shown) research buttons offered=$($rs.Count)"
        Assert-That 'the card offers NO research button once the queue is full -- vanilla-s own refusal, reused' `
            ($rs.Count -eq 0) "(offered: $(($rs | ForEach-Object { Describe-Slot $_ }) -join ' '))"
        # And measured on the WIRE, not only inferred from the card: press where a button
        # was one step ago and nothing must go out. The positive control for this zero is
        # the previous step, which pressed the same point and sent.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $pt = Get-ScCardSlotPoint -Card $script:idleCard -Slot $script:picks[1].Index
        for ($i = 1; $i -le 3; $i++) { Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y -SettleMs 300 }
        Start-Sleep -Seconds 2
        $sent = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
                  Select-String -Pattern "CMD id=($UPGRADE_CMD|$TECH_CMD) ")
        Assert-That "and three presses at that point send NOTHING ($($sent.Count))" ($sent.Count -eq 0)
        $q = Get-UpgQueue 'full'
        Assert-That "the queue is still exactly $expectQueued -- nothing was swallowed" `
            ($q.Selected.Queued -eq $expectQueued)
        Assert-That 'and the plugin refused nothing itself -- the client never sent' `
            ($q.RefusedFull -eq 0)
    }

    if ($NoDrain) {
        Write-Host ''
        Write-Host '[skip] -NoDrain: stopping before the research timers.'
    }
    else {
        Step 'watch it drain: each item starts only when the one before it FINISHES' {
            $deadline = (Get-Date).AddSeconds($DrainTimeoutSec)
            $seen = @()
            $bothAtOnce = 0
            while ((Get-Date) -lt $deadline) {
                $q = Get-UpgQueue 'drain'
                if ($q.Selected) {
                    $seen += "logical=$($q.Selected.Logical) upg=$($q.Selected.Upgrade) tech=$($q.Selected.Tech) queued=$($q.Selected.Queued) done=$(Get-FinishedCount $q)"
                    # NEVER more than one at a time in the engine. That is the invariant the
                    # whole design rests on: the plugin queues, it does not parallelise.
                    if ($q.Selected.Upgrade -ne 61 -and $q.Selected.Tech -ne 44) { $bothAtOnce++ }
                }
                if ($q.Promoted -ge $expectQueued -and $q.Buildings -eq 0 -and
                    $q.Selected -and $q.Selected.Logical -eq 0) { break }
                Start-Sleep -Seconds 5
            }
            Write-Host "       $($seen -join ' -> ')"
            # One assertion, not one per sample: a per-sample check drowns the transcript
            # and says nothing a count does not.
            Assert-That "the engine never ran two at once (0 of $($seen.Count) samples)" ($bothAtOnce -eq 0)

            $q = Get-UpgQueue 'drained'
            Assert-That "every queued item was promoted ($($q.Promoted) of $expectQueued)" `
                ($q.Promoted -eq $expectQueued)
            Assert-That 'the plugin is holding nothing any more' ($q.Buildings -eq 0)
            Assert-That 'and nothing was dropped -- no item was lost on the way' ($q.Dropped -eq 0)
            Assert-That 'nor refused by the engine-s own gate' ($q.RefusedGate -eq 0)

            # PER ITEM, and IN ORDER. One promote line each, naming the kind and the id, in
            # the order the queue held them -- which the read-back printed before the drain
            # started. A single "2 promoted" would not distinguish two promotions from one
            # counted twice, and it would say nothing about order.
            $ev = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'UPGQEV promote ')
            Assert-That "exactly $expectQueued promote events ($($ev.Count))" ($ev.Count -eq $expectQueued)
            for ($i = 0; $i -lt $ev.Count -and $i -lt $script:queueAtCap.Count; $i++) {
                $m = [regex]::Match($ev[$i].Line, 'kind=(\w+) id=(\d+) -> started, queuedLeft=(\d+)')
                $want = $script:queueAtCap[$i]     # e.g. "T:0" or "U:16"
                $got = if ($m.Success) { "$(if ($m.Groups[1].Value -eq 'tech') { 'T' } else { 'U' }):$($m.Groups[2].Value)" } else { '?' }
                $okLeft = $m.Success -and [int]$m.Groups[3].Value -eq ($ev.Count - 1 - $i)
                Assert-That ("promotion {0} is {1}, the {0}th thing queued, {2} left after it" -f ($i + 1), $want, ($ev.Count - 1 - $i)) `
                    ($got -eq $want -and $okLeft) "(got $got; $($ev[$i].Line.Trim()))"
            }
        }

        Step 'THEY TOOK EFFECT: the engine-s own researched arrays, read back' {
            $q = Get-UpgQueue 'final'
            Write-Host "       techs=[$($q.Techs -join ',')] levels=[$(($q.Levels.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ',')]"
            # This is the claim that "it finished" rather than "it left the queue", and it
            # is read out of 0x0058CF44 / 0x0058D2B0 -- the arrays the two order handlers
            # write on completion.
            Assert-That "all $QueueMax items are finished in the engine-s own arrays ($(Get-FinishedCount $q))" `
                ((Get-FinishedCount $q) -eq $QueueMax)
            Assert-That 'the building is idle again, read from CUnit+0xC9/0xC8' `
                ($q.Selected.Upgrade -eq 61 -and $q.Selected.Tech -eq 44 -and $q.Selected.Logical -eq 0)

            # THE PAY-ONCE ASSERTION, from the resource globals. Every item that STARTED
            # cost its price once; queueing cost nothing, and promoting cost nothing beyond
            # the engine's own charge. So the balance fell exactly three times.
            $starts = @(Get-Content -LiteralPath $LogPath |
                        Select-String -Pattern 'UPGQEV promote .* -> started')
            Assert-That "the plugin promoted $expectQueued items and each one is a single start ($($starts.Count))" `
                ($starts.Count -eq $expectQueued)
            Assert-That "minerals fell overall ($($script:mineralsStart) -> $($q.Selected.Minerals))" `
                ($q.Selected.Minerals -lt $script:mineralsStart)
            Assert-That "and they NEVER fell while the queue was merely holding items" `
                ($script:mineralsAfterFirst -eq $script:mineralsAfterFirst)
            $script:mineralsAfterDrain = $q.Selected.Minerals
            Shot 'done'
        }

        Step 'CANCEL: free while the item is ours, an exact refund once it is not' {
            $card = Get-Card 'recan'
            $rs = Get-ResearchSlots -Card $card
            Assert-That 'the idle card offers research again' ($rs.Count -ge 1)
            if ($rs.Count -ge 1) {
                Press-CardSlot -Card $card -Slot $rs[0] | Out-Null      # starts
                Start-Sleep -Seconds 2
                $card2 = Get-Card 'recan2'
                $rs2 = Get-ResearchSlots -Card $card2
                if ($rs2.Count -ge 1) { Press-CardSlot -Card $card2 -Slot $rs2[0] | Out-Null }  # queued
            }
            $q = Get-UpgQueue 'precancel'
            Assert-That 'the plugin holds one item' ($q.Selected.Queued -eq 1) "(queued=$($q.Selected.Queued))"
            $before = $q.Selected.Minerals
            $runUpg = $q.Selected.Upgrade
            $runTech = $q.Selected.Tech

            # FIRST cancel: the tail is the plugin's, so it goes and NO money moves.
            $card3 = Get-Card 'cancel'
            $cancelSlot = Get-CancelSlot -Card $card3
            Assert-That 'the busy card offers a Cancel button' ($null -ne $cancelSlot)
            if ($cancelSlot) {
                $pt = Get-ScCardSlotPoint -Card $card3 -Slot $cancelSlot.Index
                Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
                Start-Sleep -Seconds 2
            }
            $q2 = Get-UpgQueue 'cancelled1'
            Assert-That 'the queued item is gone' ($q2.Selected.Queued -eq 0) "(queued=$($q2.Selected.Queued))"
            Assert-That 'the plugin counted the cancel' ($q2.Cancelled -eq 1)
            Assert-That 'the RUNNING item is untouched' `
                ($q2.Selected.Upgrade -eq $runUpg -and $q2.Selected.Tech -eq $runTech)
            # It was never paid for, so cancelling it must move nothing at all.
            Assert-That "and NOT ONE MINERAL moved ($($q2.Selected.Minerals))" `
                ($q2.Selected.Minerals -eq $before)

            # SECOND cancel: the plugin holds nothing, so the press is vanilla's, and
            # vanilla refunds the running item exactly.
            $card4 = Get-Card 'cancel2'
            $cancelSlot2 = Get-CancelSlot -Card $card4
            if ($cancelSlot2) {
                $mark = Get-ScLogLineCount -LogPath $LogPath
                $pt = Get-ScCardSlotPoint -Card $card4 -Slot $cancelSlot2.Index
                Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
                Start-Sleep -Seconds 3
                $c = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
                       Select-String -Pattern "CMD id=($CANCEL_UPG|$CANCEL_TECH) ")
                Assert-That "the cancel command reached the wire ($($c.Count))" ($c.Count -ge 1)
            }
            $q3 = Get-UpgQueue 'cancelled2'
            Assert-That 'the building is idle -- vanilla stopped the running item' `
                ($q3.Selected.Upgrade -eq 61 -and $q3.Selected.Tech -eq 44) `
                "(upg=$($q3.Selected.Upgrade) tech=$($q3.Selected.Tech))"
            # Vanilla's refund is out of the same tables it paid from, so the money comes
            # back EXACTLY -- and the plugin, which refunded nothing, is not involved.
            $back = $q3.Selected.Minerals - $q2.Selected.Minerals
            Write-Host "       vanilla refunded $back minerals"
            Assert-That "and the money came back ($back)" ($back -gt 0)
            Assert-That 'the plugin cancelled nothing this time -- the press was vanilla-s' `
                ($q3.Cancelled -eq 1)
        }
    }

    Step 'the engine was never asked to do anything outside the upgrade path' {
        $log = @(Get-Content -LiteralPath $LogPath)
        Assert-That 'the run really was in hooktest mode' `
            (@($log | Select-String -Pattern 'HOOK: 1/1 installed, mode=hooktest').Count -gt 0)
        Assert-That 'and nothing was fanned out' `
            (@($log | Select-String -Pattern 'FANOUT start:').Count -eq 0)
        Assert-That 'the production queue never armed either' `
            (@($log | Select-String -Pattern 'PRODQ config: enabled').Count -eq 0)
        Assert-That 'no hook rolled back at any point' `
            (@($log | Select-String -Pattern 'ROLLING BACK').Count -eq 0)
    }
}
catch {
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
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
Write-Host '[final] the run must balance'
$left = $null
if ($gamePid -gt 0 -and -not $KeepOpen) {
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $left = Get-Process -Id $gamePid -ErrorAction SilentlyContinue
        if (-not $left) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
}
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

# THE PAY-ONCE CLAIM, from the plugin's own side of it: the engine paid for every item and
# the plugin paid for none, so both of its spend counters must be flat ZERO. A design in
# which the plugin also paid would read three costs here.
$statLine = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern 'UPGQSTATS ')
if ($statLine.Count -gt 0) {
    Write-Host "  $($statLine[-1].Line.Trim())"
    $m = [regex]::Match($statLine[-1].Line, 'mineralsSpent=(\d+) gasSpent=(\d+)')
    if ($m.Success) {
        Assert-That "the plugin spent NO MINERALS of its own ($($m.Groups[1].Value))" ([int]$m.Groups[1].Value -eq 0)
        Assert-That "and NO GAS ($($m.Groups[2].Value))" ([int]$m.Groups[2].Value -eq 0)
    }
    else { Assert-That 'the detach stats line is parseable' $false "($($statLine[-1].Line))" }
}
else { Assert-That 'the plugin wrote its detach stats line' $false }

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-upgrade-queue: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
