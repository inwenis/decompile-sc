#Requires -Version 7
<#
.SYNOPSIS
Building-group selection by double-click, ctrl-click, shift-click and control-group recall.

.DESCRIPTION
unit_IsStandardAndMovable (0x0047B770) gates every selection path, not only the drag box:
SortAllUnits 0x0046F0F0 at 0x0046F1A3 (double/ctrl-click), the click handler 0x0046FB40 at
0x0046FD27/0x0046FD44 (shift-click ADD), combineSelectionsLists 0x0046F290 at
0x0046F2C8/0x0046F2E8 (shift+box), and the SIM gate 0x0049AF80 that caps the control-group
row at one (research/building-groups.md 8). Three arms, one launch each: -Measure reports
every layer, asserting only the fixture and that each input reached the engine; the default
asserts the feature; -Stock (%SCPLUGIN_BUILDING_GROUPS%=0) proves the same inputs select ONE
building, so the feature arm has something to fail against (AGENTS.md "Absence assertions
must first be proved positive"). Fixture, generated per run and deleted after (AGENTS.md hard
rule 1): 6 Barracks plus 6 Marines for the mixed arm, both human-owned. Barracks because a
production building takes a plain right-click order (a Missile Turret takes none); six because
eight at 128 px span 304 client px vertically plus box margin and the battlefield ends at
y=340 with the camera centred, and six is under the engine's twelve so "the ENGINE holds all
of them" is assertable.

.EXAMPLE
./tools/plugin/test-building-parity.ps1 -Measure

.EXAMPLE
./tools/plugin/test-building-parity.ps1

.EXAMPLE
./tools/plugin/test-building-parity.ps1 -Stock
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath,
    [string]$ShotDir = 'C:\sc-work\logs\036-building-parity-frames',
    [string]$FixtureDir,
    # The BEFORE measurement: report every layer, assert almost nothing.
    [switch]$Measure,
    # The control arm: the feature switched off at plugin-install time.
    [switch]$Stock,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
if ($Measure -and $Stock) { throw 'test: -Measure and -Stock are separate arms; pass one.' }
$arm = if ($Measure) { 'measure' } elseif ($Stock) { 'stock' } else { 'feature' }
if (-not $LogPath) { $LogPath = "C:\sc-work\logs\036-building-parity-$arm.log" }

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-oracle-guard.ps1')

$failures = 0
$step = 0

# Pinned ids, asserted rather than reported.
#   BARRACKS units.dat 111 (0x6F), 4x3 tiles, a PRODUCTION building -- it fails
#            unit_IsStandardAndMovable on the units.dat Building flag (0x01) and it is
#            not in unit_isUnselectable's list, so vanilla selects exactly one.
#   MARINE   units.dat 0 (0x00). The mixed arm's units.
$BARRACKS_ID    = 111
$BARRACKS_TYPE  = '0x6F'
$MARINE_TYPE    = '0x00'
$BARRACKS_COUNT = 6
$MARINE_COUNT   = 6
$GROUP          = 1     # the control group this suite drives

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

# The measurement arm REPORTS where the feature arm ASSERTS. Same call sites, so the two
# arms cannot drift apart, and a measurement run can never be read as a passing test.
function Assert-Feature {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($script:Measure) { Write-Host "  ---- (measure) $What -> $(if ($Ok) { 'yes' } else { 'NO' }) $Detail" }
    else { Assert-That $What $Ok $Detail }
}

function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    & $Body
}

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-ScState {
    param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec
}

# THE THREE-LAYER READ. `client` is clientSelectionGroup (0x00597208), what the STOCK
# status row draws; `active` is activePlayerSelection (0x006284B8), the client's own
# selection; `sim` is playersSelections[player] (0x006284E8), what the simulation holds
# and what every order applier iterates. A symptom does not say which of the three
# refused; these three numbers do (research/building-groups.md 2-3).
function Get-ScSelSnap {
    param([string]$Tag)
    $line = @(Get-Content -LiteralPath $script:LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern ([regex]::Escape("SELSNAP [$Tag]"))) | Select-Object -Last 1
    if (-not $line) { throw "test: no SELSNAP line for marker '$Tag' -- needs the task-036 build." }
    $m = [regex]::Match($line.Line,
        'client=(\d+) clientCount=(\d+) active=(\d+) sim=(\d+)')
    if (-not $m.Success) { throw "test: could not parse SELSNAP: $($line.Line)" }
    # The POINTERS the engine holds, not only how many: a step that must click a unit the
    # engine has selected picks from these. Format matches Get-ScWorldState's `unit=0x...`
    # so the two intersect.
    $ptrLine = @(Get-Content -LiteralPath $script:LogPath -ErrorAction SilentlyContinue |
                 Select-String -Pattern 'SELSNAP activePlayerSelection') | Select-Object -Last 1
    $ptrs = @()
    if ($ptrLine) {
        $ptrs = @([regex]::Matches($ptrLine.Line, '=0x([0-9A-Fa-f]{8})') |
                  ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() })
    }
    [pscustomobject]@{
        Client = [int]$m.Groups[1].Value; ClientCount = [int]$m.Groups[2].Value
        Active = [int]$m.Groups[3].Value; Sim = [int]$m.Groups[4].Value
        Units  = $ptrs
        Line   = $line.Line.Trim()
    }
}

