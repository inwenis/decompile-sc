#Requires -Version 7
<#
.SYNOPSIS
PLUGIN-vs-STOCK: does a Sunken Colony attack a Medic that walks into its range? Same map,
same positions, same order, run once with the plugin active and once with `-Mode observe`,
which installs no hook at all -- and once more with Marines in the Medics' place as the
control that says whether the Sunken can shoot ANYTHING there.

This is task 022's question 2, from the user: "there was a moment where sunken didn't
attack my medic and I'm not sure if it's a bug that we introduced or I just saw something
wrong."

.DESCRIPTION
The prior is strongly "not ours" -- the plugin hooks selection commit, command emission,
the HUD row dispatcher, and draws circles; it has no AI or targeting code in it at all.
The point of this test is not to restate the prior, it is to try to break it.

  * The MEDIC arm walks a block of Medics into a lone Sunken Colony and watches, from the
    engine's own unit lists, whether anything takes damage and what the Sunken's order id
    does. Run in `fanout` and in `observe`.
  * The MARINE arm is the same map with Marines in the Medics' place. It is the control
    that separates "the Sunken does not shoot a Medic" from "the Sunken cannot shoot from
    there at all" -- without it, a quiet Sunken proves nothing about Medics.

A Medic has no weapon, so it cannot provoke a Sunken by shooting it; a Marine can and
does. That difference is the whole point of running both.

.EXAMPLE
./tools/plugin/test-sunken-acquire.ps1

.EXAMPLE
./tools/plugin/test-sunken-acquire.ps1 -Modes fanout -UnitTypes medic
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\022',
    [int]$UnitCount = 6,
    [ValidateSet('medic', 'marine')][string[]]$UnitTypes = @('medic', 'marine'),
    [ValidateSet('fanout', 'observe')][string[]]$Modes = @('fanout', 'observe'),
    # How long to stand next to the Sunken before deciding it is not going to attack.
    # A Sunken's attack cooldown is well under a second; thirty is not a close call.
    [int]$WatchSeconds = 45,
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

$TYPE_ID = @{ medic = 34; marine = 0 }     # richchk UnitId; asserted in game, not trusted
$SUNKEN_TYPE = 146                          # Zerg Sunken Colony
# Sunken Colony weapon range is 7 tiles = 224 map pixels. The block is walked to about
# +220px east of the start location and the Sunken sits at +448, so the near edge of the
# block ends up well inside that range -- and the test does not take that on trust, it
# reports the measured distance from the engine's own sprite positions.
$SUNKEN_RANGE_PX = 224
# The Sunken's own order id, read out of this run rather than assumed: it sits on 0x12
# with nothing in range and moves to 0x13 the moment the block arrives, in every arm.
# That is a much sharper "did it acquire a target" signal than hit points, which Medics
# heal back -- so both are reported and both are compared across the arms.
$SUNKEN_IDLE_ORDER = 0x12
$SUNKEN_ATTACK_ORDER = 0x13
$WALK_X = 540
$WALK_Y = 240
$ENEMY_OFFSET_X = 448

$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
# THIS TASK'S OWN FIXTURE FOLDER, not the shared 00-testmap.
# The map browser picks by ROW, so sharing a folder means two workers pick each other's
# maps -- which happened twice during task 022, once in each direction, and cost a run
# each time. A folder of our own removes the interference in both directions rather than
# racing for it. The name sorts before every other 00-t* folder ('0' < any letter), so the
# first-row folder click that every suite here uses still lands on it.
$mapDir = Join-Path $GameDir 'Maps\BroodWar\00-t022'

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

# The leading comma keeps the ARRAY an array on the way out. Without it PowerShell
# unrolls a function's array return, so a group that has been wiped comes back as $null
# and `.Count` throws under StrictMode -- which is exactly what happens in the Marine arm,
# where a Sunken one-shots a Marine and the whole block can be gone before the next scan.
function Get-Mine { param($Scan, [int]$Type) ,@($Scan.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $Type }) }
function Get-Sunken { param($Scan) ,@($Scan.Units | Where-Object { $_.Type -eq $SUNKEN_TYPE }) }
function Get-TotalHp { param($Units) $t = 0; foreach ($u in $Units) { $t += $u.Hp }; $t }
function Get-MinDistance {
    param($A, $B)
    if ($A.Count -eq 0 -or $B.Count -eq 0) { return -1 }   # nothing left to measure
    $best = [int]::MaxValue
    foreach ($a in $A) { foreach ($b in $B) {
        $d = [int][math]::Sqrt([math]::Pow($a.X - $b.X, 2) + [math]::Pow($a.Y - $b.Y, 2))
        if ($d -lt $best) { $best = $d }
    } }
    $best
}

