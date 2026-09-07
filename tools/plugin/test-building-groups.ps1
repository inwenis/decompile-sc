#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that a drag box over N same-type BUILDINGS selects all N,
every one of them gets a selection circle, and one right-click rallies every one of them
-- asserted per building from in-process state, never from the picture.

.DESCRIPTION
WHAT VANILLA DOES. `unit_IsStandardAndMovable` (0x0047B770) gates both sides of the
selection path: on the client `SortAllUnits` (0x0046F0F0) drops every candidate that
fails it and, if that emptied the list, substitutes the LAST one it dropped and returns
a count of 1 (`0x0046F223` remembers it; `0x0046F27A`..`0x0046F281` put it back); in the
simulation `addUnitToSelectionSlot` (0x0049AF80) refuses every slot but the first to a
unit that fails it. So vanilla selects exactly one building per box, and the simulation
holds exactly one whatever arrives on the wire. Evidence: research/building-groups.md.

One arm per invocation, each its own game launch because the arm is fixed at
plugin-install time: -Stock is the negative control that gives the feature arm's
"sixteen" something to fail against, the default arm is the feature, -Combat is the
liveness arm. Fixtures are generated at run time and deleted afterwards, because
generated maps are game content (AGENTS.md § "Test fixtures").

.EXAMPLE
./tools/plugin/test-building-groups.ps1 -Stock

.EXAMPLE
./tools/plugin/test-building-groups.ps1

.EXAMPLE
./tools/plugin/test-building-groups.ps1 -Combat
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath,
    [string]$ShotDir = 'C:\sc-work\logs\024-building-frames',
    # This run's fixture folder. Defaults to this AGENT's own (Resolve-ScFixtureDir), so
    # two workers can never land in one folder and move each other's browser rows.
    [string]$FixtureDir,
    # The control arm: the feature switched off at plugin-install time.
    [switch]$Stock,
    # The liveness arm: buildings that die while selected.
    [switch]$Combat,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
if ($Stock -and $Combat) { throw 'test: -Stock and -Combat are separate arms; pass one.' }
$arm = if ($Stock) { 'stock' } elseif ($Combat) { 'combat' } else { 'feature' }
if (-not $LogPath) { $LogPath = "C:\sc-work\logs\024-building-groups-$arm.log" }

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')

$failures = 0
$step = 0

# Pinned ids, asserted rather than reported.
#   TURRET   units.dat 124 (0x7C). A 2x2-tile Terran building: it fails
#            unit_IsStandardAndMovable on the units.dat Building flag (0x01) and it is
#            not in unit_isUnselectable's list, so vanilla selects exactly one of them.
#   BARRACKS units.dat 111 (0x6F). 4x3 tiles, and a PRODUCTION building, which is what
#            gives it the rally point the right-click step reads back.
#   MARINE   the computer force for the -Combat arm: anything that shoots a building
#            would do, it is named so the fixture's unit-count check can see it.
$TURRET_ID     = 124
$BARRACKS_ID   = 111
$TURRET_TYPE   = '0x7C'
$BARRACKS_TYPE = '0x6F'
# Sixteen 2x2-tile turrets on the 64 px grid form a 4x4 block spanning 192x192 px, which is
# what lets one drag box hold them all inside the 632x336 battlefield Select-ScUnitsByMap
# clamps to.
$TURRET_COUNT   = 16
$BARRACKS_COUNT = 6
# FOUR marines, not eight, and see UnitHp below. Measured, not guessed: eight marines
# against sixteen turrets at 12% hit points deal ~0.96 HP/s each and wipe the block in
# about fifty seconds -- half of it dead before the box lands, all of it dead before the
# right-click goes out, so the fan-out builds nothing and the arm proves nothing. A
# liveness arm needs the group to die as a TRICKLE, not as a volley.
$ENEMY_COUNT    = 4

