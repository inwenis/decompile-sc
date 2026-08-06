#Requires -Version 7
<#
.SYNOPSIS
Ghidra headless analysis of a PE: import, auto-analyze, export a disassembly listing and
decompiled C for one function -- single command, no GUI.

.DESCRIPTION
Thin wrapper around Ghidra's analyzeHeadless. Creates a throwaway project under
tools/ghidra/ghidra_projects/<run-id>/ (gitignored, unique per run so concurrent invocations
never collide), imports -InputPE, runs auto-analysis, then runs the
ExportListingAndDecompile.java postScript (tools/ghidra/scripts/), which writes:
  <OutDir>/<binary-name>.listing.txt          -- full disassembly listing (unless -SkipListing)
  <OutDir>/<binary-name>.<function-name>.c    -- decompiled C for the selected function
  <OutDir>/.ghidra-analyze-manifest.properties -- this run's freshness/result record

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
(gitignored). Reused across runs -- each run's manifest is what proves ITS OWN output is
current; a stale .c from a previous function is never mistaken for this run's result.

.PARAMETER GhidraInstallDir
Ghidra install directory (the one containing support/analyzeHeadless.bat). Default:
$env:GHIDRA_INSTALL_DIR, else the single ghidra_* directory found next to this script.

.PARAMETER ProjectDir
Parent directory to hold this run's throwaway Ghidra project (a unique subdirectory is created
per run and removed afterwards). Default: tools/ghidra/ghidra_projects (gitignored).

.PARAMETER Processor
Ghidra language ID override (e.g. x86:LE:32:default). Only needed when Ghidra misidentifies
the processor/compiler from the PE header -- see tools/ghidra/README.md for the StarCraft
1.16.1 settings.

.PARAMETER CompilerSpec
Ghidra compiler spec ID override (e.g. windows), passed as -cspec. Only valid together with
-Processor. Not needed today (windows is the correct default for x86:LE:32:default) -- exposed
for if 1.16.1 ever needs something else.

.PARAMETER SkipListing
Skip the full disassembly listing export and only decompile the target function. The listing
is regenerated in full on every run (tens of MB for a StarCraft.exe-sized binary); use this
when only the decompiled C is needed, e.g. scripted many-address sweeps.

.PARAMETER DecompileTimeoutSecs
Per-function decompile timeout, in seconds. Default: 60. Raise this for large/complex
functions (realistic on a 1.2 MB StarCraft.exe binary).

.EXAMPLE
./tools/ghidra/analyze.ps1 -InputPE C:\Windows\SysWOW64\kernel32.dll -FunctionName CreateFileW

