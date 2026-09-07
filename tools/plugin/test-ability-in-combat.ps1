#Requires -Version 7
<#
.SYNOPSIS
PLUGIN-vs-STOCK: does using an ability on a >12 selection IN COMBAT stop the units
fighting? A block of Supply Depots is attacked by 36 units, ONE ability is used once
mid-fight, and every unit's order is compared across that moment -- with the plugin
active, and again with `-Mode observe`, which installs no hook at all.

Two abilities, the same measurement (`-Ability`):

  stim  (default) 36 Marines, Stim Pack, pressed with 'T'. Task 022's original arm; its
        numbers and its fixture are unchanged by the parameterisation.
  cloak           36 GHOSTS, Personnel Cloaking, clicked on the Cloak card slot -- THE
        USER'S ACTUAL UNIT. Task 026 made this arm possible: it read the command card
        out of process memory, found the Cloak button greyed because the fixture
        generator wrote PTEx with the wrong index order, and fixed the generator. The
        slot is not guessed -- it is located in the live card by its Button action
        0x00423730 (the code that builds command 0x21) and clicked at the centre the
        engine's own hit-test computes.

This is task 022's question 3, from the user's report: "when i played a cloacked ghost
did not attack enemies at some point - check that if we might have changed that behav",
and the conductor's hypothesis for it: that the Select commands the fan-out replays
interrupt orders that are already running.

.DESCRIPTION
The hypothesis is testable directly. The fan-out emits `Select`+order pairs only when a
command is issued, so the moment to look at is the instant a fanned-out command goes out
while the units are busy doing something else. Cloak is the sharpest such command: it is
untargeted, it costs the acting unit ENERGY, and -- this is the point -- its handler does
NOT touch the main order. 0x004C0720 loops the selection calling 0x00491B30, which
deducts CUnit+0xA2 and sets the SECONDARY order (CUnit+0xA6) to 0x6D. Nothing in that
path writes CUnit+0x4D. So a unit that was attacking must still be attacking afterwards,
and if ours are not, the difference is ours.

WHAT IS COMPARED, AND WHY IT IS A FAIR COMPARISON
Both arms carry the same read-only WORLD scan (-WorldScan 1), which walks the ENGINE's
own per-player unit lists and installs no hook -- so the stock arm is stock apart from an
observer that only reads, and both arms are measured by the same instrument. In
`-Mode observe` the plugin installs zero hooks: no command interception, no Select
interception, no dispatcher detour. The metric is per unit and matched by CUnit pointer
across two scans, so "unit 5 stopped attacking" is a statement about unit 5 and not about
a histogram that happens to move.

WHY THE STIM ARM STILL EXISTS NOW THAT CLOAK CAN BE DRIVEN. It is not a stand-in any
more, it is a second data point: Stim and Cloak take different paths through the client
(Stim's handler writes a timer at CUnit+0x115, Cloak's writes the SECONDARY order at
CUnit+0xA6 and deducts energy), and neither is supposed to touch the main order. An
interruption that showed up in one and not the other would say something specific. Task
022's earlier claim -- that nothing in this harness could make the client emit Cloak --
was TRUE ONLY BECAUSE THE FIXTURE NEVER GRANTED THE TECH; the button was on the card the
whole time, greyed. See research/command-card.md.

.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1

.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1 -Ability cloak   # Ghosts, the user's own unit

.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1 -Modes fanout   # the plugin arm alone
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    # WHICH ABILITY IS USED MID-FIGHT. Everything else about the measurement is identical;
    # see the ability descriptor below for what each one changes.
    [ValidateSet('stim', 'cloak')][string]$Ability = 'stim',
    # Defaulted AFTER the param block so it can follow -Ability (see below). Left as a
    # parameter so a caller can still pin it.
    [string]$LogDir,
    # Which folder under Maps\ the fixture is generated into; see test-burrow-fanout.ps1.
    # Default is what this suite has always used.
    [string]$FixtureDir,
    [int]$UnitCount = 36,
    # NO low-energy tail by default. The client's own command card refuses an ability
    # when the units it can see cannot pay for it -- the same send-side gate this task
    # found on Stim's fourth press -- so a low-energy tail can disable the button and
    # leave the run measuring nothing at all. Pass -DamagedCount to put the engine's
    # affordability gate back in the picture once the ability is known to fire.
    [int]$DamagedCount = 0,
    [int]$DamagedEnergy = 5,
    # THE ENEMY CANNOT SHOOT BACK **BY ANY CHOICE OF ITS OWN**, AND THERE IS A LOT OF IT.
    # Both halves are the fixture doing the job the assertion should not have to.
    #
    # The measurement compares a two-second window against two-second controls either side
    # of it, so the fight has to be STEADY across all three. Against Hydralisks it was not:
    # with sixteen, the group lost units fast enough that the controls disagreed by exactly
    # the margin the script calls too unstable to mean anything; with ten, the Marines
    # wiped them mid-measurement and the second control caught 23 units dropping to idle
    # at once -- the fight ENDING, not the ability doing anything.
    #
    # Lurkers were tried and were a mistake worth recording: an UNBURROWED Lurker has no
    # weapon, but a computer-owned one BURROWS on its own -- and a burrowed Lurker is all
    # weapon, with splash, into a Marine ball. Player 0 went 36 -> 2 units during the
    # measurement. The premise has to be "cannot attack", not "is not currently attacking".
    #
    # A SUPPLY DEPOT cannot attack, cannot move, and cannot decide to do either. Twelve of
    # them is 6000 hit points, which 36 Marines chew through slowly enough that the fight
    # outlasts all three measurement windows, and nothing shoots back so the population
    # does not decay at all. The units under test are still doing the thing the hypothesis
    # is about -- attacking -- which is all it needs. Removing the return fire removes the
    # noise, not the test.
    [int]$EnemyCount = 12,
    [string]$EnemyType = '109',       # units.dat 109, Terran Supply Depot
    [string]$EnemyRace = 'terran',
    [ValidateSet('fanout', 'observe')][string[]]$Modes = @('fanout', 'observe'),
    [int]$EngageTimeoutSec = 60,
    # How long to let the fight settle after engagement before the first control window,
    # for the arms whose descriptor asks for it. Bounded: a fight that never settles is
    # measured anyway and the control-spread assertion is left to catch it.
    [int]$SettleTimeoutSec = 45,
    # How many times the three-window measurement may be re-taken while looking for a set
    # in which no target died. See the block comment above the loop for why that matters.
    [int]$MeasureTries = 4,
    # How far the two control windows may disagree before the fight is declared too
    # unstable to measure. Strictly less than this; see the assertion.
    [int]$ControlSpreadLimit = 6,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0
$step = 0
$script:armLock = $null