# THE -Combat ARM'S VICTIMS ARE BARRACKS, NOT TURRETS. Its claim is about the COMMAND
# path -- "a dead building in the selection reaches no emitted Select" -- so it needs a
# building that accepts a right-click at all. A Missile Turret does not: immobile and
# non-production, it has neither a move order nor a rally point. Measured from the
# engine's own command stream: a right-click with sixteen turrets selected queues NOTHING
# (the plugin's CMD log holds only 0x37 syncs and not one 0x14), so there is no command
# to fan out, `dropped` stays 0, and the arm cannot fail honestly. Barracks are the type
# the feature arm proves a right-click fans out (`FANOUT start: cmd=0x14`).
$VICTIM_ID    = if ($Combat) { $BARRACKS_ID } else { $TURRET_ID }
$VICTIM_TYPE  = if ($Combat) { $BARRACKS_TYPE } else { $TURRET_TYPE }
$VICTIM_COUNT = if ($Combat) { $BARRACKS_COUNT } else { $TURRET_COUNT }
# 4x3-tile buildings need the same 128 px grid the feature arm's Barracks block uses; at
# the turrets' 64 px they would overlap and the engine would refuse to place them.
$VICTIM_SPACING = if ($Combat) { 128 } else { 64 }

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-testmap' -Suite 'building-groups' }
$mapDir = $FixtureDir
# One name per fixture SHAPE, named for this SUITE, so "mine" is decidable from the
# filename alone. Only the name this arm creates is declared -- the declaration is the
# list this run cleans up.
$mapName = if ($Combat) { 'building-groups-combat.scx' } else { 'building-groups.scx' }
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

# The plugin watches ONE marker path and it is not ours to choose: it logs the one it
# opened (`OBSERVER marker file:`) and that is `<log dir>\marker.txt`. A per-arm name
# here makes every state read time out with the plugin working perfectly. The arms are
# sequential, so sharing it is not a contention risk.
$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-ScState {
    param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec
}

# "Every live unit is of exactly one type, and it is this one." Single-bucket, because a
# histogram whose largest bucket is 12 of 16 says nothing about the other four.
function Assert-ScAllOneType {
    param([string]$What, $State, [string]$ExpectedType)
    $only = @($State.Types.Keys)
    $ok = ($only.Count -eq 1) -and ($State.Types[$only[0]] -eq $State.Live) -and
          ($only[0] -eq $ExpectedType)
    Assert-That "$What`: all $($State.Live) are $ExpectedType" $ok "(got $($State.TypesText))"
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] arm=$arm   StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0}-{1:d2}-{2}.png" -f $arm, $script:shotN, $tag)) -FullWindow | Out-Null
}

# Box a set of units EXACTLY, by map position, with the camera moved to them first.
# NOT a full-screen drag: this fixture holds two selectable blocks, and a full-screen
# drag after centring on the turret block still reaches a Barracks -- vanilla's "last
# rejected candidate" fallback then picks THAT and the run measures the wrong block.
# So: centre with a minimap click, ask the plugin where the viewport is (`WORLD [...]
# screen=(left,top)`, the engine's own 0x0062848C / 0x006284A8) and convert each unit's
# map position into the client coordinate a posted drag carries: client = map - origin.
# Returns $false when the block is not fully on screen, so "the camera did not go where
# we asked" fails as itself instead of as a wrong count.
function Select-ScUnitsByMap {
    param(
        [Parameter(Mandatory)][object[]]$Units,      # WORLD-scan rows: .X and .Y in map px
        [Parameter(Mandatory)][int]$TileX,           # where to point the camera first
        [Parameter(Mandatory)][int]$TileY,
        [string]$Tag = 'aim',
        [int]$Margin = 24,
        [int]$MapW = 128, [int]$MapH = 96
    )
    $p = Get-ScMinimapPoint -MapTilesW $MapW -MapTilesH $MapH -TileX $TileX -TileY $TileY
    Send-ScClick -Hwnd $script:hwnd -X $p.X -Y $p.Y
    Start-Sleep -Milliseconds 800

    # The origin has to be re-read AFTER the camera move, so this is a fresh scan.
    $w = Get-ScWorldState -LogPath $script:LogPath -Tag $Tag -MarkerPath $script:markerPath
    if (-not $w.Screen) { throw 'test: the plugin did not report the viewport origin (needs the task-024 build).' }
    $script:lastScreen = $w.Screen
    $x1 = ($Units | Measure-Object X -Minimum).Minimum - $w.Screen.Left - $Margin
    $x2 = ($Units | Measure-Object X -Maximum).Maximum - $w.Screen.Left + $Margin
    $y1 = ($Units | Measure-Object Y -Minimum).Minimum - $w.Screen.Top  - $Margin
    $y2 = ($Units | Measure-Object Y -Maximum).Maximum - $w.Screen.Top  + $Margin
    # The battlefield, not the window: the HUD starts around y=348 at 640x480 and a drag
    # into it is a click on the console, not on the map.
    if ($x1 -lt 4 -or $y1 -lt 4 -or $x2 -gt 636 -or $y2 -gt 340) {
        Write-Host "       (block at client [$x1,$y1]-[$x2,$y2] is not fully on the battlefield)"
        return $false
    }
    Write-Host "       (boxing client [$x1,$y1]-[$x2,$y2]; viewport at map ($($w.Screen.Left),$($w.Screen.Top)))"
    Send-ScDrag -Hwnd $script:hwnd -X1 $x1 -Y1 $y1 -X2 $x2 -Y2 $y2 -Steps 20
    Start-Sleep -Seconds 2
    return $true
}

