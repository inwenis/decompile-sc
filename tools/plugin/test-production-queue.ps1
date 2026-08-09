#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that a production building can hold MORE THAN FIVE queued
items -- with the queue read out of the building's own memory, not off the screen, and
with the player's minerals accounted to the last one.

Task 025, from the user's words: "enable queuing more then 5 units."

.DESCRIPTION
The engine's queue is `u16 buildQueue[5]` at `CUnit+0x98`, a five-slot ring whose head is
the byte at `+0xA4`, and the 5 is a literal in six functions
(research/production-queue.md 2-3). The plugin does not widen it. It holds the tail of the
logical queue itself and hands items to the engine's five as slots free up, paying for each
item EXACTLY ONCE at the moment it accepts it -- which is what vanilla does
(production-queue.md 4.2).

So there are three claims to make in a live game, and this suite makes all three from
memory reads:

  1. MORE THAN FIVE ARE QUEUED. The `PRODQSEL` oracle prints the five slots of
     `CUnit+0x98` verbatim beside the plugin's own overflow, so `logical=9` is
     `engineLen=5` (read from the building) plus `overflow=4` (read from the plugin).
     Nothing here comes from the status area, which still draws five icons.
  2. THEY BUILD, IN ORDER, ONE PER FREED SLOT. Every promotion logs a `PRODQEV promote`
     line naming the type, the slot it went into and how many are left; the run asserts
     one per over-cap item, with the count walking down to zero, and then asserts the
     resulting units exist in the engine's own unit list.
  3. EACH IS PAID FOR ONCE. Minerals are asserted to an exact figure after the burst and
     asserted UNCHANGED thereafter -- promotion moves no money, so a second payment would
     show up as a drop while the queue drains.

WHY THE RESULT CANNOT BE FAKED

  * The queue length is read from `CUnit+0x98` on the game's side of the wire. The plugin
    cannot make `engineLen` read 5 without five real entries being there.
  * The positive/negative pair is inside one run and one oracle. Before the clicks,
    `PRODQ ... buildings=0 captured=0` -- the same line that later reads `captured=4`. An
    oracle that could not fail would print the second without the first.
  * The counters are arithmetic, not narrative: 12 clicks, 4 captured, 3 refused by the
    cap => 5 went to the engine, which is the engine's cap stated as a subtraction.
  * The cap refusal is exercised on purpose (`-QueueMax` below `-Clicks`), so "the plugin
    accepted everything" and "the plugin accepted what it was configured to" are
    distinguishable.
  * The map has no hostiles, one unit-less computer slot, and its only trigger sets
    resources once -- so nothing but this test can move a mineral.

THE FIXTURE needs something no earlier one did: STARTING RESOURCES. A CHK has no such
field and Use Map Settings hands out none, so task 025 added `--starting-minerals` /
`--starting-gas` to tools/make_test_map.py -- one `Always -> Set Resources` trigger, and
the generator's own validation proves from the bytes that the trigger carries no
game-ending action.

.EXAMPLE
./tools/plugin/test-production-queue.ps1

.EXAMPLE
./tools/plugin/test-production-queue.ps1 -Clicks 12 -QueueMax 9 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\025\production-queue.log',
    [string]$ShotDir = 'C:\sc-work\logs\025\production-frames',
    [string]$FixtureDir,
    # How many times the Train hotkey is pressed. Deliberately MORE than -QueueMax, so the
    # cap refusal is exercised rather than assumed absent.
    [int]$Clicks = 12,
    # The plugin's total logical queue length, the engine's five included. 9 = 5 engine +
    # 4 plugin, which is both comfortably over the vanilla cap and inside the 10 supply a
    # lone Command Center provides -- so the fixture needs no Supply Depot to be placeable
    # for the run to mean anything.
    [int]$QueueMax = 9,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 1000,
    # Long enough for nine SCVs. One SCV is 20 game seconds; a single-player custom game
    # runs at Fastest, so ~9-13 real seconds each. 240s leaves room and the drain loop
    # exits as soon as the queue is empty.
    [int]$DrainTimeoutSec = 240,
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
$CC_TYPE   = 106          # units.dat 106, richchk UnitId 'Terran Command Center'
$SCV_TYPE  = 7            # units.dat 7,   richchk UnitId 'Terran SCV'
$SCV_COST  = 50           # minerals; asserted against the run's own arithmetic below
$TRAIN_KEY = 0x53         # 'S', the Command Center command card's Train SCV hotkey
$TRAIN_CMD = '0x1F'       # research/data/command-opcodes.tsv
$ENGINE_SLOTS = 5         # research/production-queue.md 2.3