# THE ABILITY DESCRIPTOR. Everything that differs between the two arms lives here, so
# the measurement below reads the same for both and neither arm can quietly acquire a
# different yardstick from the other.
#
# The EFFECT ORACLE is the load-bearing field. In `-Mode observe` there is no CMD or
# FANOUT line to look at (no hook is installed), so without a world-visible effect a
# swallowed input produces 0/0/0 and every assertion passes while measuring nothing. Each
# ability therefore names a per-unit predicate the read-only world scan can evaluate:
#   stim  -- CUnit+0x115, the timer 0x004C2F30 writes;
#   cloak -- CUnit+0xA6, the SECONDARY order 0x00491B30 sets to 0x6D. That handler also
#            deducts CUnit+0xA2 (energy) and touches the main order nowhere, which is
#            exactly why this ability is the sharp test of the interruption hypothesis.
# Set from -EnemyType / the ability descriptor just below the descriptor table. The
# allowed values are the weaponless, immobile Terran buildings this suite has verified.
$ENEMY_TYPE_ID = 109
# units.dat ids this suite will accept as a target block, with the property that matters:
# no weapon, and no way for the unit to DECIDE to act (a computer-owned Command Centre
# with no orders never lifts off). "Cannot attack", not "is not currently attacking" --
# the distinction a burrowing Lurker taught this file the hard way.
$ENEMY_TYPES_OK = @{ 109 = 'Terran Supply Depot (500 hp)'; 106 = 'Terran Command Centre (1500 hp)' }
$IDLE_ORDER = 0x03
$CLOAK_ORDER2 = 0x6D       # research/ability-semantics.md §3
# The Ghost Cloak BUTTON's action function -- what NAMES a card slot as Cloak in the
# memory read. Byte-exact, not inferred: 0x00423730 is
# `if (sendGate()) { buf = {0x21, shiftFlag}; queueCommand(buf, 2); }`
# (research/command-card.md §4).
$CLOAK_ACTION = '00423730'
# The same slot's other face; it sends 0x22. Slot 7 is a TOGGLE, so which of the two the
# card shows depends on whether the portrait unit is currently cloaked -- and a take that
# re-uses the ability therefore clicks Decloak. Both are the same button and the same
# fan-out; what is being measured is a fanned-out command issued mid-fight, in either
# direction (research/command-card.md §3.1).
$DECLOAK_ACTION = '00423270'
$CLOAK_PAIR = @($CLOAK_ACTION, $DECLOAK_ACTION)

$ABILITIES = @{
    stim = @{
        Name = 'Stim Pack'; UnitName = 'marine'; UnitType = 0; UnitLabel = 'Marines'
        Tech = 'stim-packs'; TechPattern = 'PTEx: player 0 has researched 0\(stim-packs\)'
        Cmd = '0x36'; Cmds = @('0x36')
        # 'T' -- plain, unmodified, so 021's accelerator finding does not bite.
        Key = 0x54
        EffectName = 'the stim effect'
        Effect = { param($U) $U.Stim -gt 0 }
        # What 0x004C2F30 writes to CUnit+0x115; nothing may exceed it.
        Bound = { param($U) $U.Stim -le 0x25 }
        BoundName = "no timer exceeds the handler's own 0x25"
        # Stim is paid for in HIT POINTS.
        Paid = { param($Now, $Before) $Now.Hp -lt $Before.Hp }
        PaidName = 'hit points'
        NeedCard = $false
        EnemyCount = 12
        # Supply Depot, 500 hit points. Unchanged: this arm's published numbers were
        # measured against this block.
        EnemyType = '109'
        # OFF for stim, deliberately: this arm's published numbers were measured without
        # it and turning it on would change them for no reason. See the cloak entry.
        Settle = $false
        # NOT A TOGGLE: a TIMED buff that OUTLIVES a take (issue #39). 0x004C2F30 writes
        # 0x25 to CUnit+0x115 and the engine counts it down over roughly twelve seconds,
        # which is longer than one three-window take plus its resettle. So a retake that
        # simply pressed T again would find every unit already carrying the effect, and
        # the did-it-fire oracle -- "how many units carry it, before vs after" -- would
        # read a delta of zero and fail the arm for a reason that is entirely the
        # harness's. See the retake loop, which waits for the effect to lapse.
        Toggle = $false
    }
    cloak = @{
        Name = 'Personnel Cloaking'; UnitName = 'ghost'; UnitType = 1; UnitLabel = 'Ghosts'
        Tech = 'personnel-cloaking'
        TechPattern = 'PTEx: player 0 has researched 10\(personnel-cloaking\)'
        Cmd = '0x21'; Cmds = @('0x21', '0x22')   # Cloak / Decloak -- the two faces of slot 7
        # NO KEY. The card's hotkey path and its mouse path both test the same disabled
        # bit, so with the tech researched either would do -- but the CLICK is the one
        # that can be aimed at the button's own rect, read from the live dialog, which is
        # what removes the "the input missed" confound task 022 could not remove.
        Key = $null
        EffectName = "the cloak secondary order 0x$('{0:x2}' -f $CLOAK_ORDER2)"
        Effect = { param($U) $U.Order2 -eq $CLOAK_ORDER2 }
        # Cloak has no timer to bound; the secondary order is the state itself.
        Bound = $null
        BoundName = ''
        # Cloak is paid for in ENERGY (0x00491B30 deducts CUnit+0xA2), and it keeps
        # draining while it is up, so "lower than before" is a safe direction.
        Paid = { param($Now, $Before) $Now.Energy -lt $Before.Energy }
        PaidName = 'energy'
        NeedCard = $true
        # MORE TARGETS THAN THE STIM ARM, and for a measured reason: a Ghost out-damages a
        # Marine per second (10 per shot on a 22-frame cooldown against 6 on 15) and
        # out-ranges it by three, so more of the group is in range at once. The block has
        # to outlast three measurement windows -- the assertion that catches this is
        # "the target block outlasted the measurement", and a block that dies mid-run puts
        # the end of the fight inside a control window (§8.4b of ability-semantics.md).
        EnemyCount = 16
        # A COMMAND CENTRE, NOT A SUPPLY DEPOT, and this is the fixture doing the job an
        # assertion should not have to. 1500 hit points against the depot's 500, so the
        # interval between target deaths triples and none can die inside a two-second
        # window in practice. Measured on the depot block: the plugin arm lost a target
        # roughly every 13 s (16 -> 13 across one run) and one of those deaths landed
        # INSIDE the ability window, idling 33 of 36 Ghosts at once -- the exact signature
        # the hypothesis predicts, manufactured by the fixture. The no-target-died gate
        # below catches that; this stops it happening. Both are kept: the fixture makes
        # clean runs the normal case, the gate makes a dirty one impossible to publish.
        # Still weaponless and immobile -- a computer-owned Command Centre with no orders
        # cannot lift off, so the "cannot attack, cannot decide to" premise is unchanged.
        EnemyType = '106'
        # WAIT FOR THE FIGHT TO SETTLE before the first control window. Measured, not
        # guessed: on the first cloak run the leading control saw 6 order changes and the
        # trailing one saw 0 -- a spread of exactly the bound the suite calls too unstable
        # to measure, and it refused the run. The cause was not decay but ARRIVAL: a Ghost
        # out-ranges a Marine by three tiles, so the group trickles into range over several
        # seconds and every arrival is a 0x06 Move -> 0x0a AttackUnit transition that lands
        # in whichever window catches it. Measuring after the histogram stops moving is the
        # fix; widening the tolerance would only have hidden it.
        Settle = $true
        # A TOGGLE (issue #39). Slot 7's second use is Decloak -- command 0x22, the same
        # button and the same fan-out -- so a retake that clicks it again produces a
        # LARGE effect delta in the other direction (36 -> 0) rather than the zero delta
        # a re-applied timed buff produces. Nothing to wait for; the assertions below
        # already read the magnitude of the change rather than its sign.
        Toggle = $true
    }
}
$ABIL = $ABILITIES[$Ability]
$UNIT_TYPE = $ABIL.UnitType
$ABILITY_CMD = $ABIL.Cmd
$ABILITY_KEY = $ABIL.Key
# The descriptor supplies the default only when the CALLER did not. -EnemyCount 12 passed
# explicitly must stay 12 even on the arm whose descriptor says 16.
if (-not $PSBoundParameters.ContainsKey('EnemyCount')) { $EnemyCount = $ABIL.EnemyCount }
if (-not $PSBoundParameters.ContainsKey('EnemyType'))  { $EnemyType  = $ABIL.EnemyType }
$ENEMY_TYPE_ID = [int]$EnemyType
if (-not $LogDir) { $LogDir = $(if ($Ability -eq 'stim') { 'C:\sc-work\logs\022' } else { 'C:\sc-work\logs\026' }) }
# The camera opens centred on the start location and never moves on its own, so a click
# at client x is an order to (start.x + x - 320). Same constants as test-combat-death.ps1.
$WALK_X = 540
$WALK_Y = 240