.EXAMPLE
./tools/ghidra/analyze.ps1 -InputPE game\StarCraft.exe -FunctionAddress 0x4A2B10 `
    -Processor x86:LE:32:default -DecompileTimeoutSecs 180
#>
param(
    [Parameter(Mandatory)][string]$InputPE,
    [string]$FunctionName,
    [string]$FunctionAddress,
    [string]$OutDir,
    [string]$GhidraInstallDir,
    [string]$ProjectDir,
    [string]$Processor,
    [string]$CompilerSpec,
    [switch]$SkipListing,
    [int]$DecompileTimeoutSecs = 60
)

$ErrorActionPreference = 'Stop'

if (-not $FunctionName -and -not $FunctionAddress) {
    throw 'Provide -FunctionName or -FunctionAddress.'
}
if ($FunctionName -and $FunctionAddress) {
    throw 'Provide only one of -FunctionName / -FunctionAddress, not both.'
}
if ($CompilerSpec -and -not $Processor) {
    throw '-CompilerSpec requires -Processor (Ghidra -cspec cannot be used without -processor).'
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

# Unique per-run project dir + name: a fixed name would let concurrent runs (this repo's agents
# all share the machine) collide on Ghidra's project lock, and a killed run's orphaned lock
# would then wedge every later run too.
if (-not $ProjectDir) { $ProjectDir = Join-Path $toolsGhidraDir 'ghidra_projects' }
$runId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runProjectDir = Join-Path $ProjectDir "run-$runId"
New-Item -ItemType Directory -Path $runProjectDir -Force | Out-Null
$projectName = "analyze-$runId"

if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'work/scratch/ghidra-out' }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# The manifest is the ONLY trustworthy success signal (see below) -- delete any stale one up
# front so a crash before the post-script even runs can't leave a prior run's "OK" behind.
$manifestPath = Join-Path $OutDir '.ghidra-analyze-manifest.properties'
if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }

$scriptPath = Join-Path $toolsGhidraDir 'scripts'
$selector = if ($FunctionAddress) { $FunctionAddress } else { $FunctionName }
$skipListingArg = if ($SkipListing) { 'true' } else { 'false' }

$headlessArgs = @(
    $runProjectDir, $projectName,
    '-import', $InputPE,
    '-scriptPath', $scriptPath,
    '-postScript', 'ExportListingAndDecompile.java', $OutDir, $selector, $skipListingArg, $DecompileTimeoutSecs,
    '-deleteProject'
)
if ($Processor) { $headlessArgs += @('-processor', $Processor) }
if ($CompilerSpec) { $headlessArgs += @('-cspec', $CompilerSpec) }

$succeeded = $false
try {
    Write-Host "analyze.ps1: $analyzeHeadless $($headlessArgs -join ' ')"
    # Ghidra's launch.bat runs `pause` on a non-zero exit, which hangs forever waiting on a
    # keypress if stdin is the console. Feed it a closed/empty stdin so a launch failure fails
    # fast instead of hanging the caller.
    '' | & $analyzeHeadless @headlessArgs
    if ($LASTEXITCODE -ne 0) { throw "analyzeHeadless exited with code $LASTEXITCODE" }

    # analyzeHeadless can exit 0 even when the post-script threw (it logs "REPORT SCRIPT ERROR"
    # and carries on) -- and OutDir is reused across runs, so a glob for "*.c" would just find
    # a PREVIOUS run's output and report false success. The manifest is written by the
    # post-script ONLY after it fully succeeded (see ExportListingAndDecompile.java), was
    # deleted before this run started, so its presence + status=OK is the one thing that
    # actually proves THIS run produced current output.
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "analyze.ps1: no manifest written ($manifestPath) -- the post-script did not complete successfully. Check the analyzeHeadless output above for a script error."
    }
    $manifest = ConvertFrom-StringData (Get-Content -LiteralPath $manifestPath -Raw)
    if ($manifest.status -ne 'OK') {
        throw "analyze.ps1: manifest status is '$($manifest.status)', not OK."
    }
    $cPath = Join-Path $OutDir $manifest.cFile
    if (-not (Test-Path -LiteralPath $cPath)) {
        throw "analyze.ps1: manifest references decompiled-C file that doesn't exist: $cPath"
    }
    if ($manifest.listingFile -ne 'SKIPPED') {
        $listingPath = Join-Path $OutDir $manifest.listingFile
        if (-not (Test-Path -LiteralPath $listingPath)) {
            throw "analyze.ps1: manifest references listing file that doesn't exist: $listingPath"
        }
    }

    Write-Host "analyze.ps1: done. Resolved '$($manifest.selector)' -> $($manifest.resolvedFunctionName) @ $($manifest.resolvedEntry) ($($manifest.resolvedVia))"
    Write-Host "analyze.ps1: decompiled C: $cPath"
    if ($manifest.listingFile -ne 'SKIPPED') { Write-Host "analyze.ps1: listing: $(Join-Path $OutDir $manifest.listingFile)" }
    $succeeded = $true
}
finally {
    if (Test-Path -LiteralPath $runProjectDir) {
        try { Remove-Item -LiteralPath $runProjectDir -Recurse -Force -ErrorAction Stop }
        catch {
            # A leftover run-<guid> dir can't wedge a LATER run (each run gets its own GUID), but it
            # can mean a process still holds this run's project locked -- worth failing loudly on,
            # not just warning, when the run otherwise looked successful. If $succeeded is still
            # false, the try block already threw its own (more specific) error; don't mask it by
            # throwing here too -- PowerShell finally-block exceptions replace the original.
            $msg = "analyze.ps1: could not clean up Ghidra project dir $runProjectDir -- $_. " +
                "Delete it manually before this dir fills up: Remove-Item -Recurse -Force '$runProjectDir'"
            if ($succeeded) { throw $msg } else { Write-Warning $msg }
        }
    }
}