try {
    Step "generate the fixture: $mapName" {
        Wait-ScFixtureFolderFree -Run $fixtures
        # --enemy-owner player is the two-block form: the generator that places a COMPUTER
        # force for the combat fixture places this one under the human, the only way to
        # get two selectable blocks of DIFFERENT types onto one map. 512 px east clears
        # the default 256 px minimum gap between the bounding boxes (turrets end at +96,
        # barracks start at +384) and puts each block off screen when the view is centred
        # on the other.
        $genArgs = @{
            UnitCount = $VICTIM_COUNT; UnitType = "$VICTIM_ID"; Player = 0
            GridSpacing = $VICTIM_SPACING; Race = 'terran'; OutputPath = $mapPath
        }
        if ($Combat) {
            # The victims must die on a schedule this suite can steer between: the first
            # death AFTER the box (step 5 asserts all six are alive when the group forms)
            # and the last one well after the order (step 6 needs live ones left on the
            # wire to compare the dead ones against). Do not lower it: at 12% the first
            # death lands before the box and the last before the order. Measured on THIS
            # fixture: at 15% (150 HP) four marines focus-firing take one Barracks all the
            # way down and put 46 more into a second inside the ~20 s before the box --
            # about 12 HP/s between them. 60% of a Barracks' 1000 HP is 600, so the first
            # falls around fifty seconds in: after the box, and inside step 6's 180 s
            # deadline even at half that rate.
            $genArgs += @{
                UnitHp = 60
                EnemyCount = $ENEMY_COUNT; EnemyType = 'marine'
                EnemyOwner = 'computer'; EnemyRace = 'terran'
                # 256 px east leaves 112 px between the two bounding boxes -- INSIDE a
                # Marine's 128 px range, which is the point: this arm needs them to engage
                # on the first frame where every other fixture needs the opposite. Hence
                # MinEnemyGap 96: the generator's 128 px floor keeps fixtures idle and
                # would refuse this one.
                EnemyOffsetX = 256; EnemyOffsetY = 0; EnemySpacing = 48; MinEnemyGap = 96
            }
        }
        else {
            $genArgs += @{
                EnemyCount = $BARRACKS_COUNT; EnemyType = "$BARRACKS_ID"
                EnemyOwner = 'player'; EnemyRace = 'terran'
                EnemyOffsetX = 512; EnemyOffsetY = 0; EnemySpacing = 128
            }
        }
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'nothing can end the game on its own (TRIG is empty)' `
            (@($gen | Select-String -Pattern 'TRIG holds 0 byte').Count -gt 0)
        Assert-That "the human's player id is not left to the engine to pick" `
            (@($gen | Select-String -Pattern 'no force randomises start locations').Count -gt 0)
    }

    $groups = if ($Stock) { '0' } else { '1' }
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -Circles 1 -HudRow 0 -WorldScan 1 -BuildingGroups $groups `
        -InjectWindowedHelper WMode -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'the plugin came up in the configuration this arm asked for' {
        # Proved POSITIVE from the plugin's own config line rather than assumed from the
        # argument: the stock arm's point is that the feature really is off, and "we
        # passed 0" is not that.
        $cfg = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'FANOUT config: .* buildingGroups=(\d)' -TimeoutSec 30)
        Assert-That 'the plugin logged its configuration' ($cfg.Count -gt 0)
        if ($cfg.Count -gt 0) {
            $got = [regex]::Match($cfg[-1], 'buildingGroups=(\d)').Groups[1].Value
            Assert-That "building groups are $(if ($Stock) { 'OFF' } else { 'ON' }) in this arm (buildingGroups=$got)" `
                ($got -eq $groups)
            Write-Host "       $($cfg[-1].Trim())"
        }
    }

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        # LAST CHECK BEFORE THE ROW IS CLICKED, not only at generate time: the folder can
        # be added to in between, and every row below the addition moves.
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2      # Use Map Settings, verified
        Shot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN
        # OK button, then asserted gone (AGENTS.md § "Tips dialog") -- never a fixed point,
        # never the registry.
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    # Where the blocks actually are, read out of the engine's own unit lists rather than
    # computed from the generator's arguments: a block the engine refused to place shows
    # up here as a wrong count, before any selection claim rests on it. The tile
    # coordinates are what every minimap click below aims at.
    Step 'the map spawned what it was asked to, and this is where it is' {
        $world = Get-ScWorldState -LogPath $LogPath -Tag 'world' -MarkerPath $markerPath
        $mine = @($world.Units | Where-Object { $_.Owner -eq 0 })
        $script:victims = @($mine | Where-Object { $_.Type -eq $VICTIM_ID })
        $victims = $script:victims
        $victimName = if ($Combat) { 'Barracks' } else { 'Missile Turrets' }
        Assert-That "all $VICTIM_COUNT $victimName were placed ($($victims.Count))" `
            ($victims.Count -eq $VICTIM_COUNT)
        if ($victims.Count -eq 0) { throw 'test: no victims placed -- nothing below can be interpreted.' }
        $script:victimTile = [pscustomobject]@{
            X = [int]((($victims | Measure-Object X -Average).Average) / 32)
            Y = [int]((($victims | Measure-Object Y -Average).Average) / 32)
        }
        Write-Host "       $victimName centred on tile ($($victimTile.X),$($victimTile.Y))"

        if ($Combat) {
            $foes = @($world.Units | Where-Object { $_.Owner -ne 0 })
            Assert-That "the computer force is there ($($foes.Count))" ($foes.Count -gt 0)
            Assert-That "the player owns nothing but the $VICTIM_COUNT victims ($($mine.Count))" `
                ($mine.Count -eq $VICTIM_COUNT)
        }
        else {
            $script:turrets = $script:victims
            $turrets = $script:turrets
            $script:turretTile = $script:victimTile
            $turretTile = $script:turretTile
            $script:barracks = @($mine | Where-Object { $_.Type -eq $BARRACKS_ID })
            $barracks = $script:barracks
            Assert-That "all $BARRACKS_COUNT Barracks were placed ($($barracks.Count))" `
                ($barracks.Count -eq $BARRACKS_COUNT)
            Assert-That "the player owns nothing else ($($mine.Count) in total)" `
                ($mine.Count -eq $TURRET_COUNT + $BARRACKS_COUNT)
            if ($barracks.Count -eq 0) { throw 'test: no barracks placed.' }
            $script:barracksTile = [pscustomobject]@{
                X = [int]((($barracks | Measure-Object X -Average).Average) / 32)
                Y = [int]((($barracks | Measure-Object Y -Average).Average) / 32)
            }
            Write-Host "       barracks centred on tile ($($barracksTile.X),$($barracksTile.Y))"
            # The mixed-building box cannot hold BOTH whole blocks -- 512 px apart is wider
            # than the battlefield -- so it is aimed at the facing edges: the easternmost
            # column of turrets and the westernmost column of barracks. That is a genuine
            # mixed box (two building types, no units) and it fits.
            $tx = ($script:turrets | Measure-Object X -Maximum).Maximum
            $bx = ($script:barracks | Measure-Object X -Minimum).Minimum
            $script:mixedUnits = @($script:turrets | Where-Object { $_.X -eq $tx }) +
                                 @($script:barracks | Where-Object { $_.X -eq $bx })
            $script:midTile = [pscustomobject]@{
                X = [int]((($script:mixedUnits | Measure-Object X -Average).Average) / 32)
                Y = [int]((($script:mixedUnits | Measure-Object Y -Average).Average) / 32)
            }
            # The blocks must be more than a screen-half apart, or "the box held exactly
            # these" is luck rather than a property of the fixture.
            Assert-That 'the two blocks are more than a screen-half apart' `
                ([math]::Abs($turretTile.X - $barracksTile.X) * 32 -gt 320)
        }
    }

    if ($Stock) {
        Step 'STOCK: with building groups off, a box over 16 turrets selects ONE' {
            $aimed = Select-ScUnitsByMap -Units $script:turrets -TileX $turretTile.X -TileY $turretTile.Y -Tag 'aim-stock'
            Assert-That 'the turret block is on screen and was boxed' $aimed
            $stockState = Get-ScState 'stock'
            Assert-That "vanilla selects exactly one building ($($stockState.N))" ($stockState.N -eq 1)
            Assert-That '  and the engine holds that one' ($stockState.Visible -eq 1)
            Assert-ScAllOneType '  the one it picked' $stockState $TURRET_TYPE
            Assert-That "  and the sim's capacity is reported as one (simSlots=$($stockState.SimSlots))" `
                ($stockState.SimSlots -eq 1)
            # Nothing grew: the log line the feature writes must be ABSENT here, and the
            # feature arm proves the same pattern MATCHES -- which is what makes the
            # absence worth asserting (AGENTS.md § "Oracles: absence and defect-era checks").
            $bg = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'BGROUP box:')
            Assert-That 'no building group was ever formed' ($bg.Count -eq 0) `
                ($bg.Count -gt 0 ? "($($bg[0].Line.Trim()))" : '')
            Write-Host "       $($stockState.Line)"
            Shot 'stock-one-building'
        }
    }
    elseif ($Combat) {
        Step "the box holds all $VICTIM_COUNT Barracks before anything dies" {
            $aimed = Select-ScUnitsByMap -Units $script:victims -TileX $victimTile.X -TileY $victimTile.Y -Tag 'aim-combat'
            Assert-That 'the Barracks block is on screen and was boxed' $aimed
            $before = Get-ScState 'combat-before'
            Assert-That "the selection holds all $VICTIM_COUNT ($($before.N))" ($before.N -eq $VICTIM_COUNT)
            Assert-ScAllOneType '  the boxed buildings' $before $VICTIM_TYPE
            Assert-That "every one of them is alive ($($before.Live))" ($before.Live -eq $VICTIM_COUNT)
            Assert-That "the liveness gate is ON (liveness=$($before.Liveness))" ($before.Liveness -eq 1)
            Write-Host "       $($before.Line)"
            Shot 'combat-before'
        }

        Step 'a building in the selection dies, and its tag reaches no Select' {
            # Wait for a MIXED selection -- some dead AND some still alive -- not merely
            # for "one died": that distinction is the whole arm. On `live < n` alone the
            # fixture can kill the rest before the order is posted, handing the fan-out a
            # selection with nothing live in it: it emits no Select at all, so "no dead tag
            # reached the wire" passes with zero tags on the wire. An absence with nothing
            # to fail against is not evidence (AGENTS.md § "Oracles: absence and defect-era
            # checks"), so the live ones are part of the precondition and a window that
            # never opens fails HERE, naming itself, instead of downstream.
            $deadline = (Get-Date).AddSeconds(180)
            $state = $null
            while ((Get-Date) -lt $deadline) {
                $state = Get-ScState 'combat-wait'
                if ($state.Live -lt $state.N -and $state.Live -gt 0) { break }
                Start-Sleep -Seconds 1
            }
            Assert-That "the selection holds dead AND live buildings at once ($($state.Live) live of $($state.N))" `
                ($state.Live -lt $state.N -and $state.Live -gt 0) "(got $($state.Line))"
            # hp0: a unit killed by DAMAGE whose slot has not been recycled, which a
            # uniqueness check comparing slots alone cannot see.
            Assert-That "the dead one is seen as dead, not merely as recycled (hp0=$($state.Hp0) removed=$($state.Removed))" `
                (($state.Hp0 + $state.Removed) -gt 0)
            Write-Host "       $($state.Line)"
            Shot 'combat-death'

            $mark = Get-ScLogLineCount -LogPath $LogPath
            Send-ScClick -Hwnd $hwnd -X 60 -Y 40 -Right
            Start-Sleep -Seconds 3
            $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

            # PROVE A COMMAND WAS ISSUED AT ALL, before asking what the fan-out did with
            # it: "no Select carried a dead tag" is trivially true when no Select was
            # built (see $VICTIM_ID for the selection that queues nothing).
            $started = @($lines | Select-String -Pattern 'FANOUT start: cmd=0x14')
            Assert-That 'the right-click actually queued a command for these buildings' `
                ($started.Count -gt 0) '(no FANOUT start line -- the engine issued no command)'
            if ($started.Count -gt 0) { Write-Host "       $($started[-1].Line.Trim())" }

            $sel = @($lines | Select-String -Pattern 'FANOUT select: in=(\d+) out=(\d+) dropped=(\d+)')
            Assert-That 'the fan-out reported every Select it built' ($sel.Count -gt 0)
            $considered = 0; $emitted = 0; $dropped = 0
            foreach ($l in $sel) {
                $m = [regex]::Match($l.Line, 'in=(\d+) out=(\d+) dropped=(\d+)')
                $considered += [int]$m.Groups[1].Value
                $emitted    += [int]$m.Groups[2].Value
                $dropped    += [int]$m.Groups[3].Value
            }
            $after = Get-ScState 'combat-after'
            # POSITIVE first: the wire has to have carried something, or every claim
            # below it is about an empty wire.
            Assert-That "the live buildings were put on the wire (out=$emitted)" ($emitted -gt 0)
            Assert-That "the dead buildings were dropped from it (dropped=$dropped)" ($dropped -gt 0)
            # The fan-out's own accounting, summed over the same lines: every member of the
            # selection it looked at either went out or was refused, none silently
            # forgotten. A per-line identity, so it holds however many chunks the turn
            # budget lets out before the rest defer.
            Assert-That "every building it considered was either emitted or dropped ($considered = $emitted + $dropped)" `
                ($considered -eq $emitted + $dropped)
            # The forensics line names the unit AND the term that refused it, so "it was
            # dropped" and "it was dropped for the right reason" are different claims.
            $forensics = @($lines | Select-String -Pattern 'FANOUT stale drop: unit=0x[0-9A-F]+ .* why=(hp0|removed|recycled)')
            Assert-That 'and each drop named which term refused it' ($forensics.Count -gt 0) `
                ($forensics.Count -gt 0 ? "($($forensics[0].Line.Trim()))" : '')
            Assert-That 'the game survived commanding a selection with a dead building in it' `
                ($null -ne (Get-Process -Id $gamePid -ErrorAction SilentlyContinue))
            Write-Host "       $($after.Line)"
            Shot 'combat-after'
        }
    }
    else {
        Step "a box over $TURRET_COUNT same-type buildings selects all $TURRET_COUNT" {
            $mark = Get-ScLogLineCount -LogPath $LogPath
            $aimed = Select-ScUnitsByMap -Units $script:turrets -TileX $turretTile.X -TileY $turretTile.Y -Tag 'aim-turrets'
            Assert-That 'the turret block is on screen and was boxed' $aimed
            $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

            $bg = @($lines | Select-String -Pattern 'BGROUP box: lead=0x[0-9A-Fa-f]+ type=(\d+) owner=(\d+) flags=0x([0-9A-Fa-f]+) -> selected (\d+)')
            Assert-That "the plugin grew the engine's one building into a group" ($bg.Count -gt 0)
            if ($bg.Count -gt 0) {
                Write-Host "       $($bg[-1].Line.Trim())"
                $m = [regex]::Match($bg[-1].Line, 'type=(\d+) owner=(\d+) flags=0x([0-9A-Fa-f]+) -> selected (\d+)')
                Assert-That "  it grouped the turret type ($($m.Groups[1].Value))" `
                    ([int]$m.Groups[1].Value -eq $TURRET_ID)
                # The units.dat flags for that type, read out of the LIVE game: this is
                # what makes 0x00664080 the flags table rather than an inherited claim,
                # and bit 0x01 (Building) is the bit the gate refused it for.
                $flags = [Convert]::ToUInt32($m.Groups[3].Value, 16)
                Assert-That "  and that type carries the units.dat BUILDING flag (0x$($m.Groups[3].Value))" `
                    (($flags -band 0x1) -ne 0)
            }

            $script:boxed = Get-ScState 'turrets'
            Assert-That "the selection holds all $TURRET_COUNT ($($boxed.N))" ($boxed.N -eq $TURRET_COUNT)
            Assert-ScAllOneType 'the boxed buildings' $boxed $TURRET_TYPE
            Assert-That "the engine itself still holds only twelve ($($boxed.Visible))" ($boxed.Visible -eq 12)
            Assert-That "the rest are past its cap ($($boxed.Overflow))" `
                ($boxed.Overflow -eq $TURRET_COUNT - 12)
            Assert-That "the simulation holds ONE building at a time (simSlots=$($boxed.SimSlots))" `
                ($boxed.SimSlots -eq 1)
            Write-Host "       $($boxed.Line)"
            Shot 'sixteen-buildings'
        }

        Step "every one of the $TURRET_COUNT has a selection circle" {
            # Per building, from its OWN sprite flag 0x01 -- the bit that says a circle
            # image (0x231..0x23A) is attached. The ENGINE sets it for the twelve it selects
            # and sc_circles for the four past the cap, so this one number covers both
            # halves and is not satisfied by "our share is circled".
            Assert-That "all $TURRET_COUNT buildings are circled ($($boxed.Circled)/$($boxed.CircledOf))" `
                ($boxed.Circled -eq $TURRET_COUNT -and $boxed.CircledOf -eq $TURRET_COUNT)
            $show = @(Get-Content -LiteralPath $LogPath |
                      Select-String -Pattern 'CIRCLES show: (\d+)/(\d+) units circled')
            Assert-That 'the plugin circled the ones past the cap' ($show.Count -gt 0)
            if ($show.Count -gt 0) {
                $m = [regex]::Match($show[-1].Line, 'CIRCLES show: (\d+)/(\d+)')
                Assert-That "  it attached every one it tried ($($m.Groups[1].Value)/$($m.Groups[2].Value))" `
                    ($m.Groups[1].Value -eq $m.Groups[2].Value)
                Assert-That "  and that is the over-cap count ($($m.Groups[1].Value) vs $($boxed.Overflow))" `
                    ([int]$m.Groups[1].Value -eq $boxed.Overflow)
            }
        }

        Step "one right-click rallies all $BARRACKS_COUNT Barracks" {
            $aimed = Select-ScUnitsByMap -Units $script:barracks -TileX $barracksTile.X -TileY $barracksTile.Y -Tag 'aim-barracks'
            Assert-That 'the barracks block is on screen and was boxed' $aimed
            $before = Get-ScState 'barracks'
            Assert-That "the box holds all $BARRACKS_COUNT Barracks ($($before.N))" ($before.N -eq $BARRACKS_COUNT)
            Assert-ScAllOneType 'the boxed buildings' $before $BARRACKS_TYPE
            Assert-That "the engine holds all $BARRACKS_COUNT of them ($($before.Visible))" `
                ($before.Visible -eq $BARRACKS_COUNT)
            Assert-That "the simulation still holds ONE at a time (simSlots=$($before.SimSlots))" `
                ($before.SimSlots -eq 1)
            Write-Host "       $($before.Line)"
            Shot 'six-barracks'

            $mark = Get-ScLogLineCount -LogPath $LogPath
            # A point clear of the block itself, in the top-left of the battlefield. What
            # matters is that it is ONE point and every building must end up carrying it.
            Send-ScClick -Hwnd $hwnd -X 60 -Y 40 -Right
            Start-Sleep -Seconds 3
            $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

            $start = @($lines | Select-String -Pattern 'FANOUT start: cmd=0x14 .* units=(\d+) .* slots=(\d+) -> (\d+) Select\+order pairs')
            Assert-That 'the right-click was fanned out' ($start.Count -gt 0)
            if ($start.Count -gt 0) {
                Write-Host "       $($start[-1].Line.Trim())"
                $m = [regex]::Match($start[-1].Line, 'units=(\d+) .* slots=(\d+) -> (\d+) Select')
                Assert-That "  one Select per building ($($m.Groups[3].Value) pairs for $($m.Groups[1].Value) units)" `
                    ([int]$m.Groups[3].Value -eq $BARRACKS_COUNT)
                Assert-That "  because the sim holds one at a time (slots=$($m.Groups[2].Value))" `
                    ([int]$m.Groups[2].Value -eq 1)
            }
            Assert-That 'every pair went out' (@($lines | Select-String -Pattern 'FANOUT done').Count -gt 0)

            $after = Get-ScState 'rallied'
            # THE ASSERTION. One rally bucket covering every live building: the histogram
            # key is the packed (x << 16) | y each building carries in CUnit+0xF8/+0xFA, so
            # a fan-out that reached four of six shows up as two buckets rather than as a
            # smaller total. `before` is the same read taken ahead of the click, so "they
            # were already rallied there" is ruled out rather than assumed.
            $nowKeys = @($after.Rally.Keys)
            Assert-That "the rally point changed (was [$($before.RallyText)], now [$($after.RallyText)])" `
                ($after.RallyText -ne $before.RallyText)
            Assert-That "every one of the $BARRACKS_COUNT is rallied to the SAME point (buckets: $($nowKeys.Count))" `
                ($nowKeys.Count -eq 1 -and $after.Rally[$nowKeys[0]] -eq $after.Live -and
                 $after.Live -eq $BARRACKS_COUNT) `
                "(got $($after.RallyText) over $($after.Live) live)"
            Write-Host "       $($after.Line)"
            Shot 'rallied'
        }

        Step 'a MIXED-BUILDING box selects one type, and only one' {
            # Vanilla picks one building out of a mixed box, arbitrarily; the feature keeps
            # THAT choice and widens it to that building's type, so the outcome is
            # vanilla's lead plus its siblings and never a second arbitrary rule of ours.
            # Which type wins is whatever vanilla alone would select, so the assertion is
            # "exactly one type, and more than one of it", not a fixed type.
            $aimed = Select-ScUnitsByMap -Units $script:mixedUnits -TileX $midTile.X -TileY $midTile.Y -Tag 'aim-mixed'
            Assert-That 'both building types are on screen and were boxed together' $aimed
            $mixed = Get-ScState 'mixed'
            $only = @($mixed.Types.Keys)
            Assert-That "the mixed box selected exactly ONE building type ($($mixed.TypesText))" `
                ($only.Count -eq 1)
            Assert-That '  and it is one of the two types on the map' `
                ($only.Count -eq 1 -and ($only[0] -eq $TURRET_TYPE -or $only[0] -eq $BARRACKS_TYPE))
            Assert-That "  and more than one of them was selected ($($mixed.N))" ($mixed.N -gt 1)
            Write-Host "       $($mixed.Line)"
            Shot 'mixed-box'
        }

        Step 'a single CLICK on a building still selects exactly one' {
            # SortAllUnits is called with `clicked != 0` on every click path and the feature
            # refuses to touch those, so this must stay stock. Asserted, because "only the
            # drag box changed" is a claim about a branch nobody can see from outside.
            $aimed = Select-ScUnitsByMap -Units $script:barracks -TileX $barracksTile.X -TileY $barracksTile.Y -Tag 'aim-click'
            Assert-That 'the barracks block is on screen and was boxed' $aimed
            $boxedAgain = Get-ScState 'before-click'
            Assert-That "the box selected $BARRACKS_COUNT first ($($boxedAgain.N))" `
                ($boxedAgain.N -eq $BARRACKS_COUNT)
            # Aimed at a REAL barracks, converted from its map position through the viewport
            # origin the box above just read: a click that lands on empty ground clears the
            # selection and would pass this step for the wrong reason.
            $target = $script:barracks | Select-Object -First 1
            $cx = $target.X - $script:lastScreen.Left
            $cy = $target.Y - $script:lastScreen.Top
            Write-Host "       (clicking the barracks at client ($cx,$cy))"
            Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
            Start-Sleep -Seconds 2
            $clicked = Get-ScState 'clicked'
            Assert-That "a click selects exactly one building ($($clicked.N))" ($clicked.N -eq 1)
            Assert-That '  and the engine holds that one' ($clicked.Visible -eq 1)
            Write-Host "       $($clicked.Line)"
            Shot 'single-click'
        }
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
    # Only this run's own declared fixture, on every path, and only an EMPTY folder -- an
    # empty folder of ours still pushes every browser row below it down for everyone else.
    Remove-ScOwnFixture -Run $fixtures
    Remove-ScOwnFixtureDir -Dir $mapDir
}

Write-Host ''
Write-Host '[final] the run must balance'
$stats = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
           Select-String -Pattern 'CIRCLES stats:.* shown=(\d+) hidden=(\d+) held=(-?\d+) skipped=(\d+) noImage=(\d+) lost=(\d+)')
if ($stats.Count -eq 0) {
    Assert-That 'a CIRCLES stats line was written on detach' $false
}
else {
    $m = [regex]::Match($stats[-1].Line, 'shown=(\d+) hidden=(\d+) held=(-?\d+) skipped=(\d+) noImage=(\d+) lost=(\d+)')
    Write-Host "  $($stats[-1].Line.Trim())"
    Assert-That "the circle accounting balances ($($m.Groups[1].Value) = $($m.Groups[2].Value) detached + $($m.Groups[3].Value) held)" `
        ([int]$m.Groups[1].Value -eq [int]$m.Groups[2].Value + [int]$m.Groups[3].Value)
    Assert-That 'no circle was lost to a stale unit or sprite' ([int]$m.Groups[6].Value -eq 0)
    Assert-That 'the image free list never ran out' ([int]$m.Groups[5].Value -eq 0)
}

$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'this run left no fixture behind' (-not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-building-groups [$arm]: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
