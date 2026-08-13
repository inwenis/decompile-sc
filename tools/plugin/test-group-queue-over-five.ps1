#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that a player can keep queueing PAST FIVE at EVERY building
of a multi-building selection -- the over-cap queueing task 025 shipped for one building,
measured for a group, with every building's queue read out of that building's own memory
and the money accounted to the last mineral.

Task 038, from the user's words (2026-08-11): "can't queue more than 5 units per building
when multiple buildings are selected".

.DESCRIPTION
Two shipped features meet here and this suite is the instrument that says whether they
meet correctly:

  * task 025 (`sc_prodqueue.cpp`) keeps the ENGINE's five-slot ring one item BELOW its cap
    so the client keeps offering the Train button and keeps sending 0x1F. The over-cap
    items live in the plugin's own per-building list. The whole design is inverted on
    purpose: the client never sends a sixth Train, so nothing can be caught on receipt
    (AGENTS.md, "A player-input feature is unproven until the wire has been watched").
  * task 030 (`sc_prodfan.cpp`) lights the Train button for a same-type building group and
    fans ONE press out into one Select+Train pair per building.

So the measurement this suite exists to make is the one the seam decides:

  1. HOW MANY OF $Clicks PRESSES REACH THE WIRE with the group selected. `queueCommand`
     (0x00485BD0) is hooked, so every command this game sends is logged. If the client
     stops offering the button once a building's ring is full, the count stops at five and
     THAT is the bug the user is reporting. This is the headline number, and it is the
     evidence AGENTS.md demands for anything that starts with a player input.
  2. WHAT EACH BUILDING ACTUALLY HOLDS. The `PRODQ` oracle prints, per tracked building,
     the ENGINE's own five slots read straight out of CUnit+0x98 plus the plugin's
     overflow -- and `PRODFAN` prints the engine's slots for every SELECTED building,
     tracked or not. Both are reads of the building's memory, never of the screen.
  3. WHAT IT COST. The player's minerals come from the engine's own resource globals. The
     identity that has to hold is "queued x cost, once each" -- a queue that grows without
     charging would be a worse bug than the one being fixed (task file, Context).

WHY THE RESULT CANNOT BE FAKED

  * THE BEFORE-STATE IS READ AND ASSERTED, per building, from the same oracles -- so a
    queue that was already full cannot read as a success and an oracle that always says
    yes cannot pass unnoticed (AGENTS.md: an absence has to be proved positive somewhere).
  * THE ENGINE'S OWN NUMBERS CARRY EVERY CLAIM. "N are queued" is asserted as the ring
    contents plus the money the engine deducted, not as the plugin's counters; the plugin's
    stats line is read only to assert it spent NOTHING of its own.
  * THE CANCEL PATH IS EXERCISED WITH REAL MONEY ON IT: an item the plugin is holding is
    cancelled and the refund is read back out of the resource globals.
  * THE SINGLE-BUILDING CASE IS RE-MEASURED IN THE SAME RUN, through the same oracles, so
    a regression to task 025 cannot hide behind a group that happens to work.
  * The map has no hostiles and one unit-less computer slot, and its only trigger sets
    resources once -- nothing but this test can move a mineral or queue an item.

