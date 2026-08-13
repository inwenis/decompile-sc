#Requires -Version 7
<#
Pester cases for the merge gate's hotfix path (task 072, issue #107).

WHY THESE EXIST. 2026-08-13: PR #105 broke every lock-taking suite on main;
live task 070 had the two-line fix ready as PR #106 -- and there was no
supported way to merge it. `merge-task.ps1 -Task 070` would have merged the
task's own deliverable and STAMPED THE TASK CLOSED mid-flight;
`merge-task.ps1 -Task 070 -Pr 106` bound '106' to the common parameter
-ProgressAction and died on an enum error. The conductor ran `gh pr merge` by
hand, against the standing rule. The fixture cases below run the real script:
the hotfix case fails against the pre-072 script by construction (the -Pr
binding error), and the stamp assertions pin that the hotfix path never
closes a task while the deliverable path still does.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../scripts/lib/merge-task.ps1')
    . (Join-Path $PSScriptRoot '../scripts/lib/close-task.ps1')  # Test-HasMergedStamp
}

Describe 'Get-HotfixRefusalReason' {

    It 'refuses a worker, same as the normal gate' {
        Get-HotfixRefusalReason -TaskId '070' -AgentTask '071' -Pr '106' `
            -TaskPrNumber '200' -HeadRefName 'task070-lockfix' |
            Should -Match 'worker'
    }

    It "refuses the task's own deliverable PR -- that merge must close the task, so it must run without -Pr" {
        $r = Get-HotfixRefusalReason -TaskId '070' -AgentTask $null -Pr '200' `
            -TaskPrNumber '200' -HeadRefName 'task070-widescreen'
        $r | Should -Match 'own deliverable'
        $r | Should -Match 'WITHOUT -Pr'
    }

    It 'refuses when the head branch could not be read -- ownership cannot be verified' {
        Get-HotfixRefusalReason -TaskId '070' -AgentTask $null -Pr '106' `
            -TaskPrNumber '200' -HeadRefName $null |
            Should -Match 'could not be read'
    }

    It "refuses a head branch belonging to another task" {
        Get-HotfixRefusalReason -TaskId '070' -AgentTask $null -Pr '106' `
            -TaskPrNumber '200' -HeadRefName 'task071-other-thing' |
            Should -Match 'does not belong to task 070'
    }

    It 'refuses a branch that merely starts with the task id digits (task0700-*)' {
        Get-HotfixRefusalReason -TaskId '070' -AgentTask $null -Pr '106' `
            -TaskPrNumber '200' -HeadRefName 'task0700-imposter' |
            Should -Match 'does not belong to task 070'
    }

    It 'allows a second PR off a task-owned branch (the #106 shape)' {
        Get-HotfixRefusalReason -TaskId '070' -AgentTask $null -Pr '106' `
            -TaskPrNumber '200' -HeadRefName 'task070-lockfix-strictmode' |
            Should -BeNullOrEmpty
    }

    It 'allows a hotfix from a task that has no deliverable PR yet (pr: -)' {
        Get-HotfixRefusalReason -TaskId '070' -AgentTask $null -Pr '106' `
            -TaskPrNumber $null -HeadRefName 'task070-lockfix-strictmode' |
            Should -BeNullOrEmpty
    }
}

Describe 'merge-task.ps1 -Pr against a fixture repo (issue #107)' {

    BeforeEach {
        $script:root = Join-Path ([IO.Path]::GetTempPath()) "merge-tests-$([guid]::NewGuid().ToString('N'))"
        $script:repo = Join-Path $script:root 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'work/tasks') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'work/messages/conductor') -Force | Out-Null

        # The whole scripts tree, copied: merge-task.ps1 resolves close-task.ps1,
        # set-conductor-status.ps1, refresh-pr-status.ps1 etc. off its OWN
        # location, so running the copy keeps every side effect (status.json,
        # pr-status.json, git commits) inside the fixture -- never in this repo.
        Copy-Item -Recurse -Path (Join-Path $PSScriptRoot '../scripts') -Destination (Join-Path $script:repo 'scripts')
        $script:mergeScript = Join-Path $script:repo 'scripts/merge-task.ps1'

        $script:taskFile = Join-Path $script:repo 'work/tasks/070-widescreen.md'
        Set-Content -LiteralPath $script:taskFile -Value @'
# Task 070 — widescreen thing

## Status

agent: 070
model: sonnet
pr: https://github.com/inwenis/decompile-sc/pull/200
'@

        # A real repo with a real origin, so the close path's pull/commit/push
        # all work: repo tracks main on a bare clone one directory up.
        git -C $script:repo init -q -b main 2>&1 | Out-Null
        git -C $script:repo config user.email 't@t' | Out-Null
        git -C $script:repo config user.name 't' | Out-Null
        git -C $script:repo add -A 2>&1 | Out-Null
        git -C $script:repo commit -q -m init 2>&1 | Out-Null
        $script:origin = Join-Path $script:root 'origin.git'
        git clone -q --bare $script:repo $script:origin 2>&1 | Out-Null
        git -C $script:repo remote add origin $script:origin 2>&1 | Out-Null
        git -C $script:repo fetch -q origin 2>&1 | Out-Null
        git -C $script:repo branch -q --set-upstream-to=origin/main main 2>&1 | Out-Null

        # A PASSING local receipt whose sha prefixes the head sha the shim reports.
        $script:receipt = Join-Path $script:root 'receipt.json'
        [ordered]@{
            sha = 'abc1234'; verdict = 'pass'; ranAt = '2026-08-13T12:00:00Z'
            skipped = @(); requiredSkipped = @(); dirty = $false; dirtyFiles = @()
        } | ConvertTo-Json | Set-Content -LiteralPath $script:receipt

        # gh shim: cloud checks always report 'none' (Actions down -- the exact
        # 2026-08-13 conditions), so every merge below is gated on the receipt.
        # Calls are logged one per line so a test can assert a merge DID NOT run.
        $script:ghLog = Join-Path $script:root 'gh-calls.log'
        Set-Content -LiteralPath $script:ghLog -Value ''
        $env:GH_SHIM_LOG = $script:ghLog
        $env:GH_SHIM_HEADSHA = 'abc1234def56789000000000000000000000000'
        $env:GH_SHIM_HEADREF = 'task070-lockfix-strictmode'
        function global:gh {
            # a literal comma-separated token (`--json state,mergedAt`) reaches a
            # FUNCTION as an array argument -- rejoin it the way gh.exe would see it
            $flat = foreach ($a in $args) { if ($a -is [array]) { $a -join ',' } else { $a } }
            $line = ($flat -join ' ')
            Add-Content -LiteralPath $env:GH_SHIM_LOG -Value $line
            $global:LASTEXITCODE = 0
            if ($line -match 'pr view' -and $line -match 'headRefOid') { return $env:GH_SHIM_HEADSHA }
            if ($line -match 'pr view' -and $line -match 'state,mergedAt') { return 'MERGED|2026-08-13T17:00:00Z' }
            if ($line -match 'pr view' -and $line -match 'state,mergeStateStatus,headRefName') {
                return '{"state":"OPEN","mergeStateStatus":"CLEAN","headRefName":"' + $env:GH_SHIM_HEADREF + '"}'
            }
            if ($line -match 'pr view' -and $line -match 'state,mergeStateStatus') {
                return '{"state":"OPEN","mergeStateStatus":"CLEAN"}'
            }
            if ($line -match 'pr checks') { $global:LASTEXITCODE = 8; return 'no checks reported' }
            return '{}'
        }

        # These tests play the conductor; a worker's env (this very Pester run
        # may be inside one) would trip the worker refusal first.
        $script:savedAgentTask = $env:AGENT_TASK
        $env:AGENT_TASK = $null
    }

    AfterEach {
        Remove-Item function:global:gh -ErrorAction SilentlyContinue
        if ($null -ne $script:savedAgentTask) { $env:AGENT_TASK = $script:savedAgentTask }
        else { $env:AGENT_TASK = $null }
        $env:GH_SHIM_LOG = $null; $env:GH_SHIM_HEADSHA = $null; $env:GH_SHIM_HEADREF = $null
        if ($script:root -and (Test-Path -LiteralPath $script:root)) {
            Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'merges a hotfix PR from a live task and the task stays OPEN (fails pre-072: -Pr bound to -ProgressAction)' {
        $out = & $script:mergeScript -Task 070 -Pr 106 -LocalCiReceipt $script:receipt 6>&1 | ForEach-Object { "$_" }
        $joined = $out -join "`n"

        # gated on the receipt, merged, and said out loud that nothing closed
        $joined | Should -Match 'SUBSTITUTED by local receipt'
        $joined | Should -Match 'WITHOUT closing task 070'
        $joined | Should -Match 'stays OPEN'
        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Match '(?m)^pr merge 106 '

        # the whole bug: no stamp, no close commit, task file untouched
        Test-HasMergedStamp -Content (Get-Content -Raw -LiteralPath $script:taskFile) | Should -BeFalse
        (git -C $script:repo log --format=%s) -join "`n" | Should -Not -Match 'close task 070'
    }

    It 'still closes the task on the deliverable path (no -Pr) -- existing behaviour unchanged' {
        & $script:mergeScript -Task 070 -LocalCiReceipt $script:receipt 6>&1 | Out-Null

        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Match '(?m)^pr merge 200 '
        Test-HasMergedStamp -Content (Get-Content -Raw -LiteralPath $script:taskFile) | Should -BeTrue
        (git -C $script:repo log --format=%s) -join "`n" | Should -Match 'close task 070 \(PR #200 merged\)'
    }

    It 'refuses a PR whose head branch belongs to another task, and merges nothing' {
        $env:GH_SHIM_HEADREF = 'task071-other-thing'
        { & $script:mergeScript -Task 070 -Pr 106 -LocalCiReceipt $script:receipt 6>$null } |
            Should -Throw '*does not belong to task 070*'
        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Not -Match 'pr merge'
        Test-HasMergedStamp -Content (Get-Content -Raw -LiteralPath $script:taskFile) | Should -BeFalse
    }

    It "refuses -Pr naming the task's own deliverable -- that merge must close the task" {
        { & $script:mergeScript -Task 070 -Pr 200 -LocalCiReceipt $script:receipt 6>$null } |
            Should -Throw "*own deliverable*"
        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Not -Match 'pr merge'
    }

    It 'refuses a hotfix with no receipt when cloud checks did not run' {
        { & $script:mergeScript -Task 070 -Pr 106 6>$null } |
            Should -Throw '*no CI checks reported*'
        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Not -Match 'pr merge'
    }

    It 'refuses a hotfix on a FAILING receipt' {
        [ordered]@{
            sha = 'abc1234'; verdict = 'fail'; ranAt = '2026-08-13T12:00:00Z'
            skipped = @(); requiredSkipped = @(); dirty = $false; dirtyFiles = @()
        } | ConvertTo-Json | Set-Content -LiteralPath $script:receipt
        { & $script:mergeScript -Task 070 -Pr 106 -LocalCiReceipt $script:receipt 6>$null } |
            Should -Throw "*verdict is 'fail'*"
        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Not -Match 'pr merge'
    }

    It 'refuses a worker on the hotfix path too' {
        $env:AGENT_TASK = '071'
        { & $script:mergeScript -Task 070 -Pr 106 -LocalCiReceipt $script:receipt 6>$null } |
            Should -Throw '*worker*'
        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Not -Match 'pr merge'
    }

    It 'refuses -Pr combined with -StopAgent -- stopping the worker belongs to the close path' {
        { & $script:mergeScript -Task 070 -Pr 106 -StopAgent -LocalCiReceipt $script:receipt 6>$null } |
            Should -Throw '*cannot be combined*'
        (Get-Content -Raw -LiteralPath $script:ghLog) | Should -Not -Match 'pr merge'
    }
}
