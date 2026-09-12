#Requires -Version 7
<#
.SYNOPSIS
PLUGIN-vs-STOCK: does using an ability on a >12 selection IN COMBAT stop the units
fighting? A block of weaponless buildings is attacked by 36 units, ONE ability is used
once mid-fight, and every unit's main order is compared across that moment -- with the
plugin active, and again with `-Mode observe`, which installs no hook at all.
.DESCRIPTION
-Ability stim: 36 Marines, Stim Pack, pressed with 'T'. -Ability cloak: 36 Ghosts,
Personnel Cloaking, clicked on the live card's Cloak slot -- the sharp test, because its
handler never writes the main order (see $ABILITIES). Stim is the second data point: a
different client path that is also not supposed to touch the main order. Both arms carry
the same read-only world scan; the metric is per unit, matched by CUnit pointer across
scans. Background: research/ability-semantics.md §7, research/command-card.md.
.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1
.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1 -Ability cloak
.EXAMPLE
./tools/plugin/test-ability-in-combat.ps1 -Modes fanout   # the plugin arm alone
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    # Which ability is used mid-fight; $ABILITIES below holds everything that differs per arm.
    [ValidateSet('stim', 'cloak')][string]$Ability = 'stim',
    # Defaulted after the param block so it can follow -Ability; a caller can still pin it.
    [string]$LogDir,
    # Folder under Maps\ the fixture is generated into; defaulted below via Resolve-ScFixtureDir.
    [string]$FixtureDir,
    [int]$UnitCount = 36,
    # No low-energy tail by default: the command card refuses an ability when the units it
    # can see cannot pay for it (research/command-card.md §4.3), so a tail can grey the
    # button and leave the run measuring nothing. Pass -DamagedCount to test that gate.
    [int]$DamagedCount = 0,
    [int]$DamagedEnergy = 5,
    # THE ENEMY CANNOT SHOOT BACK BY ANY CHOICE OF ITS OWN, AND THERE IS A LOT OF IT. The
    # three two-second windows need a STEADY fight. Do not use Hydralisks: with sixteen the
    # group lost units fast enough that the controls disagreed by exactly the spread limit;
    # with ten the Marines wiped them mid-measurement and the second control saw 23 units
    # idle at once -- the fight ending. Do not use Lurkers: unburrowed they have no weapon,
    # but a computer-owned one burrows on its own and went 36 -> 2 Marines with splash. The
    # premise is "cannot attack", not "is not currently attacking". Twelve Supply Depots is
    # 6000 hp, which 36 Marines chew through slowly enough to outlast all three windows.
    [int]$EnemyCount = 12,
    [string]$EnemyType = '109',       # units.dat 109, Terran Supply Depot
    [string]$EnemyRace = 'terran',
    [ValidateSet('fanout', 'observe')][string[]]$Modes = @('fanout', 'observe'),
    [int]$EngageTimeoutSec = 60,
    # Settle time after engagement, for arms whose descriptor asks for it. Bounded: an
    # unsettled fight is measured anyway and left to the control-spread assertion.
    [int]$SettleTimeoutSec = 45,
    # Re-takes allowed while looking for a three-window set in which no target died.
    [int]$MeasureTries = 4,
    # Control windows disagreeing by this much or more make the fight too unstable to measure.
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

# Overwritten from -EnemyType once the descriptor default is applied below.
$ENEMY_TYPE_ID = 109
# units.dat ids accepted as a target block: no weapon, and no way to DECIDE to act (a
# computer-owned Command Centre with no orders never lifts off). See -EnemyCount.
$ENEMY_TYPES_OK = @{ 109 = 'Terran Supply Depot (500 hp)'; 106 = 'Terran Command Centre (1500 hp)' }
$IDLE_ORDER = 0x03
$CLOAK_ORDER2 = 0x6D       # research/ability-semantics.md §3
# The Ghost Cloak BUTTON's action function, which is what names a card slot as Cloak in
# the memory read. Byte-exact (research/command-card.md §4): 0x00423730 is
# `if (sendGate()) { buf = {0x21, shiftFlag}; queueCommand(buf, 2); }`
$CLOAK_ACTION = '00423730'
# The same slot's other face; it sends 0x22. Slot 7 is a TOGGLE, so which face the card
# shows depends on whether the portrait unit is currently cloaked, and a re-take clicks
# Decloak. Same button, same fan-out, same measurement (research/command-card.md §3.1).
$DECLOAK_ACTION = '00423270'
$CLOAK_PAIR = @($CLOAK_ACTION, $DECLOAK_ACTION)

