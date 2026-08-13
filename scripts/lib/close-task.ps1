# Pure/testable helpers for close-task.ps1 (task 035 -- USER RULE
# "completed = PR merged"). No `gh`, no `git`, no process work lives here --
# those side effects stay in scripts/close-task.ps1 so this file can be
# dot-sourced straight into Pester and exercised on strings. See
# tests/close-task.Tests.ps1.

function Get-TaskPrNumber {
    # PR number from a task file's `pr:` line, or $null when there is no PR to
    # merge (`pr: -`, `pr: - (cancelled)`, or no pr: line). Real values are
    # GitHub pull URLs ending in /pull/<n>.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $m = [regex]::Match($Content, '(?m)^pr:\s*(.+?)\s*$')
    if (-not $m.Success) { return $null }
    $value = $m.Groups[1].Value.Trim()
    if ($value -eq '' -or $value.StartsWith('-')) { return $null }
    $num = [regex]::Match($value, '/pull/(\d+)')
    if (-not $num.Success) { return $null }
    return $num.Groups[1].Value
}

function Test-PrIsMerged {
    # gh reports a pull request state as MERGED | OPEN | CLOSED. Only MERGED
    # means the work actually landed (CLOSED = closed without merging).
    param([Parameter(Mandatory)][AllowEmptyString()][string]$State)
    return $State -eq 'MERGED'
}

function Get-CloseRefusalReason {
    # The gate. Returns $null when the task may be closed, otherwise a
    # human-readable reason to refuse. This is the pure heart of close-task.ps1's
    # "refuse to stamp an unmerged PR" guarantee.
    #
    # Task 069, issue #96: a task with no PR used to be refused with "already
    # completed -- nothing to verify or stamp", which was FALSE twice over: the
    # status derivation completes only on a merged: stamp, so an unstamped
    # report-only task reads queued/running forever, and board-lint class 2 kept
    # (rightly) flagging it while this gate forbade the only remedy. A no-PR task
    # WITH a report is now closeable -- the report is the deliverable to verify;
    # a no-PR task with NO report still refuses, because nothing was delivered.
    param(
        [AllowNull()][AllowEmptyString()][string]$PrNumber,
        [AllowNull()][AllowEmptyString()][string]$PrState,
        [bool]$ReportExists = $false
    )
    if ([string]::IsNullOrEmpty($PrNumber)) {
        if ($ReportExists) { return $null }
        return 'task has no PR (pr: -) and no report at work/reports/ -- nothing was delivered, nothing to stamp'
    }
    if (-not (Test-PrIsMerged -State $PrState)) {
        return "PR #$PrNumber is '$PrState', not MERGED -- refusing to stamp merged:"
    }
    return $null
}

function Get-MergedDate {
    # The date portion (yyyy-MM-dd) of gh's mergedAt (an ISO instant), which is
    # what we stamp into `merged:`. A bare date passes straight through.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$MergedAt)
    $m = [regex]::Match($MergedAt, '^\d{4}-\d{2}-\d{2}')
    if (-not $m.Success) { throw "Unrecognized merged-at value: '$MergedAt'" }
    return $m.Value
}

function Add-MergedStamp {
    # Insert (or replace) a `merged: <Date>` line in a task file's Status block,
    # placed directly under the `pr:` line. Preserves the file's existing line
    # endings (task files are CRLF). Pure string transform.
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Date
    )
    $eol = if ($Content -match "`r`n") { "`r`n" } else { "`n" }

    # already stamped -> replace the value in place, never duplicate
    $mergedRe = [regex]'(?m)^merged:[^\r\n]*'
    if ($mergedRe.IsMatch($Content)) {
        return $mergedRe.Replace($Content, "merged: $Date", 1)
    }

    $prRe = [regex]'(?m)^pr:[^\r\n]*'
    $m = $prRe.Match($Content)
    if (-not $m.Success) { throw 'No pr: line found; cannot stamp merged: after it.' }
    $insertAt = $m.Index + $m.Length  # end of the 'pr: ...' text, before its EOL
    return $Content.Substring(0, $insertAt) + $eol + "merged: $Date" + $Content.Substring($insertAt)
}

function New-CloseCommitMessage {
    # The standard close-commit subject (matches the repo's existing history:
    # "chore(tasks): close task NNN (PR #M merged)"). No PR number = the
    # report-only close (task 069, issue #96).
    param(
        [Parameter(Mandatory)][string]$Task,
        [AllowNull()][AllowEmptyString()][string]$PrNumber
    )
    $id = '{0:D3}' -f [int]$Task
    if ([string]::IsNullOrEmpty($PrNumber)) {
        return "chore(tasks): close task $id (report-only; no PR)"
    }
    return "chore(tasks): close task $id (PR #$PrNumber merged)"
}

function Test-HasMergedStamp {
    # Whether a task file's content already carries a `merged:` stamp with a
    # real value. Shared gate for -Prune (task 063 -- memory lesson: never
    # prune an open task's worktree) and for prune-worktrees.ps1's backlog scan.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    return [regex]::IsMatch($Content, '(?m)^merged:\s*\S')
}

function Get-TaskSlug {
    # tasks/<NNN>-<slug>.md FILE NAME (not full path) -> slug, mirroring the
    # naming convention new-task.ps1 writes. Needed to reconstruct the
    # taskNNN-<slug> branch name for -Prune's `git branch -D`.
    param([Parameter(Mandatory)][string]$FileName)
    $m = [regex]::Match($FileName, '^\d{3}-(.+)\.md$')
    if (-not $m.Success) { throw "Get-TaskSlug: '$FileName' doesn't match NNN-<slug>.md" }
    return $m.Groups[1].Value
}

function Get-PruneRefusalReason {
    # The prune gate (mirrors Get-CloseRefusalReason's shape): refuse to
    # remove a task's worktree unless (a) its file carries a merged: stamp
    # -- memory lesson: never prune an open task's worktree -- and (b) the
    # worktree is clean, so -Prune never silently discards uncommitted work.
    # Side effects (worktree existence, git status) are the caller's job;
    # this stays pure so the refusal matrix is Pester-testable on strings.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][bool]$WorktreeExists,
        [Parameter(Mandatory)][bool]$WorktreeClean
    )
    if (-not (Test-HasMergedStamp -Content $Content)) {
        return "task has no merged: stamp -- refusing to prune an open task's worktree"
    }
    if (-not $WorktreeExists) {
        return 'worktree does not exist -- nothing to prune'
    }
    if (-not $WorktreeClean) {
        return 'worktree has uncommitted changes (git status --porcelain nonempty) -- refusing to discard work; remove by hand after inspecting'
    }
    return $null
}
