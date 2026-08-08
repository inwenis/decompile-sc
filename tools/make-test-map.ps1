#Requires -Version 7
<#
.SYNOPSIS
    Generate a single-player StarCraft 1.16.1 test map with many units already
    placed for one player, so a single drag-box selects more than the classic
    12-unit selection cap (task009).

.DESCRIPTION
    Thin wrapper around tools/make_test_map.py (a raw-CHK patcher over richchk's
    MPQ binding -- see tools/README-test-map.md). Takes an existing melee map as
    a terrain/start-location template, appends N placed units near the chosen
    player's start location, disables every other player slot so nothing hostile
    is on the map, and strips the template's triggers so nothing can end the game.

    Runs the generator's own structural validation pass afterward and prints
    its output -- no need for a separate validate step.

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
    # Pixels between placed units (32 = one tile). Units bigger than a tile need more:
    # the game silently drops the ones it cannot place, and a map that was asked for 36
    # units comes up with a handful.
    [int]$GridSpacing = 32,
    [string]$TemplatePath = 'C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx',
    [string]$OutputPath = 'C:\sc-work\1161-base\Maps\test-many-units.scx',
    # Leave the template's player slots alone. For a template that is already a playable
    # single-player scenario (a stock campaign mission), rewriting them deletes the
    # mission's own actors.
    [switch]$KeepOwnr,
    # Drop the target player's existing units first, so the placed group is all one type.
    # A mixed selection is offered only the basic command card in game -- no ability buttons.
    [switch]$ClearPlayerUnits,
    # Keep the template's TRIG/MBRF sections. NOT for a test fixture: every stock map
    # ships triggers that end the game, and they fire within seconds of loading a
    # generated map (tools/README-test-map.md, "why generated maps used not to play").
    [switch]$KeepTriggers,
    # Race written into SIDE for the human and computer slots. Defaults to the race the
    # placed unit type belongs to. It must not be left as a ladder template's "User
    # Selectable" -- that slot gets MELEE starting units even under Use Map Settings.
    [ValidateSet('zerg', 'terran', 'protoss')]
    [string]$Race,
    # --- the combat variant (task 019) -------------------------------------------
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
    # 'computer' is the combat fixture; 'player' is the placement probe -- same unit
    # types at the same coordinates but owned by the human, so a test can box them and
    # count them in-process.
    [ValidateSet('computer', 'player')]
    [string]$EnemyOwner,
    [int]$MinEnemyGap,
    # Hit points for the placed units, as a PERCENTAGE of the type's maximum (1-100).
    # Lower is how the combat fixture makes its victims die in seconds rather than
    # minutes without changing anything else about them.
    [ValidateRange(1, 100)]
    [int]$UnitHp
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$venvPython = Join-Path $repoRoot '.venv/Scripts/python.exe'
if (Test-Path -LiteralPath $venvPython) {
    $python = $venvPython
}
elseif (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Warning "No .venv found at $venvPython -- falling back to 'python' on PATH. Run ./setup.ps1 to pin dependencies."
    $python = 'python'
}
else {
    throw "No .venv found at $venvPython and no 'python' on PATH. Run ./setup.ps1 first."
}

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

& $python @pyArgs
exit $LASTEXITCODE
