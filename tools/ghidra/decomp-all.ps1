#Requires -Version 7
<#
.SYNOPSIS
Decompile every function of a PE into one .c file per function, named from the Magnetar table.

.DESCRIPTION
One persistent Ghidra project under -ProjectDir (default C:\sc-work\ghidra: outside every
worktree, so a worktree prune can never take it), analyzed once per program. Then the Magnetar
names go in as IMPORTED labels + calling conventions (StarCraft.exe only), and DecompileMany
writes <OutDir>\<program>\:
  index.tsv            one row per function: entry address, name, body bytes, .c file
  names.tsv            the parsed Magnetar table (kind, addr, name, conv)
  names-report.txt     how many names applied / kept / rejected, plus the Function ID count
  0x<addr>.<name>.c    decompiled C, one file per function
  decompile.log        the analyzeHeadless log of the decompile pass
Everything under OutDir is derived game content: it stays outside the repo.

.EXAMPLE
./tools/ghidra/decomp-all.ps1
.EXAMPLE
./tools/ghidra/decomp-all.ps1 -InputPE C:\sc-work\1161-base\storm.dll
#>
param(
    [string]$InputPE = 'C:\sc-work\1161-base\StarCraft.exe',
    [string]$ProjectDir = 'C:\sc-work\ghidra',
    [string]$OutDir = 'C:\sc-work\decomp',
    [int]$DecompileTimeoutSecs = 120
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'magnetar-names.ps1')
$sweep = Join-Path $PSScriptRoot 'sweep.ps1'
$program = Split-Path $InputPE -Leaf
$out = Join-Path $OutDir $program
New-Item -ItemType Directory -Path $out -Force | Out-Null

# Import + auto-analysis once per program; the marker is written only after Prepare returned.
$imported = Join-Path $ProjectDir "$program.imported"
if (-not (Test-Path -LiteralPath $imported)) {
    & $sweep -Mode Prepare -InputPE $InputPE -ProjectDir $ProjectDir -LogFile (Join-Path $ProjectDir "import-$program.log")
    Set-Content -LiteralPath $imported -Value (Get-Date -Format o)
}

if ($program -ieq 'StarCraft.exe') {
    $namesTsv = Join-Path $out 'names.tsv'
    $rows = ConvertFrom-MagnetarOffsets -Lines (Get-Content -LiteralPath (Get-MagnetarOffsets -CacheDir (Join-Path $ProjectDir 'magnetar')))
    Export-MagnetarTsv -Rows $rows -Path $namesTsv
    & $sweep -Mode Run -ProjectDir $ProjectDir -ProgramName $program -Script ApplyNames.java `
        -ScriptArgs (Join-Path $out 'names-report.txt'), $namesTsv
    Get-Content -LiteralPath (Join-Path $out 'names-report.txt')
}

# A renamed function changes its file name; stale .c files from an earlier pass must not survive.
Get-ChildItem -LiteralPath $out -Filter '*.c' | Remove-Item -Force
& $sweep -Mode Run -ProjectDir $ProjectDir -ProgramName $program -Script DecompileMany.java `
    -ScriptArgs (Join-Path $out 'index.tsv'), 'ALL', $DecompileTimeoutSecs -LogFile (Join-Path $out 'decompile.log')

$index = Import-Csv -LiteralPath (Join-Path $out 'index.tsv') -Delimiter "`t"
$failed = @($index | Where-Object status -ne 'OK')
Write-Host "decomp-all.ps1: $($index.Count) functions, $($failed.Count) not decompiled -> $out"
$failed | ForEach-Object { Write-Host "  $($_.funcEntry) $($_.funcName): $($_.status)" }
