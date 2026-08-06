#Requires -Version 7
<#
.SYNOPSIS
Cut a new task file, create its worktree off fresh origin/main, and (unless
-NoSpawn) spawn the worker -- one command instead of the hand-done checklist
(report 055 PROPOSAL 2: table rows #13 numbering, #14 model, #23 model,
#24 one-tab-per-task, #43 worktree/branch naming).

.DESCRIPTION
1. Next free 3-digit task id (scans work/tasks/, a gap left by a cancelled task
   is never reused).
2. work/tasks/NNN-<slug>.md from work/tasks/_template.md with every substitutable field
   filled (NNN, slug, title, model, date, worktree path, branch name); Goal
   and Context are left as clearly-marked TODO(conductor) blocks.
3. `git fetch origin` then `git worktree add ... origin/main` -- always a
   fresh remote base (2026-07-17 stale-base lesson), never local main.
4. Unless -NoSpawn: spawn-agent.ps1, with the model read back FROM THE TASK
   FILE (not the -Model param directly, so the file is the source of truth)
   and -Permissions bypass (the 2026-07-11 standing default). Does not touch
   spawn-agent.ps1's own default -- that is task 063's job.
5. -Commit stages+commits the cut with the standard "chore(tasks): cut task
   NNN (<slug>)" message; otherwise prints the next-step commands.

.EXAMPLE
./scripts/new-task.ps1 -Slug fix-thing -Model opus -Title 'Fix the thing'

.EXAMPLE
./scripts/new-task.ps1 -Slug demo -NoSpawn -Repo C:\fixtures\conductor
#>
param(
    [Parameter(Mandatory)][string]$Slug,
    [ValidateSet('haiku', 'sonnet', 'opus', 'fable')]
    [string]$Model = 'sonnet',
    [string]$Title,
    [switch]$NoSpawn,
    [switch]$Commit,
    # override for fixture-repo testing/demos; defaults to the real repo this
    # script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/new-task.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')

if (-not (Test-ValidSlug -Slug $Slug)) {
    throw "new-task: -Slug '$Slug' must be lowercase kebab-case (letters, digits, hyphens) -- it becomes a worktree dir and branch name."
}

$tasksDir = Join-Path (Get-DataRoot -RepoRoot $Repo) 'tasks'
$templatePath = Join-Path $tasksDir '_template.md'
if (-not (Test-Path -LiteralPath $templatePath)) { throw "new-task: no template at $templatePath" }

$existingIds = @(Get-TaskIdsInDir -TasksDir $tasksDir)
$taskId = Get-NextTaskId -ExistingIds $existingIds
# Subject rotation (2026-07-18, user caught a day-stale subject): doing a
# thing IS the subject - never fail the real operation over it.
try { & (Join-Path $PSScriptRoot 'set-conductor-status.ps1') -State processing -Subject "cutting task $taskId" | Out-Null } catch {}
if (-not $Title) { $Title = ConvertTo-TitleFromSlug -Slug $Slug }

$templateContent = Get-Content -LiteralPath $templatePath -Raw
$taskContent = New-TaskFileContent -TemplateContent $templateContent -TaskId $taskId -Slug $Slug -Title $Title -Model $Model

$taskFilePath = Join-Path $tasksDir "$taskId-$Slug.md"
if (Test-Path -LiteralPath $taskFilePath) { throw "new-task: $taskFilePath already exists." }
[IO.File]::WriteAllText($taskFilePath, $taskContent, [Text.UTF8Encoding]::new($false))
Write-Host "wrote $taskFilePath"

$fetchArgs = Get-FetchArgs -Repo $Repo
git @fetchArgs
if ($LASTEXITCODE -ne 0) { throw 'new-task: git fetch origin failed.' }

$worktreeArgs = Get-WorktreeAddArgs -Repo $Repo -TaskId $taskId -Slug $Slug
git @worktreeArgs
if ($LASTEXITCODE -ne 0) { throw 'new-task: git worktree add failed.' }
$worktreePath = "$Repo-task$taskId"
Write-Host "worktree: $worktreePath (branch task$taskId-$Slug, base origin/main)"

if (-not $NoSpawn) {
    $modelFromFile = Get-TaskModel -Content $taskContent
    Write-Host "spawning worker (model: $modelFromFile, permissions: bypass) ..."
    & (Join-Path $PSScriptRoot 'spawn-agent.ps1') -TaskFile $taskFilePath -WorkDir $worktreePath -Model $modelFromFile -Permissions bypass
}

$commitMessage = New-CutCommitMessage -TaskId $taskId -Slug $Slug
if ($Commit) {
    git -C $Repo add -- $taskFilePath
    if ($LASTEXITCODE -ne 0) { throw 'new-task: git add failed.' }
    git -C $Repo commit -m $commitMessage | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'new-task: git commit failed.' }
    Write-Host "committed: $commitMessage"
}
else {
    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host "  1. Fill Goal/Context in $taskFilePath (marked TODO(conductor))."
    Write-Host "  2. git -C `"$Repo`" add -- `"$taskFilePath`""
    Write-Host "     git -C `"$Repo`" commit -m `"$commitMessage`""
    Write-Host '     (or rerun with -Commit to do this automatically)'
}
