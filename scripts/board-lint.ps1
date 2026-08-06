#Requires -Version 7
<#
.SYNOPSIS
Board-consistency linter (task 131): detect drift between task-file state and
reality so the board can't quietly lie again.

.DESCRIPTION
USER 2026-08-06, after 10 finished tasks sat unstamped for two weeks: "board
lying - can we have sth that watches for it to make sure it doesn't happen
again." Status is DERIVED (task 071) from observables the board already
reads -- so this is a linter over those observables, not more manual
bookkeeping.

Detects 5 drift classes (scripts/lib/board-lint.ps1 has the pure logic for
each):
  1. PR link whose GitHub state is MERGED/CLOSED but no merged: stamp.
  2. no PR, no stamp, but a report exists -- report-only task, unstamped.
  3. merged: stamp present but the task worktree still exists (close-out
     incomplete).
  4. registry entry whose pid is dead, task unstamped, no open PR, no
     report -- worker died mid-task.
  5. registry entry with no matching task file, or a spawned task whose file
     still carries TODO(conductor) placeholders -- contract never written.

Detection only -- never auto-fixes anything.

Wired two places: config/conductor-sessionstart.ps1 prints one line per
finding on every conductor session start, and this script also runs
standalone (or from CI later) via plain stdout lines + exit code (0 = clean,
1 = findings).

Class 1's PR state comes from scratch/pr-status.json when present -- the
cache refresh-pr-status.ps1 already writes every SessionStart hook run, one
step before this one runs, so the common (hook) path costs ZERO extra gh
calls. Only when that cache is missing (a fresh checkout, standalone/CI) does
this fall back to ONE batched `gh pr list --json` call for the whole repo --
never one call per task. Offline (gh missing, or the call fails) degrades by
skipping class 1 with a note -- never a false positive.

.EXAMPLE
./scripts/board-lint.ps1

.EXAMPLE
./scripts/board-lint.ps1 -SkipGh
#>
param(
    [string]$Repo = (Split-Path $PSScriptRoot -Parent),
    [string]$GhRepo = 'inwenis/decompile-sc',
    # skip both the pr-status.json cache and the gh call (class 1 entirely)
    # -- used by CI/offline runs and tests.
    [switch]$SkipGh
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/data-root.ps1')
. (Join-Path $PSScriptRoot 'lib/board-lint.ps1')

$dataRoot = Get-DataRoot -RepoRoot $Repo
$tasksDir = Join-Path $dataRoot 'tasks'
$reportsDir = Join-Path $dataRoot 'reports'
$agentsDir = Join-Path $dataRoot 'scratch/agents'

$taskFiles = @(Get-ChildItem -Path $tasksDir -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{3}-.+\.md$' })

$reportIds = [Collections.Generic.HashSet[string]]::new()
@(Get-ChildItem -Path $reportsDir -Filter '*.md' -ErrorAction SilentlyContinue) |
    ForEach-Object { [regex]::Match($_.Name, '^(\d{3})-').Groups[1].Value } |
    Where-Object { $_ } |
    ForEach-Object { [void]$reportIds.Add($_) }

# Registry keyed by task id (hashtable, not a per-task Where-Object scan --
# O(n) instead of O(tasks x registry entries), the difference between ~440ms
# and ~10ms on this repo's current ~130 tasks / ~96 registry entries).
$registryByTask = @{}
@(Get-ChildItem -Path $agentsDir -Filter '*.json' -ErrorAction SilentlyContinue) |
    ForEach-Object { $registryByTask[$_.BaseName] = $_ }

$lines = @()

# Class 1 PR state: cache first (zero gh cost), live batched call as fallback.
$prStateByTask = $null
$prStateByNumber = $null
if (-not $SkipGh) {
    $prStatusPath = Join-Path $dataRoot 'scratch/pr-status.json'
    if (Test-Path -LiteralPath $prStatusPath) {
        $cacheMap = ConvertFrom-PrStatusCache -Json (Get-Content -LiteralPath $prStatusPath -Raw)
        if ($cacheMap.Count -gt 0) { $prStateByTask = $cacheMap }
    }
    if (-not $prStateByTask) {
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            try {
                $raw = gh pr list --repo $GhRepo --state all --json number,state --limit 500 2>$null
                if ($LASTEXITCODE -eq 0 -and $raw) {
                    $prStateByNumber = @{}
                    foreach ($pr in ($raw | ConvertFrom-Json)) { $prStateByNumber["$($pr.number)"] = $pr.state }
                }
                else {
                    $lines += 'board-lint: gh pr list failed -- skipping class 1 (merged/closed-but-unstamped) check'
                }
            }
            catch {
                $lines += "board-lint: gh pr list errored ($_) -- skipping class 1 check"
            }
        }
        else {
            $lines += 'board-lint: gh not on PATH -- skipping class 1 (merged/closed-but-unstamped) check'
        }
    }
}

$findings = @()

foreach ($file in $taskFiles) {
    $task = [regex]::Match($file.BaseName, '^(\d{3})').Groups[1].Value
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $reportExists = $reportIds.Contains($task)
    $regFile = $registryByTask[$task]
    $registryExists = [bool]$regFile
    $worktreeExists = Test-Path -LiteralPath "$Repo-task$task"

    $prState = $null
    if ($prStateByTask) {
        $prState = $prStateByTask[$task]
    }
    elseif ($prStateByNumber) {
        $prNum = Get-TaskPrNumber -Content $content
        if ($prNum) { $prState = $prStateByNumber[$prNum] }
    }

    $pidAlive = $false
    if ($registryExists) {
        try {
            $entry = Get-Content -LiteralPath $regFile.FullName -Raw | ConvertFrom-Json
            $pidAlive = [bool](Get-Process -Id $entry.pwshPid -ErrorAction SilentlyContinue)
        }
        catch { $pidAlive = $false }
    }

    $findings += Get-Class1Finding -Task $task -Content $content -PrState $prState
    $findings += Get-Class2Finding -Task $task -Content $content -ReportExists $reportExists
    $findings += Get-Class3Finding -Task $task -Content $content -WorktreeExists $worktreeExists
    $findings += Get-Class4Finding -Task $task -Content $content -RegistryExists $registryExists `
        -PidAlive $pidAlive -PrState $prState -ReportExists $reportExists
    $findings += Get-Class5bFinding -Task $task -Content $content -RegistryExists $registryExists
}

$existingTaskIds = @($taskFiles | ForEach-Object { [regex]::Match($_.BaseName, '^(\d{3})').Groups[1].Value })
$findings += Get-Class5aFindings -RegistryTaskIds @($registryByTask.Keys) -ExistingTaskIds $existingTaskIds

$findings = @($findings | Where-Object { $_ })
$lines += $findings | ForEach-Object { Format-BoardLintLine -Finding $_ }
if (-not $findings) { $lines += 'board-lint: clean -- no drift detected' }

$lines -join "`n" | Write-Output
exit ([int]([bool]$findings.Count))
