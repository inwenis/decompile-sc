#Requires -Version 7
<#
.SYNOPSIS
Decompile every function of a PE into one .c file per function, with Magnetar names, prototypes,
register conventions, structs, enums and global types applied first.

.DESCRIPTION
One persistent Ghidra project under -ProjectDir (default C:\sc-work\ghidra: outside every
worktree, so a worktree prune can never take it), analyzed once per program. For StarCraft.exe
the Magnetar tables go in first (ApplyTypes.java, then ApplyNames.java); then DecompileMany
writes <OutDir>\<program>\:
  index.tsv          one row per function: entry, name, name source, size, .c file
  ranges.tsv         one row per contiguous body range: address -> function, exactly
  names.tsv          the parsed Magnetar table (kind, addr, name, conv, proto, storage)
  types.txt          every imported struct field with its offset, every enum value
  types-report.txt   parser result + struct sizes checked against Magnetar's static_asserts
  names-report.txt   names / prototypes / globals applied, kept, failed; the Function ID count
  0x<addr>.<name>.c  decompiled C, one file per function
Everything under OutDir is derived game content: it stays outside the repo.

.EXAMPLE
./tools/ghidra/decomp-all.ps1
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
$run = { param($script, [string[]]$scriptArgs, $log) & $sweep -Mode Run -ProjectDir $ProjectDir -ProgramName $program -Script $script -ScriptArgs $scriptArgs -LogFile $log }

# Import + auto-analysis once per program; the marker is written only after Prepare returned.
$imported = Join-Path $ProjectDir "$program.imported"
if (-not (Test-Path -LiteralPath $imported)) {
    & $sweep -Mode Prepare -InputPE $InputPE -ProjectDir $ProjectDir -LogFile (Join-Path $ProjectDir "import-$program.log")
    Set-Content -LiteralPath $imported -Value (Get-Date -Format o)
}

if ($program -ieq 'StarCraft.exe') {
    $cache = Join-Path $ProjectDir 'magnetar'
    $offsets = @(Get-Content -LiteralPath (Get-MagnetarFile -CacheDir $cache -Name offsets.cpp))
    $types = @(Get-Content -LiteralPath (Get-MagnetarFile -CacheDir $cache -Name types.h))
    $t = ConvertFrom-MagnetarTypes -Lines $types
    # COM interfaces the game only holds by pointer: neither Magnetar file defines them.
    $com = [regex]::Matches(($offsets + $types) -join "`n", '\bIDirect\w+') | ForEach-Object Value | Sort-Object -Unique
    $header = Join-Path $cache 'magnetar.h'
    Set-Content -LiteralPath $header -Value (@($com | ForEach-Object { "typedef struct $_ $_;" }) + $t.header) -Encoding utf8
    Export-MagnetarTsv -Rows $t.enums -Path (Join-Path $cache 'enums.tsv')
    Export-MagnetarTsv -Rows $t.sizes -Path (Join-Path $cache 'sizes.tsv')
    & $run ApplyTypes.java @((Join-Path $out 'types-report.txt'), $header, (Join-Path $cache 'enums.tsv'),
        (Join-Path $cache 'sizes.tsv'), (Join-Path $out 'types.txt')) (Join-Path $out 'types.log')
    Get-Content -LiteralPath (Join-Path $out 'types-report.txt') -TotalCount 6

    $namesTsv = Join-Path $out 'names.tsv'
    Export-MagnetarTsv -Rows (ConvertFrom-MagnetarOffsets -Lines $offsets) -Path $namesTsv
    & $run ApplyNames.java @((Join-Path $out 'names-report.txt'), $namesTsv) (Join-Path $out 'names.log')
    Get-Content -LiteralPath (Join-Path $out 'names-report.txt') | Where-Object { $_ -notmatch "`t" -and $_ -notmatch '^#' }
}

# A renamed function changes its file name; stale .c files from an earlier pass must not survive.
Get-ChildItem -LiteralPath $out -Filter '*.c' | Remove-Item -Force
& $run DecompileMany.java @((Join-Path $out 'index.tsv'), 'ALL', $DecompileTimeoutSecs) (Join-Path $out 'decompile.log')

$index = Import-Csv -LiteralPath (Join-Path $out 'index.tsv') -Delimiter "`t"
$failed = @($index | Where-Object status -ne 'OK')
Write-Host "decomp-all.ps1: $($index.Count) functions, $($failed.Count) not decompiled -> $out"
$failed | ForEach-Object { Write-Host "  $($_.funcEntry) $($_.funcName): $($_.status)" }
