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

  The receipt also carries `pluginBuild` (issue #73, task 056): the build id,
  source digest and sha256 of the scplugin.dll the hooktest step built, read back
  out of the DLL itself. A sha alone says which SOURCE was checked; this says
  which BINARY the one gate that can fail on a logic error actually ran against.
  It is $null when hooktest skipped, because "no binary was built" and "a binary
  was built and not identified" are different facts.

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

    # ISSUE #72 HOLE 2. A dirty worktree means the bytes the steps below actually exercise are
    # NOT the committed tree named by $sha -- uncommitted edits (tracked or new/untracked; git
    # status --porcelain reports both, and Pester globs the filesystem so an untracked test file
    # is exercised same as a committed one) get tested and the receipt attributes the result to
    # the clean sha anyway. Recorded on the receipt, not refused here: run-ci-local.ps1 stays
    # usable for a quick local check against in-progress edits. The merge gate is what refuses it
    # (Get-CiReceiptRefusalReason in lib/ci-local.ps1), because that is the actual gate.
    $dirtyFiles = @(git status --porcelain | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $dirty = $dirtyFiles.Count -gt 0

    # ISSUE #72 HOLE 1 (part 1/2). Delete any receipt already on disk for THIS sha before any
    # step runs. Without this, a run that crashes partway (the exact failure mode part 2 below
    # fixes for Pester, but nothing guarantees it is the only way to crash) leaves an earlier
    # PASS receipt for the same sha sitting untouched, and merge-task.ps1 has no way to tell that
    # receipt apart from one this run actually produced.
    $receiptDir = Join-Path $repoRoot 'work/scratch/ci-local'
    New-Item -ItemType Directory -Force -Path $receiptDir | Out-Null
    $receiptPath = Join-Path $receiptDir "$branch-$sha.json"
    if (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath -Force }

    $results = [ordered]@{}
    $failed = @()
    $skipped = @()
    $requiredSkipped = @()
    # ISSUE #73 item 4, task 056. Filled in by the hooktest step when it actually builds;
    # stays $null when that step skips, so the receipt says "this run built nothing"
    # rather than carrying a build identity nothing in the run produced.
    $pluginBuild = $null

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
            # ISSUE #72 HOLE 3b: classify from lib/ci-local.ps1, which looks at the LAST
            # element when a step's body emitted output before returning Skip-Step -- $out is
            # then an array, and the old inline check here (`$out -is [psobject]`) is false for
            # an array, so the skip silently read as a pass. See Get-CiStepSkip.
            $skip = Get-CiStepSkip -Out $out
            if ($skip.IsSkip) {
                $script:results[$Name] = @{ ok = $true; skipped = $true
                                            required = [bool]$Required; detail = $skip.Reason }
                $script:skipped += $Name
                if ($Required) { $script:requiredSkipped += $Name }
                Write-Host ("   SKIP $Name -- $($skip.Reason)" + $(if ($Required) { '  (REQUIRED)' } else { '' }))
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
        # ISSUE #72 HOLE 1 (part 2/2). -CI sets Pester's Run.Exit = $true regardless of
        # -PassThru, which calls `exit` the instant a run goes red -- killing THIS PROCESS at
        # this line, before the throw below, the receipt write at the bottom of the script, and
        # the FAIL summary ever run. Measured on this machine with a deliberately-red fixture:
        # the child process exits 1 here and nothing after this line executes. Dropping -CI
        # keeps -PassThru's result object flowing to the throw on the next line instead, which
        # the Step wrapper above catches like any other step failure.
        $r = Invoke-Pester -Path tests -PassThru
        if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) Pester test(s) failed" }
        # ISSUE #72 HOLE 3a. PassedCount alone is what a stale receipt used to be judged by --
        # a smaller number with nothing to compare it against. SkippedCount/NotRunCount go into
        # the same detail string that lands in receipt.steps.pester.detail AND in the printed
        # "OK" line below, so an individual `It` (or whole container) that skipped is visible
        # next to the pass rather than silently shrinking the count. Not gated on: an
        # environment gap (no python -- see tests/make-test-map.Tests.ps1) is a fact about the
        # machine, the same reasoning run-ci-local.ps1 already applies to the optional ruff/
        # hooktest STEPS, one level down at the individual-test level.
        $subSkip = if ($r.SkippedCount -gt 0 -or $r.NotRunCount -gt 0) {
            ", $($r.SkippedCount) SKIPPED, $($r.NotRunCount) not-run (not compared against anything -- see AGENTS.md 'a skipped gate is not a passed gate')"
        } else { '' }
        "$($r.PassedCount) passed$subSkip"
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

    # ISSUE #35 -- the collision gate, and REQUIRED because it needs nothing but the
    # source. hooktest part numbers used to be written by hand and three branches each
    # claimed one another branch had already taken (024/026 -> [13], 021/025 -> [11],
    # 028/029 -> [16]). Every one merged cleanly on its own -- the declarations are in
    # different regions of the file, so git sees no conflict -- and was found only by
    # the person who merged the second side.
    #
    # hooktest.cpp now derives the number from the order the parts run (see Part()), so
    # a collision is no longer expressible. This step is what keeps it that way: it
    # fails if anyone writes a part header by hand again, and it fails on a duplicate
    # part NAME, which is the identifier that replaced the number.
    #
    # Deliberately NOT the same step as 'hooktest' below: that one needs the pinned
    # 32-bit toolchain and legitimately skips on a machine without it, and a gate for a
    # cross-branch collision must not be skippable on the branch that introduces one.
    Step 'hooktest-parts' -Required {
        $src = Join-Path $WorkDir 'tools/plugin/src/hooktest.cpp'
        if (-not (Test-Path -LiteralPath $src)) { return Skip-Step 'no tools/plugin/src/hooktest.cpp' }
        $text = Get-Content -Raw -LiteralPath $src

        $handWritten = @([regex]::Matches($text, 'printf\("\\n\[\d+\]'))
        if ($handWritten.Count -gt 0) {
            throw ("$($handWritten.Count) hand-written part header(s) in hooktest.cpp " +
                   "($($handWritten.ForEach({ $_.Value }) -join ', ')) -- use Part(`"name`"), " +
                   'which numbers by run order so two branches cannot claim the same number.')
        }

        $names = @([regex]::Matches($text, '(?m)^\s*Part\("([^"]+)"\)').ForEach({ $_.Groups[1].Value }))
        # PROVED POSITIVE: a regex that matched nothing would make the duplicate check
        # below vacuously green, which is the exact shape AGENTS.md's absence rule warns
        # about. If Part() is ever renamed, this fails loudly instead of passing hollow.
        if ($names.Count -lt 10) {
            throw "found only $($names.Count) Part(...) declarations in hooktest.cpp; the part scan is not matching (did Part() get renamed?)"
        }
        $dupes = @($names | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($dupes.Count -gt 0) {
            throw ("duplicate hooktest part name(s): " +
                   (($dupes | ForEach-Object { "'$($_.Name)' x$($_.Count)" }) -join ', ') +
                   ' -- the part name is what a failing log line is identified by, so two parts cannot share one.')
        }
        "$($names.Count) hooktest parts, all uniquely named, none hand-numbered"
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
        # ISSUE #73 item 4, task 056. This step is the only one that produces a BINARY, so it
        # is the only one that can say which binary the receipt's verdict covers. Recorded on
        # the receipt below (buildId/pluginSrcDigest/pluginDllSha256) -- read out of the DLL
        # that was just built, never recomputed from git here, so a receipt cannot claim a
        # build identity that no artifact ever had.
        $builtDll = Join-Path $WorkDir 'work/scratch/plugin-build/scplugin.dll'
        if (Test-Path -LiteralPath $builtDll) {
            . (Join-Path $WorkDir 'tools/plugin/sc-build-id.ps1')
            $stamp = Get-ScDllBuildStamp -Path $builtDll
            if ($stamp) {
                $script:pluginBuild = [ordered]@{
                    buildId       = $stamp.BuildId
                    srcDigest     = $stamp.SrcDigest
                    dllSha256     = (Get-FileHash -LiteralPath $builtDll -Algorithm SHA256).Hash
                }
            }
        }
        "hooktest 0 failures$(if ($script:pluginBuild) { " (built $($script:pluginBuild.buildId) src=$($script:pluginBuild.srcDigest))" })"
    }

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
        # ISSUE #72 HOLE 2. Present even when empty/false, same belt-and-braces reasoning as
        # skipped/requiredSkipped above -- merge-task.ps1 refuses a receipt missing this field
        # rather than assume a pre-tracking receipt was clean.
        dirty           = $dirty
        dirtyFiles      = $dirtyFiles
        # ISSUE #73 item 4. Which BINARY this receipt's verdict covers -- the identity
        # stamped into the DLL the hooktest step built, read back out of it. $null when
        # no build happened in this run (hooktest skipped), which is a different fact
        # from "it built something unidentified" and must not read as one.
        pluginBuild     = $pluginBuild
        steps           = $results
        note            = 'local reproduction of .github/workflows/ci.yml, plus hooktest when a 32-bit toolchain is present; does NOT include the in-game suites'
    }
    $path = $receiptPath
    ($receipt | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8

    Write-Host ''
    # Printed on every path, including the pass: what did NOT run -- or what
    # this run cannot vouch for -- is part of the result, not a footnote to it.
    if ($skipped.Count -gt 0) { Write-Host "ci-local: NOT RUN -- $($skipped -join ', ')" }
    if ($dirty) {
        Write-Host "ci-local: DIRTY WORKTREE ($($dirtyFiles.Count) change(s)) -- this receipt cannot substitute for CI at sha $sha; commit or stash and re-run"
    }
    if ($pluginBuild) {
        Write-Host "ci-local: plugin built in this run -- $($pluginBuild.buildId) src=$($pluginBuild.srcDigest) sha256=$($pluginBuild.dllSha256)"
    } else {
        Write-Host 'ci-local: no plugin binary was built in this run (hooktest skipped) -- this receipt covers source checks only.'
    }
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
