# Derived task status for the orchestration scripts (task 071) -- the pwsh
# mirror of the product core's src/core/deriveStatus.ts. Nothing here reads a
# `state:` line: workers stopped writing status transitions, so every fact
# below is an observable something else already produced.
#
#   registry entry     scratch/agents/<NNN>.json   (spawn-agent.ps1)
#   pr state           scratch/pr-status.json      (refresh-pr-status.ps1)
#   merged: stamp      tasks/NNN-*.md              (close-task.ps1)
#   open question      messages/**/*.md            (send-message.ps1 -Type question)
#
# Kept a separate, dot-sourceable file so Pester can exercise the rule table on
# plain values -- see tests/derived-status.Tests.ps1.

function Get-DerivedTaskStatus {
    # The rule table. merged > review > blocked > running > queued: the
    # furthest-along observable wins, because the order is "how far has this
    # task actually got". Same precedence as deriveStatus.ts -- change both or
    # neither.
    param(
        # A worker was spawned for this task (alive or stopped -- "is it alive
        # right now" is liveness, which only the console displays).
        [switch]$Registered,
        # open | merged | closed, as pr-status.json spells it.
        [AllowNull()][AllowEmptyString()][string]$PrState,
        [AllowNull()][AllowEmptyString()][string]$MergedStamp,
        [switch]$UnansweredQuestion
    )

    if (-not [string]::IsNullOrWhiteSpace($MergedStamp) -or $PrState -eq 'merged') { return 'completed' }
    if ($PrState -eq 'open') { return 'review' }
    if ($UnansweredQuestion) { return 'blocked' }
    if ($Registered) { return 'running' }
    return 'queued'
}

function Get-TaskMergedStampFor {
    # `merged: <date>` out of tasks/NNN-*.md, or $null.
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Task)
    $file = Get-ChildItem -Path (Join-Path $Root "tasks/$Task-*.md") -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $file) { return $null }
    $m = [regex]::Match((Get-Content -LiteralPath $file.FullName -Raw), '(?m)^merged:\s*(\S+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-PrStateFor {
    # The task's PR state out of the conductor's pr-status.json snapshot, or
    # $null when the file is missing/unreadable or carries no entry for it.
    # Never throws: a stale or half-written snapshot must not break a board.
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Task)
    $path = Join-Path $Root 'scratch/pr-status.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
    $entry = $data.PSObject.Properties[$Task]
    if (-not $entry) { return $null }
    return $entry.Value.state
}

function Get-BlockedTaskIds {
    # Every task id that asked a question (send-message.ps1 -Type question) no
    # answer points back at. An answer is any message carrying
    # `re: <question filename>` -- the same derivation questions.ts does for
    # the UI. This is the ONE signal a worker still emits, and it emits it by
    # asking, not by editing a status.
    #
    # Answers ALWAYS land in a different directory than the question, so this
    # has to look at the whole messages/ tree -- which is why it is one pass
    # returning a set, rather than a per-task probe a board would run 70 times.
    param([Parameter(Mandatory)][string]$Root)

    # NOTE the unary commas on every return: PowerShell enumerates a collection
    # it returns, which would hand the caller loose strings (or $null for an
    # empty set) instead of the HashSet.
    $blocked = [Collections.Generic.HashSet[string]]::new()
    $messagesDir = Join-Path $Root 'messages'
    if (-not (Test-Path -LiteralPath $messagesDir)) { return ,$blocked }

    $contents = @{}
    $answered = [Collections.Generic.HashSet[string]]::new()
    foreach ($f in Get-ChildItem -Path $messagesDir -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue) {
        $body = Get-Content -LiteralPath $f.FullName -Raw
        $contents[$f.Name] = $body
        $re = [regex]::Match($body, '(?m)^re:\s*(\S+)')
        if ($re.Success) { [void]$answered.Add($re.Groups[1].Value) }
    }

    foreach ($name in $contents.Keys) {
        $body = $contents[$name]
        if ($body -notmatch '(?m)^type:\s*question\b') { continue }
        if ($answered.Contains($name)) { continue }
        $from = [regex]::Match($body, '(?m)^from:\s*(\S+)\s*$')
        # Only a WORKER's own open question blocks it; a conductor question is
        # the conductor's business.
        if ($from.Success -and $from.Groups[1].Value -match '^\d{3}$') {
            [void]$blocked.Add($from.Groups[1].Value)
        }
    }
    return ,$blocked
}

function Get-DerivedStatus {
    # The whole derivation for one task, read off a repo root. This is what
    # every orchestration script should call instead of parsing `state:`.
    # Pass -BlockedIds when deriving many tasks in a loop (a board) so the
    # messages/ tree is scanned once instead of once per task.
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Task,
        [AllowNull()][Collections.Generic.HashSet[string]]$BlockedIds
    )
    if ($null -eq $BlockedIds) { $BlockedIds = Get-BlockedTaskIds -Root $Root }
    $registered = Test-Path -LiteralPath (Join-Path $Root "scratch/agents/$Task.json")
    return Get-DerivedTaskStatus `
        -Registered:$registered `
        -PrState (Get-PrStateFor -Root $Root -Task $Task) `
        -MergedStamp (Get-TaskMergedStampFor -Root $Root -Task $Task) `
        -UnansweredQuestion:($BlockedIds.Contains($Task))
}

function Test-TaskStatusAllowsStop {
    # stop-agent.ps1 -IfDone: a worker may be stopped once it has delivered
    # (its PR is open or merged) or is parked on a question for the human.
    # Replaces the old `state: done|blocked` assertion -- same intent, read
    # from observables instead of the worker's word.
    param([Parameter(Mandatory)][string]$Status)
    return $Status -in @('completed', 'review', 'blocked')
}
