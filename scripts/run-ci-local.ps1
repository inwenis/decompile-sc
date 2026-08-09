#Requires -Version 7
<#
.SYNOPSIS
  Run the CI workflow's checks locally, against a worktree, and write a receipt.

.DESCRIPTION
  .github/workflows/ci.yml is pure pwsh + python -- nothing in it needs GitHub's
  runner. When Actions cannot run (billing, outage, offline), this reproduces the
  same gates locally so a merge is still evidenced rather than waved through.

  Steps mirrored from ci.yml, in order:
    1. parse-check every .ps1
    2. validate JSON under config/ and .claude/
    3. Pester, if tests/ exists
    4. guard against tracked game-content / oversized files (hard rule 1)
    5. byte-compile tools/*.py
    6. ruff, if installed

  It deliberately does NOT run hooktest or the in-game suites: those are the
  worker's evidence and they need the game. This is the CI equivalent, no more.

  Writes a receipt to work/scratch/ci-local/<branch>-<sha>.json so a merge can
  cite something durable. The receipt is scratch (gitignored) by design -- it
  records that a check ran, it is not a claim to be committed.

.EXAMPLE
  ./scripts/run-ci-local.ps1 -WorkDir C:/git/decompile-sc-task021
#>
param(
    [string]$WorkDir = (Split-Path $PSScriptRoot -Parent),
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path -LiteralPath $WorkDir)) { throw "WorkDir not found: $WorkDir" }
Push-Location -LiteralPath $WorkDir
try {
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    $sha = (git rev-parse --short HEAD).Trim()
    $results = [ordered]@{}
    $failed = @()

    function Step {
        param([string]$Name, [scriptblock]$Body)
        if (-not $Quiet) { Write-Host "== $Name" }
        try {
            $out = & $Body
            $script:results[$Name] = @{ ok = $true; detail = "$out" }
            if (-not $Quiet) { Write-Host "   OK  $out" }
        } catch {
            $script:results[$Name] = @{ ok = $false; detail = $_.Exception.Message }
            $script:failed += $Name
            Write-Host "   FAIL $Name -- $($_.Exception.Message)"
        }
    }

    Step 'parse-ps1' {
        $files = Get-ChildItem -Path . -Filter *.ps1 -Recurse -File |
            Where-Object { $_.FullName -notmatch '\\\.git\\' }
        $bad = @()
        foreach ($f in $files) {
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$parseErrors) | Out-Null
            if ($parseErrors.Count -gt 0) { $bad += $f.FullName }
        }
        if ($bad.Count -gt 0) { throw "parse errors in: $($bad -join ', ')" }
        "parsed $($files.Count) .ps1 files"
    }

    Step 'validate-json' {
        $jsonFiles = @()
        foreach ($dir in @('config', '.claude')) {
            if (Test-Path $dir) { $jsonFiles += Get-ChildItem -Path $dir -Filter *.json -Recurse -File }
        }
        $bad = @()
        foreach ($f in $jsonFiles) {
            try { Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json | Out-Null }
            catch { $bad += $f.FullName }
        }
        if ($bad.Count -gt 0) { throw "invalid JSON: $($bad -join ', ')" }
        "validated $($jsonFiles.Count) JSON files"
    }

    Step 'pester' {
        if (-not (Test-Path 'tests')) { return 'no tests/ -- skipped' }
        Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop
        $r = Invoke-Pester -Path tests -CI -PassThru
        if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) Pester test(s) failed" }
        "$($r.PassedCount) passed"
    }

    Step 'game-content-guard' {
        $bannedExt = @('.exe', '.dll', '.mpq', '.snp', '.grp', '.chk', '.rep', '.idb', '.i64', '.gpr',
                       '.scm', '.scx', '.pcx', '.smk', '.wav')
        $maxBytes = 5MB
        $tracked = git ls-files
        $bad = @()
        foreach ($f in $tracked) {
            if ($bannedExt -contains ([System.IO.Path]::GetExtension($f).ToLowerInvariant())) { $bad += $f; continue }
            if ((Test-Path -LiteralPath $f -PathType Leaf) -and ((Get-Item -LiteralPath $f).Length -gt $maxBytes)) { $bad += $f }
        }
        if ($bad.Count -gt 0) { throw "tracked game-content/oversized: $($bad -join ', ')" }
        "checked $($tracked.Count) tracked files"
    }

    Step 'compile-python' {
        if (-not (Test-Path 'tools')) { return 'no tools/ -- skipped' }
        $py = if (Test-Path '.venv/Scripts/python.exe') { '.venv/Scripts/python.exe' } else { 'python' }
        & $py -m compileall -q tools
        if ($LASTEXITCODE -ne 0) { throw "compileall exit $LASTEXITCODE" }
        'tools/ byte-compiled'
    }

    Step 'ruff' {
        $py = if (Test-Path '.venv/Scripts/python.exe') { '.venv/Scripts/python.exe' } else { 'python' }
        & $py -m ruff --version *> $null
        if ($LASTEXITCODE -ne 0) { $global:LASTEXITCODE = 0; return 'ruff not installed -- skipped' }
        & $py -m ruff check tools
        if ($LASTEXITCODE -ne 0) { throw "ruff reported findings" }
        'ruff clean'
    }

    $receiptDir = Join-Path $repoRoot 'work/scratch/ci-local'
    New-Item -ItemType Directory -Force -Path $receiptDir | Out-Null
    $receipt = [ordered]@{
        branch    = $branch
        sha       = $sha
        workDir   = $WorkDir
        ranAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        verdict   = if ($failed.Count -eq 0) { 'pass' } else { 'fail' }
        failed    = $failed
        steps     = $results
        note      = 'local reproduction of .github/workflows/ci.yml; does NOT include hooktest or in-game suites'
    }
    $path = Join-Path $receiptDir "$branch-$sha.json"
    ($receipt | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8

    Write-Host ''
    if ($failed.Count -eq 0) {
        Write-Host "ci-local: PASS  $branch@$sha  -> $path"
    } else {
        Write-Host "ci-local: FAIL  $branch@$sha  ($($failed -join ', '))  -> $path"
        exit 1
    }
} finally {
    Pop-Location
}
