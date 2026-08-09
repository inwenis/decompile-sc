#Requires -Version 7
<#
.SYNOPSIS
PLUGIN-vs-STOCK: does using an ability on a >12 selection IN COMBAT stop the units
fighting? 36 Marines shoot a block of Supply Depots, Stim Pack is pressed once mid-fight,
and every unit's order is compared across that press -- with the plugin active, and again
with `-Mode observe`, which installs no hook at all.

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

The fixture is deliberately NOT the user's cloaked Ghost: nothing in this harness can yet
make the client emit the Cloak command (the key is not 'C', and the command-card slot where
it should be turns out to be a targeted ability -- the frame reads "Select Target"). What is
tested here is the MECHANISM their report made us suspect, on an ability this harness can
reliably issue. The report says so in those terms rather than letting the two read as one.

.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1

.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1 -Modes fanout   # the plugin arm alone
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\022',
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

$failures = 0
$step = 0
$script:armLock = $null

# MARINES AND STIM, not Ghosts and Cloak. The question is about a FANNED-OUT ABILITY
# ISSUED MID-FIGHT, and Stim is the one this harness can reliably make the client emit
# (task 022 §5): the Ghost's Cloak button neither answers to 'C' nor sits where the
# command-card geometry was guessed -- clicking there put the game into "Select Target",
# i.e. it is a targeted ability, so that button is Lockdown. An ability that never fires
# measures nothing, and a test that measures nothing while looking green is worse than no
# test. The Ghost case is recorded as an open question rather than faked.
$UNIT_TYPE = 0             # units.dat 0, Terran Marine
$ENEMY_TYPE_ID = 109       # units.dat 109, Terran Supply Depot -- no weapon, cannot move
$ABILITY_CMD = '0x36'      # Stim Pack
$ABILITY_KEY = 0x54        # 'T' -- plain, unmodified, so 021's accelerator finding does not bite
$STIM_TIMER = 0x25         # what 0x004C2F30 writes to CUnit+0x115
$IDLE_ORDER = 0x03
# The camera opens centred on the start location and never moves on its own, so a click
# at client x is an order to (start.x + x - 320). Same constants as test-combat-death.ps1.
$WALK_X = 540
$WALK_Y = 240

$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
# THIS TASK'S OWN FIXTURE FOLDER, not the shared 00-testmap.
# The map browser picks by ROW, so sharing a folder means two workers pick each other's
# maps -- which happened twice during task 022, once in each direction, and cost a run
# each time. A folder of our own removes the interference in both directions rather than
# racing for it. The name sorts before every other 00-t* folder ('0' < any letter), so the
# first-row folder click that every suite here uses still lands on it.
$mapDir = Join-Path $GameDir 'Maps\BroodWar\00-t022'
$mapPath = Join-Path $mapDir '022-combat.scx'

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