# One read, both oracles, one marker: the plugin's shadow list AND the engine's three
# arrays at the same instant (scplugin.cpp PollMarker writes SELSNAP and UNITSTATE off
# the one trigger).
function Read-ScBoth {
    param([string]$Tag, [int]$TimeoutSec = 15)
    $u = Get-ScState $Tag $TimeoutSec
    # Get-ScUnitState appends "-<seq>" to the tag it writes into the marker; recover it
    # from the line it just matched so both reads name the same instant.
    $label = [regex]::Match($u.Line, 'UNITSTATE \[([^\]]*)\]').Groups[1].Value
    $s = Get-ScSelSnap $label
    [pscustomobject]@{ Unit = $u; Sel = $s; Label = $label }
}

function Show-Both {
    param($Both, [string]$What)
    Write-Host "       $What"
    Write-Host "         shadow: $($Both.Unit.Line)"
    Write-Host "         engine: $($Both.Sel.Line)"
}

function Assert-ScAllOneType {
    param([string]$What, $State, [string]$ExpectedType)
    $only = @($State.Types.Keys)
    $ok = ($only.Count -eq 1) -and ($State.Types[$only[0]] -eq $State.Live) -and
          ($only[0] -eq $ExpectedType)
    Assert-Feature "$What`: all $($State.Live) are $ExpectedType" $ok "(got $($State.TypesText))"
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] arm=$arm   StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-testmap' -Suite 'building-parity' }
$mapDir = $FixtureDir
$mapName = 'building-parity.scx'
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

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

# Centre on a block and remember the viewport, so every later click is aimed at a REAL
# unit through its map position. A hardcoded client point is the defect that cost six
# runs in one day.
function Set-ScView {
    param(
        [Parameter(Mandatory)][int]$TileX, [Parameter(Mandatory)][int]$TileY,
        [string]$Tag = 'aim', [int]$MapW = 128, [int]$MapH = 96
    )
    $p = Get-ScMinimapPoint -MapTilesW $MapW -MapTilesH $MapH -TileX $TileX -TileY $TileY
    Send-ScClick -Hwnd $script:hwnd -X $p.X -Y $p.Y
    Start-Sleep -Milliseconds 800
    $w = Get-ScWorldState -LogPath $script:LogPath -Tag $Tag -MarkerPath $script:markerPath
    if (-not $w.Screen) { throw 'test: the plugin did not report the viewport origin.' }
    $script:lastScreen = $w.Screen
    return $w
}

# Map position -> client pixel, through the viewport origin the plugin just reported.
function Get-ScClientPoint {
    param([Parameter(Mandatory)]$Unit)
    [pscustomobject]@{
        X = $Unit.X - $script:lastScreen.Left
        Y = $Unit.Y - $script:lastScreen.Top
    }
}

function Test-ScOnBattlefield {
    param([Parameter(Mandatory)]$Point)
    ($Point.X -ge 4 -and $Point.Y -ge 4 -and $Point.X -le 636 -and $Point.Y -le 340)
}

function Select-ScUnitsByMap {
    param([Parameter(Mandatory)][object[]]$Units, [int]$Margin = 24)
    $x1 = ($Units | Measure-Object X -Minimum).Minimum - $script:lastScreen.Left - $Margin
    $x2 = ($Units | Measure-Object X -Maximum).Maximum - $script:lastScreen.Left + $Margin
    $y1 = ($Units | Measure-Object Y -Minimum).Minimum - $script:lastScreen.Top  - $Margin
    $y2 = ($Units | Measure-Object Y -Maximum).Maximum - $script:lastScreen.Top  + $Margin
    if ($x1 -lt 4 -or $y1 -lt 4 -or $x2 -gt 636 -or $y2 -gt 340) {
        Write-Host "       (block at client [$x1,$y1]-[$x2,$y2] is not fully on the battlefield)"
        return $false
    }
    Write-Host "       (boxing client [$x1,$y1]-[$x2,$y2])"
    Send-ScDrag -Hwnd $script:hwnd -X1 $x1 -Y1 $y1 -X2 $x2 -Y2 $y2 -Steps 20
    Start-Sleep -Seconds 2
    return $true
}

