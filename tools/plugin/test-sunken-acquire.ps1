#Requires -Version 7
<#
.SYNOPSIS
PLUGIN-vs-STOCK: does a Sunken Colony attack a Medic that walks into its range? Same map,
positions and order, once with the plugin active and once with `-Mode observe`, which
installs no hook at all, plus a Marine arm as the control.

.DESCRIPTION
The plugin hooks selection commit, command emission and the HUD row dispatcher and draws
circles, and carries no AI or targeting code at all, so any difference between the arms is
a finding about us rather than an expected one.

A Medic has no weapon, so it cannot provoke a Sunken by shooting it; a Marine can and
does. That difference is why both arms run.

.EXAMPLE
./tools/plugin/test-sunken-acquire.ps1
.EXAMPLE
./tools/plugin/test-sunken-acquire.ps1 -Modes fanout -UnitTypes medic
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\022',
    # Which folder under Maps\ the fixture is generated into; see test-burrow-fanout.ps1.
    [string]$FixtureDir,
    # MORE THAN TWELVE, on purpose. At six units the fan-out never fires, the overflow
    # circles have nothing to draw and the HUD row never pages -- so the "fanout" arm would
    # be stock plus four pass-through hooks, and the comparison would answer "does LOADING
    # the plugin change acquisition" rather than "does our FAN-OUT change it". Asserted in
    # game below, not just intended here.
    [int]$UnitCount = 18,
    [ValidateSet('medic', 'marine')][string[]]$UnitTypes = @('medic', 'marine'),
    [ValidateSet('fanout', 'observe')][string[]]$Modes = @('fanout', 'observe'),
    # How long to stand next to the Sunken before deciding it is not going to attack.
    # A Sunken's attack cooldown is well under a second, so this window is not a close call.
    [int]$WatchSeconds = 45,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
. (Join-Path $scriptDir 'sc-oracle-guard.ps1')

$failures = 0
$step = 0
$script:armLock = $null

$TYPE_ID = @{ medic = 34; marine = 0 }     # richchk UnitId; asserted in game, not trusted
$SUNKEN_TYPE = 146                          # Zerg Sunken Colony
# Sunken Colony weapon range is 7 tiles = 224 map pixels. The block is walked to about
# +220px east of the start location and the Sunken sits at +448, so the near edge ends up
# well inside range -- reported as a distance measured from the engine's sprite positions.
$SUNKEN_RANGE_PX = 224
# The Sunken's own order id, read out of the run rather than assumed: 0x12 with nothing in
# range, 0x13 the moment the block arrives, in every arm. A sharper "did it acquire a
# target" signal than hit points, which Medics heal back -- so both are reported and
# compared across the arms.
$SUNKEN_IDLE_ORDER = 0x12
$SUNKEN_ATTACK_ORDER = 0x13
$WALK_X = 540
$WALK_Y = 240
$ENEMY_OFFSET_X = 448

$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
# A FIXTURE FOLDER OF ITS OWN, not the shared 00-testmap: sharing one means two workers can
# pick each other's maps. With $env:AGENT_TASK set this resolves to THIS agent's own folder,
# so two concurrent runs of this suite cannot land in one folder and overwrite each other's
# identically-named fixture. No row is assumed from the name -- Select-ScBrowserMap computes
# every click from the filesystem and verifies what opened.
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t022' -Suite 'sunken-acquire' }
$mapDir = $FixtureDir
$mapName = 'sunken-acquire.scx'
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

# The leading comma keeps the ARRAY an array on the way out. Without it PowerShell unrolls
# a function's array return, so a wiped group comes back as $null and `.Count` throws under
# StrictMode -- which is what happens when a Sunken one-shots the last Marine in the block.
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

