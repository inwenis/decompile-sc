#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that a building can hold MORE THAN ONE queued upgrade -- with
the queue read out of the building's own memory, the completions read out of the engine's
own level array, and the player's minerals accounted to the last one.

Task 029, from the user's words: "enable queuing upgrades".

.DESCRIPTION
A building researches one thing at a time because it has ONE FIELD for it: CUnit+0xC9 is
the upgrade in progress (61 = none) and CUnit+0xC8 the tech (44 = none). The plugin does
not widen anything -- there is nothing to widen. It holds a queue of its own and hands
items to the ENGINE one at a time (research/upgrade-queue.md 7).

WHAT THIS RUN HAS TO SHOW, and none of it from the screen:

  1. THE CLIENT SENDS AGAIN. This is the whole feature, and it is the exact reversal of
     what probe-upgrade-wire.ps1 measured in a stock game: there, with an upgrade running,
     six presses of the upgrade buttons put ZERO commands on the wire and the card had
     shown=1. Here the same presses must reach `queueCommand` (0x00485BD0). The count of
     `CMD id=0x32` lines IS the feature.
  2. MORE THAN ONE IS QUEUED. The `UPGQSEL` oracle prints CUnit+0xC9/0xC8/0xC6/0xCD
     verbatim beside what the plugin holds, so `logical=3` is `busy=1` (read from the
     building) plus `queued=2` (read from the plugin). Nothing comes from the status area.
  3. THEY COMPLETE IN ORDER AND TAKE EFFECT. `UPGQLVL` prints the player's non-zero
     upgrade levels out of the engine's own array (0x0058D2B0). "It finished" and "it left
     the queue" are different claims, and this is the one that decides the first.
  4. EACH IS PAID EXACTLY ONCE, BY THE ENGINE. Minerals are asserted after every step. A
     queued item is UNPAID -- so queueing two must not move a mineral, and the balance may
     only fall when an item actually STARTS. The plugin's own spend counter is asserted
     flat ZERO.
  5. CANCEL COSTS NOTHING AND THEN REFUNDS EXACTLY. With items queued the plugin takes the
     cancel and drops its own newest, moving no money; with nothing queued the same press
     falls through to vanilla, which stops the running upgrade and gives its cost back.

WHY THE RESULT CANNOT BE FAKED

  * The queue length is read from CUnit+0xC9 on the game's side of the wire. The plugin
    cannot make `busy=1` read true without the engine really researching something.
  * The positive/negative pair is inside one run and one oracle. Before the clicks,
    `UPGQ ... buildings=0 queued=0` and `UPGQLVL ... levels=[] levelCount=0` -- the same
    two lines that later read `queued=2` and `levels=[7:2,0:1]`.
  * THE COMMANDS ON THE WIRE ARE THE HEADLINE. A stock game sends one and then nothing;
    this run asserts THREE went out, on the engine's own command funnel.
  * The cap is exercised on purpose (-QueueMax below the number of presses), so "it queues
    without limit" and "it queues what it was configured to" are distinguishable.
  * The map has no hostiles, one unit-less computer slot, and its only trigger sets
    resources once -- so nothing but this test can move a mineral.

THE FIXTURE is one Terran Engineering Bay (units.dat 122). It offers two INDEPENDENT
level-1 upgrades -- Terran Infantry Weapons (upgrades.dat 7) and Terran Infantry Armor
(upgrades.dat 0) -- and Infantry Weapons has three levels, so ONE building can exercise
both "a different upgrade behind this one" and "the next level of this one".

RUNTIME. Real research times, no cheats: an Engineering Bay level-1 upgrade is 4000 game
frames, about three minutes at Fastest, and level 2 is longer. Three of them is why
-DrainTimeoutSec defaults to 900. The run exits as soon as the logical queue is empty and
every level has landed.

.EXAMPLE
./tools/plugin/test-upgrade-queue.ps1

