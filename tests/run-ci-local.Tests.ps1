#Requires -Version 7
<#
Integration coverage for scripts/run-ci-local.ps1 itself -- the receipt WRITER. Everything in
tests/ci-local.Tests.ps1 covers the pure helpers in lib/ci-local.ps1 in-process; this file proves
the actual script, run as a real child process, behaves the way those helpers assume it does.

THE BUG THIS PINS (task 053 / issue #72 hole 1). `Invoke-Pester -Path tests -CI -PassThru` calls
`exit` the instant a run goes red -- Pester's -CI switch sets `Configuration.Run.Exit = $true`
regardless of -PassThru -- so the WHOLE run-ci-local.ps1 process used to die at that line. The
`if ($r.FailedCount -gt 0) { throw ... }` on the next line, the receipt write at the bottom of
the script, and the FAIL summary never ran. Measured on this machine (conductor, 2026-08-12) with
a deliberately-red fixture suite: the child process exit code is 1 and a marker line placed right
after Invoke-Pester never printed. If an EARLIER run at the same sha had written a PASS receipt,
that stale file survived untouched and merge-task.ps1 accepted it -- a red run and a green run
then differed only in console output nobody re-reads.

These tests invoke scripts/run-ci-local.ps1 as a CHILD PROCESS (`pwsh -File ...`) against a
throwaway git fixture repo under $TestDrive -- never the real repo; see AGENTS.md's task-074 note
on not writing into a repo's own tracked directories from a test. An in-process call would be
worthless here anyway: the exact bug this pins would `exit` THIS Pester host too.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RunCiLocal = Join-Path $script:RepoRoot 'scripts/run-ci-local.ps1'
    $script:CreatedReceipts = [System.Collections.Generic.List[string]]::new()

    function New-CiFixtureRepo {
        <#
        Minimal git repo with one committed Pester test file, so run-ci-local.ps1's own git
        plumbing (rev-parse, status --porcelain, ls-files) has something real to read.
        #>
        param(
            [Parameter(Mandatory)][string]$TestBody,   # an Pester It-block body, e.g. '1 | Should -Be 1'
            [switch]$LeaveDirty                        # leave an uncommitted edit after the commit
        )
        $dir = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir 'tests') -Force | Out-Null
        # A marker line BEFORE the throw-worthy assertion: if hole 1 regresses, this prints and
        # the process then dies inside Invoke-Pester before the receipt is ever written -- the
        # console transcript names exactly where execution stopped.
        Set-Content -LiteralPath (Join-Path $dir 'tests/fixture.Tests.ps1') -Encoding utf8 -Value @"
Describe 'fixture' {
    It 'does the thing' {
        $TestBody
    }
}
"@
        Push-Location $dir
        try {
            git init -q -b main | Out-Null
            git config user.email 'ci-local-tests@example.invalid' | Out-Null
            git config user.name 'ci-local-tests' | Out-Null
            git add -A | Out-Null
            git commit -q -m 'fixture' | Out-Null
            if ($LeaveDirty) {
                Add-Content -LiteralPath (Join-Path $dir 'tests/fixture.Tests.ps1') -Value '# uncommitted edit'
            }
        } finally { Pop-Location }
        $dir
    }

    function Get-CiFixtureReceiptPath {
        param([Parameter(Mandatory)][string]$WorkDir)
        Push-Location $WorkDir
        try {
            $branch = (git rev-parse --abbrev-ref HEAD).Trim()
            $sha = (git rev-parse --short HEAD).Trim()
        } finally { Pop-Location }
        Join-Path $script:RepoRoot "work/scratch/ci-local/$branch-$sha.json"
    }

    function Invoke-CiFixtureRun {
        <#
        Runs the real script as a CHILD PROCESS -- see the file banner for why that is load-
        bearing, not incidental, for the test this exists to write.
        #>
        param([Parameter(Mandatory)][string]$WorkDir)
        $receiptPath = Get-CiFixtureReceiptPath -WorkDir $WorkDir
        if (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath -Force }
        $script:CreatedReceipts.Add($receiptPath)
        # Not -Quiet: the printed-summary assertions in this file need the per-step OK/SKIP/FAIL
        # lines, which -Quiet suppresses for the non-skip, non-fail case.
        $out = & pwsh -NoLogo -NoProfile -File $script:RunCiLocal -WorkDir $WorkDir 2>&1 | Out-String
        [pscustomobject]@{
            ExitCode    = $LASTEXITCODE
            Output      = $out
            ReceiptPath = $receiptPath
        }
    }
}

