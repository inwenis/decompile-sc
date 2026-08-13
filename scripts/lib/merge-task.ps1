# Pure/testable helpers for merge-task.ps1 (task 059 -- the mechanical merge
# gate). No `gh`, no `git`, no process work lives here -- those side effects
# stay in scripts/merge-task.ps1 so this file can be dot-sourced straight into
# Pester and exercised on strings. Same split as lib/close-task.ps1.
# See tests/merge-task.Tests.ps1.

function Get-ChecksVerdict {
    # Collapse `gh pr checks <pr> --json bucket,workflow` (a JSON array of
    # checks) into one word: pass | fail | pending | none.
    #
    # gh's buckets are pass | fail | pending | skipping | cancel. A skip is not
    # a failure; a cancel is. Anything unparseable (gh prints "no checks
    # reported on the 'x' branch" and exits 8) is 'none' -- never guess green.
    #
    # 'none' specifically means OUR workflow did not run. This repo also gets
    # third-party app checks (GitGuardian runs on every PR, `workflow` empty),
    # so "some check passed" is not evidence that the tests ran -- a branch cut
    # before ci.yml existed would otherwise look green off a secrets scan alone.
    # Those third-party checks still count for fail/pending: a red one is red.
    param(
        [AllowNull()][AllowEmptyString()][string]$Json,
        # `name:` of the workflow in .github/workflows/ci.yml
        [string]$Workflow = 'CI'
    )

    if ([string]::IsNullOrWhiteSpace($Json)) { return 'none' }
    try { $checks = @($Json | ConvertFrom-Json) } catch { return 'none' }

    $ours = @($checks | Where-Object { $_.workflow -eq $Workflow })
    if ($ours.Count -eq 0) { return 'none' }

    $buckets = @($checks | ForEach-Object { $_.bucket } | Where-Object { $_ })
    if ($buckets | Where-Object { $_ -in @('fail', 'cancel') }) { return 'fail' }
    if ($buckets | Where-Object { $_ -eq 'pending' }) { return 'pending' }
    return 'pass'
}

function Get-TaskMergedStamp {
    # The `merged: <date>` value close-task.ps1 stamps, or $null when the task
    # was never closed. A stamped task must never be merged again.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $m = [regex]::Match($Content, '(?m)^merged:\s*(\S+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-LocalRefusalReason {
    # Half the gate that needs no network: who is running this, and whether the
    # task has an unmerged PR at all. merge-task.ps1 runs this BEFORE spending
    # a `gh` round-trip.
    #
    # Task 071 removed the `state: done` check that used to sit here. Status is
    # derived from observables now -- workers write no state transitions -- so
    # "the worker says it has finished" is not a fact this gate can read. The
    # evidence that replaces it is the PR itself: it must exist (below) and be
    # OPEN (Get-RemoteRefusalReason). A worker that has not finished has not
    # opened a PR, and one that opened a PR has delivered something to review.
    param(
        [Parameter(Mandatory)][string]$TaskId,
        # $env:AGENT_TASK -- set means a worker is running this, and workers
        # never merge (AGENTS.md). merge-task.ps1 is the only merge path, so
        # this is where that rule is enforced for it.
        [AllowNull()][AllowEmptyString()][string]$AgentTask,
        [AllowNull()][AllowEmptyString()][string]$PrNumber,
        [AllowNull()][AllowEmptyString()][string]$MergedStamp
    )

    if (-not [string]::IsNullOrEmpty($AgentTask)) {
        return "a worker (AGENT_TASK=$AgentTask) may never merge a PR -- ask the conductor to run merge-task"
    }
    if ([string]::IsNullOrEmpty($PrNumber)) {
        return "task $TaskId has no PR (pr: -) -- nothing to merge"
    }
    if (-not [string]::IsNullOrEmpty($MergedStamp)) {
        return "task $TaskId is already stamped 'merged: $MergedStamp' -- it was closed on that date"
    }
    return $null
}

