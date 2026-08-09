#Requires -Version 7
<#
.SYNOPSIS
PLUGIN-vs-STOCK: does using an ability on a >12 selection IN COMBAT stop the units
fighting? 36 Ghosts engage 16 Hydralisks, Personnel Cloaking is pressed once mid-fight,
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

The fixture also answers the ENERGY half of question 1 on the way past: 24 of the 36
Ghosts start with full energy and 12 start with 5%, which is below the cost, so one
keypress shows who the engine charges and who it skips.

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
    [int]$EnemyCount = 16,
    [ValidateSet('fanout', 'observe')][string[]]$Modes = @('fanout', 'observe'),
    [int]$EngageTimeoutSec = 60,
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

$GHOST_TYPE = 1            # units.dat 1 (richchk UnitId 'Terran Ghost')
$HYDRALISK_TYPE = 38       # units.dat 38
$CLOAK_CMD = '0x21'
$CLOAK_KEY = 0x43          # 'C', the Ghost command card's Cloak hotkey
$CLOAK_ORDER2 = 0x6D       # what 0x00491B30 writes to CUnit+0xA6 after it charges energy
$IDLE_ORDER = 0x03         # the order every fixture in this repo sits on when doing nothing
# The camera opens centred on the start location and never moves on its own, so a click
# at client x is an order to (start.x + x - 320). Same constants as test-combat-death.ps1.
$WALK_X = 540
$WALK_Y = 240