$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
# A FIXTURE FOLDER OF ITS OWN, not the shared 00-testmap.
# Sharing a folder means two workers can pick each other's maps -- which happened twice
# during task 022, once in each direction, and cost a run each time. A folder of our own
# removes the interference in both directions rather than racing for it. No row is
# assumed from the name any more: Select-ScBrowserMap computes every click from the
# filesystem and verifies what opened.
# Not a bare default any more: with $env:AGENT_TASK set this resolves to THIS
# agent's own folder, so two concurrent runs of this same suite cannot land in one
# folder and overwrite each other's identically-named fixture (task 023 review).
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t022' -Suite 'ability-in-combat' }
$mapDir = $FixtureDir
# One NAME per fixture, and the two abilities need different units, so they are two
# different fixtures of the same suite. The stim name is left exactly as it was so a
# concurrent 022-shaped run sees the file it has always seen.
$mapName = $(if ($Ability -eq 'stim') { 'ability-in-combat.scx' } else { "ability-in-combat-$Ability.scx" })
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

function New-Fixture {
    # Possibly several workers -- see Wait-ScFixtureFolderFree. Never
    # `Remove-Item -Recurse` this directory.
    Wait-ScFixtureFolderFree -Run $fixtures
    $genArgs = @{
        UnitCount = $UnitCount; UnitType = $ABIL.UnitName; Player = 0
        TechResearched = $ABIL.Tech
    }
    if ($DamagedCount -gt 0) {
        $genArgs.DamagedCount = $DamagedCount
        $genArgs.DamagedHp = 100
        $genArgs.DamagedEnergy = $DamagedEnergy
    }
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs `
        -EnemyCount $EnemyCount -EnemyType $EnemyType -EnemyRace $EnemyRace `
        -OutputPath $mapPath 2>&1
    $gen | Where-Object { "$_" -notmatch 'WARNING:StormLib' } | ForEach-Object { Write-Host "       $_" }
    Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
    # The generator's own read-back. NOT sufficient on its own -- until task 026 it used
    # the same wrong PTEx index as the writer and happily confirmed a byte the engine
    # never read (research/command-card.md §6). The ENGINE's opinion is asserted in the
    # arm itself, off the card read-back's tech arrays.
    Assert-That "$($ABIL.Name) is researched for the human slot" `
        (@($gen | Select-String -Pattern $ABIL.TechPattern).Count -gt 0)
    if ($DamagedCount -gt 0) {
        Assert-That "the low-energy tail is in the map file ($DamagedCount at $DamagedEnergy%)" `
            (@($gen | Select-String -Pattern "tail starts at $DamagedEnergy% energy").Count -gt 0)
    }
}