# The shared-folder race has TWO halves and the wait before generation only covers one:
# another worker can clear the folder, or drop a file into it, between the moment this
# fixture is written and the moment the map browser is clicked -- and the browser picks by
# ROW, so a foreign file silently changes which map loads. Re-checked here, as late as
# possible, and named as the cause if it fails.
function Assert-ScFixtureStillMine {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$MapPath)
    $mine = Split-Path $MapPath -Leaf
    if (-not (Test-Path -LiteralPath $MapPath)) {
        throw "test: $mine is gone from $Dir between generation and launch -- another worker's cleanup took it. Regenerate; do not interpret this run."
    }
    $foreign = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -ne $mine })
    if ($foreign.Count -gt 0) {
        throw ("test: {0} also holds {1}, which this test did not create. The map browser picks by ROW, so the wrong map would load. Refusing to start." -f $Dir, (($foreign | ForEach-Object { $_.Name }) -join ', '))
    }
}

# One arm: one unit type, one plugin mode.
function Invoke-Arm {
    param([Parameter(Mandatory)][string]$UnitType, [Parameter(Mandatory)][string]$Mode)

    $tag = "$UnitType-$Mode"
    $logPath = Join-Path $LogDir "sunken-$tag.log"
    $shotDir = Join-Path $LogDir "sunken-$tag-frames"
    $markerPath = Join-Path $LogDir 'marker.txt'
    $mapPath = Join-Path $mapDir "022-sunken.scx"
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
    New-Item -ItemType Directory -Path $shotDir -Force | Out-Null

    Wait-ScTestMapDirFree -Dir $mapDir -MyMapPath $mapPath
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount $UnitCount -UnitType $UnitType -Player 0 -Race terran `
        -EnemyCount 1 -EnemyType $SUNKEN_TYPE -EnemyRace zerg `
        -EnemyOffsetX $ENEMY_OFFSET_X -EnemyOffsetY 0 `
        -OutputPath $mapPath 2>&1
    $gen | Where-Object { "$_" -notmatch 'WARNING:StormLib' } | ForEach-Object { Write-Host "       $_" }
    Assert-That "[$tag] the generator succeeded" ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"

    Assert-ScFixtureStillMine -Dir $mapDir -MapPath $mapPath
    Wait-ScNoGameRunning
    $script:armLock = Enter-ScLaunchLock -TaskId "022-sunken-$tag"
    $script:armPid = 0
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode $Mode -WorldScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $logPath 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:armPid = [int]$Matches[1] }
        }
    $gamePid = $script:armPid
    if (-not $gamePid) { throw "test: could not parse the game pid for arm '$tag'." }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid
    $script:shotSeq = 0
    function ArmShot([string]$t) {
        $script:shotSeq++
        Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir ("{0:d2}-{1}.png" -f $script:shotSeq, $t)) -FullWindow | Out-Null
    }

    $result = [ordered]@{ Tag = $tag; UnitType = $UnitType; Mode = $Mode; LogPath = $logPath; Pid = $gamePid; MapPath = $mapPath }
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
        Set-ScGameType -Hwnd $hwnd -Index 2
        ArmShot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        Send-ScClick -Hwnd $hwnd -X 200 -Y 261
        Start-Sleep -Seconds 2

        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $result.Boxed = Get-ScWorldState -LogPath $logPath -Tag 'boxed' -MarkerPath $markerPath
        ArmShot 'boxed'

        Send-ScClick -Hwnd $hwnd -X $WALK_X -Y $WALK_Y -Right
        Start-Sleep -Seconds 8
        $result.Arrived = Get-ScWorldState -LogPath $logPath -Tag 'arrived' -MarkerPath $markerPath
        ArmShot 'arrived'

        # SAMPLE REPEATEDLY, AND KEEP THE MINIMUM. Medics heal each other, so a single
        # sample taken after the fact can show a group at full health that has in fact
        # been shot several times -- which would turn "the Sunken attacked" into "the
        # Sunken did nothing" for the one unit type this question is about. The Marine
        # arm does not need this; running the same measurement on both is what keeps the
        # two arms comparable.
        $minHp = Get-TotalHp (Get-Mine $result.Arrived $TYPE_ID[$UnitType])
        $samples = [math]::Max(1, [int]($WatchSeconds / 5))
        for ($i = 0; $i -lt $samples; $i++) {
            Start-Sleep -Seconds 5
            $w = Get-ScWorldState -LogPath $logPath -Tag "watch$i" -MarkerPath $markerPath
            $hp = Get-TotalHp (Get-Mine $w $TYPE_ID[$UnitType])
            if ($hp -lt $minHp) { $minHp = $hp }
            $result.Watched = $w
        }
        $result.MinHp = $minHp
        ArmShot 'watched'
    }
    finally {
        if (-not $KeepOpen -and $gamePid -gt 0) {
            try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Out-Null }
            catch { Write-Host "  FAIL close-game failed for arm '$tag': $($_.Exception.Message)"; $script:failures++ }
            Start-Sleep -Seconds 2
        }
        Exit-ScLaunchLock -Lock $script:armLock
        $script:armLock = $null
        if (-not $KeepOpen -and (Test-Path -LiteralPath $mapPath)) {
            Remove-Item -LiteralPath $mapPath -Force -ErrorAction SilentlyContinue
        }
        Remove-ScOwnFixtureDir -Dir $mapDir
    }
    return $result
}

$exePath = Join-Path $GameDir 'StarCraft.exe'
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

$arms = @{}
try {
    foreach ($ut in $UnitTypes) {
        foreach ($mode in $Modes) {
            Step "ARM '$ut' / '$mode': walk $UnitCount $ut(s) into a Sunken Colony and watch for ${WatchSeconds}s" {
                $arm = Invoke-Arm -UnitType $ut -Mode $mode
                $arms["$ut-$mode"] = $arm
                $type = $TYPE_ID[$ut]

                $mine0 = Get-Mine $arm.Boxed $type
                $sunk0 = Get-Sunken $arm.Boxed
                # Loud, and named: a melee start looks like a normal game and every number
                # after it is nonsense (task 021).
                $melee = @($arm.Boxed.Units | Where-Object { $_.Player -eq 0 -and $_.Type -in 7, 0x40, 0x29, 0x23, 0x2A })
                Assert-That "[$($arm.Tag)] the fixture spawned $UnitCount $ut(s)" ($mine0.Count -eq $UnitCount) `
                    ($melee.Count -gt 0 ? "(got $($mine0.Count); player 0 owns SCV/Drone-shaped units -- THIS IS A MELEE START, the Game Type pick did not take)" : "(got $($mine0.Count))")
                # A Zerg structure placed off creep is the one thing about this fixture
                # that could quietly not happen, so it is asserted before anything else is
                # concluded from the Sunken's silence.
                Assert-That "[$($arm.Tag)] the Sunken Colony exists in game" ($sunk0.Count -eq 1) `
                    "(found $($sunk0.Count) unit(s) of type $SUNKEN_TYPE)"
                if ($mine0.Count -ne $UnitCount -or $sunk0.Count -ne 1) { return }

                $mine1 = Get-Mine $arm.Arrived $type
                $sunk1 = Get-Sunken $arm.Arrived
                $mine2 = Get-Mine $arm.Watched $type
                $sunk2 = Get-Sunken $arm.Watched

                $arm.DistArrived = Get-MinDistance $mine1 $sunk1
                $arm.DistWatched = Get-MinDistance $mine2 $sunk2
                $arm.MyHpArrived = Get-TotalHp $mine1
                $arm.MyHpWatched = Get-TotalHp $mine2
                $arm.MyHpStart = Get-TotalHp $mine0
                $arm.SunkenHpStart = Get-TotalHp $sunk0
                $arm.SunkenHpWatched = Get-TotalHp $sunk2
                $arm.SunkenOrders = (($sunk2 | ForEach-Object { '0x{0:x2}' -f $_.Order }) -join ',')
                # A Marine block can kill the Sunken outright, so "no Sunken" is a real
                # outcome and reads as -1 rather than throwing.
                $arm.SunkenOrderBefore = $(if ($sunk0.Count -gt 0) { $sunk0[0].Order } else { -1 })
                $arm.SunkenOrderAfter = $(if ($sunk2.Count -gt 0) { $sunk2[0].Order } else { -1 })
                $arm.SunkenAcquired = ($arm.SunkenOrderAfter -eq $SUNKEN_ATTACK_ORDER)
                $arm.Survivors = $mine2.Count
                $arm.MyHpMin = $arm.MinHp
                # "It was shot" is the LOWEST hit-point total seen while standing there,
                # or a missing unit -- not the final reading, which healing can restore.
                $arm.Attacked = ($arm.MyHpMin -lt $arm.MyHpStart) -or ($mine2.Count -lt $UnitCount)

                Write-Host ("       [{0}] closest {1} to the Sunken: {2}px on arrival, {3}px after the watch (weapon range {4}px)" -f `
                    $arm.Tag, $ut, $arm.DistArrived, $arm.DistWatched, $SUNKEN_RANGE_PX)
                Write-Host ("       [{0}] my hit points {1} -> {2} (lowest seen {3}); survivors {4}/{5}; Sunken hp {6} -> {7}; Sunken order(s) {8}" -f `
                    $arm.Tag, $arm.MyHpStart, $arm.MyHpWatched, $arm.MyHpMin, $arm.Survivors, $UnitCount,
                    $arm.SunkenHpStart, $arm.SunkenHpWatched, $arm.SunkenOrders)

                # The fixture is only meaningful if the units actually got within range.
                # -1 means the block is gone, which is itself proof it got in range.
                Assert-That "[$($arm.Tag)] the block really did walk inside the Sunken's weapon range (closest $($arm.DistWatched)px, arrival $($arm.DistArrived)px, range ${SUNKEN_RANGE_PX}px)" `
                    (($arm.DistWatched -ge 0 -and $arm.DistWatched -le $SUNKEN_RANGE_PX) -or
                     ($arm.DistArrived -ge 0 -and $arm.DistArrived -le $SUNKEN_RANGE_PX) -or
                     $arm.Survivors -lt $UnitCount)
                Assert-That "[$($arm.Tag)] the world scan was not taken mid-edit" `
                    ($arm.Watched.Counts[0].Units -eq $arm.Watched.Counts[0].Recount -and $arm.Watched.Counts[0].Complete -eq 1)
                # The fixture must START quiet, or "it attacked" says nothing about the walk.
                Assert-That "[$($arm.Tag)] the Sunken was idle before the block arrived (order 0x$('{0:x2}' -f $arm.SunkenOrderBefore))" `
                    ($arm.SunkenOrderBefore -eq $SUNKEN_IDLE_ORDER)
            }
        }
    }

    Step 'THE COMPARISON: is the Sunken behaving differently with our plugin in the process?' {
        foreach ($ut in $UnitTypes) {
            $f = $arms["$ut-fanout"]; $o = $arms["$ut-observe"]
            if (-not $f -or -not $o) { continue }
            Write-Host ("       {0}: fanout attacked={1} (hp {2}, lowest {3}), observe attacked={4} (hp {5}, lowest {6})" -f `
                $ut, $f.Attacked, $f.MyHpStart, $f.MyHpMin, $o.Attacked, $o.MyHpStart, $o.MyHpMin)
            # THE QUESTION. Whatever the Sunken does, stock and plugin must do the same
            # thing -- that is what makes the answer "ours" or "vanilla".
            Assert-That "$ut`: the plugin arm and the stock arm agree on whether the Sunken attacked (both $($f.Attacked))" `
                ($f.Attacked -eq $o.Attacked) `
                "(fanout=$($f.Attacked) observe=$($o.Attacked) -- a DIFFERENCE HERE IS OURS AND MUST BE REPORTED BEFORE ANYTHING ELSE)"
            Assert-That "$ut`: and on whether it ACQUIRED at all (Sunken order 0x$('{0:x2}' -f $f.SunkenOrderAfter) vs 0x$('{0:x2}' -f $o.SunkenOrderAfter))" `
                ($f.SunkenAcquired -eq $o.SunkenAcquired)
        }
        $med = $arms['medic-observe']; $mar = $arms['marine-observe']
        if ($med -and $mar) {
            Write-Host ("       stock, side by side: Medics attacked={0}, Marines attacked={1}" -f $med.Attacked, $mar.Attacked)
            # The control that gives the medic result meaning: if the Sunken cannot shoot
            # anything from there, a quiet Sunken says nothing about Medics.
            Assert-That 'stock: the Sunken CAN shoot something standing there (the Marine control)' `
                ($mar.Attacked) '(if this fails the fixture never put anything in range, and the medic result means nothing)'
        }
    }

    if ($arms.ContainsKey('medic-observe')) {
        Step 'the stock arm must really be stock' {
            $o = $arms['medic-observe']
            $obsLog = Get-Content -LiteralPath $o.LogPath
            Assert-That 'no hook was installed and no command was intercepted in the observe arm' `
                (@($obsLog | Select-String -Pattern 'FANOUT start|HOOK install').Count -eq 0)
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

Write-Host ''
Write-Host '[final] the run must balance'
foreach ($k in $arms.Keys) {
    $left = Get-Process -Id $arms[$k].Pid -ErrorAction SilentlyContinue
    Assert-That "the '$k' game process is gone" ($KeepOpen -or $null -eq $left)
}
$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-sunken-acquire: $failures failure(s)"
exit ($failures -eq 0 ? 0 : 1)