# A DOUBLE CLICK, posted. The engine's double-click state is one global, DAT_0066FF58,
# written only by the mouse-event tick (0x0046FF70) when the event type at +0xC is 6 --
# the type the window procedure hands to 0x004D1A50 for WM_LBUTTONDBLCLK (0x203) -- so
# posting that message IS the double click above the window procedure. The click handler
# then requires the clicked unit to be ALREADY SELECTED (sprite flags & 8, 0x0046FB6E),
# so the ordinary click comes first; that is also the order Windows delivers.
function Send-ScDoubleClick {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][int]$X,
          [Parameter(Mandatory)][int]$Y, [int]$SettleMs = 1200)
    Send-ScClick -Hwnd $Hwnd -X $X -Y $Y -SettleMs 400
    $lp = ConvertTo-ScLParam $X $Y
    [void][ScDrive.Native]::PostMessage($Hwnd, 0x0203, [IntPtr]0x0001, $lp)   # WM_LBUTTONDBLCLK, MK_LBUTTON
    Start-Sleep -Milliseconds 60
    [void][ScDrive.Native]::PostMessage($Hwnd, 0x0202, [IntPtr]0, $lp)        # WM_LBUTTONUP
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
}

# Everything this suite reads about the client funnel, per input: how many candidates the
# engine was handed, what its OWN SortAllUnits returned, and what the plugin made of it.
function Get-ScSortLines {
    param([int]$Mark)
    @(Get-Content -LiteralPath $script:LogPath | Select-Object -Skip $Mark |
      Select-String -Pattern 'SORT candidates=(\d+) clicked=0x([0-9A-Fa-f]+) -> engine=(\d+) selected=(\d+)')
}

function Show-SortLines {
    # @() on the way in: a single Select-String match arrives as a SCALAR (PowerShell
    # unrolls a one-element array through a parameter) and `.Count` on it throws.
    param($Lines, [string]$What)
    $l = @($Lines)
    if ($l.Count -eq 0) { Write-Host "       $What`: NO SortAllUnits call reached the client funnel" }
    else { foreach ($one in $l) { Write-Host "       $What`: $($one.Line.Trim())" } }
}

