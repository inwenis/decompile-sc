#Requires -Version 7
<#
.SYNOPSIS
Merge a task's PR the one true way: verify the gate, squash-merge, then hand off
to close-task.ps1. (Task 059 -- the mechanical merge gate.)

.DESCRIPTION
The conductor's single merge command, and the only sanctioned merge path. Branch
protection is unavailable on this repo (private + free plan: the protection API
answers 403), so the required-checks rule lives here instead, in the same
verify-gate style as close-task.ps1.

It refuses unless ALL of:
  * the caller is the conductor  -- AGENT_TASK unset (workers never merge);
  * the task file has a `pr:` URL and is not already stamped `merged:`;
  * the PR is OPEN  -- since task 071 this replaces the old `state: done`
    check: status is derived from observables, so an existing OPEN PR IS the
    evidence that the worker delivered something mergeable;
  * the PR is not BEHIND origin/main, not conflicting, not a draft;
  * `gh pr checks` is green on the PR's head -- no red, nothing pending, and
    checks actually ran (a branch that predates ci.yml reports none: merge
    origin/main into it and push).

-HumanOk is accepted but not required today: the conductor is the human's
delegate for merges. The policy switch lives in lib/merge-task.ps1
(-RequireHumanOk) -- flip it there to make the flag mandatory.

On success: `gh pr merge --squash`, then close-task.ps1 -Task NNN, which pulls
main, stamps `merged: <date>` and commits. Closing is NOT duplicated here.

.EXAMPLE
./scripts/merge-task.ps1 -Task 059

.EXAMPLE
./scripts/merge-task.ps1 -Task 59 -StopAgent
#>
param(
    [Parameter(Mandatory)][string]$Task,
    # reserved for future policy (see -RequireHumanOk in lib/merge-task.ps1)
    [switch]$HumanOk,
    # path to a PASSING scripts/run-ci-local.ps1 receipt for this PR's head sha;
    # substitutes for the cloud CI verdict when Actions cannot run (billing/outage)
    [string]$LocalCiReceipt,
    # forwarded to close-task.ps1: also stop the worker's tab after closing
    [switch]$StopAgent,
    # override for fixture-repo testing (task 074 -- no test may write into
    # the real tasks/ dir); defaults to the real repo this script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/merge-task.ps1')
. (Join-Path $PSScriptRoot 'lib/close-task.ps1')
. (Join-Path $PSScriptRoot 'lib/agent-lifecycle.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')

$repo = $Repo
$dataRoot = Get-DataRoot -RepoRoot $repo
$taskId = '{0:D3}' -f [int]$Task
# Subject rotation (2026-07-18, user caught a day-stale subject): doing a
# thing IS the subject - never fail the real operation over it.
try { & (Join-Path $PSScriptRoot 'set-conductor-status.ps1') -State processing -Subject "merging task $taskId" | Out-Null } catch {}

$taskFile = Get-ChildItem -Path (Join-Path $dataRoot "tasks/$taskId-*.md") -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $taskFile) { throw "No task file work/tasks/$taskId-*.md under $repo." }

$content = Get-Content -LiteralPath $taskFile.FullName -Raw
$prNumber = Get-TaskPrNumber -Content $content