# THE ABILITY DESCRIPTOR: everything that differs between the two arms lives here, so the
# measurement below reads the same for both. Effect is the per-unit oracle the read-only
# world scan evaluates in BOTH arms (the observe arm has no CMD/FANOUT line to look at):
#   stim  -- CUnit+0x115, the timer 0x004C2F30 writes;
#   cloak -- CUnit+0xA6, the SECONDARY order 0x00491B30 sets to 0x6D. 0x004C0720 loops the
#            selection calling it; it deducts CUnit+0xA2 and never writes the main order
#            CUnit+0x4D -- which is what makes Cloak the sharp test of "replayed Selects
#            interrupt running orders": any main-order change across it is ours.
$ABILITIES = @{
    stim = @{
        Name = 'Stim Pack'; UnitName = 'marine'; UnitType = 0; UnitLabel = 'Marines'
        Tech = 'stim-packs'; TechPattern = 'PTEx: player 0 has researched 0\(stim-packs\)'
        Cmd = '0x36'; Cmds = @('0x36')
        # 'T', plain: a MODIFIED key resolves through TranslateAcceleratorA, which a posted
        # message can never satisfy (research/control-groups.md §5).
        Key = 0x54
        EffectName = 'the stim effect'
        Effect = { param($U) $U.Stim -gt 0 }
        # What 0x004C2F30 writes to CUnit+0x115; nothing may exceed it.
        Bound = { param($U) $U.Stim -le 0x25 }
        BoundName = "no timer exceeds the handler's own 0x25"
        Paid = { param($Now, $Before) $Now.Hp -lt $Before.Hp }
        PaidName = 'hit points'
        NeedCard = $false
        EnemyCount = 12
        # Supply Depot, 500 hp: this arm's published numbers were measured against this block.
        EnemyType = '109'
        # Off: the published numbers (research/ability-semantics.md §7.4) were measured without it.
        Settle = $false
        # Not a toggle: a timed buff (~12 s) that outlives a take, so a retake must first wait
        # for it to lapse (Wait-EffectLapsed).
        Toggle = $false
    }
    cloak = @{
        Name = 'Personnel Cloaking'; UnitName = 'ghost'; UnitType = 1; UnitLabel = 'Ghosts'
        Tech = 'personnel-cloaking'
        TechPattern = 'PTEx: player 0 has researched 10\(personnel-cloaking\)'
        Cmd = '0x21'; Cmds = @('0x21', '0x22')   # Cloak / Decloak -- the two faces of slot 7
        # No key: hotkey and mouse paths test the same disabled bit (research/command-card.md
        # §5), but only the CLICK can be aimed at the button's own rect read from the live
        # dialog, which rules out "the input missed".
        Key = $null
        EffectName = "the cloak secondary order 0x$('{0:x2}' -f $CLOAK_ORDER2)"
        Effect = { param($U) $U.Order2 -eq $CLOAK_ORDER2 }
        # Cloak has no timer to bound; the secondary order is the state itself.
        Bound = $null
        BoundName = ''
        # Energy keeps draining while cloak is up, so "lower than before" is the safe direction.
        Paid = { param($Now, $Before) $Now.Energy -lt $Before.Energy }
        PaidName = 'energy'
        NeedCard = $true
        # More targets than the stim arm: a Ghost out-damages a Marine (10 per shot on a
        # 22-frame cooldown against 6 on 15) and out-ranges it by three, so more of the
        # group is in range at once and the block must still outlast three windows
        # (research/ability-semantics.md §8.4b).
        EnemyCount = 16
        # Command Centre (1500 hp), not Supply Depot (500): the interval between target
        # deaths triples, so none dies inside a two-second window in practice. Measured on
        # the depot block: the plugin arm lost a target every ~13 s (16 -> 13 in one run)
        # and one death landed INSIDE the ability window, idling 33 of 36 Ghosts at once --
        # the hypothesis's exact signature, manufactured by the fixture. The no-target-died
        # gate catches that; this keeps clean takes the normal case. Still weaponless and
        # immobile: a computer-owned Command Centre with no orders cannot lift off.
        EnemyType = '106'
        # Measured, not guessed: without settling, the leading control saw 6 order changes
        # and the trailing one 0 -- exactly the spread limit -- and the run was refused. The
        # cause is ARRIVAL, not decay: Ghosts out-range Marines by three tiles, so the group
        # trickles into range and each arrival is a 0x06 Move -> 0x0a AttackUnit transition.
        # Do not widen the tolerance instead; that only hides it.
        Settle = $true
        # A toggle: a retake clicks Decloak (0x22, same button, same fan-out), a LARGE
        # effect delta in the other direction (36 -> 0). Nothing to wait for; the
        # assertions read the magnitude of the change, not its sign.
        Toggle = $true
    }
}
$ABIL = $ABILITIES[$Ability]
$UNIT_TYPE = $ABIL.UnitType
$ABILITY_CMD = $ABIL.Cmd
$ABILITY_KEY = $ABIL.Key
# The descriptor supplies the default only when the caller did not: an explicit
# -EnemyCount 12 stays 12 even on the arm whose descriptor says 16.
if (-not $PSBoundParameters.ContainsKey('EnemyCount')) { $EnemyCount = $ABIL.EnemyCount }
if (-not $PSBoundParameters.ContainsKey('EnemyType'))  { $EnemyType  = $ABIL.EnemyType }
$ENEMY_TYPE_ID = [int]$EnemyType
if (-not $LogDir) { $LogDir = $(if ($Ability -eq 'stim') { 'C:\sc-work\logs\022' } else { 'C:\sc-work\logs\026' }) }
# The camera opens centred on the start location and never moves on its own, so a click
# at client x is an order to (start.x + x - 320). Same constants as test-combat-death.ps1.
$WALK_X = 540
$WALK_Y = 240