function Get-RemoteRefusalReason {
    # Half the gate that reads GitHub: the PR's own state, its position against
    # origin/main, and its CI verdict.
    param(
        [Parameter(Mandatory)][string]$PrNumber,
        [AllowNull()][AllowEmptyString()][string]$PrState,
        [AllowNull()][AllowEmptyString()][string]$MergeStateStatus,
        [AllowNull()][AllowEmptyString()][string]$ChecksVerdict
    )

    if ($PrState -ne 'OPEN') {
        return "PR #$PrNumber is '$PrState', not OPEN -- nothing to merge"
    }

    switch ($MergeStateStatus) {
        'BEHIND' { return "PR #$PrNumber is BEHIND origin/main -- merge origin/main into the branch and push, then re-run" }
        'DIRTY'  { return "PR #$PrNumber has merge conflicts with origin/main -- resolve them on the branch first" }
        'DRAFT'  { return "PR #$PrNumber is a draft -- mark it ready for review first" }
    }

    switch ($ChecksVerdict) {
        'fail'    { return "CI is red on PR #$PrNumber -- fix the branch, do not merge around it" }
        'pending' { return "CI is still running on PR #$PrNumber -- wait for it" }
        'none'    { return "no CI checks reported on PR #$PrNumber -- the branch predates .github/workflows/ci.yml; merge origin/main into it and push" }
    }

    return $null
}

function Get-HotfixRefusalReason {
    # The -Pr gate (issue #107): merge a hotfix PR raised by a LIVE task
    # without closing that task. Everything the normal gate checks about the
    # PR itself (OPEN, position against main, CI verdict, receipt
    # substitution) still runs through Get-RemoteRefusalReason and the receipt
    # path; this covers only what is DIFFERENT about the hotfix case: who may
    # run it, that the named PR is not the task's own deliverable (that path
    # must go through the close), and that the PR's head branch actually
    # belongs to the named task (branch convention taskNNN-<slug>).
    param(
        [Parameter(Mandatory)][string]$TaskId,
        # $env:AGENT_TASK -- same rule as Get-LocalRefusalReason: workers
        # never merge, hotfix or not.
        [AllowNull()][AllowEmptyString()][string]$AgentTask,
        [Parameter(Mandatory)][string]$Pr,
        # the task file's own pr: number, $null when it has none yet
        [AllowNull()][AllowEmptyString()][string]$TaskPrNumber,
        [AllowNull()][AllowEmptyString()][string]$HeadRefName
    )

    if (-not [string]::IsNullOrEmpty($AgentTask)) {
        return "a worker (AGENT_TASK=$AgentTask) may never merge a PR -- ask the conductor to run merge-task"
    }
    if (-not [string]::IsNullOrEmpty($TaskPrNumber) -and $Pr -eq $TaskPrNumber) {
        return "PR #$Pr is task $TaskId's own deliverable (its pr: line) -- run merge-task.ps1 -Task $TaskId WITHOUT -Pr so the task is closed with it"
    }
    if ([string]::IsNullOrEmpty($HeadRefName)) {
        return "PR #$Pr's head branch could not be read -- cannot verify it belongs to task $TaskId"
    }
    if ($HeadRefName -notlike "task$TaskId-*") {
        return "PR #$Pr's head branch '$HeadRefName' does not belong to task $TaskId (expected task$TaskId-*) -- run with the task that owns that branch"
    }
    return $null
}

function Get-MergeRefusalReason {
    # The whole gate, in the order a human wants to read it: role, then task
    # hygiene, then the PR, then CI, then policy. $null means "merge it".
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [AllowNull()][AllowEmptyString()][string]$AgentTask,
        [AllowNull()][AllowEmptyString()][string]$PrNumber,
        [AllowNull()][AllowEmptyString()][string]$PrState,
        [AllowNull()][AllowEmptyString()][string]$MergedStamp,
        [AllowNull()][AllowEmptyString()][string]$MergeStateStatus,
        [AllowNull()][AllowEmptyString()][string]$ChecksVerdict,
        [switch]$HumanOk,
        # Policy switch: the conductor is the human's delegate, so an explicit
        # -HumanOk is NOT required today. Flip this to make it mandatory.
        [switch]$RequireHumanOk
    )

    $local = Get-LocalRefusalReason -TaskId $TaskId -AgentTask $AgentTask `
        -PrNumber $PrNumber -MergedStamp $MergedStamp
    if ($local) { return $local }

    $remote = Get-RemoteRefusalReason -PrNumber $PrNumber -PrState $PrState `
        -MergeStateStatus $MergeStateStatus -ChecksVerdict $ChecksVerdict
    if ($remote) { return $remote }

    if ($RequireHumanOk -and -not $HumanOk) {
        return "policy requires an explicit -HumanOk for task $TaskId"
    }

    return $null
}