function Invoke-Arm {
    param([Parameter(Mandatory)][string]$UnitType, [Parameter(Mandatory)][string]$Mode)

    $tag = "$UnitType-$Mode"
    $logPath = Join-Path $LogDir "sunken-$tag.log"
    $shotDir = Join-Path $LogDir "sunken-$tag-frames"
    $markerPath = Join-Path $LogDir 'marker.txt'
    $mapPath = Join-Path $mapDir $mapName
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
    New-Item -ItemType Directory -Path $shotDir -Force | Out-Null

    # Four arms run in sequence and each regenerates the same declared fixture, so the
    # wait clears only OUR file and never counts an earlier arm's as foreign.
    Wait-ScFixtureFolderFree -Run $fixtures
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount $UnitCount -UnitType $UnitType -Player 0 -Race terran `
        -EnemyCount 1 -EnemyType $SUNKEN_TYPE -EnemyRace zerg `
        -EnemyOffsetX $ENEMY_OFFSET_X -EnemyOffsetY 0 `
        -OutputPath $mapPath 2>&1
    $gen | Where-Object { "$_" -notmatch 'WARNING:StormLib' } | ForEach-Object { Write-Host "       $_" }
    Assert-That "[$tag] the generator succeeded" ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
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
        # Every row from the filesystem, and the opened folder verified before the map row
        # is clicked: a hardcoded row picks whatever foreign .scx happens to sort before
        # ours (AGENTS.md § "Map browser").
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2
        ArmShot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        # Found in the engine's own dialog list and dismissed by ITS OWN OK button, then
        # asserted gone -- never a fixed point, never the registry (AGENTS.md § "Tips dialog").
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $logPath | Out-Null
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
        # sample taken after the fact can show a group at full health that has in fact been
        # shot several times -- turning "the Sunken attacked" into "the Sunken did nothing"
        # for the one unit type this question is about. The Marine arm does not need this;
        # running the same measurement on both is what keeps the two arms comparable.
        $minHp = Get-TotalHp (Get-Mine $result.Arrived $TYPE_ID[$UnitType])
        $samples = [math]::Max(1, [int]($WatchSeconds / 5))
        # THE SUNKEN'S ORDER IS SAMPLED THE SAME WAY THE HIT POINTS ARE. One reading off the
        # last scan is unsafe for the same reason and worse: a Sunken that acquired
        # mid-window and returned to idle before that scan reads "never acquired", and it
        # reads that way in BOTH arms, so the two agree on a non-event. AcquiredAny is "at
        # any point in the window", which is what "did it acquire" means.
        $acquiredAny = $false
        $ordersSeen = @()
        $scans = 0
        for ($i = 0; $i -lt $samples; $i++) {
            Start-Sleep -Seconds 5
            $w = Get-ScWorldState -LogPath $logPath -Tag "watch$i" -MarkerPath $markerPath
            $hp = Get-TotalHp (Get-Mine $w $TYPE_ID[$UnitType])
            if ($hp -lt $minHp) { $minHp = $hp }
            $sunkNow = Get-Sunken $w
            foreach ($s in $sunkNow) {
                $ordersSeen += ('0x{0:x2}' -f $s.Order)
                if ($s.Order -eq $SUNKEN_ATTACK_ORDER) { $acquiredAny = $true }
            }
            $scans++
            $result.Watched = $w
        }
        $result.MinHp = $minHp
        $result.AcquiredAny = $acquiredAny
        $result.WatchSamples = $scans
        $result.OrdersSeen = (($ordersSeen | Sort-Object -Unique) -join ',')
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
        if (-not $KeepOpen) { Remove-ScOwnFixture -Run $fixtures }
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
                # after it is nonsense (AGENTS.md § "Game Type / `Custom Type`").
                $melee = @($arm.Boxed.Units | Where-Object { $_.Player -eq 0 -and $_.Type -in 7, 0x40, 0x29, 0x23, 0x2A })
                Assert-That "[$($arm.Tag)] the fixture spawned $UnitCount $ut(s)" ($mine0.Count -eq $UnitCount) `
                    ($melee.Count -gt 0 ? "(got $($mine0.Count); player 0 owns SCV/Drone-shaped units -- THIS IS A MELEE START, the Game Type pick did not take)" : "(got $($mine0.Count))")
                # A Zerg structure placed off creep is the one thing about this fixture that
                # could quietly not happen; assert it before reading the Sunken's silence.
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
                # Recorded on the arm as well as asserted, because the plugin-vs-stock
                # comparison downstream needs it as its witness: two arms whose blocks never
                # arrived agree that nothing happened.
                $arm.InRange = (($arm.DistWatched -ge 0 -and $arm.DistWatched -le $SUNKEN_RANGE_PX) -or
                                ($arm.DistArrived -ge 0 -and $arm.DistArrived -le $SUNKEN_RANGE_PX) -or
                                $arm.Survivors -lt $UnitCount)
                Assert-That "[$($arm.Tag)] the block really did walk inside the Sunken's weapon range (closest $($arm.DistWatched)px, arrival $($arm.DistArrived)px, range ${SUNKEN_RANGE_PX}px)" `
                    $arm.InRange
                # The plugin arm must actually be exercising the feature, or it is not a test
                # of the feature. Only meaningful in the fanout arm; the stock arm is
                # supposed to hold twelve and cap.
                if ($arm.Mode -eq 'fanout') {
                    $fan = @(Get-Content -LiteralPath $arm.LogPath |
                             Select-String -Pattern 'FANOUT start: cmd=0x14 .* units=(\d+)')
                    $fanUnits = if ($fan.Count -gt 0) {
                        [int]([regex]::Match($fan[-1].Line, 'units=(\d+)').Groups[1].Value)
                    } else { 0 }
                    Assert-That "[$($arm.Tag)] the move order was FANNED OUT past the cap ($fanUnits units)" `
                        ($fanUnits -gt 12) `
                        '(at or below twelve the plugin arm is stock plus pass-through hooks, and the comparison says nothing about the fan-out)'
                }
                Assert-That "[$($arm.Tag)] the world scan was not taken mid-edit" `
                    ($arm.Watched.Counts[0].Units -eq $arm.Watched.Counts[0].Recount -and $arm.Watched.Counts[0].Complete -eq 1)
                # The fixture must START quiet, or "it attacked" says nothing about the walk.
                Assert-That "[$($arm.Tag)] the Sunken was idle before the block arrived (order 0x$('{0:x2}' -f $arm.SunkenOrderBefore))" `
                    ($arm.SunkenOrderBefore -eq $SUNKEN_IDLE_ORDER)
            }
        }
    }

    Step 'THE COMPARISON: is the Sunken behaving differently with our plugin in the process?' {
        # HOW MANY PAIRS ACTUALLY REACHED THIS COMPARISON. The `continue` below is
        # legitimate -- `-Modes fanout` alone leaves no stock arm to compare against -- but
        # uncounted it lets a run that compared NOTHING print no assertions here and exit 0,
        # indistinguishable from a run in which everything agreed.
        $pairsCompared = 0
        foreach ($ut in $UnitTypes) {
            $f = $arms["$ut-fanout"]; $o = $arms["$ut-observe"]
            if (-not $f -or -not $o) { continue }
            $pairsCompared++
            Write-Host ("       {0}: fanout attacked={1} (hp {2}, lowest {3}, {4} samples, orders {5}), observe attacked={6} (hp {7}, lowest {8}, {9} samples, orders {10})" -f `
                $ut, $f.Attacked, $f.MyHpStart, $f.MyHpMin, $f.WatchSamples, $f.OrdersSeen,
                $o.Attacked, $o.MyHpStart, $o.MyHpMin, $o.WatchSamples, $o.OrdersSeen)
            # THE WITNESS both of the assertions below need: each arm's block has to have
            # got within the Sunken's reach. Without it, two arms that never arrived are
            # both "not attacked", the comparison passes, and the run reports parity between
            # two no-ops. Asserted per arm above; here it GATES.
            $bothProvoked = ($f.InRange -eq $true -and $o.InRange -eq $true)
            # THE QUESTION. Whatever the Sunken does, stock and plugin must do the same
            # thing -- that is what makes the answer "ours" or "vanilla".
            Assert-That "$ut`: the plugin arm and the stock arm agree on whether the Sunken attacked (both $($f.Attacked))" `
                (Test-ScWitnessed -Claim ($f.Attacked -eq $o.Attacked) -Witness $bothProvoked) `
                "(fanout=$($f.Attacked) inRange=$($f.InRange); observe=$($o.Attacked) inRange=$($o.InRange) -- a DIFFERENCE HERE IS OURS AND MUST BE REPORTED BEFORE ANYTHING ELSE; two arms that never reached the Sunken agree about nothing)"
            # ACQUIRED AT ANY POINT IN THE WINDOW, not in the last scan.
            Assert-That "$ut`: and on whether it ACQUIRED at any point in the window (fanout orders [$($f.OrdersSeen)] vs observe [$($o.OrdersSeen)])" `
                (Test-ScWitnessed -Claim ($f.AcquiredAny -eq $o.AcquiredAny) -Witness $bothProvoked) `
                "(fanout=$($f.AcquiredAny) over $($f.WatchSamples) sample(s); observe=$($o.AcquiredAny) over $($o.WatchSamples) sample(s))"
        }
        # AND THE COUNT GATES THE STEP. Zero pairs is not agreement.
        Assert-That "arms compared: $pairsCompared plugin/stock pair(s) of the $($UnitTypes.Count) unit type(s) asked for" `
            (Test-ScReached -Count $pairsCompared) `
            "(-Modes was '$($Modes -join ',')' -- this suite's whole question is a COMPARISON, so a run with only one mode has not asked it)"
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
            $f = $arms['medic-fanout']
            $obsLog = Get-Content -LiteralPath $o.LogPath
            $fanLog = Get-Content -LiteralPath $f.LogPath

            # AN ABSENCE ASSERTION IS WORTH NOTHING UNLESS THE SAME PATTERN IS SHOWN TO
            # MATCH SOMETHING. Do not probe for a string the plugin never writes: 'HOOK
            # install' matches no log at all (the real lines are `HOOK %s: installed at %p`
            # and `HOOK: %d/%d installed`), so it passes on a fanout log too. Each pattern
            # below is checked POSITIVE against the plugin arm's log first, and only then
            # required absent from the stock arm's.
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
            # And a POSITIVE statement about what the stock arm is, not just what it is not.
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
