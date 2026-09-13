#Requires -Version 7
<#
.SYNOPSIS
Free disk under the machine data root: delete what a suite, a probe or ./deploy.ps1 recreates.
Keeps the pristine install, the toolchain, the working copy, cnc-ddraw, the decompiled C, the
Ghidra project, the registry baseline and the user's deployed game. Empties logs\ but keeps the
folder: the plugin writes into it without creating it. Refuses while a StarCraft runs or a launch
holds sc-launch.lock, since both write under logs\.
.EXAMPLE
./clean.ps1 -WhatIf
./clean.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$DataRoot = 'C:\decompile-sc-data')
$ErrorActionPreference = 'Stop'

if (Get-Process StarCraft -ErrorAction SilentlyContinue) {
    throw 'clean: a StarCraft is running; close it first (AGENTS.md § "Stopping a run / orphaned games").'
}
$work = Join-Path $DataRoot 'sc-work'
$lock = Join-Path $work 'logs\sc-launch.lock'
if (Test-Path -LiteralPath $lock) {
    try { [IO.File]::Open($lock, 'Open', 'ReadWrite', 'None').Dispose() }
    catch { throw "clean: a launch holds $lock; retry when it is done." }
}

$targets = @(
    Get-ChildItem -LiteralPath (Join-Path $DataRoot 'sc-deploy') -Force -ErrorAction SilentlyContinue |
        Where-Object Name -ne 'starcraft-modded'
    Get-ChildItem -LiteralPath $work -Force -ErrorAction SilentlyContinue |
        Where-Object Name -notin '1161-base', 'cnc-ddraw', 'decomp', 'ghidra', 'registry', 'logs'
    Get-ChildItem -LiteralPath (Join-Path $work 'logs') -Force -ErrorAction SilentlyContinue
)
$deleted = 0
$freed = 0
foreach ($t in $targets) {
    $bytes = if ($t.PSIsContainer) { (Get-ChildItem -LiteralPath $t.FullName -Recurse -Force -File | Measure-Object Length -Sum).Sum } else { $t.Length }
    if ($PSCmdlet.ShouldProcess($t.FullName, ('delete {0:N0} MB' -f ($bytes / 1MB)))) {
        Remove-Item -LiteralPath $t.FullName -Recurse -Force
        $deleted++
        $freed += $bytes
    }
}
Write-Host ('clean: deleted {0} of {1} entries, {2:N0} MB freed under {3}' -f $deleted, $targets.Count, ($freed / 1MB), $DataRoot)