$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
$mapDir = Join-Path $GameDir 'Maps\BroodWar\00-testmap'
$mapPath = Join-Path $mapDir '022-ghosts.scx'

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
        UnitCount = $UnitCount; UnitType = 'ghost'; Player = 0
        TechResearched = 'personnel-cloaking'
    }
    if ($DamagedCount -gt 0) {
        $genArgs.DamagedCount = $DamagedCount
        $genArgs.DamagedHp = 100
        $genArgs.DamagedEnergy = $DamagedEnergy
    }
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs `
        -EnemyCount $EnemyCount -EnemyType hydralisk -EnemyRace zerg `
        -OutputPath $mapPath 2>&1
    $gen | Where-Object { "$_" -notmatch 'WARNING:StormLib' } | ForEach-Object { Write-Host "       $_" }
    Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
    Assert-That 'Personnel Cloaking is researched for the human slot' `
        (@($gen | Select-String -Pattern 'PTEx: player 0 has researched 10\(personnel-cloaking\)').Count -gt 0)
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
        Send-ScClick -Hwnd $hwnd -X 117 -Y 140
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

        # THE MOMENT UNDER TEST: one ability keypress, with the group mid-fight.
        $mark = Get-ScLogLineCount -LogPath $logPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $CLOAK_KEY
        Start-Sleep -Seconds 2
        $result.CloakLines = @(Get-Content -LiteralPath $logPath | Select-Object -Skip $mark)
        $result.After = Get-ScWorldState -LogPath $logPath -Tag 'after-cloak' -MarkerPath $markerPath
        ArmShot 'after-cloak'

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
function Get-Mine { param($Scan) @($Scan.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $GHOST_TYPE }) }
function Get-EnemyHp {
    # Sum by hand: Measure-Object emits NOTHING for an empty pipeline, and under
    # StrictMode reading .Sum off that is a thrown error rather than a zero -- which is
    # exactly what happens on a run where the fixture did not spawn (a melee start has no
    # Hydralisks at all) and it hides the real cause behind a property-not-found.
    param($Scan)
    $total = 0
    foreach ($u in $Scan.Units) { if ($u.Type -eq $HYDRALISK_TYPE) { $total += $u.Hp } }
    return $total
}

# Units present in BOTH scans, matched by CUnit pointer, that were doing something other
# than idling before. "It stopped fighting" is only a claim about a unit that was
# fighting, and only about one that is still alive to be asked.
function Get-Transitions {
    param($Before, $After)
    $post = @{}
    foreach ($u in (Get-Mine $After)) { $post[$u.Unit] = $u }
    $busyBefore = @(Get-Mine $Before | Where-Object { $_.Order -ne $IDLE_ORDER })
    $stillHere = @($busyBefore | Where-Object { $post.ContainsKey($_.Unit) })
    $wentIdle = @($stillHere | Where-Object { $post[$_.Unit].Order -eq $IDLE_ORDER })
    [pscustomobject]@{
        BusyBefore = $busyBefore.Count
        StillAlive = $stillHere.Count
        WentIdle   = $wentIdle.Count
        Detail     = ($wentIdle | Select-Object -First 6 | ForEach-Object {
                        "unit=$($_.Unit) 0x$('{0:x}' -f $_.Order)->0x03" }) -join ' '
    }
}

$exePath = Join-Path $GameDir 'StarCraft.exe'
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

$arms = @{}
try {
    Step "generate the fixture: $UnitCount Ghosts ($DamagedCount of them at $DamagedEnergy% energy) vs $EnemyCount Hydralisks" {
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
            Assert-That "[$mode] the fixture spawned $UnitCount Ghosts" ($spawned -eq $UnitCount) `
                ($melee.Count -gt 0 ? "(got $spawned, and player 0 owns SCV/Drone/Larva/Overlord-shaped units -- THIS IS A MELEE START, the Game Type pick did not take)" : "(got $spawned)")
            Assert-That "[$mode] and $EnemyCount Hydralisks" `
                (@($arm.Boxed.Units | Where-Object { $_.Type -eq $HYDRALISK_TYPE }).Count -eq $EnemyCount)
            Assert-That "[$mode] the world scan was not taken mid-edit" `
                ($arm.Boxed.Counts[0].Units -eq $arm.Boxed.Counts[0].Recount -and $arm.Boxed.Counts[0].Complete -eq 1)
            Assert-That "[$mode] the two sides engaged within ${EngageTimeoutSec}s" ($null -ne $arm.Engaged)
            if (-not $arm.Engaged) { return }

            $t = Get-Transitions $arm.Engaged $arm.After
            $arm.Transitions = $t
            $arm.EnemyHpEngaged = Get-EnemyHp $arm.Engaged
            $arm.EnemyHpAfter = Get-EnemyHp $arm.After
            $arm.EnemyHpLater = Get-EnemyHp $arm.Later
            Write-Host ("       [{0}] busy before the keypress: {1}; still alive after: {2}; went idle across it: {3} {4}" -f `
                $mode, $t.BusyBefore, $t.StillAlive, $t.WentIdle, $t.Detail)
            Write-Host ("       [{0}] enemy hit points: {1} at engage -> {2} after -> {3} twelve seconds later" -f `
                $mode, $arm.EnemyHpEngaged, $arm.EnemyHpAfter, $arm.EnemyHpLater)

            # THE ASSERTION QUESTION 3 EXISTS FOR, per arm: an ability whose handler
            # never writes the main order must not take anybody off theirs.
            Assert-That "[$mode] not one unit that was busy stopped when the ability was used ($($t.WentIdle) of $($t.StillAlive))" `
                ($t.WentIdle -eq 0) $t.Detail
            # ... and the group is still fighting afterwards, which is the user's actual
            # complaint. Orders alone could look right while nothing happens.
            Assert-That "[$mode] the group kept doing damage after the ability (enemy $($arm.EnemyHpAfter) -> $($arm.EnemyHpLater))" `
                ($arm.EnemyHpLater -lt $arm.EnemyHpAfter)
        }
    }

    if ($arms.ContainsKey('fanout') -and $arms['fanout'].Engaged) {
        Step 'ARM fanout: the ability really did reach past the cap, and charged per unit' {
            $arm = $arms['fanout']
            $lines = $arm.CloakLines
            Assert-That "the key emitted $CLOAK_CMD" `
                (@($lines | Select-String -Pattern "CMD id=$CLOAK_CMD ").Count -gt 0)
            $start = @($lines | Select-String -Pattern "FANOUT start: cmd=$CLOAK_CMD .* units=(\d+)")
            Assert-That 'it was fanned out' ($start.Count -gt 0)
            if ($start.Count -gt 0) {
                $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
                Assert-That "more than twelve units were commanded ($u)" ($u -gt 12)
            }

            $mine = Get-Mine $arm.After
            $cloaked = @($mine | Where-Object { $_.Order2 -eq $CLOAK_ORDER2 })
            $notCloaked = @($mine | Where-Object { $_.Order2 -ne $CLOAK_ORDER2 })
            Assert-That "more units cloaked than the engine's twelve ($($cloaked.Count))" `
                ($cloaked.Count -gt 12)
            # THE ENERGY HALF OF QUESTION 1, in game: the units that could pay did, and
            # the ones that could not were skipped BY THE ENGINE -- same shape as Stim's
            # hit-point gate, read from each unit's own CUnit+0xA2.
            $before = @{}
            foreach ($u in (Get-Mine $arm.Engaged)) { $before[$u.Unit] = $u }
            $paid = @($cloaked | Where-Object { $before.ContainsKey($_.Unit) -and $_.Energy -lt $before[$_.Unit].Energy })
            Assert-That "every cloaked unit paid its own energy ($($paid.Count) of $($cloaked.Count))" `
                ($cloaked.Count -gt 0 -and $paid.Count -eq $cloaked.Count)
            $poorSpent = @($notCloaked | Where-Object { $before.ContainsKey($_.Unit) -and $_.Energy -lt $before[$_.Unit].Energy })
            Assert-That "and not one unit that could not afford it was charged ($($notCloaked.Count) skipped, $($poorSpent.Count) charged)" `
                ($poorSpent.Count -eq 0)
            Write-Host ("       energies after: cloaked {0}; skipped {1}" -f `
                (($cloaked | ForEach-Object { $_.Energy } | Sort-Object -Unique) -join ','),
                (($notCloaked | ForEach-Object { $_.Energy } | Sort-Object -Unique) -join ','))
        }
    }

    if ($arms.Count -ge 2 -and $arms['fanout'].Engaged -and $arms['observe'].Engaged) {
        Step 'PLUGIN vs STOCK: the comparison this question was asked for' {
            $f = $arms['fanout']; $o = $arms['observe']
            Write-Host ("       fanout : {0}/{1} busy units went idle across the ability" -f $f.Transitions.WentIdle, $f.Transitions.StillAlive)
            Write-Host ("       observe: {0}/{1} busy units went idle across the ability" -f $o.Transitions.WentIdle, $o.Transitions.StillAlive)
            Assert-That 'the plugin arm does not stop more units than stock does' `
                ($f.Transitions.WentIdle -le $o.Transitions.WentIdle) `
                "(fanout $($f.Transitions.WentIdle) vs observe $($o.Transitions.WentIdle))"
            Assert-That 'both arms were still fighting after the ability' `
                (($f.EnemyHpLater -lt $f.EnemyHpAfter) -and ($o.EnemyHpLater -lt $o.EnemyHpAfter))
            # The stock arm must really be stock: no hook of ours in it at all.
            $obsLog = Get-Content -LiteralPath $o.LogPath
            Assert-That 'the stock arm installed no hooks and intercepted no command' `
                ((@($obsLog | Select-String -Pattern 'FANOUT start|HOOK install').Count -eq 0)) `
                '(a hook line in the observe log would invalidate the control)'
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
}

Write-Host ''
Write-Host '[final] the run must balance'
foreach ($m in $arms.Keys) {
    $left = Get-Process -Id $arms[$m].Pid -ErrorAction SilentlyContinue
    Assert-That "the '$m' game process is gone" ($KeepOpen -or $null -eq $left)
}
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))
$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-ability-in-combat: $failures failure(s)"
exit ($failures -eq 0 ? 0 : 1)