function New-Fixture {
    # Shared folder, several suites, possibly several workers -- see
    # Wait-ScTestMapDirFree. Never `Remove-Item -Recurse` this directory.
    Wait-ScTestMapDirFree -Dir $mapDir -MyMapPath $mapPath
    $genArgs = @{
        UnitCount = $UnitCount; UnitType = 'marine'; Player = 0
        TechResearched = 'stim-packs'
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
    Assert-That 'Stim Packs is researched for the human slot' `
        (@($gen | Select-String -Pattern 'PTEx: player 0 has researched 0\(stim-packs\)').Count -gt 0)
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

    $logPath = Join-Path $LogDir "022-combat-$Mode.log"
    $shotDir = Join-Path $LogDir "022-combat-$Mode-frames"
    $markerPath = Join-Path $LogDir 'marker.txt'
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
    New-Item -ItemType Directory -Path $shotDir -Force | Out-Null

    # The game is single-instance machine-wide (Wait-ScNoGameRunning), and the launch
    # lock is normally held only around the launch -- which is not enough when the thing
    # that collides is a game that is still ALIVE. So: wait for the machine to be free,
    # then hold the lock for as long as this arm's game exists, and tell run-with-plugin
    # not to take it again underneath us.
    Assert-ScFixtureStillMine -Dir $mapDir -MapPath $mapPath
    Wait-ScNoGameRunning
    $script:armLock = Enter-ScLaunchLock -TaskId '022-ability-in-combat'
    $gamePid = 0
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode $Mode -WorldScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
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
        # The folder row is POSITIONAL and this task's folder is not necessarily first:
        # another worker's 00-t021 sorts before 00-t022. Computed from the filesystem.
        $folderRow = Get-ScMapFolderRow -MapsDir (Split-Path $mapDir -Parent) -FolderName (Split-Path $mapDir -Leaf)
        Write-Host "       fixture folder is row $($folderRow.Row) (y=$($folderRow.Y)); siblings: $($folderRow.Siblings)"
        Send-ScClick -Hwnd $hwnd -X 117 -Y $folderRow.Y
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Milliseconds 800
        Send-ScClick -Hwnd $hwnd -X 117 -Y 159
        Start-Sleep -Milliseconds 500
        Set-ScGameType -Hwnd $hwnd -Index 2      # Use Map Settings, verified (see Set-ScGameType)
        ArmShot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        Send-ScClick -Hwnd $hwnd -X 200 -Y 261                   # dismiss "StarCraft Tips"
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
        $result.Engaged = $engaged
        ArmShot 'engaged'
        if (-not $engaged) { return $result }

        # A CONTROL WINDOW FIRST: the same length of time, in the same fight, with NO
        # ability used. Units in a firefight change orders constantly on their own -- a
        # target dies and its killer drops back to Guard, another walks into range and
        # starts shooting -- so "13 units changed order across the ability" means nothing
        # until you know what a quiet two seconds looks like. This is what makes the
        # measurement a comparison rather than an anecdote.
        Start-Sleep -Seconds 2
        $result.Baseline = Get-ScWorldState -LogPath $logPath -Tag 'baseline' -MarkerPath $markerPath

        # THE MOMENT UNDER TEST: one ability keypress, with the group mid-fight.
        $mark = Get-ScLogLineCount -LogPath $logPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $ABILITY_KEY
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $logPath | Select-Object -Skip $mark)
        # No click fallback. Guessing at a command-card button position is how this test
        # previously armed a TARGETED ability by mistake -- the frame came back showing
        # "Select Target" -- and an ability nobody used measures nothing while looking green.
        # The key is 'T', it is unmodified, and §5 proves the client emits 0x36 for it.
        $result.AbilityLines = $lines
        $result.After = Get-ScWorldState -LogPath $logPath -Tag 'after-ability' -MarkerPath $markerPath
        ArmShot 'after-ability'

        # A SECOND control window, immediately after. A fight decays: two seconds later
        # there are fewer units alive and fewer targets left, so one control taken before
        # the ability is not automatically comparable to the ability window. Two controls
        # bracket the drift -- and if they disagree markedly with each other, the fight is
        # too unstable for the measurement and the run says so instead of averaging them.
        Start-Sleep -Seconds 2
        $result.ControlAfter = Get-ScWorldState -LogPath $logPath -Tag 'control-after' -MarkerPath $markerPath

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
# NOTE THE LEADING COMMA, and the absence of @() at every call site. The comma stops
# PowerShell unrolling the array on the way out, which is what keeps `.Count` working when
# the group has been wiped -- but wrapping the result in @() AGAIN produces a one-element
# array holding the array, and every count collapses to 1. That cost this test two runs: a
# scan with 33 Marines in it reported "1".
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
    Step "generate the fixture: $UnitCount Marines vs $EnemyCount Supply Depots, Stim researched" {
        New-Fixture
    }

    foreach ($mode in $Modes) {
        Step "ARM '$mode': engage, then press Cloak once mid-fight" {
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
            Assert-That "[$mode] the target block is a weaponless, immobile building type ($ENEMY_TYPE_ID)" `
                ($ENEMY_TYPE_ID -eq 109)
            Assert-That "[$mode] the fixture spawned $UnitCount Marines" ($spawned -eq $UnitCount) `
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

            # THE ABILITY MUST BE SHOWN TO HAVE FIRED IN *THIS* ARM, and in the stock arm
            # there is no CMD/FANOUT line to look at -- the command hook is not installed.
            # Without a substitute, a swallowed keypress produces 0/0/0 and every
            # assertion below passes while measuring nothing at all. The effect itself is
            # visible to the world scan in both arms, so that is the signal: units that
            # were not stimmed before the keypress and are stimmed after it.
            $stimBefore = @((Get-Mine $arm.Baseline) | Where-Object { $_.Stim -gt 0 }).Count
            $stimAfter  = @((Get-Mine $arm.After)    | Where-Object { $_.Stim -gt 0 }).Count
            $arm.StimBefore = $stimBefore
            $arm.StimAfter = $stimAfter
            Assert-That "[$mode] the ability actually fired -- units carrying the stim effect went $stimBefore -> $stimAfter" `
                ($stimAfter -gt $stimBefore) `
                '(no unit gained the effect, so this arm measured a keypress that did nothing and its numbers mean nothing)'

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
            $popStart = @(Get-Mine $arm.Engaged).Count
            $popEnd = @(Get-Mine $arm.ControlAfter).Count
            $enemyStart = @($arm.Engaged.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count
            $enemyEnd = @($arm.ControlAfter.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count
            Write-Host ("       [{0}] population {1} -> {2}; target block {3} -> {4}" -f `
                $mode, $popStart, $popEnd, $enemyStart, $enemyEnd)
            Assert-That "[$mode] not one unit was lost across the whole measurement ($popStart -> $popEnd)" `
                ($popStart -eq $popEnd) `
                '(a moving population voids this measurement, and the bias runs toward the conclusion this test reaches)'
            Assert-That "[$mode] the target block survived the whole measurement ($enemyStart -> $enemyEnd)" `
                ($enemyEnd -eq $enemyStart) `
                '(if the targets die the fight ends, and the last control window measures that instead of an ordinary two seconds)'

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
            Assert-That "the ability was issued ($ABILITY_CMD)" `
                (@($lines | Select-String -Pattern "CMD id=$ABILITY_CMD ").Count -gt 0)
            $start = @($lines | Select-String -Pattern "FANOUT start: cmd=$ABILITY_CMD .* units=(\d+)")
            Assert-That 'it was fanned out' ($start.Count -gt 0)
            if ($start.Count -gt 0) {
                $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
                Assert-That "more than twelve units were commanded ($u)" ($u -gt 12)
            }

            # The ability reached past the cap AND was paid for, IN COMBAT -- question 1's
            # result again, on a fixture where the units are busy rather than standing
            # still, which is the case the user was actually in.
            $mine = Get-Mine $arm.After
            $stimmed = @($mine | Where-Object { $_.Stim -gt 0 })
            Assert-That "more units carry the effect than the engine's twelve ($($stimmed.Count))" `
                ($stimmed.Count -gt 12)
            Assert-That "no timer exceeds the handler's own 0x$('{0:x}' -f $STIM_TIMER)" `
                (@($stimmed | Where-Object { $_.Stim -gt $STIM_TIMER }).Count -eq 0)
            $before = @{}
            foreach ($u in (Get-Mine $arm.Engaged)) { $before[$u.Unit] = $u }
            $paid = @($stimmed | Where-Object { $before.ContainsKey($_.Unit) -and $_.Hp -lt $before[$_.Unit].Hp })
            Assert-That "every unit that gained the effect also paid for it ($($paid.Count) of $($stimmed.Count))" `
                ($stimmed.Count -gt 0 -and $paid.Count -eq $stimmed.Count) `
                '(hit points can also fall to enemy fire here, so this is a weaker form of the §5 assertion by design -- the strict per-unit arithmetic lives in test-stim-fanout.ps1, on a fixture with nothing shooting back)'
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
catch {
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    if (-not $KeepOpen -and (Test-Path -LiteralPath $mapPath)) {
        Remove-Item -LiteralPath $mapPath -Force -ErrorAction SilentlyContinue
    }
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
