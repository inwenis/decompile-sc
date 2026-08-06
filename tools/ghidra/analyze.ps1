#Requires -Version 7
<#
.SYNOPSIS
Ghidra headless analysis of a PE: import, auto-analyze, export a disassembly listing and
decompiled C for one function -- single command, no GUI.

.DESCRIPTION
Thin wrapper around Ghidra's analyzeHeadless. Creates a throwaway project under
tools/ghidra/ghidra_projects/ (gitignored), imports -InputPE, runs auto-analysis, then runs the
ExportListingAndDecompile.java postScript (tools/ghidra/scripts/), which writes:
  <OutDir>/<binary-name>.listing.txt          -- full disassembly listing
  <OutDir>/<binary-name>.<function-name>.c    -- decompiled C for the selected function

Requires a JDK on PATH satisfying the pinned Ghidra release's minimum version, and a Ghidra
install. See tools/ghidra/README.md for the pinned version, download URL, hash, and install
steps -- none of that is fetched by this script.

.PARAMETER InputPE
Path to the PE (.exe/.dll) to analyze. Never point this at a StarCraft/Blizzard file from an
agent worktree without explicit authorization -- see tools/ghidra/README.md.

.PARAMETER FunctionName
Exact name of the function to decompile. Mutually exclusive with -FunctionAddress.

.PARAMETER FunctionAddress
Hex address (e.g. 0x401000) of the function to decompile, for stripped binaries with no
symbol -- this is the StarCraft.exe case. Mutually exclusive with -FunctionName.

.PARAMETER OutDir
Directory to write the listing + decompiled-C output. Default: work/scratch/ghidra-out
(gitignored).

.PARAMETER GhidraInstallDir
Ghidra install directory (the one containing support/analyzeHeadless.bat). Default:
$env:GHIDRA_INSTALL_DIR, else the single ghidra_* directory found next to this script.

.PARAMETER ProjectDir
Directory to hold the throwaway Ghidra project. Default: tools/ghidra/ghidra_projects
(gitignored). Deleted and recreated on every run.

.PARAMETER Processor
Ghidra language ID override (e.g. x86:LE:32:default). Only needed when Ghidra misidentifies
the processor/compiler from the PE header -- see tools/ghidra/README.md for the StarCraft
1.16.1 settings.

.PARAMETER ImageBase
Loader image base override, hex (e.g. 0x400000). Only needed when the PE's preferred base
must be forced -- see tools/ghidra/README.md.

.EXAMPLE
./tools/ghidra/analyze.ps1 -InputPE C:\Windows\SysWOW64\kernel32.dll -FunctionName CreateFileW

.EXAMPLE
./tools/ghidra/analyze.ps1 -InputPE game\StarCraft.exe -FunctionAddress 0x4A2B10 `
    -Processor x86:LE:32:default
#>
param(
    [Parameter(Mandatory)][string]$InputPE,
    [string]$FunctionName,
    [string]$FunctionAddress,
    [string]$OutDir,
    [string]$GhidraInstallDir,
    [string]$ProjectDir,
    [string]$Processor,
    [string]$ImageBase
)

$ErrorActionPreference = 'Stop'

if (-not $FunctionName -and -not $FunctionAddress) {
    throw 'Provide -FunctionName or -FunctionAddress.'
}
if ($FunctionName -and $FunctionAddress) {
    throw 'Provide only one of -FunctionName / -FunctionAddress, not both.'
}

if (-not (Test-Path -LiteralPath $InputPE -PathType Leaf)) {
    throw "InputPE not found: $InputPE"
}
$InputPE = (Resolve-Path -LiteralPath $InputPE).Path

$toolsGhidraDir = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $toolsGhidraDir -Parent) -Parent

if (-not $GhidraInstallDir) {
    if ($env:GHIDRA_INSTALL_DIR) {
        $GhidraInstallDir = $env:GHIDRA_INSTALL_DIR
    }
    else {
        $candidates = @(Get-ChildItem -LiteralPath $toolsGhidraDir -Directory -Filter 'ghidra_*' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'support/analyzeHeadless.bat') })
        if ($candidates.Count -eq 1) { $GhidraInstallDir = $candidates[0].FullName }
        elseif ($candidates.Count -gt 1) {
            throw "Multiple Ghidra installs found under $toolsGhidraDir -- pass -GhidraInstallDir explicitly."
        }
        else {
            throw "No Ghidra install found under $toolsGhidraDir. Set -GhidraInstallDir, or `$env:GHIDRA_INSTALL_DIR`, or install the pinned release per tools/ghidra/README.md."
        }
    }
}

$analyzeHeadless = Join-Path $GhidraInstallDir 'support/analyzeHeadless.bat'
if (-not (Test-Path -LiteralPath $analyzeHeadless -PathType Leaf)) {
    throw "analyzeHeadless.bat not found at $analyzeHeadless -- check -GhidraInstallDir."
}

if (-not $ProjectDir) { $ProjectDir = Join-Path $toolsGhidraDir 'ghidra_projects' }
if (Test-Path -LiteralPath $ProjectDir) { Remove-Item -LiteralPath $ProjectDir -Recurse -Force }
New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null

if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'work/scratch/ghidra-out' }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$scriptPath = Join-Path $toolsGhidraDir 'scripts'
$projectName = 'analyze'
$selector = if ($FunctionAddress) { $FunctionAddress } else { $FunctionName }

$headlessArgs = @(
    $ProjectDir, $projectName,
    '-import', $InputPE,
    '-scriptPath', $scriptPath,
    '-postScript', 'ExportListingAndDecompile.java', $OutDir, $selector,
    '-deleteProject'
)
if ($Processor) { $headlessArgs += @('-processor', $Processor) }
if ($ImageBase) { $headlessArgs += @('-loader-imagebase', $ImageBase) }

Write-Host "analyze.ps1: $analyzeHeadless $($headlessArgs -join ' ')"
& $analyzeHeadless @headlessArgs
if ($LASTEXITCODE -ne 0) { throw "analyzeHeadless exited with code $LASTEXITCODE" }

# analyzeHeadless can exit 0 even when a post-script throws (it logs "REPORT SCRIPT ERROR" and
# carries on) -- the only reliable success signal is that the two output files actually landed.
$base = [IO.Path]::GetFileName($InputPE)
$listingPath = Join-Path $OutDir "$base.listing.txt"
$decompPathGlob = Join-Path $OutDir "$base.*.c"
if (-not (Test-Path -LiteralPath $listingPath)) {
    throw "analyze.ps1: expected listing not found at $listingPath -- check the analyzeHeadless output above for a script error."
}
if (-not (Get-ChildItem -Path $decompPathGlob -ErrorAction SilentlyContinue)) {
    throw "analyze.ps1: expected decompiled-C output not found ($decompPathGlob) -- check the analyzeHeadless output above for a script error."
}

Write-Host "analyze.ps1: done. Output in $OutDir"
