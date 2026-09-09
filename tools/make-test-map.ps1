#Requires -Version 7
<#
.SYNOPSIS
    Generate a single-player StarCraft 1.16.1 test map holding more units for one
    player than the classic 12-unit selection cap, so one drag-box exceeds it.

.DESCRIPTION
    Wrapper around tools/make_test_map.py (see tools/README-test-map.md): appends
    units near a player's start on a melee-map template, disables the other player
    slots, strips triggers so nothing can end the game, then validates the result.

.EXAMPLE
    ./tools/make-test-map.ps1
    ./tools/make-test-map.ps1 -UnitCount 50 -UnitType marine -Player 0
    ./tools/make-test-map.ps1 -OutputPath C:\sc-work\1161-base\Maps\my-test.scx
#>

[CmdletBinding()]
param(
    [int]$UnitCount = 36,
    [string]$UnitType = 'marine',
    [int]$Player = 0,
    # Pixels between placed units (32 = one tile). Types bigger than a tile need more:
    # the game silently drops the ones it cannot place, so the map comes up short.
    [int]$GridSpacing = 32,
    [string]$TemplatePath = 'C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx',
    [string]$OutputPath = 'C:\sc-work\1161-base\Maps\test-many-units.scx',
    # Leave the template's player slots alone: rewriting them deletes the actors of a
    # template that is already a playable scenario (a stock campaign mission).
    [switch]$KeepOwnr,
    # Drop the target player's existing units first, so the placed group is all one type.
    # A mixed selection is offered only the basic command card in game -- no ability buttons.
    [switch]$ClearPlayerUnits,
    # Drop the template's critters, the one kind of neutral unit that moves on its own;
    # a probe that judges buffer changes against the engine's marks cannot have them.
    [switch]$ClearCritters,
    # Keep the template's TRIG/MBRF sections. NOT for a test fixture: stock triggers end
    # the game seconds after a generated map loads (tools/README-test-map.md).
    [switch]$KeepTriggers,
    # Race written into SIDE, defaulting to the placed unit type's. A ladder template's
    # "User Selectable" gets MELEE starting units even under Use Map Settings.
    [ValidateSet('zerg', 'terran', 'protoss')]
    [string]$Race,
    # --- the combat variant -------------------------------------------------------
    # Place this many COMPUTER-owned units near the player's block, so a test can walk
    # the player's units into them and get one killed. 0 keeps the hostility-free map.
    [int]$EnemyCount = 0,
    [string]$EnemyType,
    # Map pixels east/south of the player's start location for the enemy block's centre.
    [int]$EnemyOffsetX,
    [int]$EnemyOffsetY,
    [int]$EnemySpacing,
    [ValidateSet('zerg', 'terran', 'protoss')]
    [string]$EnemyRace,
    # 'computer' is the combat fixture; 'player' is the placement probe -- same types and
    # coordinates but human-owned, so a test can box them and count them in-process.
    [ValidateSet('computer', 'player')]
    [string]$EnemyOwner,
    [int]$MinEnemyGap,
    # Hit points for the placed units, as a PERCENTAGE of the type's maximum (1-100).
    # Lower makes a fixture's victims die in seconds, changing nothing else about them.
    [ValidateRange(1, 100)]
    [int]$UnitHp,
    # --- the per-unit-cost variant ------------------------------------------------
    # Pre-damage the LAST N units of the player's block to -DamagedHp instead of -UnitHp
    # (both are percentages of the type's maximum), same type and grid. One selection then
    # holds units that can afford an ability's per-unit cost and units that cannot, so one
    # keypress shows who the ENGINE skips.
    [int]$DamagedCount = 0,
    [ValidateRange(1, 100)]
    [int]$DamagedHp,
    # Energy for that same tail, the -DamagedHp counterpart for abilities whose
    # per-unit cost is energy.
    [ValidateRange(1, 100)]
    [int]$DamagedEnergy,
    # Techs to mark available AND already-researched for -Player, written into PTEx.
    # Without this nothing on a generated map has an ability that needs research --
    # which is every ability with a per-unit cost (Stim Packs, both cloaks, Siege Mode).
    [string[]]$TechResearched = @(),
    # --- the production variant ---------------------------------------------------
    # Starting resources for -Player, as ONE `Always -> Set Resources` trigger in the
    # emptied TRIG section (a CHK has no starting-resources field and Use Map Settings
    # hands out none, so a producing building otherwise affords one unit). Not with -KeepTriggers.
    [int]$StartingMinerals,
    [int]$StartingGas,
    # --- unit settings, the map's own UNIx override -------------------------------
    # Per-unit-TYPE overrides for this map only, each 'TYPE=VALUE' and repeatable.
    # -UnitBuildTime is safe nearly everywhere: build time is SETUP, not measurement
    # (`test-production-queue` waits 153 of its 224 seconds on nine SCVs at 20 game
    # seconds each; 'scv=1' deletes that term and nothing else).
    # -UnitMaxHp / -UnitShields / -UnitArmor change how long a FIGHT takes: a target
    # dying inside a measurement window forges the very signature a combat or liveness
    # suite hunts -- for damaged starting units use -UnitHp, a percentage of an unchanged max.
    # -UnitMineralCost / -UnitGasCost save no time (nothing waits on a resource) and
    # break suites doing the arithmetic: `test-production-queue` asserts 2550 = 3000 - 9 x 50.
    [string[]]$UnitBuildTime = @(),
    [string[]]$UnitMaxHp = @(),
    [string[]]$UnitShields = @(),
    [string[]]$UnitArmor = @(),
    [string[]]$UnitMineralCost = @(),
    [string[]]$UnitGasCost = @(),
    # Explicit interpreter override: skips resolution AND the import preflight, so the
    # caller vouches for it (which is how tests reach the failure paths).
    [string]$Python
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

# Resolve-ScPython probes this checkout's .venv, the MAIN checkout's .venv (worktrees are
# cut without one), then PATH python, and accepts nothing that cannot import richchk: an
# interpreter waved through on a warning fails later, and callers blame the missing map.
. (Join-Path $PSScriptRoot 'sc-python.ps1')
if ($Python) {
    $resolved = [pscustomobject]@{ Path = $Python; Source = '-Python parameter'; Probed = @() }
}
else {
    $resolved = Resolve-ScPython -RepoRoot $repoRoot -RequireModule 'richchk'
    if (-not $resolved.Path) {
        throw ("make-test-map: no python that can import richchk was found -- map generation CANNOT run. " +
               "Probed: $($resolved.Probed -join '; '). " +
               'This is the worktree-without-.venv gap (issue #97): run ./setup.ps1 in the main checkout, or pass -Python <exe>.')
    }
}
$python = $resolved.Path

$pyArgs = @(
    (Join-Path $PSScriptRoot 'make_test_map.py')
    '--unit-count', $UnitCount
    '--unit-type', $UnitType
    '--player', $Player
    '--grid-spacing', $GridSpacing
    '--template', $TemplatePath
    '--output', $OutputPath
)
if ($KeepOwnr) { $pyArgs += '--keep-ownr' }
if ($ClearPlayerUnits) { $pyArgs += '--clear-player-units' }
if ($ClearCritters) { $pyArgs += '--clear-critters' }
if ($KeepTriggers) { $pyArgs += '--keep-triggers' }
if ($Race) { $pyArgs += @('--race', $Race) }
if ($EnemyCount -gt 0) { $pyArgs += @('--enemy-count', $EnemyCount) }
if ($EnemyType) { $pyArgs += @('--enemy-type', $EnemyType) }
# 0 is a meaningful offset (due north/east of the start location on that axis), so
# these test for "the caller passed it", not for "it is non-zero".
if ($PSBoundParameters.ContainsKey('EnemyOffsetX')) { $pyArgs += @('--enemy-offset-x', $EnemyOffsetX) }
if ($PSBoundParameters.ContainsKey('EnemyOffsetY')) { $pyArgs += @('--enemy-offset-y', $EnemyOffsetY) }
if ($PSBoundParameters.ContainsKey('EnemySpacing')) { $pyArgs += @('--enemy-spacing', $EnemySpacing) }
if ($PSBoundParameters.ContainsKey('MinEnemyGap')) { $pyArgs += @('--min-enemy-gap', $MinEnemyGap) }
if ($EnemyRace) { $pyArgs += @('--enemy-race', $EnemyRace) }
if ($EnemyOwner) { $pyArgs += @('--enemy-owner', $EnemyOwner) }
if ($PSBoundParameters.ContainsKey('UnitHp')) { $pyArgs += @('--unit-hp', $UnitHp) }
if ($DamagedCount -gt 0) { $pyArgs += @('--damaged-count', $DamagedCount) }
if ($PSBoundParameters.ContainsKey('DamagedHp')) { $pyArgs += @('--damaged-hp', $DamagedHp) }
if ($PSBoundParameters.ContainsKey('DamagedEnergy')) { $pyArgs += @('--damaged-energy', $DamagedEnergy) }
foreach ($t in $TechResearched) { $pyArgs += @('--tech-researched', $t) }
# 0 is a meaningful amount ("start with nothing"), so test for "passed", not non-zero.
if ($PSBoundParameters.ContainsKey('StartingMinerals')) { $pyArgs += @('--starting-minerals', $StartingMinerals) }
if ($PSBoundParameters.ContainsKey('StartingGas')) { $pyArgs += @('--starting-gas', $StartingGas) }
# Empty by default: a caller that passes none of these gets byte-identical output, so
# unit settings cannot perturb a suite that never asks for them.
foreach ($s in $UnitBuildTime)    { $pyArgs += @('--unit-build-time', $s) }
foreach ($s in $UnitMaxHp)        { $pyArgs += @('--unit-max-hp', $s) }
foreach ($s in $UnitShields)      { $pyArgs += @('--unit-shields', $s) }
foreach ($s in $UnitArmor)        { $pyArgs += @('--unit-armor', $s) }
foreach ($s in $UnitMineralCost)  { $pyArgs += @('--unit-mineral-cost', $s) }
foreach ($s in $UnitGasCost)      { $pyArgs += @('--unit-gas-cost', $s) }

# Tee, not capture: suites parse this stream for the generator's validation lines
# (`^OK: `, `TRIG holds ...`), while a copy stays here so a failure carries the traceback
# INSIDE the throw (a caller's `$gen = & ... 2>&1` loses its capture when it aborts).
& $python @pyArgs 2>&1 | Tee-Object -Variable genOut
if ($LASTEXITCODE -ne 0) {
    $tail = (@($genOut) | ForEach-Object { "$_" } |
        Where-Object { $_ -notmatch 'WARNING:StormLibFinder' } |
        Select-Object -Last 12) -join "`n"
    throw ("make-test-map: map generation FAILED (python exit $LASTEXITCODE; interpreter: $($resolved.Source), $python). " +
           "No map was written to $OutputPath -- do not launch. Generator output (tail):`n$tail")
}
if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "make-test-map: the generator exited 0 but no map exists at $OutputPath -- nothing was delivered; do not launch."
}
