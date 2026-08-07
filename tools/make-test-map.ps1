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
    [string]$TemplatePath = 'C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx',
    [string]$OutputPath = 'C:\sc-work\1161-base\Maps\test-many-units.scx'
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

& $python (Join-Path $PSScriptRoot 'make_test_map.py') `
    --unit-count $UnitCount `
    --unit-type $UnitType `
    --player $Player `
    --template $TemplatePath `
    --output $OutputPath
exit $LASTEXITCODE