# Local half of the gate first -- no point spending gh round-trips on a task
# whose own file already disqualifies it.
$refusal = Get-LocalRefusalReason -TaskId $taskId -AgentTask $env:AGENT_TASK `
    -PrNumber $prNumber -MergedStamp (Get-TaskMergedStamp -Content $content)
if ($refusal) { throw "Refusing to merge task ${taskId}: $refusal" }

# The PR's own state + its position against the base branch. ConvertFrom-Json is
# safe here: all three fields are plain strings/bools, no dates to mangle.
# --repo pin (bootstrap review): gh resolves the target repo from the cwd's
# git remote. Without the pin, running this from any other checkout (e.g. the
# LIVE conductor repo) would evaluate -- and MERGE -- that repo's same-numbered
# PR. Every gh pr call in this script and close-task.ps1 carries the pin.
$ghRepo = 'inwenis/decompile-sc'
$viewRaw = gh pr view $prNumber --repo $ghRepo --json state,mergeStateStatus 2>&1
if ($LASTEXITCODE -ne 0) { throw "gh pr view $prNumber failed: $viewRaw" }
$view = ("$viewRaw" | Out-String) | ConvertFrom-Json

# `gh pr checks` exits non-zero when checks are red (1) or absent (8), so its
# exit code is not an error here -- the verdict comes from the payload. The
# `workflow` field is what separates our CI from third-party app checks
# (GitGuardian runs on every PR); see Get-ChecksVerdict.
$checksRaw = gh pr checks $prNumber --repo $ghRepo --json bucket,workflow,name 2>&1 | Out-String
$verdict = Get-ChecksVerdict -Json $checksRaw

# LOCAL CI SUBSTITUTION (2026-08-09). GitHub Actions can refuse to run
# account-wide (billing), which would otherwise make every merge impossible.
# scripts/run-ci-local.ps1 reproduces ci.yml exactly and writes a receipt per
# head SHA. A PASSING receipt for THIS PR's head substitutes for the cloud
# verdict -- and only then. This is a substitution with an audit trail, not a
# bypass: the receipt names the sha, the steps and the time, the sha must match
# the PR head, and the substitution is printed loudly and recorded in the PR.
if ($verdict -ne 'pass' -and $LocalCiReceipt) {
    $headSha = (gh pr view $prNumber --repo $ghRepo --json headRefOid --jq '.headRefOid' 2>&1 | Out-String).Trim()
    if (-not (Test-Path -LiteralPath $LocalCiReceipt)) {
        throw "local CI receipt not found: $LocalCiReceipt"
    }
    $receipt = Get-Content -Raw -LiteralPath $LocalCiReceipt | ConvertFrom-Json
    if ($receipt.verdict -ne 'pass') {
        throw "local CI receipt is '$($receipt.verdict)', not pass: $LocalCiReceipt"
    }
    if (-not $headSha.StartsWith($receipt.sha)) {
        throw "local CI receipt is for sha $($receipt.sha) but PR #$prNumber head is $headSha -- re-run run-ci-local.ps1 on the current head"
    }
    Write-Host "task ${taskId}: cloud CI verdict '$verdict' SUBSTITUTED by local receipt $($receipt.sha) ($($receipt.ranAt)) -- $LocalCiReceipt"
    $script:localCiNote = "Cloud CI could not run (GitHub Actions billing). Merged on a local reproduction of ci.yml: sha $($receipt.sha), ran $($receipt.ranAt), verdict pass. See scripts/run-ci-local.ps1."
    $verdict = 'pass'
}

# Full gate now that every fact is in hand. -RequireHumanOk is left off: the
# conductor is the human's delegate for merges (pass it here when that changes).
$refusal = Get-MergeRefusalReason -TaskId $taskId -AgentTask $env:AGENT_TASK `
    -PrNumber $prNumber -PrState $view.state `
    -MergedStamp (Get-TaskMergedStamp -Content $content) `
    -MergeStateStatus $view.mergeStateStatus -ChecksVerdict $verdict -HumanOk:$HumanOk
if ($refusal) { throw "Refusing to merge task ${taskId}: $refusal" }

Write-Host "task ${taskId}: PR #$prNumber OPEN, $($view.mergeStateStatus), checks $verdict -- merging (squash)"
if ($script:localCiNote) {
    # Leave the substitution on the PR itself, so the record lives where a
    # reviewer looks rather than only in this console.
    gh pr comment $prNumber --repo $ghRepo --body $script:localCiNote | Out-Host
}
gh pr merge $prNumber --repo $ghRepo --squash | Out-Host
if ($LASTEXITCODE -ne 0) { throw "gh pr merge $prNumber --squash failed -- nothing was closed." }

# Hand off: close-task.ps1 owns pulling main, stamping merged:, and committing.
$closeArgs = @{ Task = $taskId }
if ($StopAgent) { $closeArgs.StopAgent = $true }
& (Join-Path $PSScriptRoot 'close-task.ps1') @closeArgs