WHAT THE NUMBERS SHOULD BE, with the defaults ($Buildings 3, $Clicks 9):

    presses                              9
    0x1F at the funnel                   9      (each one fanned into 3 Select+order pairs)
    per building, engine ring         <= 5      (the plugin holds it at 4 while it has more)
    per building, logical queue          9      (ring + the plugin's overflow)
    units queued across the group       27
    minerals spent                    1350      (27 x 50, by the ENGINE, once each)

.EXAMPLE
./tools/plugin/test-group-queue-over-five.ps1

.EXAMPLE
./tools/plugin/test-group-queue-over-five.ps1 -Buildings 3 -Clicks 9 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\038\group-queue-over-five.log',
    [string]$ShotDir = 'C:\sc-work\logs\038\group-queue-frames',
    [string]$FixtureDir,
    # THREE buildings and NINE presses, and both numbers are chosen against the fixture's
    # own limits rather than for roundness:
    #   * 9 > 5, so every building has to go past the engine's ring for this to pass at all;
    #   * 3 x 9 = 27 SCVs, and three Command Centers supply 30 -- so "the queue stopped
    #     because the player was supply-blocked" is removed as an explanation of a short
    #     count rather than argued about afterwards (the same reason task 030 used CCs);
    #   * 27 x 50 = 1350 minerals, comfortably inside the 3000 the trigger grants.
    [int]$Buildings = 3,
    [int]$Clicks = 9,
    # The plugin's logical maximum per building. Left at the default 16 so $Clicks is well
    # clear of it: this suite measures "past five", not "at the cap".
    [int]$QueueMax = 16,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 0,
    # 250 ms between presses: fast enough that no SCV can finish inside the burst (an SCV
    # takes ~20 s), slow enough that each press is one turn's command rather than a race.
    [int]$ClickDelayMs = 250,
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
$CC_TYPE      = 106       # units.dat 106, richchk UnitId 'Terran Command Center'
$SCV_TYPE     = 7         # units.dat 7,   richchk UnitId 'Terran SCV'
$SCV_COST     = 50        # minerals
$TRAIN_KEY    = 0x53      # 'S', the Command Center card's Train SCV hotkey
$TRAIN_CMD    = '0x1F'    # research/data/command-opcodes.tsv
$QUEUE_EMPTY  = 0xE4      # research/production-queue.md 2.4
$ENGINE_SLOTS = 5         # the engine's own ring, research/production-queue.md 2.3
$ENGINE_HOLD  = 4         # SC_PRODQ_ENGINE_HOLD: what the plugin holds the ring at
# Button records, research/production-queue.md 4.1 / 8.1. A slot is named by its ACTION
# pointer, never by its index: the action IS the emitter.
$TRAIN_ACTION  = '004234b0'   # the 0x1F emitter
$TRAIN_COND    = '00428e60'   # the condition sc_prodfan detours
$CANCEL_ACTION = '00423490'   # the 0x20 emitter; its actionParam 0xFE is "cancel the last"

if ($Buildings -lt 2) { throw 'test: -Buildings must be at least 2, or there is no group.' }
if ($Clicks -le $ENGINE_SLOTS) {
    throw "test: -Clicks must exceed the engine's $ENGINE_SLOTS-slot ring, or this suite proves nothing."
}
if ($Clicks -ge $QueueMax) {
    throw "test: -Clicks ($Clicks) must stay below -QueueMax ($QueueMax); this measures past five, not the cap."
}

# ONE FOLDER PER TASK, ONE NAME PER SUITE (AGENTS.md, hard rule): the fixture is named
# after this suite, declared up front, and deleted only by this run.
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t038' }
$mapDir = $FixtureDir
$mapName = 'group-queue-over-five.scx'
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

# THE ORACLE. One marker drives every read-only oracle in the plugin, so a single handshake
# returns all three layers of the answer for ONE instant:
#
#   PRODQ    one line per building the plugin is TRACKING: the engine's five slots out of
#            CUnit+0x98, the plugin's overflow, and the player's minerals.
#   PRODFAN  one line per SELECTED building, tracked or not, carrying that building's own
#            five slots -- so a building that gained nothing still appears, and "it is not
#            in the reading" and "it holds nothing" stay different findings.
#   CARD     the command card walked out of memory, so "the Train button is dark" is a read
#            of the dialog rather than a look at a frame (AGENTS.md, task 026).
#
# It waits for BOTH summary lines, each of which its subsystem writes LAST and writes
# unconditionally -- so waiting for them means the whole answer has landed and an empty
# answer is still an answer.
$script:oracleSeq = 0
function Get-Prod {
    param([string]$Tag, [int]$TimeoutSec = 25)
    $script:oracleSeq++
    $label = "gq-$Tag-$script:oracleSeq"
    Set-ScMarker -MarkerPath $markerPath -Label $label
    $esc = [regex]::Escape($label)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $all = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
        $qLines = @($all | Select-String -Pattern "PRODQ(SEL)? \[$esc\]")
        $fLines = @($all | Select-String -Pattern "PRODFAN \[$esc\]")
        $qSummary = @($qLines | Select-String -Pattern 'buildings=\d+ max=')
        $fSummary = @($fLines | Select-String -Pattern 'buildings=\d+ selected=')
        if ($qSummary.Count -gt 0 -and $fSummary.Count -gt 0) {
            $out = [pscustomobject]@{
                Label = $label
                # PRODQ: the plugin's tracked buildings (ring + overflow), keyed by unit.
                Tracked = @{}
                TrackedCount = 0; Max = 0; Captured = 0; Promoted = 0
                Cancelled = 0; Refunded = 0; RefusedFull = 0
                # PRODFAN: every selected building's own ring.
                Rows = @(); Buildings = 0; SimSlots = 0; ClientCount = 0
                TotalQueued = 0; Minerals = 0; Gas = 0; Fanned = 0; Reached = 0
                Card = $null; Cancel = $null; CardLines = @()
                Lines = @(@($qLines | ForEach-Object { $_.Line }) + @($fLines | ForEach-Object { $_.Line }))
            }
            foreach ($l in $qLines) {
                $t = [regex]::Match($l.Line,
                    'PRODQ \[[^\]]+\] unit=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) overflowTypes=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)')
                if ($t.Success) {
                    $out.Tracked[$t.Groups[1].Value] = [pscustomobject]@{
                        Unit = $t.Groups[1].Value
                        EngineLen = [int]$t.Groups[4].Value
                        Engine = @($t.Groups[5].Value -split ',' |
                                   Where-Object { $_ -match '^0x' } |
                                   ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
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
                    'buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+)')
                if ($s.Success) {
                    $out.TrackedCount = [int]$s.Groups[1].Value
                    $out.Max = [int]$s.Groups[2].Value
                    $out.Captured = [int]$s.Groups[3].Value
                    $out.Promoted = [int]$s.Groups[4].Value
                    $out.Cancelled = [int]$s.Groups[5].Value
                    $out.Refunded = [int]$s.Groups[6].Value
                    $out.RefusedFull = [int]$s.Groups[7].Value
                }
            }
            foreach ($l in $fLines) {
                $m = [regex]::Match($l.Line,
                    'PRODFAN \[[^\]]+\] i=(\d+)/(\d+) unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(-?\d+) engine=\[([^\]]*)\] buildState=(\d+) buildUnit=0x([0-9A-Fa-f]+)(.*)$')
                if ($m.Success) {
                    $out.Rows += [pscustomobject]@{
                        Index = [int]$m.Groups[1].Value
                        Unit = $m.Groups[3].Value
                        Type = [Convert]::ToInt32($m.Groups[4].Value, 16)
                        Player = [int]$m.Groups[5].Value
                        EngineLen = [int]$m.Groups[7].Value
                        Engine = @($m.Groups[8].Value -split ',' |
                                   Where-Object { $_ -match '^0x' } |
                                   ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                        BuildUnit = $m.Groups[10].Value
                        Stale = ($m.Groups[11].Value -match 'STALE')
                    }
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'buildings=(\d+) selected=(\d+) visible=(\d+) simSlots=(-?\d+) clientCount=(\d+) totalQueued=(\d+) minerals=(\d+) gas=(\d+) enabled=(\d+) fanned=(\d+) refused=(\d+) reached=(\d+) lit=(\d+)')
                if ($s.Success) {
                    $out.Buildings = [int]$s.Groups[1].Value
                    $out.SimSlots = [int]$s.Groups[4].Value
                    $out.ClientCount = [int]$s.Groups[5].Value
                    $out.TotalQueued = [int]$s.Groups[6].Value
                    $out.Minerals = [int]$s.Groups[7].Value
                    $out.Gas = [int]$s.Groups[8].Value
                    $out.Fanned = [int]$s.Groups[10].Value
                    $out.Reached = [int]$s.Groups[12].Value
                }
            }
            # The card, from the SAME marker, so "the button was dark" and "nothing queued"
            # are two readings of one instant.
            $cardLines = @($all | Select-String -Pattern "CARD \[$esc\] slot=")
            $out.CardLines = @($cardLines | ForEach-Object { $_.Line })
            foreach ($c in $cardLines) {
                $cm = [regex]::Match($c.Line, 'slot=(\d+) (\S+) .*cond=0x([0-9A-Fa-f]+) act=0x([0-9A-Fa-f]+)')
                if (-not $cm.Success) { continue }
                $entry = [pscustomobject]@{
                    Slot = [int]$cm.Groups[1].Value
                    State = $cm.Groups[2].Value
                    Cond = $cm.Groups[3].Value.ToLower()
                    Act = $cm.Groups[4].Value.ToLower()
                }
                if ($entry.Act -eq $TRAIN_ACTION) { $out.Card = $entry }
                elseif ($entry.Act -eq $CANCEL_ACTION) { $out.Cancel = $entry }
            }
            return $out
        }
        Start-Sleep -Milliseconds 250
    }
    throw "test: no PRODQ+PRODFAN answer for marker '$label' within ${TimeoutSec}s (log: $LogPath). Was the game launched with -ProdQueue 1 -ProdFan 1?"
}

# The LOGICAL queue of one building: the engine's own occupied slots plus whatever the
# plugin is holding for it. The ring half comes from PRODFAN (every selected building) or
# PRODQ (every tracked one); they read the same memory, and where both are present this
# asserts they agree rather than preferring one.
function Get-Logical {
    param([Parameter(Mandatory)]$Prod, [Parameter(Mandatory)][string]$Unit)
    $row = @($Prod.Rows | Where-Object { $_.Unit -eq $Unit }) | Select-Object -First 1
    $trk = $Prod.Tracked[$Unit]
    $ring = if ($row) { $row.EngineLen } elseif ($trk) { $trk.EngineLen } else { -1 }
    if ($row -and $trk -and $row.EngineLen -ne $trk.EngineLen) {
        Assert-That "the two oracles agree on 0x$Unit's ring (PRODFAN $($row.EngineLen) / PRODQ $($trk.EngineLen))" $false
    }
    [pscustomobject]@{
        Unit = $Unit
        Ring = $ring
        Overflow = if ($trk) { $trk.Overflow } else { 0 }
        Logical = $ring + $(if ($trk) { $trk.Overflow } else { 0 })
        Engine = if ($row) { $row.Engine } elseif ($trk) { $trk.Engine } else { @() }
        Tracked = ($null -ne $trk)
    }
}

# Assert one building's ring slot by slot. A length is a count, and a count can be produced
# by the wrong things sitting in the wrong slots.
function Assert-Ring {
    param([string]$What, $Row, [int]$MaxLen = 5, [int]$WantType = 0)
    if ($null -eq $Row) { Assert-That "$What has a queue reading at all" $false; return }
    $eng = ($Row.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','
    Assert-That "$What's ring never exceeds the engine's $MaxLen slots ($($Row.EngineLen))" `
        ($Row.EngineLen -le $MaxLen) "(engine=[$eng])"
    if ($WantType -gt 0) {
        $occupied = @($Row.Engine | Where-Object { $_ -ne $QUEUE_EMPTY })
        $bad = @($occupied | Where-Object { $_ -ne $WantType })
        Assert-That "$What's ring holds only unit type 0x$('{0:x}' -f $WantType)" `
            ($bad.Count -eq 0) "(engine=[$eng])"
    }
}

# Box a set of units EXACTLY, by map position, camera moved to them first. Same function as
# test-group-production.ps1's, and it exists for the same reason: a full-screen drag boxes
# whatever else is on the map, and this fixture's buildings must be named, not hoped for.
function Select-ScUnitsByMap {
    param(
        [Parameter(Mandatory)][object[]]$Units,
        [Parameter(Mandatory)][int]$TileX,
        [Parameter(Mandatory)][int]$TileY,
        [string]$Tag = 'aim',
        [int]$Margin = 24,
        [int]$MapW = 128, [int]$MapH = 96
    )
    $p = Get-ScMinimapPoint -MapTilesW $MapW -MapTilesH $MapH -TileX $TileX -TileY $TileY
    Send-ScClick -Hwnd $script:hwnd -X $p.X -Y $p.Y
    Start-Sleep -Milliseconds 800
    $w = Get-ScWorldState -LogPath $script:LogPath -Tag $Tag -MarkerPath $script:markerPath
    if (-not $w.Screen) { throw 'test: the plugin did not report the viewport origin.' }
    $x1 = ($Units | Measure-Object X -Minimum).Minimum - $w.Screen.Left - $Margin
    $x2 = ($Units | Measure-Object X -Maximum).Maximum - $w.Screen.Left + $Margin
    $y1 = ($Units | Measure-Object Y -Minimum).Minimum - $w.Screen.Top  - $Margin
    $y2 = ($Units | Measure-Object Y -Maximum).Maximum - $w.Screen.Top  + $Margin
    if ($x1 -lt 4 -or $y1 -lt 4 -or $x2 -gt 636 -or $y2 -gt 340) {
        Write-Host "       (block at client [$x1,$y1]-[$x2,$y2] is not fully on the battlefield)"
        return $false
    }
    # WHAT ELSE IS IN THIS BOX. Task 025's first run boxed the play area and the engine
    # handed back a neutral MINERAL FIELD sharing the box with the building -- and a
    # mineral field is a non-movable type too, so a building group would happily grow one
    # of THOSE. Naming any foreign unit inside the rect turns that into a finding.
    $mineSet = @{}
    foreach ($u in $Units) { $mineSet[$u.Unit] = $true }
    $intruders = @($w.Units | Where-Object {
        -not $mineSet.ContainsKey($_.Unit) -and
        ($_.X - $w.Screen.Left) -ge $x1 -and ($_.X - $w.Screen.Left) -le $x2 -and
        ($_.Y - $w.Screen.Top)  -ge $y1 -and ($_.Y - $w.Screen.Top)  -le $y2
    })
    if ($intruders.Count -gt 0) {
        Write-Host "       (WARNING: $($intruders.Count) unit(s) not in the block fall inside this rect: $(($intruders | ForEach-Object { 'p{0}/0x{1:x}' -f $_.Owner, $_.Type }) -join ' '))"
    } else {
        Write-Host '       (nothing but the block itself falls inside the rect)'
    }
    Write-Host "       (boxing client [$x1,$y1]-[$x2,$y2]; viewport at map ($($w.Screen.Left),$($w.Screen.Top)))"
    Send-ScDrag -Hwnd $script:hwnd -X1 $x1 -Y1 $y1 -X2 $x2 -Y2 $y2 -Steps 20
    Start-Sleep -Seconds 2
    return $true
}

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

try {
    Step "generate the fixture: $Buildings Command Centers, $StartingMinerals minerals" {
        Wait-ScFixtureFolderFree -Run $fixtures
        # 160 px (5 tiles) apart: a Command Center is 4x3 tiles, so this clears it with a
        # tile to spare and all $Buildings still fit inside one screen's battlefield, which
        # is what makes a single drag box able to hold them.
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $Buildings -UnitType command-center -Player 0 -ClearPlayerUnits `
            -GridSpacing 160 -StartingMinerals $StartingMinerals -StartingGas $StartingGas `
            -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'the map differs from its template only where this tool meant it to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC').Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '038-group-queue-over-five'
    # BOTH features on, which is the entire point: this is the first suite in the repo to
    # run task 025's over-cap queueing and task 030's group fan-out in one game. Task 030's
    # own suite runs with -ProdQueue 0 deliberately, so the seam between them has never
    # been measured until now.
    #
    # -CardScan 1 because "is the Train button still lit after five" is a claim about a
    # dialog and is answered by walking it (AGENTS.md, task 026).
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 -CardScan 1 `
        -BuildingGroups 1 -ProdQueue 1 -ProdQueueMax $QueueMax -ProdFan 1 -QueueIndicator 1 `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'both features armed, and every hook this run depends on is spliced' {
        $log = @(Get-Content -LiteralPath $LogPath)
        Assert-That "the production queue reports itself enabled at max=$QueueMax" `
            (@($log | Select-String -Pattern "PRODQ config: enabled max=$QueueMax ").Count -gt 0)
        Assert-That 'the group fan-out reports itself ENABLED' `
            (@($log | Select-String -Pattern 'PRODFAN: ENABLED').Count -gt 0)
        # 'HOOK <name>: installed at' is the plugin's real wording, and these positives are
        # what license the absence checks later (AGENTS.md, 2026-08-09).
        $prodq = @($log | Select-String -Pattern 'HOOK (cmdrecvTrain|cmdrecvCancelTrain|productionTick): installed at')
        Assert-That "all three production detours are spliced ($($prodq.Count))" ($prodq.Count -eq 3)
        Assert-That 'and none of them rolled back' `
            (@($log | Select-String -Pattern 'PRODQ: only \d+ of 3').Count -eq 0)
        Assert-That 'the command funnel is hooked, so every command this game sends is logged' `
            (@($log | Select-String -Pattern 'HOOK queueCommand: installed at').Count -ge 1)
        Assert-That "the Train button's condition is detoured, so the group gets a button at all" `
            (@($log | Select-String -Pattern 'HOOK btnTrainCondition: installed at').Count -ge 1)
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
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2      # Use Map Settings, verified
        Shot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step "the map spawned exactly $Buildings Command Centers and nothing else" {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $ccs = @($mine | Where-Object { $_.Type -eq $CC_TYPE })
        Assert-That "player 0 owns exactly $Buildings Command Centers ($($ccs.Count))" `
            ($ccs.Count -eq $Buildings)
        Assert-That "and owns nothing else ($($mine.Count) unit(s) total)" ($mine.Count -eq $Buildings)
        Assert-That 'the world scan of player 0 was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)
        $script:ccs = $ccs
        if ($ccs.Count -gt 0) {
            $script:ccTile = [pscustomobject]@{
                X = [int]((($ccs | Measure-Object X -Average).Average) / 32)
                Y = [int]((($ccs | Measure-Object Y -Average).Average) / 32)
            }
        }
    }

    Step "box all $Buildings of them, and read every queue BEFORE anything is pressed" {
        $aimed = Select-ScUnitsByMap -Units $script:ccs -TileX $script:ccTile.X -TileY $script:ccTile.Y -Tag 'aim-group'
        Assert-That 'the block is on screen and was boxed' $aimed
        $p = Get-Prod 'group-before'
        Assert-That "the selection holds all $Buildings buildings ($($p.Buildings))" ($p.Buildings -eq $Buildings)
        Assert-That "the simulation holds ONE at a time (simSlots=$($p.SimSlots))" ($p.SimSlots -eq 1)
        Assert-That "the engine's own client selection count reads $Buildings ($($p.ClientCount))" `
            ($p.ClientCount -eq $Buildings)
        $wrong = @($p.Rows | Where-Object { $_.Type -ne $CC_TYPE -or $_.Player -ne 0 })
        Assert-That 'every selected unit is a Command Center owned by player 0' ($wrong.Count -eq 0)

        # THE NEGATIVE HALF OF EVERY PAIR BELOW. Read and asserted empty per building, so a
        # later reading of nine cannot be something that was already there -- and the two
        # oracles are shown answering ZERO before either is trusted to answer nine.
        foreach ($r in $p.Rows) { Assert-Ring "building 0x$($r.Unit) (before)" $r 0 }
        Assert-That "nothing is queued anywhere yet (totalQueued=$($p.TotalQueued))" ($p.TotalQueued -eq 0)
        Assert-That 'and the plugin is holding nothing for anybody' `
            ($p.TrackedCount -eq 0 -and $p.Captured -eq 0 -and $p.Promoted -eq 0)
        Assert-That "the player still has all $StartingMinerals minerals ($($p.Minerals))" `
            ($p.Minerals -eq $StartingMinerals)
        # The button, read out of the card's own memory. Without it there is no command to
        # fan out and the run would be measuring the client, not the feature.
        Assert-That 'the Train button is DRAWN and enabled for the group' `
            ($null -ne $p.Card -and $p.Card.State -eq 'enabled') `
            "(card slots seen: $($p.CardLines.Count))"
        if ($p.Card) {
            Assert-That "and it is the slot whose condition is 0x$TRAIN_COND" ($p.Card.Cond -eq $TRAIN_COND)
        }
        $script:groupUnits = @($p.Rows | ForEach-Object { $_.Unit })
        $script:mineralsBefore = $p.Minerals
        Shot 'group-selected'
    }

    # ------------------------------------------------------------------------------
    # THE MEASUREMENT THE TASK IS ABOUT. $Clicks presses, group selected.
    #
    # WHAT THE COUNTS MEAN, because they are easy to misread: `CMD id=` is logged inside the
    # queueCommand DETOUR and the fan-out emits its pairs through the TRAMPOLINE, so the
    # replayed Select+Train pairs deliberately do not pass the logger again. One press is
    # therefore exactly ONE `CMD id=0x1F` (the player's own, then suppressed) plus one
    # `FANOUT start` naming the pairs that went out in its place.
    # ------------------------------------------------------------------------------
    Step "press Train x$Clicks with the whole group selected -- WATCH THE WIRE" {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        for ($i = 1; $i -le $Clicks; $i++) {
            Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY -SettleMs $ClickDelayMs
        }
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ")
        $starts = @($lines | Select-String -Pattern 'FANOUT start: cmd=0x1F')
        $dones = @($lines | Select-String -Pattern "FANOUT done: $Buildings/$Buildings chunks")
        Write-Host "       $($cmds.Count) of $Clicks presses reached the funnel; $($starts.Count) were fanned out"
        $cmds | ForEach-Object { Write-Host "         $($_.Line)" }
        $starts | ForEach-Object { Write-Host "         $($_.Line)" }

        # THE HEADLINE ASSERTION, and the one that fails on current main: if the client
        # stops offering the Train button once a building's ring holds five, the count
        # stops at five and the player cannot queue past it -- which is the user's report.
        Assert-That "all $Clicks presses reached the wire, not $ENGINE_SLOTS ($($cmds.Count))" `
            ($cmds.Count -eq $Clicks)
        Assert-That "and every one was fanned out across the group ($($starts.Count))" `
            ($starts.Count -eq $cmds.Count)
        Assert-That "with all $Buildings pairs emitted in its own turn, none deferred ($($dones.Count))" `
            ($dones.Count -eq $starts.Count)
        $script:wireCmds = $cmds.Count
        $script:wireLines = @($cmds | ForEach-Object { $_.Line })
        Shot 'group-queued'
    }

    Step "every building holds $Clicks items -- ring in its own memory, the rest in the plugin" {
        $p = Get-Prod 'group-after'
        foreach ($u in $script:groupUnits) {
            $l = Get-Logical -Prod $p -Unit $u
            Write-Host ("         unit=0x{0} ring={1} overflow={2} logical={3} engine=[{4}]" -f `
                $l.Unit, $l.Ring, $l.Overflow, $l.Logical, (($l.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))
        }
        Assert-That "all $Buildings buildings are still in the reading ($($p.Buildings))" `
            ($p.Buildings -eq $Buildings)
        # THE ASSUMPTION THE EXACT NUMBERS REST ON, checked rather than commented: an SCV
        # finishing frees a slot, the plugin promotes into it, and the logical queue this
        # step is asserting would legitimately be one short. An SCV takes ~20 s and the
        # burst takes ~3 s, so this should be zero -- and if it is not, the step says which
        # assertions to stop believing instead of failing with nothing to say.
        $quiet = ($p.Promoted -eq 0)
        Assert-That "no queue slot freed while the burst was going out (promoted=$($p.Promoted))" $quiet

        foreach ($u in $script:groupUnits) {
            $row = @($p.Rows | Where-Object { $_.Unit -eq $u }) | Select-Object -First 1
            Assert-Ring "building 0x$u" $row $ENGINE_SLOTS $SCV_TYPE
            $l = Get-Logical -Prod $p -Unit $u
            if ($quiet) {
                Assert-That "building 0x$u holds all $Clicks of its items, which is MORE THAN $ENGINE_SLOTS (ring $($l.Ring) + overflow $($l.Overflow) = $($l.Logical))" `
                    ($l.Logical -eq $Clicks -and $l.Logical -gt $ENGINE_SLOTS)
                Assert-That "and the plugin is keeping its ring at $ENGINE_HOLD so the client keeps sending ($($l.Ring))" `
                    ($l.Ring -eq $ENGINE_HOLD)
            } else {
                Assert-That "building 0x$u went past the engine's $ENGINE_SLOTS (logical $($l.Logical))" `
                    ($l.Logical -gt $ENGINE_SLOTS)
            }
        }
        Assert-That "the plugin is tracking all $Buildings buildings ($($p.TrackedCount))" `
            ($p.TrackedCount -eq $Buildings)

        # THE MONEY, from the engine's own resource globals. This is drain-proof: a unit
        # finishing shortens a queue but never un-spends a mineral, so it holds whether or
        # not the window was quiet.
        $expectUnits = $Buildings * $Clicks
        $paid = $script:mineralsBefore - $p.Minerals
        Assert-That "the engine charged for every one of the $expectUnits units queued: $expectUnits x $SCV_COST = $($expectUnits * $SCV_COST) ($paid)" `
            ($paid -eq $expectUnits * $SCV_COST)
        Assert-That 'and nothing was paid for that did not queue' `
            ($paid -le $expectUnits * $SCV_COST)
        # The `cost=` half of this was read from refusedCost, which nothing incremented
        # (issue #66); the ring half is live and stays. What the cost half claimed is
        # asserted for real by the exact-charge assertion above.
        Assert-That "no Train command was refused for a full ring (full=$($p.RefusedFull))" `
            ($p.RefusedFull -eq 0)
        $script:mineralsAfterBurst = $p.Minerals
        $script:unitsQueued = $expectUnits
        $script:capturedAfterBurst = $p.Captured
    }

    Step 'the Train button is STILL lit after the burst -- the client can go on' {
        # The card, walked out of memory at the end of the burst. This is the client half of
        # the feature: the whole design of task 025 is that the button never goes dark, and
        # for a group it is task 030's detour that has to keep answering. A dark button here
        # would mean the next press produces nothing, whatever the queues say.
        $p = Get-Prod 'card-after'
        Assert-That 'the Train button is still on the card and enabled' `
            ($null -ne $p.Card -and $p.Card.State -eq 'enabled') `
            "(state: $(if ($p.Card) { $p.Card.State } else { 'absent' }))"
    }

    # ------------------------------------------------------------------------------
    # CANCEL, with real money on it. The plugin owns the tail of each logical queue, so a
    # "cancel the last queued item" is refunded by the PLUGIN out of the same two cost
    # tables the engine's own refund reads (task 028). Asserted from the resource globals.
    # ------------------------------------------------------------------------------
    Step 'cancel an item the plugin is holding, and read the refund out of the globals' {
        # One building, selected alone: the cancel path is single-gated in the engine and in
        # the plugin alike, and this is also the start of the single-building control below.
        $w = Get-World 'aim-single'
        $cc = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $CC_TYPE })[0]
        Assert-That 'the scan reports the viewport origin and a building' `
            ($null -ne $w.Screen -and $null -ne $cc)
        $cx = $cc.X - $w.Screen.Left
        $cy = $cc.Y - $w.Screen.Top
        Assert-That "the building is on screen ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2

        $before = Get-Prod 'cancel-before'
        Assert-That 'exactly one building is selected' ($before.Buildings -eq 1)
        $script:singleUnit = if ($before.Rows.Count -gt 0) { $before.Rows[0].Unit } else { $null }
        Assert-That 'and it is one of the group' `
            ($null -ne $script:singleUnit -and $script:groupUnits -contains $script:singleUnit)
        $lBefore = Get-Logical -Prod $before -Unit $script:singleUnit
        Assert-That "it is still holding more than the engine's $ENGINE_SLOTS (logical $($lBefore.Logical))" `
            ($lBefore.Logical -gt $ENGINE_SLOTS)
        Assert-That 'and the plugin is holding the tail of it, which is what makes this a plugin refund' `
            ($lBefore.Overflow -gt 0)
        Assert-That "the card offers the Cancel button (action 0x$CANCEL_ACTION)" ($null -ne $before.Cancel)

        $mineralsBeforeCancel = $before.Minerals
        $cancelledBefore = $before.Cancelled
        if ($before.Cancel) {
            $card = Get-ScCardState -LogPath $LogPath -Tag "cancel-point-$($script:oracleSeq)" -MarkerPath $markerPath
            $pt = Get-ScCardSlotPoint -Card $card -Slot $before.Cancel.Slot
            Write-Host "       Cancel button -> client ($($pt.X),$($pt.Y))"
            Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y
            Start-Sleep -Seconds 2
        }

        $after = Get-Prod 'cancel-after'
        $lAfter = Get-Logical -Prod $after -Unit $script:singleUnit
        Write-Host "       logical $($lBefore.Logical) -> $($lAfter.Logical), minerals $mineralsBeforeCancel -> $($after.Minerals)"
        Assert-That "the plugin cancelled exactly one of its own held items ($($after.Cancelled - $cancelledBefore))" `
            (($after.Cancelled - $cancelledBefore) -eq 1)
        Assert-That "the logical queue is one shorter ($($lBefore.Logical) -> $($lAfter.Logical))" `
            ($lAfter.Logical -eq $lBefore.Logical - 1)
        Assert-That "and the player got exactly $SCV_COST minerals back ($($after.Minerals - $mineralsBeforeCancel))" `
            (($after.Minerals - $mineralsBeforeCancel) -eq $SCV_COST)
        $script:mineralsAfterCancel = $after.Minerals
        $script:logicalAfterCancel = $lAfter.Logical
        Shot 'cancelled'
    }

    # ------------------------------------------------------------------------------
    # THE SINGLE-BUILDING CONTROL (acceptance criterion 3). Same oracles, same run, one
    # building selected: this is task 025's own case, and it is exactly where a regression
    # to it would hide. Its full suite is test-production-queue.ps1; this is the in-run
    # positive control that says the single path still queues past five here too.
    # ------------------------------------------------------------------------------
    Step 'the SINGLE-building case still queues past five, in this same game' {
        $before = Get-Prod 'single-before'
        Assert-That 'still exactly one building selected' ($before.Buildings -eq 1)
        $lBefore = Get-Logical -Prod $before -Unit $script:singleUnit
        $mineralsBeforeSingle = $before.Minerals
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $presses = 3
        for ($i = 1; $i -le $presses; $i++) {
            Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY -SettleMs $ClickDelayMs
        }
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ")
        $fanned = @($lines | Select-String -Pattern 'FANOUT start: cmd=0x1F')
        Write-Host "       $($cmds.Count) of $presses presses reached the funnel with ONE building selected"
        Assert-That "all $presses presses reached the wire, well past the engine's $ENGINE_SLOTS ($($cmds.Count))" `
            ($cmds.Count -eq $presses)
        # The single-building path must stay byte-for-byte the engine's: the fan-out refuses
        # a one-building selection by design (SC_PRODFAN_ONE_BUILDING), which is what keeps
        # it usable as a control arm.
        Assert-That 'and nothing was fanned out for a selection of one' ($fanned.Count -eq 0)

        $after = Get-Prod 'single-after'
        $lAfter = Get-Logical -Prod $after -Unit $script:singleUnit
        Write-Host "       logical $($lBefore.Logical) -> $($lAfter.Logical) (ring $($lAfter.Ring) + overflow $($lAfter.Overflow))"
        Assert-Ring "the single building 0x$($script:singleUnit)" `
            (@($after.Rows | Where-Object { $_.Unit -eq $script:singleUnit }) | Select-Object -First 1) `
            $ENGINE_SLOTS $SCV_TYPE
        Assert-That "its logical queue is still past the engine's $ENGINE_SLOTS ($($lAfter.Logical))" `
            ($lAfter.Logical -gt $ENGINE_SLOTS)
        # Drain-proof again: a completion can shorten the queue between the two reads, but
        # the money says how many items were accepted whatever happened to them afterwards.
        $paid = $mineralsBeforeSingle - $after.Minerals
        Assert-That "the engine charged for all $presses of them ($presses x $SCV_COST = $($presses * $SCV_COST), paid $paid)" `
            ($paid -eq $presses * $SCV_COST)
        $script:singleLogical = $lAfter.Logical
        Shot 'single-queued'
    }

    Step 'the measurement, stated as numbers' {
        Write-Host ''
        Write-Host "       buildings selected                     : $Buildings"
        Write-Host "       presses                                : $Clicks"
        Write-Host "       0x1F that reached the funnel           : $($script:wireCmds)"
        Write-Host "       units queued across the group          : $($script:unitsQueued)"
        Write-Host "       minerals the group burst moved         : $($script:mineralsBefore - $script:mineralsAfterBurst)"
        Write-Host "       items the plugin took back out of rings: $($script:capturedAfterBurst)"
        Write-Host "       single-building logical queue after    : $($script:singleLogical)"
        Write-Host ''
    }
}
finally {
    if ($gamePid -gt 0 -and -not $KeepOpen) {
        try {
            & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | ForEach-Object { Write-Host "       $_" }
        }
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

# THE PLUGIN SPENT NOTHING OF ITS OWN. Every item that queued was accepted and paid for by
# the engine's addToBuildQueue; the plugin's only resource write is the refund. That is an
# assertion, not a coincidence (sc_prodqueue.h, THE RESOURCE RULE).
#
# It used to be asserted HERE, off mineralsSpent/gasSpent -- two counters nothing ever
# incremented (issue #66). Measured before deleting them: a build that really did spend
# left both reading 0 while the balance assertions failed. So the claim is asserted where
# it can fail, against the engine's own globals: the exact-charge assertion during the
# burst, and the unchanged-balance assertion after it. What is left on this line is the
# REFUND counter, which Refund() increments for real.
$stats = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
           Select-String -Pattern 'PRODQSTATS ')
if ($stats.Count -gt 0) {
    Write-Host "  $($stats[-1].Line)"
    $m = [regex]::Match($stats[-1].Line,
        'captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+) refusedFull=(\d+) mineralsRefunded=(\d+) gasRefunded=(\d+)')
    if ($m.Success) {
        Assert-That "it refunded exactly the one cancelled item ($($m.Groups[6].Value) minerals)" `
            ([int]$m.Groups[6].Value -eq $SCV_COST)
    } else { Assert-That 'the stats line parsed' $false "($($stats[-1].Line))" }
} else { Assert-That 'the plugin wrote its production-queue stats line' $false }

$fanStats = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern 'PRODFAN STATS: ')
if ($fanStats.Count -gt 0) {
    Write-Host "  $($fanStats[-1].Line)"
    $m = [regex]::Match($fanStats[-1].Line, 'fanned=(\d+) refused=(\d+) buildingsReached=(\d+)')
    if ($m.Success) {
        Assert-That "the run fanned out all $Clicks group presses ($($m.Groups[1].Value))" `
            ([int]$m.Groups[1].Value -eq $Clicks)
        Assert-That "reaching $Buildings buildings each time ($($m.Groups[3].Value))" `
            ([int]$m.Groups[3].Value -eq $Clicks * $Buildings)
    }
} else { Assert-That 'the plugin wrote its group-production stats line' $false }

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-group-queue-over-five: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
