#Requires -Version 7
<#
.SYNOPSIS
Prune the worktrees of every MERGED task -- the backlog half of report
055 PROPOSAL 5 (close-task.ps1 -Prune only handles the task it just closed;
this catches everything closed before -Prune existed).

.DESCRIPTION
Default is a DRY RUN: lists every prunable worktree (task id, path, branch,
disk size) and a total, removes nothing. Pass -Force to actually remove them.

A worktree is prunable only when BOTH hold:
  1. its task file carries a merged: stamp (memory lesson: never prune an
     open task's worktree -- absent or unmerged tasks are never touched);
  2. its worktree is clean (`git status --porcelain` empty) -- a dirty
     worktree is skipped with a warning, never force-discarded.

STRANDED directories (issue #96, task 069). The old implementation ran
`git worktree remove --force`, which deregisters the worktree and then deletes
the directory -- so a delete that failed (a lingering handle, a just-closed
tab) left a directory that no later `git worktree list` could surface, and the
script reported `nothing prunable` over directories still on disk. Two fixes,
both here:
  1. removal now deletes the DIRECTORY first (with retries -- the common
     failure is a handle that clears within seconds) and deregisters only
     after the directory is actually gone, so a failed delete leaves the
     worktree registered and visible to the next run;
  2. every run also sweeps the repo's parent directory for `<repo>-taskNNN`
     dirs git no longer registers, so directories stranded by the OLD order
     are back in scope. A stranded dir of a merged task is removed like any
     other; one whose task is NOT merged is reported and never touched.

.EXAMPLE
./scripts/prune-worktrees.ps1

.EXAMPLE
./scripts/prune-worktrees.ps1 -Force
#>
param(
    [switch]$Force,
    # override for fixture-repo testing/demos; defaults to the real repo this
    # script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/prune-worktrees.ps1')
. (Join-Path $PSScriptRoot 'lib/close-task.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')
$dataRoot = Get-DataRoot -RepoRoot $Repo

function Remove-WorktreeDirWithRetry {
    # $null on success, the LAST error text on failure. The observed failure mode
    # (issue #96) is a handle that clears seconds after a tab closes, so a few
    # backed-off retries fix the common case; a persistent holder is reported,
    # not fought.
    param(
        [Parameter(Mandatory)][string]$Path,
        [int[]]$DelaysSeconds = @(1, 2, 4)
    )
    $attempt = 0
    $max = $DelaysSeconds.Count + 1
    while ($true) {
        $attempt++
        $err = $null
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            $err = 'Remove-Item returned but the directory still exists'
        }
        catch { $err = $_.Exception.Message }
        if ($attempt -ge $max) { return "$err (after $attempt attempt(s))" }
        Start-Sleep -Seconds $DelaysSeconds[$attempt - 1]
    }
}

$worktreeText = (git -C $Repo worktree list --porcelain) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'prune-worktrees: git worktree list failed.' }
$worktrees = @(ConvertFrom-WorktreeListPorcelain -Text $worktreeText)

$byTaskId = @{}
foreach ($wt in $worktrees) {
    $taskId = Get-TaskIdFromWorktreePath -WorktreePath $wt.Path -RepoPath $Repo
    if ($taskId) { $byTaskId[$taskId] = $wt }
}

# The strand sweep: dirs on disk shaped <repo>-taskNNN that git no longer
# registers (issue #96 -- see .DESCRIPTION).
$repoParent = Split-Path (($Repo -replace '\\', '/').TrimEnd('/')) -Parent
$diskNames = @(Get-ChildItem -LiteralPath $repoParent -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Name })
$strandIds = @(Get-StrandedWorktreeTaskIds -DiskDirNames $diskNames `
        -RegisteredTaskIds @($byTaskId.Keys) -RepoPath $Repo)

$taskFileById = @{}
$mergedById = @{}
foreach ($taskId in (@($byTaskId.Keys) + $strandIds)) {
    $taskFile = Get-ChildItem -Path (Join-Path $dataRoot "tasks/$taskId-*.md") -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $content = if ($taskFile) { Get-Content -LiteralPath $taskFile.FullName -Raw } else { '' }
    $taskFileById[$taskId] = $taskFile
    $mergedById[$taskId] = Test-HasMergedStamp -Content $content
}

$prunableIds = @(Get-PrunableWorktreeIds -WorktreeTaskIds @($byTaskId.Keys) -MergedById $mergedById | Sort-Object)
$strandPrunable = @($strandIds | Where-Object { $mergedById[$_] })
$strandUnmerged = @($strandIds | Where-Object { -not $mergedById[$_] })

# A stranded dir whose task is NOT merged is never touched, but it is NAMED --
# silence here is how six directories sat invisible (issue #96).
foreach ($id in $strandUnmerged) {
    Write-Host ("  note: $repoParent/$(Split-Path $Repo -Leaf)-task$id exists on disk, is NOT registered as a worktree, " +
        'and its task has no merged: stamp -- not touching it (stamp/close the task first, then re-run).')
}

if (-not $prunableIds -and -not $strandPrunable) {
    Write-Host 'prune-worktrees: nothing prunable -- no merged task holds a worktree or a stranded worktree directory.'
    return
}

$mode = if ($Force) { '-- REMOVING' } else { '(DRY RUN -- pass -Force to remove)' }
Write-Host "prune-worktrees: $($prunableIds.Count) merged task worktree(s), $($strandPrunable.Count) stranded dir(s) found $mode`:"

function Get-DirSizeMb {
    param([Parameter(Mandatory)][string]$Path)
    $sizeBytes = 0
    if (Test-Path -LiteralPath $Path) {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($sum) { $sizeBytes = $sum }
    }
    return $sizeBytes
}

$totalBytes = 0
$results = @()
foreach ($taskId in $prunableIds) {
    $wt = $byTaskId[$taskId]
    $sizeBytes = Get-DirSizeMb -Path $wt.Path
    $totalBytes += $sizeBytes
    $sizeMb = [Math]::Round($sizeBytes / 1MB, 1)
    Write-Host ("  {0}  {1}  [{2}]  {3} MB" -f $taskId, $wt.Path, $wt.Branch, $sizeMb)
    $results += [pscustomobject]@{ TaskId = $taskId; Path = $wt.Path; Branch = $wt.Branch; SizeMb = $sizeMb }
}
$strandResults = @()
foreach ($taskId in $strandPrunable) {
    $path = "$Repo-task$taskId"
    $sizeBytes = Get-DirSizeMb -Path $path
    $totalBytes += $sizeBytes
    $sizeMb = [Math]::Round($sizeBytes / 1MB, 1)
    $branch = $null
    if ($taskFileById[$taskId]) { $branch = "task$taskId-" + (Get-TaskSlug -FileName $taskFileById[$taskId].Name) }
    Write-Host ("  {0}  {1}  [STRANDED -- not in git worktree list]  {2} MB" -f $taskId, $path, $sizeMb)
    $strandResults += [pscustomobject]@{ TaskId = $taskId; Path = $path; Branch = $branch; SizeMb = $sizeMb }
}
Write-Host ("total: {0} worktree(s) + {1} stranded, {2} GB" -f $prunableIds.Count, $strandPrunable.Count, [Math]::Round($totalBytes / 1GB, 2))

if (-not $Force) {
    Write-Host 'DRY RUN -- nothing removed. Re-run with -Force to actually remove these.'
    return
}

function Test-AgentAlive {
    # A merged: stamp does not mean the WORKER is done -- a task can merge one PR
    # and keep working (068 was live, merged and clean the day this was written;
    # -Force would have deleted the ground under a running agent). The agent
    # registry (work/scratch/agents/<id>.json, pwshPid) is the board's own
    # liveness observable; a live pid vetoes the removal.
    param([Parameter(Mandatory)][string]$TaskId)
    $regFile = Join-Path $dataRoot "scratch/agents/$TaskId.json"
    if (-not (Test-Path -LiteralPath $regFile)) { return $false }
    try {
        $entry = Get-Content -LiteralPath $regFile -Raw | ConvertFrom-Json
        return [bool](Get-Process -Id $entry.pwshPid -ErrorAction SilentlyContinue)
    }
    catch { return $false }
}

foreach ($r in $results) {
    if (Test-AgentAlive -TaskId $r.TaskId) {
        Write-Warning ("skipping $($r.Path): the agent registry names a LIVE pid for task $($r.TaskId) -- " +
            'a merged: stamp does not mean the worker is done; not removing a running worker''s worktree.')
        continue
    }
    # A registered path already gone from disk: an interrupted earlier removal.
    # Nothing to delete -- just clean the registration and branch.
    if (-not (Test-Path -LiteralPath $r.Path)) {
        git -C $Repo worktree prune
        git -C $Repo branch -D $r.Branch 2>&1 | Out-Host
        Write-Host "cleaned registration for already-deleted worktree: $($r.Path)"
        continue
    }
    $statusOut = git -C $r.Path status --porcelain --untracked-files=all 2>&1
    $clean = ($LASTEXITCODE -eq 0) -and (-not ([string]($statusOut | Out-String)).Trim())
    if (-not $clean) {
        Write-Warning "skipping $($r.Path): not clean (git status --porcelain nonempty) -- remove by hand after inspecting."
        continue
    }
    # DIRECTORY FIRST, registration second (issue #96): if the delete fails the
    # worktree stays registered, so this run's report and every later run still
    # see it -- the old order made a failed delete invisible forever.
    $removeErr = Remove-WorktreeDirWithRetry -Path $r.Path
    if ($removeErr) {
        Write-Warning ("could not remove $($r.Path): $removeErr. Something still holds a handle " +
            '(a shell whose cwd is inside it, an editor, antivirus). The worktree stays REGISTERED, so it stays visible here -- close the holder and re-run.')
        continue
    }
    git -C $Repo worktree prune
    if ($LASTEXITCODE -ne 0) { Write-Warning "git worktree prune failed after removing $($r.Path) -- registration may need `git worktree prune` by hand." }
    Write-Host "removed worktree: $($r.Path)"
    git -C $Repo branch -D $r.Branch | Out-Host
    if ($LASTEXITCODE -eq 0) { Write-Host "deleted branch: $($r.Branch)" }
    else { Write-Warning "git branch -D $($r.Branch) failed (worktree already removed) -- delete it by hand." }
}

foreach ($r in $strandResults) {
    if (Test-AgentAlive -TaskId $r.TaskId) {
        Write-Warning ("skipping stranded $($r.Path): the agent registry names a LIVE pid for task $($r.TaskId) -- not removing under a running worker.")
        continue
    }
    # No git status possible here: the registration is gone, so the .git link
    # inside the dir points at pruned metadata. The merged: stamp is the
    # authorization, same gate as every other removal in this script.
    $removeErr = Remove-WorktreeDirWithRetry -Path $r.Path
    if ($removeErr) {
        Write-Warning ("could not remove stranded $($r.Path): $removeErr. Something still holds a handle " +
            '(a shell whose cwd is inside it, an editor, antivirus). It stays on disk and this script will keep naming it -- close the holder and re-run.')
        continue
    }
    Write-Host "removed stranded dir: $($r.Path)"
    if ($r.Branch) {
        git -C $Repo branch -D $r.Branch 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "deleted branch: $($r.Branch)" }
        # No warning on failure: the branch of a long-stranded dir is usually
        # already gone; only its existence would be news.
    }
}