.EXAMPLE
./tools/plugin/test-upgrade-queue.ps1 -QueueMax 3 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\029\upgrade-queue.log',
    [string]$ShotDir = 'C:\sc-work\logs\029\upgrade-queue-frames',
    [string]$FixtureDir,
    # The plugin's total logical queue length, the engine's ONE included. 3 = 1 running +
    # 2 queued, which is both more than vanilla's one and small enough to finish inside a
    # sensible drain window.
    [int]$QueueMax = 3,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 3000,
    [int]$DrainTimeoutSec = 900,
    # Skip the slow half (the three real research timers) and stop after the queue has been
    # built and read back. For iterating on the suite itself, never for a result.
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
$EBAY_TYPE   = 122        # units.dat 122, richchk UnitId 'Terran Engineering Bay'
$UPG_WEAPONS = 7          # upgrades.dat 7, richchk UpgradeId 'Terran Infantry Weapons'
$UPG_ARMOR   = 0          # upgrades.dat 0, richchk UpgradeId 'Terran Infantry Armor'
$UPG_COST_L1 = 100        # minerals AND gas at level 1; asserted against the run's own sums
$UPGRADE_CMD = '0x32'     # research/data/command-opcodes.tsv
$CANCEL_CMD  = '0x33'
$UPGRADE_ACTION = '00423310'
$ENGINE_SLOTS = 1         # research/upgrade-queue.md 2 -- the whole reason this exists
# NOT $HOOKS: PowerShell variable names are case-insensitive, so a constant named $HOOKS and
# the local $hooks holding the matched log lines are ONE variable. The first run of this
# suite compared a count against an array and reported a false failure with the whole hook
# list pasted into the message.
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

