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

$worktreeText = (git -C $Repo worktree list --porcelain) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'prune-worktrees: git worktree list failed.' }
$worktrees = @(ConvertFrom-WorktreeListPorcelain -Text $worktreeText)

$byTaskId = @{}
foreach ($wt in $worktrees) {
    $taskId = Get-TaskIdFromWorktreePath -WorktreePath $wt.Path -RepoPath $Repo
    if ($taskId) { $byTaskId[$taskId] = $wt }
}

$mergedById = @{}
foreach ($taskId in $byTaskId.Keys) {
    $taskFile = Get-ChildItem -Path (Join-Path $dataRoot "tasks/$taskId-*.md") -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $content = if ($taskFile) { Get-Content -LiteralPath $taskFile.FullName -Raw } else { '' }
    $mergedById[$taskId] = Test-HasMergedStamp -Content $content
}

$prunableIds = @(Get-PrunableWorktreeIds -WorktreeTaskIds @($byTaskId.Keys) -MergedById $mergedById | Sort-Object)

if (-not $prunableIds) {
    Write-Host 'prune-worktrees: nothing prunable -- no merged task holds a worktree.'
    return
}

$mode = if ($Force) { '-- REMOVING' } else { '(DRY RUN -- pass -Force to remove)' }
Write-Host "prune-worktrees: $($prunableIds.Count) merged task worktree(s) found $mode`:"

$totalBytes = 0
$results = @()
foreach ($taskId in $prunableIds) {
    $wt = $byTaskId[$taskId]
    $sizeBytes = 0
    if (Test-Path -LiteralPath $wt.Path) {
        $sum = (Get-ChildItem -LiteralPath $wt.Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($sum) { $sizeBytes = $sum }
    }
    $totalBytes += $sizeBytes
    $sizeMb = [Math]::Round($sizeBytes / 1MB, 1)
    Write-Host ("  {0}  {1}  [{2}]  {3} MB" -f $taskId, $wt.Path, $wt.Branch, $sizeMb)
    $results += [pscustomobject]@{ TaskId = $taskId; Path = $wt.Path; Branch = $wt.Branch; SizeMb = $sizeMb }
}
Write-Host ("total: {0} worktree(s), {1} GB" -f $prunableIds.Count, [Math]::Round($totalBytes / 1GB, 2))

if (-not $Force) {
    Write-Host 'DRY RUN -- nothing removed. Re-run with -Force to actually remove these.'
    return
}

foreach ($r in $results) {
    $statusOut = git -C $r.Path status --porcelain --untracked-files=all 2>&1
    $clean = ($LASTEXITCODE -eq 0) -and (-not ([string]($statusOut | Out-String)).Trim())
    if (-not $clean) {
        Write-Warning "skipping $($r.Path): not clean (git status --porcelain nonempty) -- remove by hand after inspecting."
        continue
    }
    git -C $Repo worktree remove --force $r.Path
    if ($LASTEXITCODE -ne 0) { Write-Warning "git worktree remove failed for $($r.Path) -- skipping branch delete."; continue }
    Write-Host "removed worktree: $($r.Path)"
    git -C $Repo branch -D $r.Branch | Out-Host
    if ($LASTEXITCODE -eq 0) { Write-Host "deleted branch: $($r.Branch)" }
    else { Write-Warning "git branch -D $($r.Branch) failed (worktree already removed) -- delete it by hand." }
}
