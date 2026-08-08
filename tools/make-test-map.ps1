#Requires -Version 7
<#
.SYNOPSIS
    Generate a single-player StarCraft 1.16.1 test map with many units already
    placed for one player, so a single drag-box selects more than the classic
    12-unit selection cap (task009).

.DESCRIPTION
    Thin wrapper around tools/make_test_map.py (a richchk-based CHK/MPQ
    editor -- see tools/README-test-map.md). Takes an existing melee map as a
    terrain/start-location template, appends N placed units near the chosen
    player's start location, and disables every other player slot so nothing
    hostile is on the map.

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
    [switch]$ClearPlayerUnits
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

& $python @pyArgs
exit $LASTEXITCODE