$expectOverflow = $QueueMax - $ENGINE_SLOTS
$expectRefused  = $Clicks - $QueueMax
if ($expectOverflow -lt 1) { throw "test: -QueueMax must exceed the engine's $ENGINE_SLOTS slots." }
if ($expectRefused -lt 1) { throw 'test: -Clicks must exceed -QueueMax, or the cap refusal is never exercised.' }

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t025' }
$mapDir = $FixtureDir
$mapName = 'production-queue.scx'
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

# PER ITEM, on the engine's side. `engineLen=5` is a count and a count can be produced by
# the wrong five things; this names every slot and says which one is wrong.
function Assert-EverySlot {
    param($Selected, [int]$WantType)
    $bad = @()
    for ($i = 0; $i -lt $Selected.Engine.Count; $i++) {
        if ($Selected.Engine[$i] -ne $WantType) { $bad += ("slot{0}=0x{1:x}" -f $i, $Selected.Engine[$i]) }
    }
    Assert-That ("all {0} slots of CUnit+0x98 hold unit type 0x{1:x}" -f $Selected.Engine.Count, $WantType) `
        ($Selected.Engine.Count -eq $ENGINE_SLOTS -and $bad.Count -eq 0) `
        ($bad.Count -gt 0 ? "(wrong: $($bad -join ' '))" : "(only $($Selected.Engine.Count) slots parsed)")
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

# The production-queue oracle. Same marker handshake as Get-ScWorldState, but it waits for
# the `PRODQ [label] buildings=` SUMMARY line -- which the plugin writes LAST for a marker,
# and writes unconditionally, so waiting for it means the whole answer has landed AND an
# empty answer is still an answer. (Absence has to be positively reported; see AGENTS.md.)
$script:prodqSeq = 0
function Get-ProdQueue {
    param([string]$Tag, [int]$TimeoutSec = 20)
    $script:prodqSeq++
    $label = "pq-$Tag-$script:prodqSeq"
    Set-Content -LiteralPath $markerPath -Value $label -NoNewline
    $esc = [regex]::Escape($label)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                   Select-String -Pattern "PRODQ(SEL)? \[$esc\]")
        $summary = @($lines | Select-String -Pattern 'buildings=')
        if ($summary.Count -gt 0) {
            $out = [pscustomobject]@{
                Label = $label; Selected = $null
                Buildings = 0; Max = 0; Captured = 0; Promoted = 0
                Cancelled = 0; Refunded = 0; RefusedFull = 0; RefusedCost = 0
                Tracked = @(); Lines = @($lines | ForEach-Object { $_.Line })
            }
            foreach ($l in $lines) {
                $m = [regex]::Match($l.Line,
                    'PRODQSEL \[[^\]]+\] unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) logical=(\d+) minerals=(\d+) gas=(\d+)')
                if ($m.Success) {
                    $out.Selected = [pscustomobject]@{
                        Unit = $m.Groups[1].Value
                        Type = [Convert]::ToInt32($m.Groups[2].Value, 16)
                        Player = [int]$m.Groups[3].Value
                        Head = [int]$m.Groups[4].Value
                        EngineLen = [int]$m.Groups[5].Value
                        Engine = @($m.Groups[6].Value -split ',' | ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                        Overflow = [int]$m.Groups[7].Value
                        Logical = [int]$m.Groups[8].Value
                        Minerals = [int]$m.Groups[9].Value
                        Gas = [int]$m.Groups[10].Value
                    }
                    continue
                }
                $t = [regex]::Match($l.Line,
                    'PRODQ \[[^\]]+\] unit=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) overflowTypes=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)')
                if ($t.Success) {
                    $out.Tracked += [pscustomobject]@{
                        Unit = $t.Groups[1].Value
                        EngineLen = [int]$t.Groups[4].Value
                        Overflow = [int]$t.Groups[6].Value
                        OverflowTypes = @($t.Groups[7].Value -split ',' |
                                          Where-Object { $_ -match '^0x' } |
                                          ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                        Logical = [int]$t.Groups[8].Value
                        Minerals = [int]$t.Groups[9].Value
                    }
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+) refusedCost=(\d+)')
                if ($s.Success) {
                    $out.Buildings = [int]$s.Groups[1].Value
                    $out.Max = [int]$s.Groups[2].Value
                    $out.Captured = [int]$s.Groups[3].Value
                    $out.Promoted = [int]$s.Groups[4].Value
                    $out.Cancelled = [int]$s.Groups[5].Value
                    $out.Refunded = [int]$s.Groups[6].Value
                    $out.RefusedFull = [int]$s.Groups[7].Value
                    $out.RefusedCost = [int]$s.Groups[8].Value
                }
            }
            return $out
        }
        Start-Sleep -Milliseconds 250
    }
    throw "test: no PRODQ answer for marker '$label' within ${TimeoutSec}s (log: $LogPath). Was the game launched with -ProdQueue 1?"
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

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

try {
    Step "generate the fixture: one Command Center, $StartingMinerals minerals" {
        Wait-ScFixtureFolderFree -Run $fixtures
        # One building and nothing else. A lone Command Center supplies 10 of its own
        # supply and trains SCVs at 1 each, so a queue of $QueueMax can be built without
        # a single Supply Depot -- one fewer thing that has to land on buildable ground.
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 1 -UnitType command-center -Player 0 -ClearPlayerUnits `
            -GridSpacing 160 -StartingMinerals $StartingMinerals -StartingGas $StartingGas `
            -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        # ONE trigger, and the generator has already proved from the bytes that its only
        # action is Set Resources -- so the fixture still cannot end the game by itself.
        Assert-That 'the map carries exactly the one resource trigger (2400 bytes)' `
            (@($gen | Select-String -Pattern 'TRIG holds 2400 byte').Count -gt 0)
        Assert-That 'the map differs from its template only where this tool meant it to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC').Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '025-production-queue'
    # hooktest mode: the ONE queueCommand hook, so `CMD id=` lines exist, and none of the
    # selection machinery. The production queue is a per-building feature and has nothing
    # to do with selection fan-out -- running in `fanout` would put four unrelated hooks
    # in the picture for no gain.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 `
        -ProdQueue 1 -ProdQueueMax $QueueMax `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'the plugin armed the production queue at all' {
        $cfg = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODQ config: enabled max=')
        Assert-That "the feature reports itself enabled at max=$QueueMax" `
            (@($cfg | Select-String -Pattern "max=$QueueMax ").Count -gt 0) `
            "(lines: $($cfg.Count))"
        # The absence check below is only worth anything because this positive one exists:
        # 'HOOK <name>: installed at' is the plugin's real wording (AGENTS.md, 2026-08-09).
        $hooks = @(Get-Content -LiteralPath $LogPath |
                   Select-String -Pattern 'HOOK (cmdrecvTrain|cmdrecvCancelTrain|productionTick): installed at')
        Assert-That 'all three production detours are spliced' ($hooks.Count -eq 3) `
            "(got $($hooks.Count): $(($hooks | ForEach-Object { $_.Line }) -join ' | '))"
        Assert-That 'and none of them rolled back' `
            (@(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODQ: only \d+ of 3').Count -eq 0)
    }

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -Index 2      # Use Map Settings, verified
        Shot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Send-ScClick -Hwnd $hwnd -X 200 -Y 261        # dismiss the "StarCraft Tips" dialog
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step 'the map spawned exactly one Command Center and nothing else' {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $ccs = @($mine | Where-Object { $_.Type -eq $CC_TYPE })
        Assert-That "player 0 owns exactly one Command Center ($($ccs.Count))" ($ccs.Count -eq 1)
        Assert-That "and owns nothing else ($($mine.Count) unit(s) total)" ($mine.Count -eq 1) `
            "(types seen: $((($mine | ForEach-Object { '0x{0:x}' -f $_.Type }) | Sort-Object -Unique) -join ' '))"
        Assert-That 'the world scan of player 0 was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1) `
            "(units=$($w.Counts[0].Units) recount=$($w.Counts[0].Recount) complete=$($w.Counts[0].Complete))"
        $script:ccUnit = if ($ccs.Count -gt 0) { $ccs[0].Unit } else { $null }
    }

    Step 'select the Command Center -- exactly one building, nothing else' {
        # It is the only thing the player owns, so a box over the play area can only find
        # it. The assertion below is what makes that a fact about the run rather than a
        # claim about the fixture: the Train command is SINGLE-gated, and with two units
        # selected it would silently do nothing at all.
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $q = Get-ProdQueue 'selected'
        Assert-That 'exactly one building is selected' ($null -ne $q.Selected) `
            "($(($q.Lines | Select-Object -First 2) -join ' | '))"
        if ($q.Selected) {
            Assert-That "and it is the Command Center (type 0x$('{0:x}' -f $q.Selected.Type))" `
                ($q.Selected.Type -eq $CC_TYPE)
            Assert-That 'it starts with an empty queue, read from CUnit+0x98' `
                ($q.Selected.EngineLen -eq 0) "(engine=$($q.Selected.Engine -join ','))"
            Assert-That "it starts with the $StartingMinerals minerals the trigger granted" `
                ($q.Selected.Minerals -eq $StartingMinerals) "(got $($q.Selected.Minerals))"
        }
        # THE NEGATIVE HALF of the pair. The same oracle, the same line, before anything
        # has happened -- so the positive reading later cannot be an oracle that always
        # says yes.
        Assert-That 'the plugin is holding nothing yet' `
            ($q.Buildings -eq 0 -and $q.Captured -eq 0 -and $q.Promoted -eq 0)
        Shot 'selected'
    }

    Step "press Train x$Clicks in one burst" {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        # One burst, no marker in the middle: an SCV takes ~9s to build and the burst takes
        # ~3s, so no slot can free while it is running -- which is what makes the counter
        # arithmetic below exact rather than approximate.
        for ($i = 1; $i -le $Clicks; $i++) { Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY }
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ")
        # EVERY press reaches the wire -- including the ones over the cap. That is the
        # finding this whole design rests on (production-queue.md 4.1): the build-menu
        # button is NOT disabled by a full queue, so the command is sent and the engine
        # drops it on the receive side, where the plugin can see it.
        Assert-That "all $Clicks presses emitted $TRAIN_CMD ($($cmds.Count))" ($cmds.Count -eq $Clicks)
        Shot 'queued'
    }

    Step "the building holds $QueueMax items -- $ENGINE_SLOTS in its own memory, $expectOverflow in the plugin" {
        $q = Get-ProdQueue 'queued'
        Assert-That 'the oracle still sees one selected building' ($null -ne $q.Selected)
        if ($q.Selected) {
            $s = $q.Selected
            Write-Host "       $($q.Lines | Where-Object { $_ -match 'PRODQSEL' } | Select-Object -First 1)"
            # READ FROM THE BUILDING'S OWN MEMORY. Five occupied slots at CUnit+0x98.
            Assert-That "the engine's five slots are all occupied ($($s.EngineLen))" `
                ($s.EngineLen -eq $ENGINE_SLOTS) "(engine=$(($s.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))"
            Assert-EverySlot -Selected $s -WantType $SCV_TYPE
            Assert-That "the plugin holds the other $expectOverflow ($($s.Overflow))" `
                ($s.Overflow -eq $expectOverflow)
            Assert-That "so the logical queue is $QueueMax, which is MORE THAN $ENGINE_SLOTS ($($s.Logical))" `
                ($s.Logical -eq $QueueMax -and $s.Logical -gt $ENGINE_SLOTS)
            # PAID EXACTLY ONCE, each. $QueueMax accepted items, $expectRefused refused
            # ones that must have cost nothing at all.
            $expectMinerals = $StartingMinerals - $QueueMax * $SCV_COST
            Assert-That "minerals are down by exactly $QueueMax x $SCV_COST and no more ($($s.Minerals))" `
                ($s.Minerals -eq $expectMinerals) "(expected $expectMinerals)"
        }
        Assert-That "the plugin captured exactly $expectOverflow item(s) ($($q.Captured))" `
            ($q.Captured -eq $expectOverflow)
        Assert-That "and refused exactly $expectRefused at the cap ($($q.RefusedFull))" `
            ($q.RefusedFull -eq $expectRefused)
        Assert-That 'nothing was refused for cost -- the fixture is not resource-starved' `
            ($q.RefusedCost -eq 0)
        # The engine's own cap, stated as a subtraction over this run's counters rather
        # than asserted separately: 12 commands went out, 4 were taken by the plugin and
        # 3 bounced off its cap, so the engine accepted 5 -- exactly its five slots.
        $engineTook = $Clicks - $q.Captured - $q.RefusedFull
        Assert-That "the engine itself accepted exactly $ENGINE_SLOTS of the $Clicks ($engineTook)" `
            ($engineTook -eq $ENGINE_SLOTS)
        Assert-That 'one building is tracked' ($q.Buildings -eq 1)
        if ($q.Tracked.Count -eq 1) {
            Assert-That "its overflow is all SCVs ($(($q.Tracked[0].OverflowTypes | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))" `
                (@($q.Tracked[0].OverflowTypes | Where-Object { $_ -ne $SCV_TYPE }).Count -eq 0)
        }
        $script:mineralsAfterBurst = if ($q.Selected) { $q.Selected.Minerals } else { -1 }
    }

    Step "watch it drain: every over-cap item is promoted into a freed slot, in order" {
        $deadline = (Get-Date).AddSeconds($DrainTimeoutSec)
        $seen = @()
        while ((Get-Date) -lt $deadline) {
            $q = Get-ProdQueue 'drain'
            if ($q.Selected) {
                $seen += "logical=$($q.Selected.Logical) engineLen=$($q.Selected.EngineLen) overflow=$($q.Selected.Overflow)"
                # WHILE the plugin is still holding something, the engine's five must stay
                # FULL. A freed slot that sat empty for a whole marker would mean the
                # plugin skipped a promotion, which is the defect this asserts against.
                if ($q.Selected.Overflow -gt 0) {
                    Assert-That "while $($q.Selected.Overflow) are held, the engine's ring stays full ($($q.Selected.EngineLen))" `
                        ($q.Selected.EngineLen -eq $ENGINE_SLOTS)
                }
            }
            if ($q.Promoted -ge $expectOverflow -and $q.Buildings -eq 0) { break }
            Start-Sleep -Seconds 5
        }
        Write-Host "       $($seen -join ' -> ')"

        $q = Get-ProdQueue 'drained'
        Assert-That "every over-cap item was promoted ($($q.Promoted) of $expectOverflow)" `
            ($q.Promoted -eq $expectOverflow)
        Assert-That 'the plugin is holding nothing any more' ($q.Buildings -eq 0)
        Assert-That 'and nothing was refunded -- no item was lost on the way' ($q.Refunded -eq 0)

        # PER ITEM. One promote line each, naming the type and the slot it went into, with
        # the remaining count walking down to zero. A single line saying "4 promoted"
        # would not distinguish four promotions from one promotion counted four times.
        $ev = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODQEV promote ')
        Assert-That "exactly $expectOverflow promote events ($($ev.Count))" ($ev.Count -eq $expectOverflow)
        for ($i = 0; $i -lt $ev.Count; $i++) {
            $m = [regex]::Match($ev[$i].Line, 'type=0x([0-9A-Fa-f]+) -> slot=(\d+) overflowLeft=(\d+)')
            $wantLeft = $expectOverflow - 1 - $i
            $okType = $m.Success -and [Convert]::ToInt32($m.Groups[1].Value, 16) -eq $SCV_TYPE
            $okSlot = $m.Success -and [int]$m.Groups[2].Value -ge 0 -and [int]$m.Groups[2].Value -lt $ENGINE_SLOTS
            $okLeft = $m.Success -and [int]$m.Groups[3].Value -eq $wantLeft
            Assert-That ("promotion {0}: an SCV into a real slot, {1} left after it" -f ($i + 1), $wantLeft) `
                ($okType -and $okSlot -and $okLeft) "($($ev[$i].Line.Trim()))"
        }
    }

    Step "all $QueueMax units exist, and not one was paid for twice" {
        $w = Get-World 'built'
        $scvs = @($w.Units | Where-Object { $_.Type -eq $SCV_TYPE -and $_.Player -eq 0 })
        Assert-That "player 0 owns $QueueMax SCVs -- every queued item became a unit ($($scvs.Count))" `
            ($scvs.Count -eq $QueueMax)
        Assert-That 'the Command Center is still there' `
            (@($w.Units | Where-Object { $_.Type -eq $CC_TYPE -and $_.Player -eq 0 }).Count -eq 1)
        Assert-That 'the world scan was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)

        $q = Get-ProdQueue 'final'
        Assert-That 'the queue is empty in the building own memory too' `
            ($null -ne $q.Selected -and $q.Selected.EngineLen -eq 0 -and $q.Selected.Logical -eq 0) `
            "($(($q.Lines | Where-Object { $_ -match 'PRODQSEL' } | Select-Object -First 1)))"
        # THE PAY-ONCE ASSERTION. Promotion moves no money, so the balance must be exactly
        # what it was when the burst finished -- four promotions later. A second payment
        # would show as a drop of 4 x 50 here and nowhere else.
        if ($q.Selected) {
            Assert-That "minerals are UNCHANGED across the whole drain ($($q.Selected.Minerals))" `
                ($q.Selected.Minerals -eq $script:mineralsAfterBurst) `
                "(was $script:mineralsAfterBurst after the burst)"
        }
        Assert-That "and still exactly $StartingMinerals - $QueueMax x $SCV_COST" `
            ($null -ne $q.Selected -and $q.Selected.Minerals -eq ($StartingMinerals - $QueueMax * $SCV_COST))
        Shot 'built'
    }

    Step 'the engine was never asked to do anything outside the production path' {
        $log = @(Get-Content -LiteralPath $LogPath)
        # Nothing here fans anything out -- the suite runs in hooktest mode, which installs
        # no selection hooks at all. Proved positively first: the mode line says hooktest,
        # so "no FANOUT lines" is a real absence and not a missing feature.
        Assert-That 'the run really was in hooktest mode' `
            (@($log | Select-String -Pattern 'HOOK: 1/1 installed, mode=hooktest').Count -gt 0)
        Assert-That 'and nothing was fanned out' `
            (@($log | Select-String -Pattern 'FANOUT start:').Count -eq 0)
        Assert-That 'no hook rolled back at any point' `
            (@($log | Select-String -Pattern 'ROLLING BACK').Count -eq 0)
        $stats = @($log | Select-String -Pattern 'PRODQSTATS ')
        if ($stats.Count -gt 0) { Write-Host "       $($stats[-1].Line.Trim())" }
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
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

# THE DETACH-TIME REFUND. The plugin gives back anything it is still holding before it
# un-splices, so a run can never end with the player short. By this point it is holding
# nothing, so the honest assertion is that spend and refund agree with the queue.
$statLine = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern 'PRODQSTATS ')
if ($statLine.Count -gt 0) {
    $m = [regex]::Match($statLine[-1].Line,
        'captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+) refusedCost=(\d+) mineralsSpent=(\d+) mineralsRefunded=(\d+)')
    if ($m.Success) {
        $spent = [int]$m.Groups[7].Value
        $back = [int]$m.Groups[8].Value
        Assert-That "the plugin spent exactly $expectOverflow x $SCV_COST of its own ($spent)" `
            ($spent -eq $expectOverflow * $SCV_COST)
        Assert-That 'and refunded nothing, because nothing was cancelled or lost' ($back -eq 0)
    }
    else { Assert-That 'the detach stats line is parseable' $false "($($statLine[-1].Line))" }
}
else { Assert-That 'the plugin wrote its detach stats line' $false }

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-production-queue: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
