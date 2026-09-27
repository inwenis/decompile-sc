#Requires -Version 7
<#
.SYNOPSIS
Ghidra headless driver: analyze a PE once into a persistent project, then run many cheap query
scripts against it.

.DESCRIPTION
A cross-reference sweep needs a dozen queries to see the SAME analyzed program, and a fresh
import re-analyzes the binary -- minutes per query. Prepare analyzes once and
writes the full analyzeHeadless log to -LogFile, so the "Using Language/Compiler" line, image
base and entry point are evidence rather than assumption; Run queries that program with
-noanalysis, in seconds.

Project directory and output belong under work/scratch/ (gitignored): a Ghidra project analyzing
a game binary embeds that binary and must never be committed.

.EXAMPLE
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\decompile-sc-data\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/ghidra-sweep -LogFile work/scratch/ghidra-sweep/import.log

.EXAMPLE
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-sweep `
    -ProgramName StarCraft.exe -Script XrefSweep.java `
    -ScriptArgs work/scratch/xrefs.tsv, work/scratch/globals.spec
#>
param(
    [Parameter(Mandatory)][ValidateSet('Prepare', 'Run')][string]$Mode,
    [string]$InputPE,
    [Parameter(Mandatory)][string]$ProjectDir,
    [string]$ProgramName,
    [string]$Script,
    [string[]]$ScriptArgs = @(),
    [string]$LogFile,
    # Prepare only: replace a program already in the project instead of skipping the import.
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

# Env var only: an install beside this script sits in a worktree, and pruning that deletes it.
if (-not $env:GHIDRA_INSTALL_DIR) { throw 'sweep.ps1: set $env:GHIDRA_INSTALL_DIR (tools/ghidra/README.md, Install).' }
$analyzeHeadless = Join-Path $env:GHIDRA_INSTALL_DIR 'support/analyzeHeadless.bat'
if (-not (Test-Path -LiteralPath $analyzeHeadless -PathType Leaf)) {
    throw "analyzeHeadless.bat not found at $analyzeHeadless -- check `$env:GHIDRA_INSTALL_DIR."
}
$ScriptPath = Join-Path $PSScriptRoot 'scripts'

New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path

if ($Mode -eq 'Prepare') {
    if (-not $InputPE) { throw '-Mode Prepare requires -InputPE.' }
    if (-not (Test-Path -LiteralPath $InputPE -PathType Leaf)) { throw "InputPE not found: $InputPE" }
    $InputPE = (Resolve-Path -LiteralPath $InputPE).Path

    $headlessArgs = @($ProjectDir, 'sweep', '-import', $InputPE, '-scriptPath', $ScriptPath)
    if ($Overwrite) { $headlessArgs += '-overwrite' }
}
else {
    if (-not $ProgramName) { throw '-Mode Run requires -ProgramName.' }
    if (-not $Script) { throw '-Mode Run requires -Script.' }

    # Contract with every query script in scripts/: its first arg is its output path, and it
    # writes <that path>.manifest with status=OK as its LAST action. Deleting a stale manifest up
    # front stops a post-script that dies from leaving an earlier run's OK standing.
    if ($ScriptArgs.Count -lt 1) { throw '-Mode Run requires at least one -ScriptArgs (the output path).' }

    # analyzeHeadless is a .bat, so cmd.exe re-splits the command line on COMMAS as well as
    # spaces: one argument containing a comma silently reaches the GhidraScript as several, so a
    # nine-constant sweep can watch one constant and still report success.
    foreach ($a in $ScriptArgs) {
        if ($a -match ',') {
            throw "sweep.ps1: script argument '$a' contains a comma. cmd.exe splits .bat arguments on commas, so this would reach the script as multiple arguments. Use '+' as a list separator instead."
        }
    }
    $manifestPath = $ScriptArgs[0] + '.manifest'
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }

    $headlessArgs = @(
        $ProjectDir, 'sweep',
        '-process', $ProgramName,
        '-noanalysis',
        '-scriptPath', $ScriptPath,
        '-postScript', $Script
    ) + $ScriptArgs
}

Write-Host "sweep.ps1: $analyzeHeadless $($headlessArgs -join ' ')"

# Ghidra's launch.bat runs `pause` on a non-zero exit; feed it empty stdin so a launch failure
# fails fast instead of blocking on a keypress.
if ($LogFile) {
    New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null
    '' | & $analyzeHeadless @headlessArgs 2>&1 | Tee-Object -FilePath $LogFile
}
else {
    '' | & $analyzeHeadless @headlessArgs 2>&1
}
if ($LASTEXITCODE -ne 0) { throw "analyzeHeadless exited with code $LASTEXITCODE" }

if ($Mode -eq 'Run') {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "sweep.ps1: no manifest at $manifestPath -- the post-script did not complete. analyzeHeadless exits 0 on script errors; check the output above for REPORT SCRIPT ERROR."
    }
    $manifest = ConvertFrom-StringData (Get-Content -LiteralPath $manifestPath -Raw)
    if ($manifest.status -ne 'OK') { throw "sweep.ps1: manifest status '$($manifest.status)', not OK." }
    Write-Host "sweep.ps1: OK -- $($manifest.rows) rows -> $($ScriptArgs[0])"
}
else {
    Write-Host "sweep.ps1: project prepared at $ProjectDir (sweep). Log: $LogFile"
}