# One arm: launch in $Mode, walk into the enemy, press Cloak, and take the three scans
# the comparison needs. Returns the metrics; assertions that only make sense for one arm
# are made by the caller.
function Invoke-Arm {
    param([Parameter(Mandatory)][string]$Mode)

    $logPath = Join-Path $LogDir "$Ability-combat-$Mode.log"
    $shotDir = Join-Path $LogDir "$Ability-combat-$Mode-frames"
    $markerPath = Join-Path $LogDir 'marker.txt'
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
    New-Item -ItemType Directory -Path $shotDir -Force | Out-Null

    # The game is single-instance machine-wide (Wait-ScNoGameRunning), and the launch
    # lock is normally held only around the launch -- which is not enough when the thing
    # that collides is a game that is still ALIVE. So: wait for the machine to be free,
    # then hold the lock for as long as this arm's game exists, and tell run-with-plugin
    # not to take it again underneath us.
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $script:armLock = Enter-ScLaunchLock -TaskId '022-ability-in-combat'
    $gamePid = 0
    # -CardScan only where the arm needs it: it is read-only and hookless in both modes,
    # but it writes a block of CARD lines per marker and there is no reason to carry that
    # in an arm that never asks for a card.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode $Mode -WorldScan 1 -CardScan ($ABIL.NeedCard ? '1' : '0') `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $logPath 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:armPid = [int]$Matches[1] }
        }
    $gamePid = $script:armPid
    if (-not $gamePid) { throw "test: could not parse the game pid for arm '$Mode'." }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid
    $shotN = 0
    function ArmShot([string]$t) {
        $script:shotSeq++
        Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir ("{0:d2}-{1}.png" -f $script:shotSeq, $t)) -FullWindow | Out-Null
    }
    $script:shotSeq = 0

    $result = [ordered]@{ Mode = $Mode; LogPath = $logPath; Pid = $gamePid }
    try {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415
        Start-Sleep -Seconds 2
        # Every row from the filesystem, and the opened folder verified before the map row
        # is clicked. Task 022 computed the FOLDER row here and left the MAP row hardcoded
        # at 159; that half was the original incident (a foreign .scx sorting before ours).
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2      # Use Map Settings, verified (see Set-ScGameType)
        ArmShot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN
        # OK button, then asserted gone (task 027) -- never a fixed point, never the registry.
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $logPath | Out-Null
        Start-Sleep -Seconds 2

        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $result.Boxed = Get-ScWorldState -LogPath $logPath -Tag 'boxed' -MarkerPath $markerPath
        ArmShot 'boxed'

        # Into the enemy. One right-click; in `observe` only the engine's twelve obey,
        # which is the stock behaviour and exactly what the control is for.
        $mark = Get-ScLogLineCount -LogPath $logPath
        Send-ScClick -Hwnd $hwnd -X $WALK_X -Y $WALK_Y -Right
        $result.WalkMark = $mark

        # Wait for the fight to actually start: enemy hit points below their starting
        # total is the only signal that means "shots are landing", and it is read from
        # the enemy's own units.
        $startEnemyHp = Get-EnemyHp $result.Boxed
        $deadline = (Get-Date).AddSeconds($EngageTimeoutSec)
        $engaged = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            $w = Get-ScWorldState -LogPath $logPath -Tag 'engaging' -MarkerPath $markerPath
            $hp = Get-EnemyHp $w
            if ($hp -lt $startEnemyHp) { $engaged = $w; break }
        }
        $result.StartEnemyHp = $startEnemyHp
        if (-not $engaged) {
            $result.Engaged = $engaged
            ArmShot 'engaged'
            return $result
        }

        # LET THE FIGHT SETTLE, for the arms that ask for it. "Engaged" only means the
        # first shots have landed; part of the group can still be walking into range, and
        # every arrival is an order transition that lands in whichever measurement window
        # happens to catch it. Waiting until the main-order histogram stops changing makes
        # the three windows comparable, which is the property the control-spread assertion
        # tests. Bounded, and the LAST scan taken becomes `engaged` so the first control
        # window starts from a settled fight rather than from the arrival scan.
        if ($ABIL.Settle) {
            $settleDeadline = (Get-Date).AddSeconds($SettleTimeoutSec)
            $prevHist = $null
            while ((Get-Date) -lt $settleDeadline) {
                Start-Sleep -Seconds 3
                $s = Get-ScWorldState -LogPath $logPath -Tag 'settling' -MarkerPath $markerPath
                $hist = (((Get-Mine $s) | ForEach-Object { '0x{0:x2}' -f $_.Order } |
                          Group-Object | ForEach-Object { "$($_.Name):$($_.Count)" }) |
                         Sort-Object) -join ' '
                if ($hist -eq $prevHist) { $engaged = $s; break }
                $prevHist = $hist
                $engaged = $s
            }
            Write-Host ("       [{0}] fight settled at orders [{1}]" -f $Mode, $prevHist)
            $result.SettledOrders = $prevHist
        }
        $result.Engaged = $engaged
        ArmShot 'engaged'

        # ============================================================================
        # THE MEASUREMENT, AND THE CONFOUND IT HAS TO SURVIVE
        #
        # Three windows of the same length in the same fight: a control with no ability,
        # then the ability, then a second control. Units in a firefight change orders
        # constantly on their own, so "33 units changed order across the ability" means
        # nothing until you know what an ordinary two seconds looks like.
        #
        # BUT: when a TARGET DIES, every unit that was shooting it drops from 0x0a
        # (AttackUnit) to 0x03 in the same instant -- which is bit-for-bit the signature
        # the hypothesis under test predicts. Measured on the 2026-08-09 cloak run: 33 of
        # 36 Ghosts went 0x0a -> 0x03 across the ability window, and the enemy count in
        # the very same pair of scans went 14 -> 13. A building had died inside the
        # window. Reported as-is that would have been a headline finding against our own
        # plugin, produced entirely by the fixture.
        #
        # It bites the plugin arm and not the stock arm BECAUSE THE FEATURE WORKS: in
        # fanout all 36 units are shooting, in stock only the engine's twelve, so the
        # plugin arm kills targets about three times faster and is three times as likely
        # to have one die inside a window. A confound correlated with the arm is the worst
        # kind, so it is not tolerated and not averaged -- the window is RE-TAKEN until
        # no target dies in any of the three, and a run that never gets a clean set fails
        # rather than reporting the dirty one.
        # ============================================================================
        # ============================================================================
        # AND THE SECOND CONFOUND, WHICH THE RETAKE ITSELF CREATED (issue #39)
        #
        # The retake above re-uses the ability, because a measurement window with no
        # ability use in it is not an ability window -- "apply once and retake only the
        # measurement" cannot work, there is nothing left to measure. But a TIMED buff
        # OUTLIVES a take: 0x004C2F30 writes 0x25 to CUnit+0x115 and the engine counts
        # that down over roughly twelve seconds, which is longer than one three-window
        # take plus its resettle.
        #
        # So from take 2 every Marine was already stimmed, the did-it-fire oracle --
        # units carrying the effect, before against after -- read a delta of ZERO, and
        # the suite failed. Reproducibly, on every sweep, for a reason entirely its own:
        # 36 Marines against 500 hp Supply Depots kill a target inside a two-second
        # window most runs, so the retake path is the common case, not the rare one.
        #
        # The fix is to make a retake start from the state take 1 started from: nobody
        # carrying the effect. Wait for it to lapse, then take again. A TOGGLE (cloak)
        # needs none of this -- its second use is Decloak, a large delta in the other
        # direction, which the assertions already read by magnitude.
        # ============================================================================
        function Wait-EffectLapsed {
            param([Parameter(Mandatory)][object]$Reference, [int]$TimeoutSec = 40)
            $carrying = @((Get-Mine $Reference) | Where-Object { & $ABIL.Effect $_ }).Count
            if ($carrying -eq 0) { return $Reference }
            Write-Host ("       [{0}] waiting for {1} to lapse on {2} unit(s) before the next take" -f `
                $Mode, $ABIL.EffectName, $carrying)
            $deadline = (Get-Date).AddSeconds($TimeoutSec)
            $w = $Reference
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 2
                $w = Get-ScWorldState -LogPath $logPath -Tag 'lapsing' -MarkerPath $markerPath
                $carrying = @((Get-Mine $w) | Where-Object { & $ABIL.Effect $_ }).Count
                if ($carrying -eq 0) {
                    Write-Host ("       [{0}] {1} has lapsed; taking again from a clean state" -f $Mode, $ABIL.EffectName)
                    return $w
                }
            }
            # LOUD, not a zero delta later. The issue's third suggestion, and the reason
            # this class of mistake will name itself next time instead of arriving as an
            # unexplained red suite.
            throw ("test: $($ABIL.EffectName) is still on $carrying unit(s) after ${TimeoutSec}s, so the " +
                   'next take would re-apply it to units that already carry it and the ' +
                   'did-it-fire check would read a delta of zero. Refusing to measure that ' +
                   '(issue #39). The units are being re-stimmed by something, or the timeout is too short.')
        }

        $clean = $false
        for ($take = 1; $take -le $MeasureTries; $take++) {
            # Every take starts from "nobody carries the effect", take 1 included -- so
            # this is also the assertion that the fixture handed us a clean start, and it
            # is proved positive on any retake, where the same read returns non-zero
            # before the wait and zero after it.
            if (-not $ABIL.Toggle) { $result.Engaged = Wait-EffectLapsed -Reference $result.Engaged }
            $ref = $result.Engaged
            $refEnemies = Get-EnemyCount $ref

            Start-Sleep -Seconds 2
            $baseline = Get-ScWorldState -LogPath $logPath -Tag "baseline" -MarkerPath $markerPath

            # THE CARD, READ OUT OF MEMORY, for the arm that clicks one (task 026). Taken
            # BEFORE the ability so the slot the click aims at is the slot this take
            # measured, and so a greyed button is caught as a fixture failure here rather
            # than as a mysterious zero later. The tech arrays in the same read are THE
            # ENGINE's opinion of the fixture, which the generator's own read-back cannot
            # give. Re-read every take: slot 7 is a TOGGLE and shows whichever face
            # matches the portrait unit's current state.
            $cloakSlot = $null
            if ($ABIL.NeedCard) {
                $card = Get-ScCardState -LogPath $logPath -Tag "card" -MarkerPath $markerPath
                $result.Card = $card
                $hits = @($card.Slots | Where-Object { $_.HasButton -and $_.Action -in $CLOAK_PAIR })
                if ($hits.Count -ne 1) {
                    throw ("test: the live command card carries $($hits.Count) slots with the Cloak " +
                           "toggle (0x$CLOAK_ACTION / 0x$DECLOAK_ACTION), expected exactly one. " +
                           "Card: $($card.Lines -join ' | ')")
                }
                $cloakSlot = $hits[0]
                $result.CloakSlot = $cloakSlot
                $result.TechResearched = @($card.TechResearched)
                Write-Host ("       [{0}] take {1}: card slot {2} is {3}, showing its {4} face; engine says player {5} researched [{6}]" -f `
                    $Mode, $take, $cloakSlot.Index, $cloakSlot.State,
                    ($cloakSlot.Action -eq $CLOAK_ACTION ? 'Cloak' : 'Decloak'),
                    $card.TechPlayer, (@($card.TechResearched) -join ' '))
                if ($cloakSlot.Disabled) {
                    throw ("test: the Cloak button is GREYED on the live card, so no input could issue it and " +
                           "this arm would measure nothing. Engine-researched techs: [$(@($card.TechResearched) -join ' ')].")
                }
            }

            # THE MOMENT UNDER TEST: one ability use, with the group mid-fight.
            $mark = Get-ScLogLineCount -LogPath $logPath
            if ($null -ne $ABILITY_KEY) {
                # No click fallback for the keyed ability. Guessing at a command-card
                # button position is how this test previously armed a TARGETED ability by
                # mistake -- the frame came back showing "Select Target" -- and an ability
                # nobody used measures nothing while looking green. The key is 'T', it is
                # unmodified, and task 022 §5 proves the client emits 0x36 for it.
                Send-ScKey -Hwnd $hwnd -VirtualKey $ABILITY_KEY
            }
            else {
                # And no guessed coordinate for the clicked one either: the point is the
                # live control's own rect plus its dialog's origin, the sum the engine
                # forms at 0x00458850. That is what makes a silent result mean "the button
                # refused" rather than "the click landed between buttons".
                $p = Get-ScCardSlotPoint -Card $result.Card -Slot $cloakSlot.Index
                Write-Host ("       [{0}] take {1}: clicking card slot {2} at its own computed centre ({3},{4})" -f `
                    $Mode, $take, $cloakSlot.Index, $p.X, $p.Y)
                Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y
            }
            Start-Sleep -Seconds 2
            $lines = @(Get-Content -LiteralPath $logPath | Select-Object -Skip $mark)
            $after = Get-ScWorldState -LogPath $logPath -Tag "after-ability" -MarkerPath $markerPath

            # A SECOND control window, immediately after. A fight decays: two seconds
            # later there are fewer targets left, so one control taken before the ability
            # is not automatically comparable to the ability window. Two controls bracket
            # the drift -- and if they disagree markedly, the fight is too unstable for
            # the measurement and the run says so instead of averaging them.
            Start-Sleep -Seconds 2
            $controlAfter = Get-ScWorldState -LogPath $logPath -Tag "control-after" -MarkerPath $markerPath

            $enemyRun = @($refEnemies, (Get-EnemyCount $baseline), (Get-EnemyCount $after),
                          (Get-EnemyCount $controlAfter))
            $clean = @($enemyRun | Select-Object -Unique).Count -eq 1
            Write-Host ("       [{0}] take {1}: targets alive across the three windows: {2}{3}" -f `
                $Mode, $take, ($enemyRun -join ' -> '),
                ($clean ? '  (clean)' : '  <- a target died inside a window; re-taking'))

            $result.AbilityLines = $lines
            $result.Baseline = $baseline
            $result.After = $after
            $result.ControlAfter = $controlAfter
            $result.Takes = $take
            $result.CleanTake = $clean
            $result.EnemyRun = $enemyRun
            if ($clean) { break }

            # Not clean. Let the group re-acquire and settle before the next take -- the
            # order churn a death causes is exactly what must not be inside a window.
            Start-Sleep -Seconds 5
            $result.Engaged = Get-ScWorldState -LogPath $logPath -Tag "resettling" -MarkerPath $markerPath
        }
        ArmShot 'after-ability'

        Start-Sleep -Seconds 12
        $result.Later = Get-ScWorldState -LogPath $logPath -Tag 'later' -MarkerPath $markerPath
        ArmShot 'later'
    }
    finally {
        if (-not $KeepOpen -and $gamePid -gt 0) {
            try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Out-Null }
            catch { Write-Host "  FAIL close-game failed for arm '$Mode': $($_.Exception.Message)"; $script:failures++ }
            Start-Sleep -Seconds 2
        }
        Exit-ScLaunchLock -Lock $script:armLock
        $script:armLock = $null
    }
    return $result
}

