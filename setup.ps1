#Requires -Version 7
<#
.SYNOPSIS
Verify prerequisites for decompile-sc and set up the Python venv. Idempotent —
safe to re-run any time; it only reports and (re)creates .venv/installs deps.
#>
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$failures = 0

function Report {
    param([bool]$Ok, [string]$Name, [string]$Detail, [switch]$Fatal)
    $mark = $Ok ? 'OK  ' : ($Fatal ? 'FAIL' : 'warn')
    Write-Host ("[{0}] {1,-14} {2}" -f $mark, $Name, $Detail)
    if (-not $Ok -and $Fatal) { $script:failures++ }
}

# --- pwsh >= 7 (the #Requires already enforces it; report the version) ---
Report $true 'pwsh' "v$($PSVersionTable.PSVersion)"

# --- git ---
$git = Get-Command git -ErrorAction SilentlyContinue
Report ($null -ne $git) 'git' ($git ? (git --version) : 'not found on PATH') -Fatal

# --- python 3.11+ ---
$python = Get-Command python -ErrorAction SilentlyContinue
$pyOk = $false
if ($python) {
    $pyVer = (python --version) -replace '^Python\s+', ''
    $v = [version]($pyVer -replace '[^\d.].*$', '')
    $pyOk = ($v -ge [version]'3.11')
    Report $pyOk 'python' ($pyOk ? "v$pyVer" : "v$pyVer — need 3.11+") -Fatal
}
else {
    Report $false 'python' 'not found on PATH' -Fatal
}

# --- JDK + Ghidra: needed later for headless analysis, NOT fatal now ---
$java = Get-Command java -ErrorAction SilentlyContinue
Report ($null -ne $java) 'jdk' ($java ? "java found: $($java.Source)" : 'not on PATH — needed later for Ghidra headless, not fatal now')

$ghidra = Get-Command analyzeHeadless -ErrorAction SilentlyContinue
if (-not $ghidra) { $ghidra = Get-Command ghidraRun -ErrorAction SilentlyContinue }
$ghidraDetail = if ($ghidra) { "found: $($ghidra.Source)" }
elseif ($env:GHIDRA_INSTALL_DIR) { "not on PATH, but GHIDRA_INSTALL_DIR=$($env:GHIDRA_INSTALL_DIR)" }
else { 'not on PATH — needed later, not fatal now' }
Report ($null -ne $ghidra -or $null -ne $env:GHIDRA_INSTALL_DIR) 'ghidra' $ghidraDetail

# --- Python venv at .venv + requirements.txt ---
if ($pyOk) {
    $venvPath = Join-Path $repoRoot '.venv'
    $venvPython = Join-Path $venvPath 'Scripts/python.exe'
    if (Test-Path -LiteralPath $venvPython) {
        Report $true 'venv' ".venv already exists — skipping creation (idempotent)"
    }
    else {
        Write-Host 'setup: creating .venv ...'
        python -m venv $venvPath
        if ($LASTEXITCODE -ne 0) { throw 'setup: python -m venv failed.' }
        Report $true 'venv' '.venv created'
    }

    $reqFile = Join-Path $repoRoot 'requirements.txt'
    if (Test-Path -LiteralPath $reqFile) {
        Write-Host 'setup: pip install -r requirements.txt ...'
        & $venvPython -m pip install -r $reqFile --quiet
        if ($LASTEXITCODE -ne 0) { throw 'setup: pip install failed.' }
        Report $true 'deps' 'requirements.txt installed into .venv'
    }
    else {
        Report $true 'deps' 'no requirements.txt yet — nothing to install (add one when tools/ grows deps)'
    }
}
else {
    Report $false 'venv' 'skipped — python 3.11+ missing'
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host "setup: $failures required prerequisite(s) missing (see FAIL lines above)."
    exit 1
}
Write-Host 'setup: all required prerequisites present.'
exit 0
