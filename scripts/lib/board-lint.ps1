# Pure classification logic for scripts/board-lint.ps1 (task 131 -- board-
# consistency linter). USER 2026-08-06, after 10 finished tasks sat unstamped
# for two weeks: "board lying - can we have sth that watches for it." Status
# is DERIVED (task 071), so the fix is a linter over the same observables the
# board already reads, not more manual bookkeeping.
#
# No gh/git/process calls live here -- those side effects stay in
# scripts/board-lint.ps1 so this file can be dot-sourced straight into Pester
# and exercised on strings/hashtables/bools. Same split as
# scripts/lib/close-task.ps1, whose Get-TaskPrNumber / Test-HasMergedStamp are
# reused below rather than re-implemented (same regex, one place to fix).

. (Join-Path $PSScriptRoot 'close-task.ps1')

function Get-Class1Finding {
    # Class 1: task file has a PR link whose GitHub state is MERGED/CLOSED but
    # no merged: stamp. $PrState is THIS task's own current PR state (any
    # casing -- MERGED/merged), resolved by the caller from either
    # scratch/pr-status.json (the cache refresh-pr-status.ps1 already writes
    # every hook run -- zero extra gh calls) or a live batched gh pr list
    # call. $null means unknown/offline -- always returns $null so a run with
    # no PR data can never false-positive class 1.
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [AllowNull()][AllowEmptyString()][string]$PrState
    )
    if ([string]::IsNullOrEmpty($PrState)) { return $null }
    $prNumber = Get-TaskPrNumber -Content $Content
    if (-not $prNumber) { return $null }
    if (Test-HasMergedStamp -Content $Content) { return $null }
    $upper = $PrState.ToUpperInvariant()
    if ($upper -notin @('MERGED', 'CLOSED')) { return $null }
    return [PSCustomObject]@{
        Task     = $Task
        Class    = 1
        Evidence = "PR #$prNumber is $upper on GitHub but task file has no merged: stamp"
    }
}

function ConvertFrom-PrStatusCache {
    # scratch/pr-status.json's raw text -> hashtable task id -> PR state
    # string, skipping the fetchedAt stamp. Pure JSON parsing so the
    # cache-reuse path (the common case: the hook just refreshed this file
    # moments earlier, so class 1 costs zero extra gh calls) is
    # Pester-testable without a real refresh-pr-status.ps1 run. Never throws
    # -- unreadable/malformed content just yields an empty map, which the
    # caller treats as "no cache, fall back to a live call."
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Json)) { return $map }
    try { $data = $Json | ConvertFrom-Json } catch { return $map }
    foreach ($prop in $data.PSObject.Properties) {
        if ($prop.Name -eq 'fetchedAt') { continue }
        $state = $prop.Value.state
        if ($state) { $map[$prop.Name] = "$state" }
    }
    return $map
}

function Get-Class2Finding {
    # Class 2: no PR, no stamp, but a report exists at work/reports/<nnn>-*.md
    # -- a report-only task delivered without ever getting stamped.
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][bool]$ReportExists
    )
    if (Get-TaskPrNumber -Content $Content) { return $null }
    if (Test-HasMergedStamp -Content $Content) { return $null }
    if (-not $ReportExists) { return $null }
    return [PSCustomObject]@{
        Task     = $Task
        Class    = 2
        Evidence = 'no PR, no merged: stamp, but a report exists at work/reports/ -- probably done, unstamped'
    }
}

function Get-Class3Finding {
    # Class 3: merged: stamp present but the task worktree still exists on
    # disk -- close-out incomplete (no -Prune, or it refused/failed).
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][bool]$WorktreeExists
    )
    if (-not (Test-HasMergedStamp -Content $Content)) { return $null }
    if (-not $WorktreeExists) { return $null }
    return [PSCustomObject]@{
        Task     = $Task
        Class    = 3
        Evidence = "merged: stamp present but worktree C:/git/decompile-sc-task$Task still exists"
    }
}

function Get-Class4Finding {
    # Class 4: registry entry whose pid is dead but the task is unstamped and
    # has no open PR -- worker died mid-task, a genuine stall. Distinct from
    # class 2: a report already on disk means the work was actually
    # delivered, so that case is left to class 2 instead of double-flagged.
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][bool]$RegistryExists,
        [Parameter(Mandatory)][bool]$PidAlive,
        [AllowNull()][AllowEmptyString()][string]$PrState,
        [Parameter(Mandatory)][bool]$ReportExists
    )
    if (-not $RegistryExists) { return $null }
    if ($PidAlive) { return $null }
    if (Test-HasMergedStamp -Content $Content) { return $null }
    if ($PrState -and $PrState.ToLowerInvariant() -eq 'open') { return $null }
    if ($ReportExists) { return $null }
    return [PSCustomObject]@{
        Task     = $Task
        Class    = 4
        Evidence = 'registry entry pid is dead, task unstamped, no open PR, no report -- worker died mid-task'
    }
}

function Get-Class5aFindings {
    # Class 5 (missing file): a registry entry (work/scratch/agents/<nnn>.json)
    # names a task with no matching work/tasks/<nnn>-*.md -- a worker was
    # spawned but the contract file itself is gone or was never committed.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RegistryTaskIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExistingTaskIds
    )
    $existing = [Collections.Generic.HashSet[string]]::new()
    foreach ($id in $ExistingTaskIds) { [void]$existing.Add($id) }
    $findings = @(
        foreach ($id in $RegistryTaskIds) {
            if ($existing.Contains($id)) { continue }
            [PSCustomObject]@{
                Task     = $id
                Class    = 5
                Evidence = "registry entry scratch/agents/$id.json exists but work/tasks/$id-*.md is missing"
            }
        }
    )
    # Unary comma: without it PowerShell unwraps a single-element result into
    # a bare scalar instead of a 1-element array (same gotcha
    # Get-WatchdogBoardLines documents).
    return , $findings
}

function Get-Class5bFinding {
    # Class 5 (unwritten contract): a spawned task (registry entry exists)
    # whose file still carries template TODO(conductor) placeholders -- the
    # contract was never actually filled in.
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][bool]$RegistryExists
    )
    if (-not $RegistryExists) { return $null }
    if ($Content -notmatch 'TODO\(conductor\)') { return $null }
    return [PSCustomObject]@{
        Task     = $Task
        Class    = 5
        Evidence = 'task was spawned but its file still carries TODO(conductor) placeholders -- contract never written'
    }
}

function Format-BoardLintLine {
    # One output line per finding (acceptance criterion 1: "each output line
    # names task + class + evidence").
    param([Parameter(Mandatory)]$Finding)
    return "task $($Finding.Task): class $($Finding.Class) -- $($Finding.Evidence)"
}