# --- per-arm derived numbers ---------------------------------------------------
# The leading comma keeps the ARRAY an array on the way out: PowerShell unrolls a
# function's array return, so a wiped group comes back as $null and `.Count` throws under
# StrictMode -- which is what happens the moment the Hydralisks win an exchange.
# ==========================================================================
# NOTE THE LEADING COMMA, AND NEVER WRITE @(Get-Mine ...) -- IT SILENTLY
# RETURNS 1. The comma stops PowerShell unrolling the array on the way out,
# which is what keeps `.Count` working when the group has been wiped. But
# wrapping the result in @() AGAIN builds a one-element array holding the
# array, so every count collapses to exactly 1 -- a plausible-looking
# number, never an error.
#
# THIS HAS NOW CAUGHT THIS FILE TWICE, with this note already written above
# it the second time: once reporting "1" for a scan holding 33 Marines, and
# again reporting a population of "1" out of 36. If you are adding a count,
# grep this file for `@(Get-Mine` before you run it.
# ==========================================================================
function Get-Mine { param($Scan) ,@($Scan.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $UNIT_TYPE }) }
function Get-EnemyHp {
    # Sum by hand: Measure-Object emits NOTHING for an empty pipeline, and under
    # StrictMode reading .Sum off that is a thrown error rather than a zero -- which is
    # exactly what happens on a run where the fixture did not spawn (a melee start has no
    # enemies at all) and it hides the real cause behind a property-not-found.
    param($Scan)
    $total = 0
    foreach ($u in $Scan.Units) { if ($u.Type -eq $ENEMY_TYPE_ID) { $total += $u.Hp } }
    return $total
}
# HOW MANY TARGETS ARE STILL ALIVE. The count, not the hit points: what wrecks a window is
# a target being DESTROYED (every unit shooting it drops to 0x03 at once), and hit points
# falling steadily is the fight working normally.
function Get-EnemyCount {
    param($Scan)
    $n = 0
    foreach ($u in $Scan.Units) { if ($u.Type -eq $ENEMY_TYPE_ID) { $n++ } }
    return $n
}