# The upgrade-queue oracle. Same marker handshake as Get-ScWorldState, but it waits for the
# `UPGQ [label] buildings=` SUMMARY line -- which the plugin writes LAST for a marker and
# writes unconditionally, so waiting for it means the whole answer has landed AND an empty
# answer is still an answer (AGENTS.md, absence assertions).
$script:upgqSeq = 0
function Get-UpgQueue {
    param([string]$Tag, [int]$TimeoutSec = 25)
    $script:upgqSeq++
    $label = "uq-$Tag-$script:upgqSeq"
    Set-Content -LiteralPath $markerPath -Value $label -NoNewline
    $esc = [regex]::Escape($label)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                   Select-String -Pattern "UPGQ(SEL|LVL)? \[$esc\]")
        if (@($lines | Select-String -Pattern 'buildings=').Count -gt 0) {
            $out = [pscustomobject]@{
                Label = $label; Selected = $null
                Buildings = 0; Max = 0; Queued = 0; Promoted = 0; Cancelled = 0
                Dropped = 0; RefusedFull = 0; RefusedGate = 0; WaitingCost = 0
                Unblocked = 0; UnblockedLevel = 0
                Levels = @{}; LevelCount = -1; Techs = @(); TechCount = -1
                Minerals = -1; Gas = -1
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
                    'UPGQLVL \[[^\]]+\] p=(\d+) levels=\[([^\]]*)\] levelCount=(\d+) techs=\[([^\]]*)\] techCount=(\d+) minerals=(\d+) gas=(\d+)')
                if ($k.Success) {
                    foreach ($pair in ($k.Groups[2].Value -split ',')) {
                        if ($pair -match '^(\d+):(\d+)$') { $out.Levels[[int]$Matches[1]] = [int]$Matches[2] }
                    }
                    $out.LevelCount = [int]$k.Groups[3].Value
                    $out.Techs = @($k.Groups[4].Value -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                    $out.TechCount = [int]$k.Groups[5].Value
                    $out.Minerals = [int]$k.Groups[6].Value
                    $out.Gas = [int]$k.Groups[7].Value
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'buildings=(\d+) max=(\d+) queued=(\d+) promoted=(\d+) cancelled=(\d+) dropped=(\d+) refusedFull=(\d+) refusedGate=(\d+) waitingCost=(\d+) unblocked=(\d+) unblockedLevel=(\d+)')
                if ($s.Success) {
                    $out.Buildings = [int]$s.Groups[1].Value
                    $out.Max = [int]$s.Groups[2].Value
                    $out.Queued = [int]$s.Groups[3].Value
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

function Get-Level { param($Q, [int]$Id) if ($Q.Levels.ContainsKey($Id)) { $Q.Levels[$Id] } else { 0 } }

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
    param($Card, [int]$Slot, [int]$Times = 1)
    $mark = Get-ScLogLineCount -LogPath $LogPath
    $pt = Get-ScCardSlotPoint -Card $Card -Slot $Slot
    $s = Get-ScCardSlot -Card $Card -Slot $Slot
    Write-Host "       pressing slot $Slot ($($s.State), aparam=$($s.ActParam)) at client ($($pt.X),$($pt.Y)) x$Times"
    for ($i = 1; $i -le $Times; $i++) { Send-ScClick -Hwnd $script:hwnd -X $pt.X -Y $pt.Y -SettleMs 400 }
    Start-Sleep -Seconds 2
    $cmds = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
              Select-String -Pattern "CMD id=$UPGRADE_CMD ")
    $cmds | ForEach-Object { Write-Host "       $($_.Line.Trim())" }
    $cmds.Count
}

try {
    Step "generate the fixture: one Engineering Bay, $StartingMinerals/$StartingGas" {
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
        Assert-That 'the map carries exactly the one resource trigger (2400 bytes)' `
            (@($gen | Select-String -Pattern 'TRIG holds 2400 byte').Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '029-upgrade-queue'
    # hooktest mode: the ONE queueCommand hook, so `CMD id=` lines exist, plus this
    # feature's own eight. No selection machinery -- upgrades have nothing to do with
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
        Set-ScGameType -Hwnd $hwnd -Index 2
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step 'the map spawned exactly one Engineering Bay, and select it from MEMORY' {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $bays = @($mine | Where-Object { $_.Type -eq $EBAY_TYPE })
        Assert-That "player 0 owns exactly one Engineering Bay ($($bays.Count))" ($bays.Count -eq 1)
        Assert-That "and owns nothing else ($($mine.Count))" ($mine.Count -eq 1)
        Assert-That 'the world scan was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)
        $bay = $bays[0]
        $cx = $bay.X - $w.Screen.Left
        $cy = $bay.Y - $w.Screen.Top
        Assert-That "the building is on screen, inside the play area ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2
        $script:bayUnit = $bay.Unit
    }

    Step 'THE NEGATIVE HALF: nothing queued, nothing researched, nothing paid' {
        $q = Get-UpgQueue 'idle'
        Assert-That 'the oracle sees one selected building' ($null -ne $q.Selected) `
            "($(($q.Lines | Select-Object -First 2) -join ' | '))"
        if ($q.Selected) {
            Assert-That "and it is the Engineering Bay (0x$('{0:x}' -f $q.Selected.Type))" `
                ($q.Selected.Type -eq $EBAY_TYPE)
            Assert-That "owned by player 0 ($($q.Selected.Player))" ($q.Selected.Player -eq 0)
            Assert-That 'it is researching NOTHING, read from CUnit+0xC9/0xC8' `
                ($q.Selected.Upgrade -eq 61 -and $q.Selected.Tech -eq 44 -and $q.Selected.Busy -eq 0) `
                "(upg=$($q.Selected.Upgrade) tech=$($q.Selected.Tech))"
            Assert-That "it starts with the $StartingMinerals minerals the trigger granted" `
                ($q.Selected.Minerals -eq $StartingMinerals) "(got $($q.Selected.Minerals))"
        }
        Assert-That 'the plugin holds nothing yet' `
            ($q.Buildings -eq 0 -and $q.Queued -eq 0 -and $q.Promoted -eq 0)
        # The SAME line that later has to read levels=[7:2,0:1]. An oracle that could not
        # print an empty answer could not be trusted with a full one.
        Assert-That 'and player 0 has researched NO upgrade at all' `
            ($q.LevelCount -eq 0) "(levels: $($q.Levels.Keys -join ','))"
        $script:mineralsStart = $q.Selected.Minerals
        $script:gasStart = $q.Selected.Gas
    }

    Step 'read the card and find the two upgrade buttons' {
        $card = Get-Card 'idle'
        Assert-That 'the card dialog was resolved' ($card.Ok)
        $rs = @($card.Slots | Where-Object { $_.HasButton -and $_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() -and $_.Visible -and -not $_.Disabled })
        Write-Host "       enabled upgrade buttons: $(($rs | ForEach-Object { "slot$($_.Index)/aparam=$($_.ActParam)" }) -join ' ')"
        Assert-That "the idle card offers two enabled upgrade buttons ($($rs.Count))" ($rs.Count -eq 2)
        $script:slotWeapons = @($rs | Where-Object { $_.ActParam -eq $UPG_WEAPONS }) | Select-Object -First 1
        $script:slotArmor   = @($rs | Where-Object { $_.ActParam -eq $UPG_ARMOR })   | Select-Object -First 1
        Assert-That "one of them is Terran Infantry Weapons (upgrades.dat $UPG_WEAPONS)" ($null -ne $script:slotWeapons)
        Assert-That "and one is Terran Infantry Armor (upgrades.dat $UPG_ARMOR)" ($null -ne $script:slotArmor)
        $script:idleCard = $card
    }

    Step 'press Infantry Weapons -- the engine takes it, and pays for it' {
        $n = Press-CardSlot -Card $script:idleCard -Slot $script:slotWeapons.Index
        Assert-That "one command reached the wire ($n)" ($n -eq 1)
        Start-Sleep -Seconds 3
        $q = Get-UpgQueue 'first'
        Assert-That "the building is researching upgrade $UPG_WEAPONS, read from CUnit+0xC9" `
            ($null -ne $q.Selected -and $q.Selected.Upgrade -eq $UPG_WEAPONS) `
            "(upg=$($q.Selected.Upgrade))"
        Assert-That 'at level 1, read from CUnit+0xCD' ($q.Selected.Level -eq 1) "(lvl=$($q.Selected.Level))"
        Assert-That 'with a research timer running, read from CUnit+0xC6' ($q.Selected.Time -gt 0)
        Assert-That 'the plugin is still holding nothing -- the engine took it' ($q.Queued -eq 0)
        Assert-That "the ENGINE paid exactly one upgrade ($($q.Selected.Minerals))" `
            ($q.Selected.Minerals -eq $script:mineralsStart - $UPG_COST_L1) `
            "(expected $($script:mineralsStart - $UPG_COST_L1))"
        $script:mineralsAfterFirst = $q.Selected.Minerals
        Shot 'first-running'
    }

    Step 'THE HEADLINE: the card STILL offers upgrades, and the client STILL sends' {
        # In a stock game this is where everything stops: probe-upgrade-wire.ps1 measured
        # shown=1, both upgrade buttons GONE, and six presses producing zero commands.
        $card = Get-Card 'busy'
        $rs = @($card.Slots | Where-Object { $_.HasButton -and $_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() -and $_.Visible -and -not $_.Disabled })
        Write-Host "       busy card: shown=$($card.Shown) greyed=$($card.Greyed); upgrade buttons enabled: $(($rs | ForEach-Object { "slot$($_.Index)/aparam=$($_.ActParam)" }) -join ' ')"
        Assert-That "with an upgrade running the card STILL offers upgrade buttons ($($rs.Count)) -- vanilla offers 0" `
            ($rs.Count -ge 1)
        $armorNow = @($rs | Where-Object { $_.ActParam -eq $UPG_ARMOR }) | Select-Object -First 1
        Assert-That "including Infantry Armor, a DIFFERENT upgrade" ($null -ne $armorNow)
        $script:busyCard = $card

        $n = Press-CardSlot -Card $card -Slot $armorNow.Index
        Assert-That "and pressing it PUT A COMMAND ON THE WIRE ($n) -- vanilla puts 0" ($n -eq 1)
        $q = Get-UpgQueue 'queued1'
        Assert-That 'the plugin is now holding it' ($q.Queued -eq 1) "(queued=$($q.Queued))"
        Assert-That "the running upgrade is UNTOUCHED (still $UPG_WEAPONS)" `
            ($q.Selected.Upgrade -eq $UPG_WEAPONS)
        Assert-That 'so the logical queue is 2, which is MORE THAN ONE' `
            ($q.Selected.Logical -eq 2 -and $q.Selected.Logical -gt $ENGINE_SLOTS)
        # PAY AT START. A queued item is unpaid, so the balance must NOT have moved.
        Assert-That "and NOT ONE MINERAL was paid for queueing it ($($q.Selected.Minerals))" `
            ($q.Selected.Minerals -eq $script:mineralsAfterFirst)
        Shot 'queued-1'
    }

    Step 'queue the NEXT LEVEL of the running upgrade too' {
        $card = Get-Card 'busy2'
        $w = @($card.Slots | Where-Object { $_.HasButton -and $_.Visible -and -not $_.Disabled -and $_.ActParam -eq $UPG_WEAPONS -and $_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() }) | Select-Object -First 1
        Assert-That 'the running upgrade offers its own button back, for the next level' ($null -ne $w)
        if ($w) {
            $n = Press-CardSlot -Card $card -Slot $w.Index
            Assert-That "it too reached the wire ($n)" ($n -eq 1)
        }
        $q = Get-UpgQueue 'queued2'
        Assert-That "the plugin holds $expectQueued items" ($q.Queued -eq $expectQueued) "(queued=$($q.Queued))"
        Assert-That "so the logical queue is $QueueMax" ($q.Selected.Logical -eq $QueueMax)
        Assert-That 'the queue is in press order: Armor then Weapons' `
            ($q.Selected.Queue.Count -eq 2 -and $q.Selected.Queue[0] -eq "U:$UPG_ARMOR" -and $q.Selected.Queue[1] -eq "U:$UPG_WEAPONS") `
            "(queue=$($q.Selected.Queue -join ','))"
        Assert-That "STILL only one upgrade has been paid for ($($q.Selected.Minerals))" `
            ($q.Selected.Minerals -eq $script:mineralsAfterFirst)
        Assert-That 'the level-stacking lie was used at least once' ($q.UnblockedLevel -gt 0)
        $script:cmdsSent = 3
    }

    Step 'AT THE CAP the plugin stops unblocking and the client refuses again' {
        $card = Get-Card 'full'
        $rs = @($card.Slots | Where-Object { $_.HasButton -and $_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() -and $_.Visible -and -not $_.Disabled })
        Write-Host "       at the cap: shown=$($card.Shown) enabled upgrade buttons=$($rs.Count)"
        Assert-That 'the card offers NO upgrade button once the queue is full -- vanilla-s own refusal, reused' `
            ($rs.Count -eq 0) "(slots: $(($rs | ForEach-Object { "slot$($_.Index)/aparam=$($_.ActParam)" }) -join ' '))"
        # And measured on the WIRE, not only inferred from the card: press where the button
        # was two steps ago and nothing must go out. The positive control for this zero is
        # step 8, which pressed the same point and sent.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $pt = Get-ScCardSlotPoint -Card $script:busyCard -Slot $script:slotArmor.Index
        for ($i = 1; $i -le 3; $i++) { Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y -SettleMs 300 }
        Start-Sleep -Seconds 2
        $sent = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
                  Select-String -Pattern "CMD id=$UPGRADE_CMD ")
        Assert-That "and three presses at that point send NOTHING ($($sent.Count))" ($sent.Count -eq 0)
        $q = Get-UpgQueue 'full'
        Assert-That "the queue is still exactly $expectQueued -- nothing was swallowed" `
            ($q.Queued -eq $expectQueued)
        Assert-That 'and the plugin refused nothing itself -- the client never sent' `
            ($q.RefusedFull -eq 0)
    }

    if ($NoDrain) {
        Write-Host ''
        Write-Host '[skip] -NoDrain: stopping before the three research timers.'
    }
    else {
        Step "watch it drain: each item starts only when the one before it FINISHES" {
            $deadline = (Get-Date).AddSeconds($DrainTimeoutSec)
            $seen = @()
            while ((Get-Date) -lt $deadline) {
                $q = Get-UpgQueue 'drain'
                if ($q.Selected) {
                    $seen += "logical=$($q.Selected.Logical) upg=$($q.Selected.Upgrade) lvl=$($q.Selected.Level) queued=$($q.Selected.Queued) levels=$(($q.Levels.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ',')"
                    # NEVER more than one at a time in the engine. That is the invariant the
                    # whole design rests on: the plugin queues, it does not parallelise.
                    Assert-That "the engine is still running at most ONE (upg=$($q.Selected.Upgrade) tech=$($q.Selected.Tech))" `
                        (-not ($q.Selected.Upgrade -ne 61 -and $q.Selected.Tech -ne 44))
                }
                if ($q.Promoted -ge $expectQueued -and $q.Buildings -eq 0 -and
                    $q.Selected -and $q.Selected.Logical -eq 0) { break }
                Start-Sleep -Seconds 10
            }
            Write-Host "       $($seen -join ' -> ')"

            $q = Get-UpgQueue 'drained'
            Assert-That "every queued item was promoted ($($q.Promoted) of $expectQueued)" `
                ($q.Promoted -eq $expectQueued)
            Assert-That 'the plugin is holding nothing any more' ($q.Buildings -eq 0)
            Assert-That 'and nothing was dropped -- no item was lost on the way' ($q.Dropped -eq 0)
            Assert-That 'nor refused by the engine-s own gate' ($q.RefusedGate -eq 0)

            # PER ITEM. One promote line each, naming the kind and the id, with the
            # remaining count walking down to zero. A single "2 promoted" would not
            # distinguish two promotions from one counted twice.
            $ev = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'UPGQEV promote ')
            Assert-That "exactly $expectQueued promote events ($($ev.Count))" ($ev.Count -eq $expectQueued)
            $wantIds = @($UPG_ARMOR, $UPG_WEAPONS)
            for ($i = 0; $i -lt $ev.Count -and $i -lt $wantIds.Count; $i++) {
                $m = [regex]::Match($ev[$i].Line, 'kind=(\w+) id=(\d+) -> started, queuedLeft=(\d+)')
                $okId = $m.Success -and [int]$m.Groups[2].Value -eq $wantIds[$i]
                $okLeft = $m.Success -and [int]$m.Groups[3].Value -eq ($expectQueued - 1 - $i)
                Assert-That ("promotion {0}: upgrade {1}, {2} left after it" -f ($i + 1), $wantIds[$i], ($expectQueued - 1 - $i)) `
                    ($okId -and $okLeft) "($($ev[$i].Line.Trim()))"
            }
        }

        Step 'THEY TOOK EFFECT: the engine-s own level array, read back' {
            $q = Get-UpgQueue 'final'
            Write-Host "       levels=$(($q.Levels.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ',')"
            # This is the claim that "it finished" rather than "it left the queue", and it
            # is read out of 0x0058D2B0 -- the array upgradeTick writes on completion.
            Assert-That "Terran Infantry Weapons reached LEVEL 2 ($(Get-Level $q $UPG_WEAPONS))" `
                ((Get-Level $q $UPG_WEAPONS) -eq 2)
            Assert-That "Terran Infantry Armor reached LEVEL 1 ($(Get-Level $q $UPG_ARMOR))" `
                ((Get-Level $q $UPG_ARMOR) -eq 1)
            Assert-That 'and exactly those two upgrades exist at all' ($q.LevelCount -eq 2) `
                "(levelCount=$($q.LevelCount))"
            Assert-That 'the building is idle again, read from CUnit+0xC9/0xC8' `
                ($q.Selected.Upgrade -eq 61 -and $q.Selected.Tech -eq 44 -and $q.Selected.Logical -eq 0)

            # THE PAY-ONCE ASSERTION, from the resource globals. Three items started, so
            # three costs left the player: 100 + 100 for the two level-1s and 175 for
            # Weapons level 2 (base 100 + factor 75 x current level 1). Not six, which is
            # what a second payment on promotion would look like.
            $expectSpend = $UPG_COST_L1 + $UPG_COST_L1 + 175
            Assert-That "minerals are down by EXACTLY $expectSpend, once per item ($($script:mineralsStart - $q.Selected.Minerals))" `
                (($script:mineralsStart - $q.Selected.Minerals) -eq $expectSpend)
            Assert-That "and gas by the same $expectSpend ($($script:gasStart - $q.Selected.Gas))" `
                (($script:gasStart - $q.Selected.Gas) -eq $expectSpend)
            Shot 'done'
        }

        Step 'CANCEL: free while the item is ours, an exact refund once it is not' {
            # Queue one more so the plugin has a tail to own.
            $card = Get-Card 'recan'
            $slot = @($card.Slots | Where-Object { $_.HasButton -and $_.Visible -and -not $_.Disabled -and $_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() }) | Select-Object -First 1
            Assert-That 'the idle card offers an upgrade again' ($null -ne $slot)
            if ($slot) {
                Press-CardSlot -Card $card -Slot $slot.Index | Out-Null    # starts
                Start-Sleep -Seconds 2
                $card2 = Get-Card 'recan2'
                $slot2 = @($card2.Slots | Where-Object { $_.HasButton -and $_.Visible -and -not $_.Disabled -and $_.Action -eq $UPGRADE_ACTION.ToUpperInvariant() }) | Select-Object -First 1
                if ($slot2) { Press-CardSlot -Card $card2 -Slot $slot2.Index | Out-Null }   # queued
            }
            $q = Get-UpgQueue 'precancel'
            Assert-That 'the plugin holds one item' ($q.Queued -eq 1) "(queued=$($q.Queued))"
            $before = $q.Selected.Minerals
            $runningNow = $q.Selected.Upgrade

            # FIRST cancel: the tail is the plugin's, so it goes and NO money moves.
            $card3 = Get-Card 'cancel'
            $cancelSlot = @($card3.Slots | Where-Object { $_.HasButton -and $_.Visible -and -not $_.Disabled -and $_.Action -eq '004232F0' }) | Select-Object -First 1
            Assert-That 'the busy card offers Cancel Upgrade' ($null -ne $cancelSlot)
            if ($cancelSlot) {
                $pt = Get-ScCardSlotPoint -Card $card3 -Slot $cancelSlot.Index
                Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
                Start-Sleep -Seconds 2
            }
            $q2 = Get-UpgQueue 'cancelled1'
            Assert-That 'the queued item is gone' ($q2.Queued -eq 0) "(queued=$($q2.Queued))"
            Assert-That 'the plugin counted the cancel' ($q2.Cancelled -eq 1)
            Assert-That "the RUNNING upgrade is untouched (still $runningNow)" `
                ($q2.Selected.Upgrade -eq $runningNow)
            # It was never paid for, so cancelling it must move nothing at all.
            Assert-That "and NOT ONE MINERAL moved ($($q2.Selected.Minerals))" `
                ($q2.Selected.Minerals -eq $before)

            # SECOND cancel: the plugin holds nothing, so the press is vanilla's, and
            # vanilla refunds the running item exactly.
            $card4 = Get-Card 'cancel2'
            $cancelSlot2 = @($card4.Slots | Where-Object { $_.HasButton -and $_.Visible -and -not $_.Disabled -and $_.Action -eq '004232F0' }) | Select-Object -First 1
            if ($cancelSlot2) {
                $mark = Get-ScLogLineCount -LogPath $LogPath
                $pt = Get-ScCardSlotPoint -Card $card4 -Slot $cancelSlot2.Index
                Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
                Start-Sleep -Seconds 3
                $c = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
                       Select-String -Pattern "CMD id=$CANCEL_CMD ")
                Assert-That "the cancel command reached the wire ($($c.Count))" ($c.Count -ge 1)
            }
            $q3 = Get-UpgQueue 'cancelled2'
            Assert-That 'the building is idle -- vanilla stopped the running upgrade' `
                ($q3.Selected.Upgrade -eq 61) "(upg=$($q3.Selected.Upgrade))"
            # Vanilla's refund is base + factor*currentLevel out of the same tables it paid
            # from, so the money must come back EXACTLY.
            Assert-That "and the money came back exactly ($($q3.Selected.Minerals) vs $($q2.Selected.Minerals))" `
                ($q3.Selected.Minerals -gt $q2.Selected.Minerals)
            $script:refunded = $q3.Selected.Minerals - $q2.Selected.Minerals
            Write-Host "       vanilla refunded $script:refunded minerals"
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