AfterAll {
    # Scratch, gitignored, harmless either way -- tidy up so repeat local runs of this suite
    # do not accumulate throwaway receipts under the real repo's work/scratch/ci-local/.
    foreach ($p in $script:CreatedReceipts) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'run-ci-local.ps1 -- a red Pester run must reach its own receipt write' {

    It 'writes verdict fail (not a stale/absent receipt) and exits non-zero' {
        $dir = New-CiFixtureRepo -TestBody '1 | Should -Be 2'
        $result = Invoke-CiFixtureRun -WorkDir $dir

        # Pre-fix: the child process died inside Invoke-Pester -CI. Nothing after that line ran,
        # so the receipt from THIS invocation would never have existed at all.
        Test-Path -LiteralPath $result.ReceiptPath |
            Should -BeTrue -Because "the receipt write must be reached even on a red Pester run:`n$($result.Output)"

        $receipt = Get-Content -Raw -LiteralPath $result.ReceiptPath | ConvertFrom-Json
        $receipt.verdict | Should -Be 'fail'
        $receipt.failed | Should -Contain 'pester'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'ci-local: FAIL'
    }

    It 'lets a green Pester run reach the receipt too, with pester recorded ok' {
        $dir = New-CiFixtureRepo -TestBody '1 | Should -Be 1'
        $result = Invoke-CiFixtureRun -WorkDir $dir

        Test-Path -LiteralPath $result.ReceiptPath | Should -BeTrue
        $receipt = Get-Content -Raw -LiteralPath $result.ReceiptPath | ConvertFrom-Json
        # NOT asserted as top-level verdict 'pass': this throwaway fixture has no tools/ dir and
        # no tools/plugin/src/hooktest.cpp, so the UNRELATED -Required compile-python/
        # hooktest-parts steps legitimately Skip-Step and push the overall verdict to
        # 'incomplete' -- correctly, that repo shape really is missing required tooling. The
        # claim this case pins is narrower and still decisive: the pester step itself passed and
        # was reached, which the pre-fix -CI bug could never show for ANY outcome.
        $receipt.steps.pester.ok | Should -BeTrue
        $receipt.failed | Should -Not -Contain 'pester'
    }

    It 'records SkippedCount/NotRunCount in the pester step detail, visible in the receipt and the printed summary' {
        $dir = New-CiFixtureRepo -TestBody 'Set-ItResult -Skipped -Because "demo skip"'
        $result = Invoke-CiFixtureRun -WorkDir $dir

        $receipt = Get-Content -Raw -LiteralPath $result.ReceiptPath | ConvertFrom-Json
        $receipt.steps.pester.detail | Should -Match '1 SKIPPED'
        $result.Output | Should -Match '1 SKIPPED'
    }
}

Describe 'run-ci-local.ps1 -- a dirty worktree is recorded on the receipt' {

    It 'sets dirty=true and names the changed file when the worktree has an uncommitted edit' {
        $dir = New-CiFixtureRepo -TestBody '1 | Should -Be 1' -LeaveDirty
        $result = Invoke-CiFixtureRun -WorkDir $dir

        $receipt = Get-Content -Raw -LiteralPath $result.ReceiptPath | ConvertFrom-Json
        $receipt.dirty | Should -BeTrue
        @($receipt.dirtyFiles) | Should -Not -BeNullOrEmpty
        $result.Output | Should -Match 'DIRTY WORKTREE'
    }

    It 'sets dirty=false on a clean worktree' {
        $dir = New-CiFixtureRepo -TestBody '1 | Should -Be 1'
        $result = Invoke-CiFixtureRun -WorkDir $dir

        $receipt = Get-Content -Raw -LiteralPath $result.ReceiptPath | ConvertFrom-Json
        $receipt.dirty | Should -BeFalse
        @($receipt.dirtyFiles) | Should -BeNullOrEmpty
    }
}

Describe 'run-ci-local.ps1 -- a crashed run cannot leave a stale pass behind' {

    It 'never leaves an old PASS receipt in place once a run at the same sha goes red' {
        # Simulates exactly the scenario hole 1 made possible: a PASS receipt already on disk
        # for this sha (written by an earlier, unrelated green run, or hand-planted here to
        # stand in for one) must not survive a run that is about to fail. Pre-fix, the -CI exit
        # happened before the receipt write was ever reached, so the stale file below would have
        # come out of this test completely untouched.
        $dir = New-CiFixtureRepo -TestBody '1 | Should -Be 2'
        $receiptPath = Get-CiFixtureReceiptPath -WorkDir $dir
        New-Item -ItemType Directory -Force -Path (Split-Path $receiptPath -Parent) | Out-Null
        '{"verdict":"pass","stale":true}' | Set-Content -LiteralPath $receiptPath -Encoding utf8
        $script:CreatedReceipts.Add($receiptPath)

        # Not Invoke-CiFixtureRun: that helper deletes any pre-existing receipt itself before
        # invoking the child, which would make this test pass for the wrong reason (the harness
        # cleaning up, not the script under test). Invoke the child directly instead, with the
        # stale file left in place for run-ci-local.ps1 itself to deal with.
        $out = & pwsh -NoLogo -NoProfile -File $script:RunCiLocal -WorkDir $dir -Quiet 2>&1 | Out-String

        Test-Path -LiteralPath $receiptPath | Should -BeTrue
        $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
        $receipt.verdict | Should -Be 'fail' -Because "the file must reflect THIS run, not the stale one:`n$out"
        $receipt.PSObject.Properties.Name | Should -Not -Contain 'stale'
    }
}