# THE MEASUREMENT THE HYPOTHESIS ASKS FOR: for every unit alive in BOTH scans, matched by
# CUnit pointer, did its MAIN ORDER change across the ability?
#
# An earlier version of this counted units that "went idle", which was the wrong predicate
# and produced a sample of one: in this engine a unit that auto-acquires from Guard keeps
# main order 0x03 while it shoots, so "busy" and "idle" are not distinguishable there. An
# order CHANGE is the thing "the replayed Selects interrupt orders" would actually produce,
# it needs no assumption about which order id means fighting, and it is comparable between
# the plugin arm and the stock arm.
function Get-Transitions {
    param($Before, $After)
    $post = @{}
    foreach ($u in (Get-Mine $After)) { $post[$u.Unit] = $u }
    $pre = Get-Mine $Before
    $stillHere = @($pre | Where-Object { $post.ContainsKey($_.Unit) })
    $changed = @($stillHere | Where-Object { $post[$_.Unit].Order -ne $_.Order })
    $wentIdle = @($stillHere | Where-Object { $_.Order -ne $IDLE_ORDER -and $post[$_.Unit].Order -eq $IDLE_ORDER })
    [pscustomobject]@{
        Before     = $pre.Count
        StillAlive = $stillHere.Count
        Changed    = $changed.Count
        WentIdle   = $wentIdle.Count
        OrdersBefore = (($pre | ForEach-Object { '0x{0:x2}' -f $_.Order } | Group-Object | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ' ')
        OrdersAfter  = (((Get-Mine $After) | ForEach-Object { '0x{0:x2}' -f $_.Order } | Group-Object | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ' ')
        Detail     = ($changed | Select-Object -First 6 | ForEach-Object {
                        "unit=$($_.Unit) 0x$('{0:x2}' -f $_.Order)->0x$('{0:x2}' -f $post[$_.Unit].Order)" }) -join ' '
    }
}

$exePath = Join-Path $GameDir 'StarCraft.exe'
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

$arms = @{}
try {
    Step "generate the fixture: $UnitCount $($ABIL.UnitLabel) vs $EnemyCount Supply Depots, $($ABIL.Name) researched" {
        New-Fixture
    }

    foreach ($mode in $Modes) {
        Step "ARM '$mode': engage, then use $($ABIL.Name) once mid-fight" {
            $arm = Invoke-Arm -Mode $mode
            $arms[$mode] = $arm
            $spawned = (Get-Mine $arm.Boxed).Count
            # A MELEE START is the failure this names on sight: the map loads, the game
            # looks normal, and the units are a standard base instead of the fixture --
            # every later number is then internally consistent nonsense (task 021).
            $melee = @($arm.Boxed.Units | Where-Object { $_.Player -eq 0 -and $_.Type -in 7, 0x40, 0x29, 0x23, 0x2A })
            # The premise the whole fixture rests on, checked where it is used: this enemy
            # has no weapon and cannot move, so it cannot DECIDE to start shooting. The
            # previous fixture used Lurkers, which have no weapon unburrowed -- and a
            # computer-owned one burrows on its own and shreds the group with splash.
            Assert-That ("[{0}] the target block is a weaponless, immobile building type ({1} = {2})" -f `
                         $mode, $ENEMY_TYPE_ID, ($ENEMY_TYPES_OK[$ENEMY_TYPE_ID] ?? 'NOT ON THE VERIFIED LIST')) `
                ($ENEMY_TYPES_OK.ContainsKey($ENEMY_TYPE_ID))
            Assert-That "[$mode] the fixture spawned $UnitCount $($ABIL.UnitLabel)" ($spawned -eq $UnitCount) `
                ($melee.Count -gt 0 ? "(got $spawned, and player 0 owns SCV/Drone/Larva/Overlord-shaped units -- THIS IS A MELEE START, the Game Type pick did not take)" : "(got $spawned)")
            Assert-That "[$mode] and $EnemyCount enemy buildings" `
                (@($arm.Boxed.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count -eq $EnemyCount)
            # EVERY scan the measurement uses, not just the first one. A torn scan drops a
            # unit, and a dropped unit cannot be seen to change its order -- so the bias is
            # DOWNWARD, i.e. towards the conclusion this test reaches. Validating only the
            # scan the numbers are not computed from would have been the wrong one to check.
            foreach ($sc in @(
                @{ N = 'boxed'; S = $arm.Boxed }, @{ N = 'engaged'; S = $arm.Engaged },
                @{ N = 'baseline'; S = $arm.Baseline }, @{ N = 'after'; S = $arm.After },
                @{ N = 'control-after'; S = $arm.ControlAfter })) {
                $c = $sc.S.Counts[0]
                Assert-That "[$mode] the '$($sc.N)' scan was not taken mid-edit" `
                    ($c.Units -eq $c.Recount -and $c.Complete -eq 1) `
                    "(units=$($c.Units) recount=$($c.Recount) complete=$($c.Complete) -- a torn scan biases the result toward 'no disturbance')"
            }
            Assert-That "[$mode] the two sides engaged within ${EngageTimeoutSec}s" ($null -ne $arm.Engaged)
            if (-not $arm.Engaged) { return }

            # THE FIXTURE, AS THE ENGINE SEES IT -- not as the generator says it wrote it.
            # Task 026: the generator verified its own PTEx write with the same wrong index
            # it wrote with, so it reported a researched tech on a map where the engine read
            # a different byte entirely. The card read-back carries the engine's own
            # per-player tech arrays, so this is the independent check.
            if ($ABIL.NeedCard) {
                Assert-That "[$mode] the ENGINE agrees $($ABIL.Name) is researched for this player" `
                    (@($arm.TechResearched) -contains 10) `
                    "(engine says [$(@($arm.TechResearched) -join ' ')])"
                Assert-That "[$mode] and the Cloak card slot was ENABLED when it was clicked (slot $($arm.CloakSlot.Index), $($arm.CloakSlot.State))" `
                    (-not $arm.CloakSlot.Disabled)
            }

            # THE ABILITY MUST BE SHOWN TO HAVE FIRED IN *THIS* ARM, and in the stock arm
            # there is no CMD/FANOUT line to look at -- the command hook is not installed.
            # Without a substitute, a swallowed keypress produces 0/0/0 and every
            # assertion below passes while measuring nothing at all. The effect itself is
            # visible to the world scan in both arms, so that is the signal: units that
            # did not carry the effect before the input and do carry it after.
            $effBefore = @((Get-Mine $arm.Baseline) | Where-Object { & $ABIL.Effect $_ }).Count
            $effAfter  = @((Get-Mine $arm.After)    | Where-Object { & $ABIL.Effect $_ }).Count
            $arm.EffectBefore = $effBefore
            $arm.EffectAfter = $effAfter
            $arm.EffectDelta = [math]::Abs($effAfter - $effBefore)
            # A CHANGE, not an increase. Cloak is a TOGGLE: if the measurement had to be
            # re-taken, the take that counts may have switched the ability OFF, which is
            # the same fanned-out command issued mid-fight and the same test of whether a
            # replayed Select interrupts a running order. Stim only ever goes up, and this
            # is satisfied either way.
            Assert-That "[$mode] the ability actually fired -- units carrying $($ABIL.EffectName) went $effBefore -> $effAfter" `
                ($effAfter -ne $effBefore) `
                '(no unit changed effect state, so this arm measured an input that did nothing and its numbers mean nothing)'

            # THE MEASUREMENT MUST BE UNCONFOUNDED, and this is the assertion that makes
            # every number below readable. A target destroyed inside a window idles every
            # unit that was shooting it -- indistinguishable from the effect under test,
            # and three times more likely in the plugin arm because the fan-out triples
            # the group's damage. Never averaged, never tolerated: no clean take, no result.
            Assert-That ("[{0}] the measurement landed in a window where no target died (take {1} of {2}; targets {3})" -f `
                         $mode, $arm.Takes, $MeasureTries, ($arm.EnemyRun -join ' -> ')) `
                ($arm.CleanTake) `
                '(a target died inside one of the three windows; every unit shooting it drops to 0x03 at once, which is exactly the signature this test looks for. Re-run rather than believing these numbers)'

            # Diagnostics first: a metric computed over the wrong scan is the failure mode
            # this whole task keeps meeting, so the raw sizes are printed before anything is
            # derived from them.
            Write-Host ("       [{0}] scans: boxed={1} engaged={2} after={3} later={4} units parsed" -f `
                $mode, @($arm.Boxed.Units).Count, @($arm.Engaged.Units).Count,
                @($arm.After.Units).Count, @($arm.Later.Units).Count)
            # Churn with no ability (engaged -> baseline) against churn across the
            # ability (baseline -> after). Same fight, same length of window.
            $ctrlBefore = Get-Transitions $arm.Engaged $arm.Baseline
            # THE FIXTURE'S OWN PRECONDITIONS, asserted before any number is derived.
            # A population that moves at all voids the measurement -- a unit that leaves
            # cannot be seen to change its order, so the bias runs toward "nothing
            # changed". And if the target block dies mid-measurement the fight ends, which
            # is what wrecked both previous fixtures.
            # NO @() around Get-Mine -- it returns the array unrolled-proof already, and
            # wrapping it again makes a one-element array holding the array. Same trap this
            # file documents above; it reported a population of "1" the first time.
            $popStart = (Get-Mine $arm.Engaged).Count
            $popEnd = (Get-Mine $arm.ControlAfter).Count
            $enemyStart = @($arm.Engaged.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count
            $enemyEnd = @($arm.ControlAfter.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count
            Write-Host ("       [{0}] population {1} -> {2}; target block {3} -> {4}" -f `
                $mode, $popStart, $popEnd, $enemyStart, $enemyEnd)
            Assert-That "[$mode] not one unit was lost across the whole measurement ($popStart -> $popEnd)" `
                ($popStart -eq $popEnd) `
                '(a moving population voids this measurement, and the bias runs toward the conclusion this test reaches)'
            # The property that matters is that THE FIGHT DOES NOT END during the windows,
            # not that no target is ever destroyed: 36 Marines will chew through a 500-point
            # building every couple of seconds, and losing one of twelve changes nothing
            # about whether the group is still shooting. What ruined the earlier fixtures
            # was the block being WIPED, after which every unit drops to idle at once and
            # the last control window measures the end of the fight. So: most of the block
            # still standing, and -- asserted separately below -- damage still being dealt
            # at the end.
            Assert-That "[$mode] the target block outlasted the measurement ($enemyStart -> $enemyEnd of $EnemyCount)" `
                ($enemyEnd -ge [math]::Ceiling($enemyStart / 2) -and $enemyEnd -gt 0) `
                '(a wiped block ends the fight, and the last control window then measures that instead of an ordinary two seconds)'

            $t = Get-Transitions $arm.Baseline $arm.After
            $ctrlAfter = Get-Transitions $arm.After $arm.ControlAfter
            # NO AGGREGATOR. Picking one of the two controls decides the answer: on the
            # first published run, max() gave threshold 13 against an observed 8 (pass by
            # five) and min() gave 7 against 8 (fail by one) -- the sign of the headline
            # excess flips with the choice. Taking the LARGER is not "conservative", it is
            # lenient: a bigger control raises the bar an excess has to clear. So both are
            # asserted, both are reported, and the strict one is the one that decides.
            $arm.ControlBefore = $ctrlBefore
            $arm.ControlAfterT = $ctrlAfter
            $arm.ControlStrict = $(if ($ctrlAfter.Changed -lt $ctrlBefore.Changed) { $ctrlAfter } else { $ctrlBefore })
            $arm.ControlLenient = $(if ($ctrlAfter.Changed -gt $ctrlBefore.Changed) { $ctrlAfter } else { $ctrlBefore })
            $ctrl = $arm.ControlStrict
            $arm.Control = $ctrl
            $arm.Transitions = $t
            $arm.EnemyHpEngaged = Get-EnemyHp $arm.Engaged
            $arm.EnemyHpAfter = Get-EnemyHp $arm.After
            $arm.EnemyHpLater = Get-EnemyHp $arm.Later
            Write-Host ("       [{0}] orders before: {1}" -f $mode, $t.OrdersBefore)
            Write-Host ("       [{0}] orders after : {1}" -f $mode, $t.OrdersAfter)
            Write-Host ("       [{0}] CONTROL before: {1} of {2} alive, {3} changed order, {4} stopped attacking" -f `
                $mode, $ctrlBefore.StillAlive, $ctrlBefore.Before, $ctrlBefore.Changed, $ctrlBefore.WentIdle)
            Write-Host ("       [{0}] CONTROL after : {1} of {2} alive, {3} changed order, {4} stopped attacking" -f `
                $mode, $ctrlAfter.StillAlive, $ctrlAfter.Before, $ctrlAfter.Changed, $ctrlAfter.WentIdle)
            # An unstable fight is a reason to distrust the measurement, not to average it.
            # STRICTLY less than the bound: the first run of this shape sat exactly ON it
            # (|10-4| = 6), i.e. precisely at the point the script itself calls too
            # unstable to mean anything, and passed. A boundary is not a margin.
            $spread = [math]::Abs($ctrlBefore.Changed - $ctrlAfter.Changed)
            Assert-That ("[{0}] the two control windows agree well enough to be a yardstick (spread {1}, must be < {2})" -f `
                         $mode, $spread, $ControlSpreadLimit) `
                ($spread -lt $ControlSpreadLimit) `
                '(the fight is decaying too fast for a two-second window to mean anything -- re-run on a steadier fixture rather than believing this)'
            Write-Host ("       [{0}] ABILITY window          : {1} of {2} alive, {3} changed order, {4} stopped attacking {5}" -f `
                $mode, $t.StillAlive, $t.Before, $t.Changed, $t.WentIdle, $t.Detail)
            Write-Host ("       [{0}] enemy hit points: {1} at engage -> {2} after -> {3} twelve seconds later" -f `
                $mode, $arm.EnemyHpEngaged, $arm.EnemyHpAfter, $arm.EnemyHpLater)

            # THE ASSERTION QUESTION 3 EXISTS FOR, per arm. "Our replayed Selects interrupt
            # running orders" predicts a step change: a Select lands on every unit at once,
            # so the ability window should knock units off their orders WHOLESALE compared
            # with an ordinary two seconds of the same fight. The control window is the
            # yardstick, and the allowance is deliberately generous -- the prediction under
            # test is dozens of units at once, not one or two more than usual.
            $allowance = 3
            # Against BOTH controls, not against a chosen one. The strict comparison is the
            # one that can fail; the lenient one is reported so the reader can see the
            # spread rather than take the author's aggregator on trust.
            Assert-That ("[{0}] using the ability disturbs no more orders than not using it -- STRICT control ({1} vs {2}+{3})" -f `
                         $mode, $t.Changed, $arm.ControlStrict.Changed, $allowance) `
                ($t.Changed -le $arm.ControlStrict.Changed + $allowance) $t.Detail
            Assert-That ("[{0}] ... and against the lenient control too ({1} vs {2}+{3})" -f `
                         $mode, $t.Changed, $arm.ControlLenient.Changed, $allowance) `
                ($t.Changed -le $arm.ControlLenient.Changed + $allowance) $t.Detail
            Assert-That ("[{0}] and it does not stop units attacking ({1} vs {2} strict / {3} lenient)" -f `
                         $mode, $t.WentIdle, $arm.ControlStrict.WentIdle, $arm.ControlLenient.WentIdle) `
                ($t.WentIdle -le $arm.ControlStrict.WentIdle + $allowance)
            # ... and the group is still fighting afterwards, which is the user's actual
            # complaint. Orders alone could look right while nothing happens.
            Assert-That "[$mode] the group kept doing damage after the ability (enemy $($arm.EnemyHpAfter) -> $($arm.EnemyHpLater))" `
                ($arm.EnemyHpLater -lt $arm.EnemyHpAfter)
        }
    }

    if ($arms.ContainsKey('fanout') -and $arms['fanout'].Engaged) {
        Step 'ARM fanout: the ability really did reach past the cap, and charged per unit' {
            $arm = $arms['fanout']
            $lines = $arm.AbilityLines
            # EITHER FACE OF THE TOGGLE. A re-taken measurement can land on the ability
            # being switched off, which is command 0x22 rather than 0x21 -- the same
            # button, the same fan-out path, and the same question.
            $cmdPat = ($ABIL.Cmds | ForEach-Object { [regex]::Escape($_) }) -join '|'
            $issued = @($lines | Select-String -Pattern "CMD id=($cmdPat) ")
            Assert-That "the ability was issued ($($ABIL.Cmds -join ' or '))" ($issued.Count -gt 0)
            $start = @($lines | Select-String -Pattern "FANOUT start: cmd=($cmdPat) .* units=(\d+)")
            Assert-That 'it was fanned out' ($start.Count -gt 0)
            if ($start.Count -gt 0) {
                $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
                Assert-That "more than twelve units were commanded ($u)" ($u -gt 12)
            }

            # The ability reached past the cap AND was paid for, IN COMBAT -- question 1's
            # result again, on a fixture where the units are busy rather than standing
            # still, which is the case the user was actually in.
            $mine = Get-Mine $arm.After
            $affected = @($mine | Where-Object { & $ABIL.Effect $_ })
            # The MAGNITUDE of the change, so a take that toggled the ability off counts
            # the same as one that toggled it on: either way more than the engine's twelve
            # units obeyed a single command, which is the fan-out doing its job.
            Assert-That ("the command reached more than the engine's twelve (effect count {0} -> {1}, delta {2})" -f `
                         $arm.EffectBefore, $arm.EffectAfter, $arm.EffectDelta) `
                ($arm.EffectDelta -gt 12)
            if ($ABIL.Bound) {
                Assert-That $ABIL.BoundName `
                    (@($affected | Where-Object { -not (& $ABIL.Bound $_) }).Count -eq 0)
            }
            # THE COST, per unit -- but only on a take that switched the ability ON. A
            # toggle-off take leaves nobody carrying the effect, so there is nothing to
            # charge and asserting over an empty set would be a check that cannot fail.
            if ($arm.EffectAfter -gt $arm.EffectBefore) {
                $before = @{}
                foreach ($u in (Get-Mine $arm.Engaged)) { $before[$u.Unit] = $u }
                $paid = @($affected | Where-Object { $before.ContainsKey($_.Unit) -and (& $ABIL.Paid $_ $before[$_.Unit]) })
                Assert-That "every unit that gained the effect also paid for it in $($ABIL.PaidName) ($($paid.Count) of $($affected.Count))" `
                    ($affected.Count -gt 0 -and $paid.Count -eq $affected.Count) `
                    '(this is a weaker form of the per-unit arithmetic by design -- hit points can also fall to enemy fire and energy also regenerates; the strict version lives in test-stim-fanout.ps1, on a fixture with nothing shooting back)'
            }
            else {
                Write-Host ("       the measured take switched the ability OFF ({0} -> {1} carrying it), so there is no per-unit cost to check here" -f `
                    $arm.EffectBefore, $arm.EffectAfter)
            }
        }
    }

    if ($arms.Count -ge 2 -and $arms['fanout'].Engaged -and $arms['observe'].Engaged) {
        Step 'PLUGIN vs STOCK: the comparison this question was asked for' {
            $f = $arms['fanout']; $o = $arms['observe']
            Write-Host ("       fanout : ability {0}/{1} changed ({2} stopped attacking); control {3}/{4} changed ({5})" -f `
                $f.Transitions.Changed, $f.Transitions.StillAlive, $f.Transitions.WentIdle, $f.Control.Changed, $f.Control.StillAlive, $f.Control.WentIdle)
            Write-Host ("       observe: ability {0}/{1} changed ({2} stopped attacking); control {3}/{4} changed ({5})" -f `
                $o.Transitions.Changed, $o.Transitions.StillAlive, $o.Transitions.WentIdle, $o.Control.Changed, $o.Control.StillAlive, $o.Control.WentIdle)
            # NORMALISE BEFORE COMPARING THE ARMS. Raw churn is not comparable between
            # them and it is important to say why: the fan-out is the thing under test, so
            # in the plugin arm ALL the units got the move order and are fighting, while in
            # stock only the engine's twelve did and the rest stand still. Measured on the
            # first run of this shape: 0x03:5 0x06:9 0x0a:17 in the plugin arm against
            # 0x03:26 0x0a:6 in stock -- twenty-six idle units cannot have their orders
            # interrupted. Comparing raw counts there would "find" a difference that is
            # only the feature working.
            #
            # What IS comparable is each arm's own EXCESS over its own control window:
            # how much more disturbance the ability caused than not using it did.
            # Reported against BOTH controls, because the sign of this number depends on
            # which one is used and hiding that behind an aggregator is how a reader gets
            # a headline they cannot check.
            $fStrict = $f.Transitions.Changed - $f.ControlStrict.Changed
            $fLenient = $f.Transitions.Changed - $f.ControlLenient.Changed
            $oStrict = $o.Transitions.Changed - $o.ControlStrict.Changed
            $oLenient = $o.Transitions.Changed - $o.ControlLenient.Changed
            Write-Host ("       excess disturbance caused by the ability -- fanout: {0} (strict) / {1} (lenient); stock: {2} / {3}" -f `
                $fStrict, $fLenient, $oStrict, $oLenient)
            $fDelta = $fStrict
            $oDelta = $oStrict
            Assert-That 'the ability disturbs no more orders under the plugin than under stock, once each arm is compared with its own control' `
                ($fDelta -le $oDelta + 5) "(fanout $fDelta vs observe $oDelta)"
            Assert-That 'both arms were still fighting after the ability' `
                (($f.EnemyHpLater -lt $f.EnemyHpAfter) -and ($o.EnemyHpLater -lt $o.EnemyHpAfter))
            # The stock arm must really be stock -- and AN ABSENCE ASSERTION IS WORTH
            # NOTHING UNLESS THE SAME PATTERN IS SHOWN TO MATCH SOMETHING. The first
            # version looked for 'HOOK install', a string the plugin never writes (the
            # real ones are `HOOK %s: installed at %p` and `HOOK: %d/%d installed`), so it
            # passed on any log at all, including a fanout one. Each pattern is now proved
            # POSITIVE against the plugin arm before being required absent from stock.
            $obsLog = Get-Content -LiteralPath $o.LogPath
            $fanLog = Get-Content -LiteralPath $f.LogPath
            foreach ($probe in @(
                @{ What = 'a hook installation line'; Pattern = 'HOOK .*installed' },
                @{ What = 'an intercepted command';   Pattern = 'CMD id=' },
                @{ What = 'a fan-out';                Pattern = 'FANOUT start' }
            )) {
                $inFanout = @($fanLog | Select-String -Pattern $probe.Pattern).Count
                $inObserve = @($obsLog | Select-String -Pattern $probe.Pattern).Count
                Assert-That "the plugin arm DOES show $($probe.What) -- so its absence below means something" `
                    ($inFanout -gt 0) "(pattern '$($probe.Pattern)' matched nothing in the fanout log either)"
                Assert-That "the stock arm shows no $($probe.What)" ($inObserve -eq 0) `
                    "(found $inObserve line(s) matching '$($probe.Pattern)')"
            }
            Assert-That 'the stock arm ran in observe mode' `
                (@($obsLog | Select-String -Pattern 'mode=observe').Count -gt 0)
            Assert-That 'and it still produced the same oracle (WORLD lines)' `
                (@($obsLog | Select-String -Pattern 'WORLD \[').Count -gt 0)
        }
    }
}
catch { Write-ScStepFailure $_ 'a test step' }
finally {
    if (-not $KeepOpen) { Remove-ScOwnFixture -Run $fixtures }
    Remove-ScOwnFixtureDir -Dir $mapDir
}

Write-Host ''
Write-Host '[final] the run must balance'
foreach ($m in $arms.Keys) {
    # WM_CLOSE is asynchronous and the game unloads the plugin on its way out, so a check
    # taken the instant close-game returns can see a process that is already exiting. Give
    # it a bounded moment rather than reporting a stranded process that is not stranded.
    $left = $null
    for ($i = 0; $i -lt 20; $i++) {
        $left = Get-Process -Id $arms[$m].Pid -ErrorAction SilentlyContinue
        if ($null -eq $left) { break }
        Start-Sleep -Milliseconds 500
    }
    Assert-That "the '$m' game process is gone" ($KeepOpen -or $null -eq $left)
}
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))
$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-ability-in-combat: $failures failure(s)"
exit ($failures -eq 0 ? 0 : 1)