$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
# A fixture folder of its own, never the shared 00-testmap: two workers sharing a folder
# pick each other's maps (AGENTS.md § Shared test-fixture folder). With $env:AGENT_TASK
# set this resolves to THIS agent's folder, so two concurrent runs of this same suite
# cannot overwrite each other's identically-named fixture. Select-ScBrowserMap computes
# every browser click from the filesystem; no row is assumed from the name.
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t022' -Suite 'ability-in-combat' }
$mapDir = $FixtureDir
# The two abilities need different units, so they are two fixtures of the same suite --
# one NAME each (AGENTS.md § Test fixtures: one folder per task, one NAME per suite).
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
    # Necessary, not sufficient: a read-back that shares the writer's index order confirms
    # a byte the engine never reads. The ENGINE's own opinion is asserted in the arm.
    Assert-That "$($ABIL.Name) is researched for the human slot" `
        (@($gen | Select-String -Pattern $ABIL.TechPattern).Count -gt 0)
    if ($DamagedCount -gt 0) {
        Assert-That "the low-energy tail is in the map file ($DamagedCount at $DamagedEnergy%)" `
            (@($gen | Select-String -Pattern "tail starts at $DamagedEnergy% energy").Count -gt 0)
    }
}

# One arm: launch in $Mode, walk into the enemy, use the ability once, and take the scans
# the comparison needs. Returns the metrics; per-arm assertions are made by the caller.
function Invoke-Arm {
    param([Parameter(Mandatory)][string]$Mode)

    $logPath = Join-Path $LogDir "$Ability-combat-$Mode.log"
    $shotDir = Join-Path $LogDir "$Ability-combat-$Mode-frames"
    $markerPath = Join-Path $LogDir 'marker.txt'
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
    New-Item -ItemType Directory -Path $shotDir -Force | Out-Null

    # The game is single-instance machine-wide, and holding the launch lock only around the
    # launch is not enough when what collides is a game that is still ALIVE. So: wait for
    # the machine to be free, hold the lock as long as this arm's game exists, and tell
    # run-with-plugin not to take it again underneath us.
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $script:armLock = Enter-ScLaunchLock -TaskId '022-ability-in-combat'
    $gamePid = 0
    # -CardScan only where the arm needs it: read-only and hookless in both modes, but it
    # writes a block of CARD lines per marker that an arm never asking for a card need not carry.
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
        Enter-ScCustomGame -Hwnd $hwnd -LogPath $logPath -Fixtures $fixtures -MapPath $mapPath -GameDir $GameDir -BeforeStart { ArmShot 'lobby' } -Noun 'test'

        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $result.Boxed = Get-ScWorldState -LogPath $logPath -Tag 'boxed' -MarkerPath $markerPath
        ArmShot 'boxed'

        # Into the enemy. One right-click; in `observe` only the engine's twelve obey,
        # which is the stock behaviour and exactly what the control is for.
        $mark = Get-ScLogLineCount -LogPath $logPath
        Send-ScClick -Hwnd $hwnd -X $WALK_X -Y $WALK_Y -Right
        $result.WalkMark = $mark

        # "Shots are landing" has one signal: enemy hit points below their starting total,
        # read from the enemy's own units.
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

        # "Engaged" only means the first shots landed; part of the group can still be walking
        # into range (see the descriptor's Settle). Wait until the main-order histogram stops
        # changing, bounded, and let the LAST scan become `engaged` so the first control
        # window starts from a settled fight.
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

        # THE MEASUREMENT: three same-length windows in one fight -- control, ability, control.
        # Units in a firefight change orders on their own, so "33 changed across the ability"
        # means nothing without knowing what an ordinary two seconds looks like.
        #
        # CONFOUND 1: when a TARGET DIES every unit shooting it drops 0x0a -> 0x03 in the same
        # instant, bit-for-bit the signature the hypothesis predicts. Measured: 33 of 36 Ghosts
        # went 0x0a -> 0x03 across the ability window while the enemy count in the same pair
        # of scans went 14 -> 13. It bites the plugin arm ~3x more BECAUSE THE FEATURE WORKS
        # (36 shooting, not the engine's twelve), so it is never averaged: re-take until no
        # target dies in any window, and fail a run that never gets a clean set.
        #
        # CONFOUND 2, made by the retake: a retake must re-use the ability, but a TIMED buff
        # outlives a take (0x004C2F30 writes 0x25 to CUnit+0x115, counted down over ~12 s,
        # longer than a take plus resettle). From take 2 every Marine already carried it, the
        # did-it-fire oracle read a delta of ZERO, and the suite failed on every sweep -- the
        # retake is the common case, since 36 Marines vs 500 hp depots kill a target inside a
        # window most runs. So a retake waits for nobody to carry the effect. A TOGGLE needs
        # none of this: its second use is a large delta the other way.
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
            # LOUD, not a zero delta later: this class of mistake names itself instead of
            # arriving as an unexplained red suite.
            throw ("test: $($ABIL.EffectName) is still on $carrying unit(s) after ${TimeoutSec}s, so the " +
                   'next take would re-apply it to units that already carry it and the ' +
                   'did-it-fire check would read a delta of zero. Refusing to measure that ' +
                   '(issue #39). The units are being re-stimmed by something, or the timeout is too short.')
        }

        $clean = $false
        for ($take = 1; $take -le $MeasureTries; $take++) {
            # Every take starts from "nobody carries the effect", take 1 included -- so this
            # also asserts the fixture handed us a clean start, and it is proved positive on
            # any retake (non-zero before the wait, zero after).
            if (-not $ABIL.Toggle) { $result.Engaged = Wait-EffectLapsed -Reference $result.Engaged }
            $ref = $result.Engaged
            $refEnemies = Get-EnemyCount $ref

            Start-Sleep -Seconds 2
            $baseline = Get-ScWorldState -LogPath $logPath -Tag "baseline" -MarkerPath $markerPath

            # THE CARD, READ OUT OF MEMORY, for the arm that clicks one. Taken BEFORE the
            # ability so the slot the click aims at is the slot this take measured, and a
            # greyed button fails here as a fixture failure rather than as a mysterious zero
            # later. The tech arrays in the same read are THE ENGINE's opinion of the fixture.
            # Re-read every take: slot 7 is a TOGGLE and shows whichever face matches the
            # portrait unit (AGENTS.md § A CARD SLOT CHANGES MEANING UNDER YOU).
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
                # No click fallback: a guessed card-button position can arm a TARGETED ability
                # instead (the frame then shows "Select Target"), and an ability nobody used
                # measures nothing while looking green. Plain 'T' is proven to make the client
                # emit 0x36 (research/ability-semantics.md §5).
                Send-ScKey -Hwnd $hwnd -VirtualKey $ABILITY_KEY
            }
            else {
                # No guessed coordinate either: the point is the live control's own rect plus
                # its dialog's origin, the sum the engine forms at 0x00458850. A silent result
                # then means "the button refused", not "the click landed between buttons".
                $p = Get-ScCardSlotPoint -Card $result.Card -Slot $cloakSlot.Index
                Write-Host ("       [{0}] take {1}: clicking card slot {2} at its own computed centre ({3},{4})" -f `
                    $Mode, $take, $cloakSlot.Index, $p.X, $p.Y)
                Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y
            }
            Start-Sleep -Seconds 2
            $lines = @(Get-Content -LiteralPath $logPath | Select-Object -Skip $mark)
            $after = Get-ScWorldState -LogPath $logPath -Tag "after-ability" -MarkerPath $markerPath

            # A second control, immediately after: a fight decays, so one control taken before
            # the ability is not automatically comparable. Two controls bracket the drift, and
            # if they disagree markedly the run says so instead of averaging them.
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
# NOTE THE LEADING COMMA, AND NEVER WRITE @(Get-Mine ...) -- IT SILENTLY RETURNS 1.
# PowerShell unrolls a function's array return, so a wiped group would come back as $null
# and `.Count` would throw under StrictMode; the comma keeps the array an array. Wrapping
# the result in @() AGAIN builds a one-element array holding the array, so every count
# collapses to exactly 1 -- a plausible number, never an error. This has bitten this file
# twice ("1" for a scan holding 33 Marines; a population of "1" out of 36). Grep this file
# for `@(Get-Mine` before running a new count.
function Get-Mine { param($Scan) ,@($Scan.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $UNIT_TYPE }) }
function Get-EnemyHp {
    # Sum by hand: Measure-Object emits NOTHING for an empty pipeline, and under StrictMode
    # reading .Sum off that throws instead of yielding zero -- exactly what a run where the
    # fixture did not spawn (a melee start has no enemies) would hit, hiding the real cause.
    param($Scan)
    $total = 0
    foreach ($u in $Scan.Units) { if ($u.Type -eq $ENEMY_TYPE_ID) { $total += $u.Hp } }
    return $total
}
# The COUNT of live targets, not hit points: a target DESTROYED idles every unit shooting
# it at once; hit points falling steadily is the fight working normally.
function Get-EnemyCount {
    param($Scan)
    $n = 0
    foreach ($u in $Scan.Units) { if ($u.Type -eq $ENEMY_TYPE_ID) { $n++ } }
    return $n
}

# For every unit alive in BOTH scans, matched by CUnit pointer, did its MAIN ORDER change?
# Do not make "went idle" the predicate: a unit that auto-acquires from Guard keeps main
# order 0x03 while it shoots, so "busy" and "idle" are indistinguishable there and the
# sample collapses to one. An order CHANGE is what "replayed Selects interrupt orders"
# would actually produce, needs no assumption about which order id means fighting, and is
# comparable between the arms.
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
            # A MELEE START is the failure this names on sight: the map loads, the game looks
            # normal, and the units are a standard base -- every later number is then
            # internally consistent nonsense (research/ability-semantics.md §8.1).
            $melee = @($arm.Boxed.Units | Where-Object { $_.Player -eq 0 -and $_.Type -in 7, 0x40, 0x29, 0x23, 0x2A })
            # The premise the whole fixture rests on, checked where it is used: this enemy has
            # no weapon and cannot move, so it cannot DECIDE to start shooting (see -EnemyCount).
            Assert-That ("[{0}] the target block is a weaponless, immobile building type ({1} = {2})" -f `
                         $mode, $ENEMY_TYPE_ID, ($ENEMY_TYPES_OK[$ENEMY_TYPE_ID] ?? 'NOT ON THE VERIFIED LIST')) `
                ($ENEMY_TYPES_OK.ContainsKey($ENEMY_TYPE_ID))
            Assert-That "[$mode] the fixture spawned $UnitCount $($ABIL.UnitLabel)" ($spawned -eq $UnitCount) `
                ($melee.Count -gt 0 ? "(got $spawned, and player 0 owns SCV/Drone/Larva/Overlord-shaped units -- THIS IS A MELEE START, the game type in effect was not Use Map Settings)" : "(got $spawned)")
            Assert-That "[$mode] and $EnemyCount enemy buildings" `
                (@($arm.Boxed.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count -eq $EnemyCount)
            # EVERY scan the measurement uses: a torn scan drops a unit, and a dropped unit
            # cannot be seen to change its order, so the bias is DOWNWARD -- toward the
            # conclusion this test reaches.
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

            # THE FIXTURE, AS THE ENGINE SEES IT. A generator verifying its own PTEx write with
            # the index order it wrote with reports a researched tech on a map where the engine
            # reads a different byte (research/command-card.md §6.3). The card read-back carries
            # the engine's per-player tech arrays, so this is the independent check.
            if ($ABIL.NeedCard) {
                Assert-That "[$mode] the ENGINE agrees $($ABIL.Name) is researched for this player" `
                    (@($arm.TechResearched) -contains 10) `
                    "(engine says [$(@($arm.TechResearched) -join ' ')])"
                Assert-That "[$mode] and the Cloak card slot was ENABLED when it was clicked (slot $($arm.CloakSlot.Index), $($arm.CloakSlot.State))" `
                    (-not $arm.CloakSlot.Disabled)
            }

            # THE ABILITY MUST BE SHOWN TO HAVE FIRED IN *THIS* ARM. The stock arm has no
            # CMD/FANOUT line (no command hook), so without a substitute a swallowed input
            # produces 0/0/0 and every assertion below passes while measuring nothing. The
            # effect is visible to the world scan in both arms, so that is the signal.
            $effBefore = @((Get-Mine $arm.Baseline) | Where-Object { & $ABIL.Effect $_ }).Count
            $effAfter  = @((Get-Mine $arm.After)    | Where-Object { & $ABIL.Effect $_ }).Count
            $arm.EffectBefore = $effBefore
            $arm.EffectAfter = $effAfter
            $arm.EffectDelta = [math]::Abs($effAfter - $effBefore)
            # A CHANGE, not an increase: Cloak is a toggle, and a re-taken measurement may have
            # switched it OFF -- the same fanned-out command mid-fight, the same test. Stim
            # only ever goes up and is satisfied either way.
            Assert-That "[$mode] the ability actually fired -- units carrying $($ABIL.EffectName) went $effBefore -> $effAfter" `
                ($effAfter -ne $effBefore) `
                '(no unit changed effect state, so this arm measured an input that did nothing and its numbers mean nothing)'

            # Never averaged, never tolerated: no clean take, no result (see THE MEASUREMENT
            # block in Invoke-Arm for the measured confound).
            Assert-That ("[{0}] the measurement landed in a window where no target died (take {1} of {2}; targets {3})" -f `
                         $mode, $arm.Takes, $MeasureTries, ($arm.EnemyRun -join ' -> ')) `
                ($arm.CleanTake) `
                '(a target died inside one of the three windows; every unit shooting it drops to 0x03 at once, which is exactly the signature this test looks for. Re-run rather than believing these numbers)'

            # Raw scan sizes first: a metric over the wrong scan is the recurring failure mode.
            Write-Host ("       [{0}] scans: boxed={1} engaged={2} after={3} later={4} units parsed" -f `
                $mode, @($arm.Boxed.Units).Count, @($arm.Engaged.Units).Count,
                @($arm.After.Units).Count, @($arm.Later.Units).Count)
            # Churn with no ability (engaged -> baseline) vs churn across it (baseline -> after).
            $ctrlBefore = Get-Transitions $arm.Engaged $arm.Baseline
            # THE FIXTURE'S OWN PRECONDITIONS, asserted before any number is derived. A
            # population that moves at all voids the measurement (a unit that leaves cannot
            # be seen to change its order, so the bias runs toward "nothing changed"), and a
            # target block that dies mid-measurement ends the fight.
            # No @() around Get-Mine -- see the note above Get-Mine.
            $popStart = (Get-Mine $arm.Engaged).Count
            $popEnd = (Get-Mine $arm.ControlAfter).Count
            $enemyStart = @($arm.Engaged.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count
            $enemyEnd = @($arm.ControlAfter.Units | Where-Object { $_.Type -eq $ENEMY_TYPE_ID }).Count
            Write-Host ("       [{0}] population {1} -> {2}; target block {3} -> {4}" -f `
                $mode, $popStart, $popEnd, $enemyStart, $enemyEnd)
            Assert-That "[$mode] not one unit was lost across the whole measurement ($popStart -> $popEnd)" `
                ($popStart -eq $popEnd) `
                '(a moving population voids this measurement, and the bias runs toward the conclusion this test reaches)'
            # The property that matters is that THE FIGHT DOES NOT END during the windows, not
            # that no target is ever destroyed: losing one of twelve changes nothing about
            # whether the group is still shooting, while a WIPED block idles every unit at
            # once and the last control window measures the end of the fight. So: most of the
            # block still standing, and damage still being dealt at the end (asserted below).
            Assert-That "[$mode] the target block outlasted the measurement ($enemyStart -> $enemyEnd of $EnemyCount)" `
                ($enemyEnd -ge [math]::Ceiling($enemyStart / 2) -and $enemyEnd -gt 0) `
                '(a wiped block ends the fight, and the last control window then measures that instead of an ordinary two seconds)'

            $t = Get-Transitions $arm.Baseline $arm.After
            $ctrlAfter = Get-Transitions $arm.After $arm.ControlAfter
            # NO AGGREGATOR. Picking one control decides the answer: measured, max() gave
            # threshold 13 against an observed 8 (pass by five) and min() gave 7 against 8
            # (fail by one). The LARGER control is not "conservative", it is lenient -- it
            # raises the bar an excess has to clear. Both are asserted and reported; the
            # strict one decides.
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
            # STRICTLY less than the bound: a run that sat exactly ON it (|10-4| = 6) is
            # precisely the instability the script names, and a boundary is not a margin.
            $spread = [math]::Abs($ctrlBefore.Changed - $ctrlAfter.Changed)
            Assert-That ("[{0}] the two control windows agree well enough to be a yardstick (spread {1}, must be < {2})" -f `
                         $mode, $spread, $ControlSpreadLimit) `
                ($spread -lt $ControlSpreadLimit) `
                '(the fight is decaying too fast for a two-second window to mean anything -- re-run on a steadier fixture rather than believing this)'
            Write-Host ("       [{0}] ABILITY window          : {1} of {2} alive, {3} changed order, {4} stopped attacking {5}" -f `
                $mode, $t.StillAlive, $t.Before, $t.Changed, $t.WentIdle, $t.Detail)
            Write-Host ("       [{0}] enemy hit points: {1} at engage -> {2} after -> {3} twelve seconds later" -f `
                $mode, $arm.EnemyHpEngaged, $arm.EnemyHpAfter, $arm.EnemyHpLater)

            # THE ASSERTION THE USER'S REPORT ASKS FOR (research/ability-semantics.md §7).
            # "Replayed Selects interrupt running orders" predicts a step change -- a Select
            # lands on every unit at once, so the ability window should knock units off their
            # orders WHOLESALE compared with an ordinary two seconds. The allowance is
            # generous: the prediction is dozens of units, not one or two more than usual.
            $allowance = 3
            # Against BOTH controls: the strict one can fail; the lenient one is reported so the
            # reader sees the spread rather than trusting an aggregator.
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
            # Either face of the toggle: a re-taken measurement can land on the ability being
            # switched off (0x22 rather than 0x21) -- same button, same fan-out, same question.
            $cmdPat = ($ABIL.Cmds | ForEach-Object { [regex]::Escape($_) }) -join '|'
            $issued = @($lines | Select-String -Pattern "CMD id=($cmdPat) ")
            Assert-That "the ability was issued ($($ABIL.Cmds -join ' or '))" ($issued.Count -gt 0)
            $start = @($lines | Select-String -Pattern "FANOUT start: cmd=($cmdPat) .* units=(\d+)")
            Assert-That 'it was fanned out' ($start.Count -gt 0)
            if ($start.Count -gt 0) {
                $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
                Assert-That "more than twelve units were commanded ($u)" ($u -gt 12)
            }

            # Reached past the cap AND paid for, IN COMBAT (research/ability-semantics.md §5
            # again, on a fixture where the units are busy -- the case the user was in).
            $mine = Get-Mine $arm.After
            $affected = @($mine | Where-Object { & $ABIL.Effect $_ })
            # The MAGNITUDE of the change: a take that toggled the ability off counts the same
            # as one that toggled it on -- either way more than the engine's twelve obeyed.
            Assert-That ("the command reached more than the engine's twelve (effect count {0} -> {1}, delta {2})" -f `
                         $arm.EffectBefore, $arm.EffectAfter, $arm.EffectDelta) `
                ($arm.EffectDelta -gt 12)
            if ($ABIL.Bound) {
                Assert-That $ABIL.BoundName `
                    (@($affected | Where-Object { -not (& $ABIL.Bound $_) }).Count -eq 0)
            }
            # The cost only on a take that switched the ability ON: a toggle-off take leaves
            # nobody carrying the effect, and asserting over an empty set cannot fail.
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
            # NORMALISE BEFORE COMPARING THE ARMS. Raw churn is not comparable: the fan-out is
            # the thing under test, so in the plugin arm ALL units got the move order and are
            # fighting while in stock only the engine's twelve did. Measured: 0x03:5 0x06:9
            # 0x0a:17 in the plugin arm against 0x03:26 0x0a:6 in stock -- twenty-six idle
            # units cannot have their orders interrupted. What IS comparable is each arm's
            # EXCESS over its own control. Reported against BOTH controls, because the sign
            # depends on which one is used.
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
            # AN ABSENCE ASSERTION IS WORTH NOTHING UNLESS THE SAME PATTERN IS SHOWN TO MATCH
            # SOMETHING (AGENTS.md § Absence assertions must first be proved positive): 'HOOK
            # install' is a string the plugin never writes (the real ones are `HOOK %s:
            # installed at %p` and `HOOK: %d/%d installed`), so it passes on any log. Each
            # pattern is proved POSITIVE against the plugin arm before being required absent.
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
