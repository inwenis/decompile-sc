#Requires -Version 7
<#
.SYNOPSIS
Save, or restore exactly, a baseline of the user's StarCraft settings
(HKCU\SOFTWARE\Blizzard Entertainment\Starcraft).

.DESCRIPTION
That key holds the user's real game settings and is shared with every run on this machine.
Only the Starcraft subkey: its siblings belong to the Battle.net app (login identity,
auth), and restoring those would sign the user out of other games.
-Save right before a write, -Restore when done: the restore first exports the current
state beside the baseline (so the restore itself can be undone), then deletes the key and
imports the baseline, so values added since are gone too. Save right before, not once: a
restore also reverts whatever the user changed since the save. Every save keeps a
timestamped copy, so no earlier state is lost to a later save.
The files stay under C:\decompile-sc-data\sc-work: they hold the user's own Recent Maps paths.

.EXAMPLE
./tools/sc-registry-baseline.ps1 -Save
# ... write HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft ...
./tools/sc-registry-baseline.ps1 -Restore
#>
[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'Save', Mandatory)][switch]$Save,
    [Parameter(ParameterSetName = 'Restore', Mandatory)][switch]$Restore,
    # Injectable so Pester proves this against a throwaway key, never the real one.
    [string]$Key = 'HKCU\SOFTWARE\Blizzard Entertainment\Starcraft',
    [string]$Dir = 'C:\decompile-sc-data\sc-work\registry'
)
$ErrorActionPreference = 'Stop'
$baseline = Join-Path $Dir 'baseline.reg'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Invoke-Reg {
    $out = & reg.exe @args 2>&1
    if ($LASTEXITCODE) { throw "reg $($args -join ' ') failed ($LASTEXITCODE): $out" }
}
function Test-Key { & reg.exe query $Key 2>&1 | Out-Null; -not $LASTEXITCODE }

New-Item -ItemType Directory -Path $Dir -Force | Out-Null

if ($Save) {
    Invoke-Reg export $Key $baseline /y
    Copy-Item -LiteralPath $baseline -Destination (Join-Path $Dir "saved-$stamp.reg")
    Write-Host "sc-registry-baseline: saved $Key to $baseline (and saved-$stamp.reg)"
    return
}

if (-not (Test-Path -LiteralPath $baseline)) {
    throw "sc-registry-baseline: no baseline at $baseline. -Save goes BEFORE a write; a save now would keep your write."
}
# A .reg file names its own key; importing another key's baseline would restore nothing
# here after the delete below.
$header = '[' + ($Key -replace '^HKCU\\', 'HKEY_CURRENT_USER\') + ']'
if (-not (Get-Content -LiteralPath $baseline -Raw).Contains($header)) {
    throw "sc-registry-baseline: $baseline does not hold $header; refusing to restore."
}

$safety = $null
if (Test-Key) {
    $safety = Join-Path $Dir "before-restore-$stamp.reg"
    Invoke-Reg export $Key $safety /y
    Invoke-Reg delete $Key /f
}
try { Invoke-Reg import $baseline }
catch {
    if ($safety) { Invoke-Reg import $safety }
    throw
}
Write-Host "sc-registry-baseline: restored $Key from $baseline$(if ($safety) { "; the state before is in $safety" })"