try {
    Step "generate the fixture: $mapName" {
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $BARRACKS_COUNT -UnitType "$BARRACKS_ID" -Player 0 `
            -GridSpacing 128 -Race terran -OutputPath $mapPath `
            -EnemyCount $MARINE_COUNT -EnemyType marine -EnemyOwner player -EnemyRace terran `
            -EnemyOffsetX 512 -EnemyOffsetY 0 -EnemySpacing 48 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'nothing can end the game on its own (TRIG is empty)' `
            (@($gen | Select-String -Pattern 'TRIG holds 0 byte').Count -gt 0)
    }

    $groups = if ($Stock) { '0' } else { '1' }
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -Circles 1 -HudRow 1 -WorldScan 1 -BuildingGroups $groups `
        -InjectWindowedHelper WMode -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'the plugin came up in the configuration this arm asked for' {
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
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2      # Use Map Settings, verified
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step 'the map spawned what it was asked to, and this is where it is' {
        $world = Get-ScWorldState -LogPath $LogPath -Tag 'world' -MarkerPath $markerPath
        $mine = @($world.Units | Where-Object { $_.Owner -eq 0 })
        $script:barracks = @($mine | Where-Object { $_.Type -eq $BARRACKS_ID })
        $script:marines  = @($mine | Where-Object { $_.Type -eq 0 })
        Assert-That "all $BARRACKS_COUNT Barracks were placed ($($script:barracks.Count))" `
            ($script:barracks.Count -eq $BARRACKS_COUNT)
        Assert-That "all $MARINE_COUNT Marines were placed ($($script:marines.Count))" `
            ($script:marines.Count -eq $MARINE_COUNT)
        Assert-That "the player owns nothing else ($($mine.Count) in total)" `
            ($mine.Count -eq $BARRACKS_COUNT + $MARINE_COUNT)
        if ($script:barracks.Count -eq 0) { throw 'test: no barracks placed -- nothing below can be interpreted.' }
        $script:barracksTile = [pscustomobject]@{
            X = [int]((($script:barracks | Measure-Object X -Average).Average) / 32)
            Y = [int]((($script:barracks | Measure-Object Y -Average).Average) / 32)
        }
        $script:marineTile = [pscustomobject]@{
            X = [int]((($script:marines | Measure-Object X -Average).Average) / 32)
            Y = [int]((($script:marines | Measure-Object Y -Average).Average) / 32)
        }
        Write-Host "       barracks centred on tile ($($script:barracksTile.X),$($script:barracksTile.Y)), marines on ($($script:marineTile.X),$($script:marineTile.Y))"
        Assert-That 'the two blocks are more than a screen-half apart' `
            ([math]::Abs($script:barracksTile.X - $script:marineTile.X) * 32 -gt 320)
    }

    # ---------------------------------------------------------------------------
    # BASELINE: the drag box, in every arm. Every later step needs a building group to
    # start from, and the box must keep working alongside the click paths.
    # ---------------------------------------------------------------------------
    Step "BOX (task 024, the regression guard): a box over $BARRACKS_COUNT Barracks" {
        Set-ScView -TileX $script:barracksTile.X -TileY $script:barracksTile.Y -Tag 'aim-box' | Out-Null
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $aimed = Select-ScUnitsByMap -Units $script:barracks
        Assert-That 'the barracks block is on screen and was boxed' $aimed
        # A hard stop, not a soft failure: every later step starts from this selection, and
        # a run that carried on would report a stale one as if it were the step's own result.
        if (-not $aimed) { throw 'test: the barracks block is not fully on the battlefield -- nothing below can be interpreted.' }
        Show-SortLines (Get-ScSortLines $mark) 'box'
        $b = Read-ScBoth 'box'
        Show-Both $b 'after the box'
        if ($Stock) {
            Assert-That "vanilla selects exactly one building ($($b.Unit.N))" ($b.Unit.N -eq 1)
            Assert-That "  and the engine's own client array holds one ($($b.Sel.Active))" ($b.Sel.Active -eq 1)
        }
        else {
            Assert-Feature "the box selects all $BARRACKS_COUNT ($($b.Unit.N))" ($b.Unit.N -eq $BARRACKS_COUNT)
            Assert-ScAllOneType '  the boxed buildings' $b.Unit $BARRACKS_TYPE
            Assert-Feature "  the engine's own client array holds all $BARRACKS_COUNT ($($b.Sel.Active))" `
                ($b.Sel.Active -eq $BARRACKS_COUNT)
            Assert-Feature "  and the status row's array holds all $BARRACKS_COUNT ($($b.Sel.Client))" `
                ($b.Sel.Client -eq $BARRACKS_COUNT)
            Assert-Feature "  while the SIMULATION holds one (sim=$($b.Sel.Sim), simSlots=$($b.Unit.SimSlots))" `
                ($b.Sel.Sim -eq 1 -and $b.Unit.SimSlots -eq 1)
        }
        Shot 'box'
    }

    # ---------------------------------------------------------------------------
    # PATH 1 -- DOUBLE CLICK
    # ---------------------------------------------------------------------------
    Step 'PATH 1 -- DOUBLE-CLICK a Barracks' {
        # Click empty ground first, away from both blocks, so Send-ScDoubleClick's leading
        # click is what selects the target (the double click's own precondition).
        Send-ScClick -Hwnd $hwnd -X 20 -Y 20
        Start-Sleep -Milliseconds 500
        $target = $script:barracks | Select-Object -First 1
        $p = Get-ScClientPoint $target
        Assert-That "the target Barracks is on the battlefield at client ($($p.X),$($p.Y))" (Test-ScOnBattlefield $p)
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDoubleClick -Hwnd $hwnd -X $p.X -Y $p.Y
        $sort = @(Get-ScSortLines $mark)
        Show-SortLines $sort 'double-click'
        # THE MEASUREMENT THAT SEPARATES THE THREE DIAGNOSES. A SortAllUnits call with a
        # non-zero `clicked` is the client funnel being asked; no line at all would mean
        # the double click never reached the handler, which is a different bug entirely.
        Assert-That 'the double click reached the client selection funnel' ($sort.Count -gt 0) `
            '(no SORT line -- the engine never ran SortAllUnits for it)'
        if ($sort.Count -gt 0) {
            $m = [regex]::Match($sort[-1].Line, 'clicked=0x([0-9A-Fa-f]+) -> engine=(\d+) selected=(\d+)')
            Assert-That "  and it went through the CLICK path, not the box (clicked=0x$($m.Groups[1].Value))" `
                ($m.Groups[1].Value -ne '00000000')
            Write-Host "       (the engine's own SortAllUnits returned $($m.Groups[2].Value); the plugin returned $($m.Groups[3].Value))"
        }
        $b = Read-ScBoth 'dblclick'
        Show-Both $b 'after the double click'
        if ($Stock) {
            Assert-That "with the feature off a double click selects ONE building ($($b.Unit.N))" ($b.Unit.N -eq 1)
        }
        else {
            Assert-Feature "a double click selects all $BARRACKS_COUNT same-type buildings ($($b.Unit.N))" `
                ($b.Unit.N -eq $BARRACKS_COUNT)
            Assert-ScAllOneType '  the selected buildings' $b.Unit $BARRACKS_TYPE
            Assert-Feature "  the engine's own client array holds all $BARRACKS_COUNT ($($b.Sel.Active))" `
                ($b.Sel.Active -eq $BARRACKS_COUNT)
        }
        Shot 'double-click'
    }

    # ---------------------------------------------------------------------------
    # PATH 2 -- CTRL-CLICK (the other caller of the same type-match funnel)
    # ---------------------------------------------------------------------------
    Step 'PATH 2 -- CTRL-CLICK a Barracks' {
        Send-ScClick -Hwnd $hwnd -X 20 -Y 20
        Start-Sleep -Milliseconds 500
        $target = $script:barracks | Select-Object -First 1
        $p = Get-ScClientPoint $target
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -Ctrl -SettleMs 1200
        $sort = @(Get-ScSortLines $mark)
        Show-SortLines $sort 'ctrl-click'
        Assert-That 'the ctrl click reached the client selection funnel' ($sort.Count -gt 0) `
            '(no SORT line -- the modifier did not reach the engine, see research/control-groups.md 5.1)'
        $b = Read-ScBoth 'ctrlclick'
        Show-Both $b 'after the ctrl click'
        if ($Stock) {
            Assert-That "with the feature off a ctrl click selects ONE building ($($b.Unit.N))" ($b.Unit.N -eq 1)
        }
        else {
            Assert-Feature "a ctrl click selects all $BARRACKS_COUNT same-type buildings ($($b.Unit.N))" `
                ($b.Unit.N -eq $BARRACKS_COUNT)
            Assert-ScAllOneType '  the selected buildings' $b.Unit $BARRACKS_TYPE
        }
        Shot 'ctrl-click'
    }

    # ---------------------------------------------------------------------------
    # PATH 3 -- SHIFT-CLICK, add and remove
    # ---------------------------------------------------------------------------
    Step 'PATH 3a -- SHIFT-CLICK ADDS a Barracks to a one-building selection' {
        $first  = $script:barracks | Select-Object -First 1
        $second = $script:barracks | Select-Object -Skip 1 -First 1
        $p1 = Get-ScClientPoint $first
        $p2 = Get-ScClientPoint $second
        Assert-That 'both target Barracks are on the battlefield' `
            ((Test-ScOnBattlefield $p1) -and (Test-ScOnBattlefield $p2))
        Send-ScClick -Hwnd $hwnd -X $p1.X -Y $p1.Y -SettleMs 800
        $before = Read-ScBoth 'shift-before'
        Show-Both $before 'one building clicked'
        Assert-That "a plain click selects exactly one building ($($before.Unit.N))" ($before.Unit.N -eq 1)

        Send-ScClick -Hwnd $hwnd -X $p2.X -Y $p2.Y -Shift -SettleMs 1200
        $after = Read-ScBoth 'shift-add'
        Show-Both $after 'after the shift-click'
        if ($Stock) {
            Assert-That "with the feature off shift-click adds nothing ($($after.Unit.N))" ($after.Unit.N -eq 1)
        }
        else {
            Assert-Feature "shift-click added the second building (now $($after.Unit.N))" ($after.Unit.N -eq 2)
            Assert-Feature "  the engine's own client array holds both ($($after.Sel.Active))" ($after.Sel.Active -eq 2)
            Assert-ScAllOneType '  the two selected' $after.Unit $BARRACKS_TYPE
        }
        Shot 'shift-add'
    }

    Step 'PATH 3b -- SHIFT-CLICK REMOVES a building from the selection' {
        # Vanilla already allows this (0x0046FB40's remove branch at 0x0046FD77 consults
        # no movable gate at all), so it is a REGRESSION check, not a new feature -- and
        # it must hold in every arm.
        Assert-That 'the barracks block is on screen and was boxed' `
            (Select-ScUnitsByMap -Units $script:barracks)
        $before = Read-ScBoth 'remove-before'
        Show-Both $before 'boxed'
        # Aim at a building the ENGINE is holding. In the stock arm the box leaves vanilla's
        # own arbitrary one selected, and shift-clicking any OTHER building takes the add
        # branch -- "the first barracks in the fixture" measures the wrong branch in
        # exactly the arm that exists to be the control.
        $target = $script:barracks | Where-Object { $before.Sel.Units -contains $_.Unit.ToUpperInvariant() } |
                  Select-Object -First 1
        Assert-That "a selected building was found to shift-click off (engine holds $($before.Sel.Units.Count))" `
            ($null -ne $target) "(engine=[$($before.Sel.Units -join ' ')])"
        if (-not $target) { throw 'test: could not identify a selected building to remove.' }
        $p = Get-ScClientPoint $target
        Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -Shift -SettleMs 1200
        $after = Read-ScBoth 'remove-after'
        Show-Both $after 'after shift-clicking a selected building'
        Assert-Feature "shift-click removed exactly one ($($before.Unit.N) -> $($after.Unit.N))" `
            ($after.Unit.N -eq $before.Unit.N - 1)
        Shot 'shift-remove'
    }

    Step 'PATH 3c -- SHIFT+BOX extends a building group' {
        $split = [int]($BARRACKS_COUNT / 2)
        $half  = @($script:barracks | Select-Object -First $split)
        $rest  = @($script:barracks | Select-Object -Skip $split)
        Assert-That 'the first half was boxed' (Select-ScUnitsByMap -Units $half)
        $before = Read-ScBoth 'shiftbox-before'
        Show-Both $before 'first half boxed'
        # A shift-held drag over the rest. Send-ScDrag posts no modifier of its own, so
        # the modifier is bracketed here the way Send-ScClick does it -- the engine tracks
        # keys in its OWN keyDown table (0x00596A18) from the messages, and 0x0046FA40
        # reads 0x00596A28 (VK_SHIFT) out of it.
        $x1 = ($rest | Measure-Object X -Minimum).Minimum - $script:lastScreen.Left - 24
        $x2 = ($rest | Measure-Object X -Maximum).Maximum - $script:lastScreen.Left + 24
        $y1 = ($rest | Measure-Object Y -Minimum).Minimum - $script:lastScreen.Top  - 24
        $y2 = ($rest | Measure-Object Y -Maximum).Maximum - $script:lastScreen.Top  + 24
        [void][ScDrive.Native]::PostMessage($hwnd, 0x0100, [IntPtr]0x10, [IntPtr]0x002A0001)  # VK_SHIFT down
        Start-Sleep -Milliseconds 60
        Send-ScDrag -Hwnd $hwnd -X1 $x1 -Y1 $y1 -X2 $x2 -Y2 $y2 -Steps 20
        [void][ScDrive.Native]::PostMessage($hwnd, 0x0101, [IntPtr]0x10, [IntPtr]0xC02A0001)  # VK_SHIFT up
        Start-Sleep -Seconds 2
        $after = Read-ScBoth 'shiftbox-after'
        Show-Both $after 'after the shift+box'
        if ($Stock) {
            Assert-That "with the feature off the shift+box changed nothing ($($before.Unit.N) -> $($after.Unit.N))" `
                ($after.Unit.N -le $before.Unit.N)
        }
        else {
            Assert-Feature "the shift+box extended the group to all $BARRACKS_COUNT ($($before.Unit.N) -> $($after.Unit.N))" `
                ($after.Unit.N -eq $BARRACKS_COUNT)
            Assert-ScAllOneType '  the extended group' $after.Unit $BARRACKS_TYPE
        }
        Shot 'shift-box'
    }

    # ---------------------------------------------------------------------------
    # THE MIXED DECISION (research/building-groups.md 9): a building group is ONE TYPE.
    # Shift-clicking a building onto a selection of UNITS, or a unit onto a building
    # group, stays refused -- which is what vanilla does, so nothing regresses either way.
    # ---------------------------------------------------------------------------
    Step 'MIXED -- shift-clicking a Barracks onto a MARINE selection stays refused' {
        Set-ScView -TileX ([int](($script:barracksTile.X + $script:marineTile.X) / 2)) `
                   -TileY $script:marineTile.Y -Tag 'aim-mixed' | Out-Null
        $onScreen = @($script:marines | Where-Object { Test-ScOnBattlefield (Get-ScClientPoint $_) })
        $barrOnScreen = @($script:barracks | Where-Object { Test-ScOnBattlefield (Get-ScClientPoint $_) })
        Assert-That "both blocks reach the same screen (marines=$($onScreen.Count) barracks=$($barrOnScreen.Count))" `
            ($onScreen.Count -gt 0 -and $barrOnScreen.Count -gt 0)
        if ($onScreen.Count -gt 0 -and $barrOnScreen.Count -gt 0) {
            Assert-That 'the marines were boxed' (Select-ScUnitsByMap -Units $onScreen)
            $before = Read-ScBoth 'mixed-before'
            Show-Both $before 'marines boxed'
            $p = Get-ScClientPoint ($barrOnScreen | Select-Object -First 1)
            Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -Shift -SettleMs 1200
            $after = Read-ScBoth 'mixed-after'
            Show-Both $after 'after shift-clicking a Barracks onto them'
            # THE CLICK HAS TO BE PROVED TO HAVE LANDED. `after.N -eq before.N` is EXACTLY
            # what a click on empty ground produces, and the aim is a world position through
            # a screen transform, the likeliest thing here to go wrong. The refusal itself
            # leaves nothing to read (declined client-side: no selection change, no command
            # out), so the witness is a POSITIVE CONTROL on the same point: click it again
            # WITHOUT shift and a Barracks must come up. It runs after the reading above, so
            # it cannot disturb what it corroborates, and the step ends here (AGENTS.md
            # "Absence assertions must first be proved positive").
            Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -SettleMs 1200
            $probe = Read-ScBoth 'mixed-aimcheck'
            Show-Both $probe 'the same point clicked WITHOUT shift -- the aim control'
            $probeTypes = @($probe.Unit.Types.Keys)
            $hitBarracks = ($probeTypes -contains $BARRACKS_TYPE)
            Assert-That "that point really is a Barracks -- clicked plain, it selects one ($($probe.Unit.TypesText))" `
                $hitBarracks `
                '(without this, a refused mix and a click on empty terrain read identically)'
            Assert-That "the Barracks did NOT join the unit selection ($($before.Unit.N) -> $($after.Unit.N))" `
                (Test-ScWitnessed -Claim ($after.Unit.N -eq $before.Unit.N) -Witness $hitBarracks)
            $types = @($after.Unit.Types.Keys)
            Assert-That '  and the selection is still marines only' `
                ($types.Count -eq 1 -and $types[0] -eq $MARINE_TYPE) "(got $($after.Unit.TypesText))"
        }
        Shot 'mixed'
    }

    # ---------------------------------------------------------------------------
    # PATH 4 -- CONTROL GROUP
    # ---------------------------------------------------------------------------
    Step "PATH 4 -- a control group of $BARRACKS_COUNT Barracks recalls all $BARRACKS_COUNT" {
        Set-ScView -TileX $script:barracksTile.X -TileY $script:barracksTile.Y -Tag 'aim-group' | Out-Null
        Assert-That 'the barracks block is on screen and was boxed' `
            (Select-ScUnitsByMap -Units $script:barracks)
        $boxed = Read-ScBoth 'group-boxed'
        Show-Both $boxed 'boxed, before Ctrl+1'

        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScControlGroupAssign -Hwnd $hwnd -Group $GROUP
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $assign = @($lines | Select-String -Pattern 'GROUP assign: group=(\d+) now holds (\d+)')
        Assert-That 'Ctrl+1 reached the engine and the plugin stored the group' ($assign.Count -gt 0) `
            '(no GROUP assign line -- the accelerator did not fire)'
        if ($assign.Count -gt 0) {
            Write-Host "       $($assign[-1].Line.Trim())"
            $stored = [int][regex]::Match($assign[-1].Line, 'now holds (\d+)').Groups[1].Value
            # The group stores whatever the SELECTION held, so the expectation is per-arm:
            # with the feature off the box selected one building and a group of one is the
            # correct stock outcome. Asserting six here fails the stock arm for the feature
            # working as intended.
            if ($Stock) {
                Assert-That "  with the feature off the group holds the one boxed building ($stored)" `
                    ($stored -eq 1)
            }
            else {
                Assert-Feature "  the plugin stored all $BARRACKS_COUNT ($stored)" ($stored -eq $BARRACKS_COUNT)
            }
        }
        # What the ENGINE stored, read from its own row: the number that lets the recall
        # give back only one, a fact about the simulation gate rather than the plugin.
        $stampedAssign = Read-ScBoth 'group-assigned'
        Show-Both $stampedAssign 'after Ctrl+1'

        # SELECT SOMETHING ELSE, not "clear": a left click on empty ground does NOT deselect
        # in this engine. The click handler returns when resolveClickedUnit finds nothing
        # (0x0046FB4B) and the drag-box handler returns on an empty box (0x0046FA5E), so
        # neither touches the selection; asserting "cleared" after a click at (20,20) reads
        # back all six still selected. Boxing the MARINES is the better precondition anyway:
        # nothing in common with the group, other side of the map, so a recall that did
        # nothing would leave marines behind and be unmistakable.
        Set-ScView -TileX $script:marineTile.X -TileY $script:marineTile.Y -Tag 'aim-elsewhere' | Out-Null
        $elsewhere = @($script:marines | Where-Object { Test-ScOnBattlefield (Get-ScClientPoint $_) })
        Assert-That 'the marines are on screen to select instead' ($elsewhere.Count -gt 0)
        Assert-That 'the marines were boxed' (Select-ScUnitsByMap -Units $elsewhere)
        $cleared = Read-ScBoth 'group-elsewhere'
        Show-Both $cleared 'after selecting something else entirely'
        Assert-That "the selection really moved off the group (now $($cleared.Unit.N) marines)" `
            ($cleared.Unit.Types.ContainsKey($MARINE_TYPE) -and -not $cleared.Unit.Types.ContainsKey($BARRACKS_TYPE))
        # Back to the group's own view, so the recalled buildings are on screen for the
        # circle count and the right-click below.
        Set-ScView -TileX $script:barracksTile.X -TileY $script:barracksTile.Y -Tag 'aim-back' | Out-Null

        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScControlGroupRecall -Hwnd $hwnd -Group $GROUP
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $recall = @($lines | Select-String -Pattern 'GROUP recall: group=(\d+) -> (\d+) unit')
        $enter  = @($lines | Select-String -Pattern 'GROUP recall enter: group=(\d+) activePlayerSelection holds visible=(\d+)')
        Assert-That 'pressing 1 reached the engine and the plugin saw the recall' ($recall.Count -gt 0) `
            '(no GROUP recall line -- the engine queued no 0x13 01)'
        if ($enter.Count -gt 0) {
            $engineGave = [int][regex]::Match($enter[-1].Line, 'visible=(\d+)').Groups[1].Value
            Write-Host "       $($enter[-1].Line.Trim())"
            Write-Host "       (the ENGINE's own recall handed back $engineGave -- its group row is filled from playersSelections, which the sim gate capped)"
        }
        if ($recall.Count -gt 0) { Write-Host "       $($recall[-1].Line.Trim())" }

        $back = Read-ScBoth 'group-recalled'
        Show-Both $back 'after pressing 1'
        if ($Stock) {
            Assert-That "with the feature off the recall brings back ONE ($($back.Sel.Active))" ($back.Sel.Active -eq 1)
        }
        else {
            Assert-Feature "the recall brings back all $BARRACKS_COUNT in the plugin's list ($($back.Unit.N))" `
                ($back.Unit.N -eq $BARRACKS_COUNT)
            # THE USER'S SYMPTOM, as a number. "It only shows 1" is the STOCK STATUS ROW,
            # which draws clientSelectionGroup -- so the row is fixed only if that array
            # holds them all, and the plugin's own shadow count says nothing about it.
            Assert-Feature "  the engine's own client array holds all $BARRACKS_COUNT ($($back.Sel.Active))" `
                ($back.Sel.Active -eq $BARRACKS_COUNT)
            Assert-Feature "  and the STATUS ROW's array holds all $BARRACKS_COUNT ($($back.Sel.Client) / count byte $($back.Sel.ClientCount))" `
                ($back.Sel.Client -eq $BARRACKS_COUNT)
            Assert-ScAllOneType '  the recalled group' $back.Unit $BARRACKS_TYPE
            Assert-Feature "  every one of them is circled ($($back.Unit.Circled)/$($back.Unit.CircledOf))" `
                ($back.Unit.Circled -eq $BARRACKS_COUNT)
        }
        Shot 'group-recalled'

        # AND THE ORDER: a recalled building group must still take one. The rally point is
        # the oracle: one histogram bucket over all of them, and it must have MOVED. One
        # bucket + bucket == live is also true of buildings NEVER RALLIED (every unrallied
        # building carries the same default packed rally value), so the before-reading is
        # captured and the assertion requires a change.
        $rallyBefore = $back.Unit.RallyText
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $hwnd -X 60 -Y 40 -Right
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $start = @($lines | Select-String -Pattern 'FANOUT start: cmd=0x14 .* units=(\d+) .* slots=(\d+)')
        if ($start.Count -gt 0) { Write-Host "       $($start[-1].Line.Trim())" }
        $rallied = Read-ScBoth 'group-rallied'
        Show-Both $rallied 'after one right-click on the recalled group'
        if (-not $Stock) {
            Assert-Feature 'the right-click on the recalled group was fanned out' ($start.Count -gt 0)
            $nowKeys = @($rallied.Unit.Rally.Keys)
            # THE MOVE, asserted separately from the agreement, because they fail for
            # different reasons and a reader needs to know which one happened: no move at
            # all means the right-click never became an order, while a move into more than
            # one bucket means the fan-out reached some of them and not others.
            Assert-Feature "the right-click MOVED the rally point ($rallyBefore -> $($rallied.Unit.RallyText))" `
                (Test-ScChanged -Before $rallyBefore -After $rallied.Unit.RallyText) `
                '(an unrallied group is also one bucket -- without this the agreement below passes for a click that did nothing)'
            Assert-Feature "every recalled building is rallied to the SAME point (buckets: $($nowKeys.Count))" `
                (Test-ScWitnessed -Claim ($nowKeys.Count -eq 1 -and $rallied.Unit.Rally[$nowKeys[0]] -eq $rallied.Unit.Live) `
                                  -Witness (Test-ScChanged -Before $rallyBefore -After $rallied.Unit.RallyText)) `
                "(got $($rallied.Unit.RallyText) over $($rallied.Unit.Live) live)"
        }
        Shot 'group-rallied'
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
    Remove-ScOwnFixture -Run $fixtures
    Remove-ScOwnFixtureDir -Dir $mapDir
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'this run left no fixture behind' (-not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-building-parity [$arm]: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
