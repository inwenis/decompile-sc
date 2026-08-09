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
    7. hooktest (build.ps1 -Test), if a 32-bit toolchain is present

  It deliberately does NOT run the in-game suites: those are the worker's
  evidence and they need the game.

  A SKIPPED GATE IS NOT A PASSED GATE (task 023). Steps marked -Required have
  no legitimate reason to be absent here, so skipping one makes the verdict
  `incomplete` rather than `pass`. Optional steps (ruff, hooktest) may skip,
  but they are named on the receipt and printed, because a merge gated on a
  receipt is gated on what that receipt actually ran.

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
. (Join-Path $PSScriptRoot 'lib/ci-local.ps1')

if (-not (Test-Path -LiteralPath $WorkDir)) { throw "WorkDir not found: $WorkDir" }
Push-Location -LiteralPath $WorkDir
try {
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    $sha = (git rev-parse --short HEAD).Trim()
    $results = [ordered]@{}
    $failed = @()
    $skipped = @()
    $requiredSkipped = @()

    # A SKIP IS NOT A PASS (task 023). A step that could not run returns
    # Skip-Step instead of a detail string, and the receipt records it by name.
    # Before this, a step that skipped simply had not thrown, so the receipt
    # read `pass` and a merge gated on it was gated on nothing.
    function Skip-Step {
        param([Parameter(Mandatory)][string]$Why)
        [pscustomobject]@{ ScStepSkipped = $true; Reason = $Why }
    }

    function Step {
        # -Required: this step has no legitimate reason to be absent on this
        # repo, so skipping it makes the whole run `incomplete` rather than
        # `pass`. Left off for genuinely optional tooling (ruff, the 32-bit
        # toolchain) whose absence is a fact about the machine, not the code.
        param([string]$Name, [scriptblock]$Body, [switch]$Required)
        if (-not $Quiet) { Write-Host "== $Name" }
        try {
            $out = & $Body
            $isSkip = ($out -is [psobject]) -and
                      (@($out.PSObject.Properties.Name) -contains 'ScStepSkipped')
            if ($isSkip) {
                $script:results[$Name] = @{ ok = $true; skipped = $true
                                            required = [bool]$Required; detail = "$($out.Reason)" }
                $script:skipped += $Name
                if ($Required) { $script:requiredSkipped += $Name }
                Write-Host ("   SKIP $Name -- $($out.Reason)" + $(if ($Required) { '  (REQUIRED)' } else { '' }))
            } else {
                $script:results[$Name] = @{ ok = $true; skipped = $false
                                            required = [bool]$Required; detail = "$out" }
                if (-not $Quiet) { Write-Host "   OK  $out" }
            }
        } catch {
            $script:results[$Name] = @{ ok = $false; skipped = $false
                                        required = [bool]$Required; detail = $_.Exception.Message }
            $script:failed += $Name
            Write-Host "   FAIL $Name -- $($_.Exception.Message)"
        }
    }

    Step 'parse-ps1' -Required {
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

    Step 'validate-json' -Required {
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

    Step 'pester' -Required {
        # REQUIRED: this repo HAS tests/, so an absent one is a deleted one,
        # not a repo that never had any -- and that must not read as green.
        if (-not (Test-Path 'tests')) { return Skip-Step 'no tests/ directory' }
        Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop
        $r = Invoke-Pester -Path tests -CI -PassThru
        if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) Pester test(s) failed" }
        "$($r.PassedCount) passed"
    }

    Step 'game-content-guard' -Required {
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

    Step 'compile-python' -Required {
        if (-not (Test-Path 'tools')) { return Skip-Step 'no tools/ directory' }
        $py = if (Test-Path '.venv/Scripts/python.exe') { '.venv/Scripts/python.exe' } else { 'python' }
        & $py -m compileall -q tools
        if ($LASTEXITCODE -ne 0) { throw "compileall exit $LASTEXITCODE" }
        'tools/ byte-compiled'
    }

    Step 'ruff' {
        $py = if (Test-Path '.venv/Scripts/python.exe') { '.venv/Scripts/python.exe' } else { 'python' }
        & $py -m ruff --version *> $null
        if ($LASTEXITCODE -ne 0) { $global:LASTEXITCODE = 0; return Skip-Step 'ruff not installed' }
        & $py -m ruff check tools
        if ($LASTEXITCODE -ne 0) { throw "ruff reported findings" }
        'ruff clean'
    }

    # THE ONE GATE THAT CAN FAIL ON A LOGIC ERROR. Parse and lint cannot: they
    # only see syntax. hooktest exercises the inline-detour engine and the log
    # for real, offline, in about six seconds, and its case [12] fails against
    # pre-023 code by construction. It is worth more here than everything above
    # it put together.
    #
    # NOT -Required, and honestly so: it needs the pinned 32-bit MinGW-w64,
    # which lives outside the repo (tools/plugin/README.md) and is not on a
    # GitHub runner. Absent toolchain is a fact about the machine, not about
    # the code -- so it SKIPS, by name, and the skip is on the receipt where a
    # reader can see the gate did not run.
    Step 'hooktest' {
        $build = Join-Path $WorkDir 'tools/plugin/build.ps1'
        if (-not (Test-Path -LiteralPath $build)) { return Skip-Step 'no tools/plugin/build.ps1' }
        $bin = if ($env:SC_MINGW32_BIN) { $env:SC_MINGW32_BIN }
               else { 'C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt\mingw32\bin' }
        if (-not (Test-Path -LiteralPath (Join-Path $bin 'g++.exe'))) {
            return Skip-Step "no 32-bit toolchain at $bin (set SC_MINGW32_BIN)"
        }
        $out = & $build -Test 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "build.ps1 -Test exit $LASTEXITCODE" }
        $tail = @($out -split "`r?`n" | Where-Object { $_ -match 'hooktest: (\d+) failure' })
        if ($tail.Count -eq 0) { throw 'build.ps1 -Test printed no hooktest verdict' }
        if ($tail[-1] -notmatch 'hooktest: 0 failure') { throw "hooktest reported failures: $($tail[-1].Trim())" }
        'hooktest 0 failures'
    }

    $receiptDir = Join-Path $repoRoot 'work/scratch/ci-local'
    New-Item -ItemType Directory -Force -Path $receiptDir | Out-Null
    $verdict = Get-CiReceiptVerdict -Failed $failed -RequiredSkipped $requiredSkipped
    $receipt = [ordered]@{
        branch          = $branch
        sha             = $sha
        workDir         = $WorkDir
        ranAt           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        verdict         = $verdict
        failed          = $failed
        # Present even when empty: merge-task.ps1 REFUSES a receipt without
        # these fields rather than assume an old one skipped nothing.
        skipped         = $skipped
        requiredSkipped = $requiredSkipped
        steps           = $results
        note            = 'local reproduction of .github/workflows/ci.yml, plus hooktest when a 32-bit toolchain is present; does NOT include the in-game suites'
    }
    $path = Join-Path $receiptDir "$branch-$sha.json"
    ($receipt | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8

    Write-Host ''
    # Printed on every path, including the pass: what did NOT run is part of
    # the result, not a footnote to it.
    if ($skipped.Count -gt 0) { Write-Host "ci-local: NOT RUN -- $($skipped -join ', ')" }
    switch ($verdict) {
        'pass' { Write-Host "ci-local: PASS  $branch@$sha  -> $path" }
        'incomplete' {
            Write-Host "ci-local: INCOMPLETE  $branch@$sha  -- required step(s) skipped: $($requiredSkipped -join ', ')  -> $path"
            Write-Host '           a skipped gate is not a passed gate; this receipt cannot substitute for CI.'
            exit 1
        }
        default {
            Write-Host "ci-local: FAIL  $branch@$sha  ($($failed -join ', '))  -> $path"
            exit 1
        }
    }
} finally {
    Pop-Location
}
