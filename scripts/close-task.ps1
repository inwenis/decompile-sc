#Requires -Version 7
<#
.SYNOPSIS
Close a task the one true way: verify its PR is MERGED, stamp `merged:` into the
task file, and commit it with the standard close message. (Task 035 -- USER RULE
"completed = PR merged".)

.DESCRIPTION
The conductor's single close command. It refuses to close a task whose PR is not
merged, so a done-but-unmerged task can never be committed as completed by
mistake (the class of bug that made PR #26/#29 read as done while still open).

Steps:
  1. Resolve work/tasks/<NNN>-*.md and read its `pr:` line.
  2. `gh pr view <pr> --json state,mergedAt` -- refuse unless state is MERGED.
  3. Stamp `merged: <mergedAt date>` under the `pr:` line (idempotent).
  4. `git add` the task file (+ work/reports/<NNN>-*.md if present) and commit with
     "chore(tasks): close task NNN (PR #M merged)".
  5. -StopAgent also reaps the worker tab (reap-agent.ps1 -IfDone -- graceful
     close, task 129; falls back to stop-agent.ps1's hard tree-kill only if
     the worker doesn't respond).

A done task with no PR (research/mockups/cancelled) is already completed by the
status mapping -- close-task refuses it (nothing to verify or stamp); just commit
the task file directly.

.EXAMPLE
./scripts/close-task.ps1 -Task 034

.EXAMPLE
./scripts/close-task.ps1 -Task 34 -StopAgent

.EXAMPLE
./scripts/close-task.ps1 -Task 34 -Prune
#>
param(
    [Parameter(Mandatory)][string]$Task,
    # also stop the worker's tab (stop-agent.ps1 -IfDone) after committing
    [switch]$StopAgent,
    # extra text appended to the commit subject after " - " (optional)
    [string]$Note,
    # after a verified-merged close: git worktree remove + branch -D the
    # task's worktree/branch. Refuses (warns, does not throw) unless the
    # just-stamped file carries merged: AND the worktree is clean (task 063,
    # report 055 P5 -- memory lesson: never prune an open task's worktree).
    [switch]$Prune,
    # override for fixture-repo testing/demos; defaults to the real repo this
    # script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/close-task.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')

$repo = $Repo
$dataRoot = Get-DataRoot -RepoRoot $repo
$taskId = '{0:D3}' -f [int]$Task

$taskFile = Get-ChildItem -Path (Join-Path $dataRoot "tasks/$taskId-*.md") -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $taskFile) { throw "No task file work/tasks/$taskId-*.md under $repo." }

$content = Get-Content -LiteralPath $taskFile.FullName -Raw
$prNumber = Get-TaskPrNumber -Content $content

# Query gh for the PR's real state (the only source of truth for "merged").
# Pull the fields via --jq as RAW strings: ConvertFrom-Json otherwise coerces
# mergedAt into a local-culture DateTime, mangling the ISO date we stamp.
$prState = $null
$mergedAt = $null
if ($prNumber) {
    # --repo pin (bootstrap review): without it gh resolves the repo from the
    # cwd's git remote -- run from the wrong checkout it would read another
    # repo's same-numbered PR and stamp merged: off the wrong state.
    $raw = gh pr view $prNumber --repo inwenis/decompile-sc --json state,mergedAt --jq '.state + "|" + (.mergedAt // "")' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh pr view $prNumber failed: $raw" }
    $parts = ("$raw").Trim() -split '\|', 2
    $prState = $parts[0]
    if ($parts.Count -gt 1 -and $parts[1]) { $mergedAt = $parts[1] }
}

$refusal = Get-CloseRefusalReason -PrNumber $prNumber -PrState $prState
if ($refusal) { throw "Refusing to close task ${taskId}: $refusal" }

# USER RULE (2026-07-15): keep the main checkout current with remote main.
# The PR just merged remotely -- pull it in before stamping/committing so the
# close commit sits on top of the merge it records.
git -C $repo pull --ff-only 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "git pull --ff-only failed -- main checkout diverged; resolve before closing." }

$date = Get-MergedDate -MergedAt $mergedAt
$stamped = Add-MergedStamp -Content $content -Date $date
[IO.File]::WriteAllText($taskFile.FullName, $stamped, [Text.UTF8Encoding]::new($false))
Write-Host "stamped merged: $date into $($taskFile.Name)"

# Stage the task file (and its report, if any). Specific paths only -- never
# `git add -A` while other workers may have unstaged edits (AGENTS.md close step).
$paths = @($taskFile.FullName)
$report = Get-ChildItem -Path (Join-Path $dataRoot "reports/$taskId-*.md") -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($report) { $paths += $report.FullName }

git -C $repo add -- $paths
if ($LASTEXITCODE -ne 0) { throw "git add failed for task $taskId." }

$subject = New-CloseCommitMessage -Task $taskId -PrNumber $prNumber
if ($Note) { $subject = "$subject - $Note" }
git -C $repo commit -m $subject | Out-Host
if ($LASTEXITCODE -ne 0) { throw "git commit failed for task $taskId." }
Write-Host "committed: $subject"

# USER RULE (ground rule 7): keep main pushed to origin -- the 2026-07-17
# stale-origin bite happened because local main sat ahead of origin with
# nobody pushing it. Warn-don't-fail: an offline conductor must still finish
# closing the task; the next successful push catches main up.
git -C $repo push origin main 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Write-Warning "git push origin main failed -- main is ahead of origin until the next successful push." }

if ($StopAgent) {
    Write-Host "reaping agent tab for task $taskId ..."
    & (Join-Path $PSScriptRoot 'reap-agent.ps1') -Task $taskId -IfDone
}

# Messages backup rides every close (2026-07-17 data-loss incident: the manual
# backup was 5 days stale when messages/user/ got wiped). Never fail the close
# over a backup hiccup -- warn and move on.
try { & (Join-Path $PSScriptRoot 'backup-messages.ps1') 6>$null } catch { Write-Warning "backup-messages failed: $_" }

if ($Prune) {
    $worktreePath = "$repo-task$taskId"
    $branch = "task$taskId-" + (Get-TaskSlug -FileName $taskFile.Name)
    $worktreeExists = Test-Path -LiteralPath $worktreePath
    $worktreeClean = $false
    if ($worktreeExists) {
        $statusOut = git -C $worktreePath status --porcelain --untracked-files=all 2>&1
        $worktreeClean = ($LASTEXITCODE -eq 0) -and (-not ([string]($statusOut | Out-String)).Trim())
    }
    $pruneRefusal = Get-PruneRefusalReason -Content $stamped -WorktreeExists $worktreeExists -WorktreeClean $worktreeClean
    if ($pruneRefusal) {
        Write-Warning "Not pruning task ${taskId}: $pruneRefusal"
    }
    else {
        git -C $repo worktree remove --force $worktreePath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "pruned worktree: $worktreePath"
            git -C $repo branch -D $branch | Out-Host
            if ($LASTEXITCODE -eq 0) { Write-Host "deleted branch: $branch" }
            else { Write-Warning "git branch -D $branch failed (worktree already removed) -- delete it by hand." }
        }
        else { Write-Warning "git worktree remove failed for $worktreePath -- prune by hand." }
    }
}

# pr-status cache freshness rides every close (report 055 P10) -- never fail
# the close over a refresh hiccup.
try {
    $prStatusOut = & (Join-Path $PSScriptRoot 'refresh-pr-status.ps1') -RepoRoot $repo 2>&1 | Select-Object -Last 1
    Write-Host "pr-status refreshed: $prStatusOut"
} catch { Write-Warning "refresh-pr-status failed: $_" }
