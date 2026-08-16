# Pure helpers for scripts/refresh-pr-status.ps1 -- no filesystem or gh
# calls, so tests can dot-source this file directly and exercise the
# extraction/mapping logic without a real checkout or network access.

# Task id + PR url from one task file's content: the `# Task NNN -- <title>`
# heading (same em-dash format src/core/parseTasks.ts matches) plus the
# Status section's `pr: <url>` line. Returns $null when either is missing,
# or when pr: is the placeholder "-" (no PR yet), or the url isn't a
# recognizable GitHub PR link.
function Get-TaskPrRef {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $headingMatch = [regex]::Match($Content, '(?m)^#\s+Task\s+(\S+)\s*—')
    if (-not $headingMatch.Success) { return $null }
    $taskId = $headingMatch.Groups[1].Value

    $prMatch = [regex]::Match($Content, '(?m)^pr:\s*(\S+)\s*$')
    if (-not $prMatch.Success) { return $null }
    $prValue = $prMatch.Groups[1].Value
    if ($prValue -eq '-') { return $null }

    $urlMatch = [regex]::Match($prValue, '/pull/(\d+)$')
    if (-not $urlMatch.Success) { return $null }

    [PSCustomObject]@{
        TaskId = $taskId
        Number = [int]$urlMatch.Groups[1].Value
        Url    = $prValue
    }
}

# Whether a task's PR still needs a live `gh pr view`, given its entry in the
# previous pr-status.json snapshot (or $null when it has none). Merged is
# terminal on GitHub -- a re-fetch can never change the answer -- so cached
# merged entries are reused. Open stays live, closed can reopen, and an entry
# with no state says nothing, so all of those are fetched. This is what keeps
# refresh cost proportional to live PRs instead of to every task ever
# finished (2026-08-16: 32s of the 40s SessionStart hook was re-fetching
# merged PRs, stalling the first prompt of every fresh session).
function Test-PrRefreshNeeded {
    param([AllowNull()]$CachedEntry)
    if ($null -eq $CachedEntry) { return $true }
    return $CachedEntry.state -ne 'merged'
}

# gh's MergeableState enum ("MERGEABLE"/"CONFLICTING"/"UNKNOWN") -> the
# boolean the console's core expects. UNKNOWN (gh hasn't finished computing
# it yet) maps to $null/absent -- an unresolved check is not the same as a
# known-clean merge.
function ConvertTo-MergeableBool {
    param([AllowNull()][string]$Mergeable)
    switch ($Mergeable) {
        'MERGEABLE' { $true }
        'CONFLICTING' { $false }
        default { $null }
    }
}

# gh's PullRequestState enum ("OPEN"/"MERGED"/"CLOSED") -> the console's
# lowercase Workstream.pr.state.
function ConvertTo-PrState {
    param([Parameter(Mandatory)][string]$State)
    $State.ToLowerInvariant()
}
