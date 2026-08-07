#Requires -Version 7
<#
.SYNOPSIS
Persistent-project Ghidra headless driver: import+analyze a PE ONCE, then run many cheap
query scripts against the already-analyzed program.

.DESCRIPTION
Companion to tools/ghidra/analyze.ps1 (task 001), which imports and re-analyzes on EVERY
invocation. That is the right shape for "decompile one function"; it is the wrong shape for a
cross-reference sweep, where a dozen different queries must all see the SAME analyzed program
and re-analysis would cost minutes each time.

Two modes:

  -Mode Prepare  imports -InputPE into a PERSISTENT Ghidra project and runs auto-analysis once.
                 Writes the full analyzeHeadless log to -LogFile so the "Using Language/Compiler"
                 line, image base and entry point can be read back as evidence rather than assumed.

  -Mode Run      runs -Script (a GhidraScript under -ScriptPath) against the already-imported
                 program with -noanalysis, passing -ScriptArgs through. Seconds, not minutes.

Freshness: every query script in scripts/ writes a `<out>.manifest` file as its LAST action and
this driver deletes any stale manifest before the run and requires a fresh one with status=OK
afterwards. analyzeHeadless exits 0 even when a post-script throws (it logs "REPORT SCRIPT
ERROR" and carries on), and query output files are reused across runs -- same failure mode
tools/ghidra/README.md documents for analyze.ps1, same defence.

The project directory and all output are expected to live under work/scratch/ (gitignored).
Never commit a Ghidra project analyzing a game binary -- it embeds the binary.

.EXAMPLE
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
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
    [string]$ProjectName = 'sweep',
    [string]$ProgramName,
    [string]$Script,
    [string[]]$ScriptArgs = @(),
    [string]$ScriptPath,
    [string]$GhidraInstallDir,
    [string]$LogFile,
    [string]$Processor,
    [string]$CompilerSpec,
    [int]$TimeoutMinutes = 90
)

$ErrorActionPreference = 'Stop'

# Resolution order matches analyze.ps1: explicit -GhidraInstallDir, then $env:GHIDRA_INSTALL_DIR,
# then a single ghidra_* install next to this script. Deliberately NO hardcoded path into another
# agent's worktree: task 005 had the install disappear mid-run when task 001's worktree was
# pruned after its merge (the install is gitignored, so pruning deleted the only copy on the
# machine). A tool that lives inside a worktree is only as durable as that worktree.
if (-not $GhidraInstallDir) {
    if ($env:GHIDRA_INSTALL_DIR) {
        $GhidraInstallDir = $env:GHIDRA_INSTALL_DIR
    }
    else {
        $candidates = @(Get-ChildItem -LiteralPath $PSScriptRoot -Directory -Filter 'ghidra_*' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'support/analyzeHeadless.bat') })
        if ($candidates.Count -eq 1) { $GhidraInstallDir = $candidates[0].FullName }
        elseif ($candidates.Count -gt 1) { throw "Multiple Ghidra installs under $PSScriptRoot -- pass -GhidraInstallDir explicitly." }
        else { throw "No Ghidra install found. Pass -GhidraInstallDir, set `$env:GHIDRA_INSTALL_DIR, or install the pinned release per tools/ghidra/README.md." }
    }
}
$analyzeHeadless = Join-Path $GhidraInstallDir 'support/analyzeHeadless.bat'
if (-not (Test-Path -LiteralPath $analyzeHeadless -PathType Leaf)) {
    throw "analyzeHeadless.bat not found at $analyzeHeadless -- check -GhidraInstallDir."
}

if (-not $ScriptPath) { $ScriptPath = Join-Path $PSScriptRoot 'scripts' }
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path

New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path

if ($Mode -eq 'Prepare') {
    if (-not $InputPE) { throw '-Mode Prepare requires -InputPE.' }
    if (-not (Test-Path -LiteralPath $InputPE -PathType Leaf)) { throw "InputPE not found: $InputPE" }
    $InputPE = (Resolve-Path -LiteralPath $InputPE).Path

    $headlessArgs = @($ProjectDir, $ProjectName, '-import', $InputPE, '-scriptPath', $ScriptPath)
    if ($Processor) { $headlessArgs += @('-processor', $Processor) }
    if ($CompilerSpec) { $headlessArgs += @('-cspec', $CompilerSpec) }
}
else {
    if (-not $ProgramName) { throw '-Mode Run requires -ProgramName.' }
    if (-not $Script) { throw '-Mode Run requires -Script.' }

    # Every query script's first arg is its output path; its manifest is that path + ".manifest".
    # Delete the stale manifest up front so a post-script that dies cannot leave a prior run's OK.
    if ($ScriptArgs.Count -lt 1) { throw '-Mode Run requires at least one -ScriptArgs (the output path).' }

    # analyzeHeadless is a .bat, so cmd.exe re-splits the command line on COMMAS as well as
    # spaces. A single argument containing a comma silently arrives at the GhidraScript as
    # several arguments -- which produced a sweep that watched one constant instead of nine and
    # still reported success. Fail loudly instead.
    foreach ($a in $ScriptArgs) {
        if ($a -match ',') {
            throw "sweep.ps1: script argument '$a' contains a comma. cmd.exe splits .bat arguments on commas, so this would reach the script as multiple arguments. Use '+' as a list separator instead."
        }
    }
    $manifestPath = $ScriptArgs[0] + '.manifest'
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }

    $headlessArgs = @(
        $ProjectDir, $ProjectName,
        '-process', $ProgramName,
        '-noanalysis',
        '-scriptPath', $ScriptPath,
        '-postScript', $Script
    ) + $ScriptArgs
}

Write-Host "sweep.ps1: $analyzeHeadless $($headlessArgs -join ' ')"

# Ghidra's launch.bat runs `pause` on a non-zero exit; feed it empty stdin so a launch failure
# fails fast instead of blocking on a keypress (same foot-gun analyze.ps1 documents).
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
    Write-Host "sweep.ps1: project prepared at $ProjectDir ($ProjectName). Log: $LogFile"
}
