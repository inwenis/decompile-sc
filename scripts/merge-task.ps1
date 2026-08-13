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

-Pr MMM (issue #107 -- the hotfix path): merge PR MMM, raised by LIVE task NNN,
WITHOUT closing the task. Same gate -- OPEN, position, CI verdict, and the same
-LocalCiReceipt substitution -- plus a refusal unless MMM's head branch is
taskNNN-* (the branch convention proves the PR belongs to that task) and a
refusal when MMM is the task's own pr: deliverable (that merge must close the
task, so it must run without -Pr). No merged: stamp is written, close-task.ps1
is not called, and the output says so in as many words -- a board reader must
never wonder why an open task has a merged PR against it.

.EXAMPLE
./scripts/merge-task.ps1 -Task 059

.EXAMPLE
./scripts/merge-task.ps1 -Task 59 -StopAgent

.EXAMPLE
./scripts/merge-task.ps1 -Task 070 -Pr 106 -LocalCiReceipt work/scratch/ci-local/task070-lockfix-strictmode-e7a0c2e.json
#>
param(
    [Parameter(Mandatory)][string]$Task,
    # reserved for future policy (see -RequireHumanOk in lib/merge-task.ps1)
    [switch]$HumanOk,
    # path to a PASSING scripts/run-ci-local.ps1 receipt for this PR's head sha;
    # substitutes for the cloud CI verdict when Actions cannot run (billing/outage)
    [string]$LocalCiReceipt,
    # HOTFIX PATH (issue #107): merge THIS open PR -- raised by live task NNN off
    # a taskNNN-* branch -- without stamping or closing the task. Bare PR number.
    [string]$Pr,
    # forwarded to close-task.ps1: also stop the worker's tab after closing
    [switch]$StopAgent,
    # override for fixture-repo testing (task 074 -- no test may write into
    # the real tasks/ dir); defaults to the real repo this script lives in
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/merge-task.ps1')
. (Join-Path $PSScriptRoot 'lib/ci-local.ps1')
. (Join-Path $PSScriptRoot 'lib/close-task.ps1')
. (Join-Path $PSScriptRoot 'lib/agent-lifecycle.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')

$repo = $Repo
$dataRoot = Get-DataRoot -RepoRoot $repo
$taskId = '{0:D3}' -f [int]$Task
$hotfix = -not [string]::IsNullOrEmpty($Pr)
if ($hotfix -and $Pr -notmatch '^\d+$') {
    throw "-Pr must be a bare PR number (e.g. 106), got '$Pr'"
}
if ($hotfix -and $StopAgent) {
    throw '-StopAgent stops the worker after closing its task; -Pr merges WITHOUT closing -- the two cannot be combined'
}
# Subject rotation (2026-07-18, user caught a day-stale subject): doing a
# thing IS the subject - never fail the real operation over it.
$subject = if ($hotfix) { "merging hotfix PR #$Pr for task $taskId" } else { "merging task $taskId" }
try { & (Join-Path $PSScriptRoot 'set-conductor-status.ps1') -State processing -Subject $subject | Out-Null } catch {}

$taskFile = Get-ChildItem -Path (Join-Path $dataRoot "tasks/$taskId-*.md") -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $taskFile) { throw "No task file work/tasks/$taskId-*.md under $repo." }

$content = Get-Content -LiteralPath $taskFile.FullName -Raw
$taskPrNumber = Get-TaskPrNumber -Content $content
$prNumber = if ($hotfix) { $Pr } else { $taskPrNumber }

if (-not $hotfix) {
    # Local half of the gate first -- no point spending gh round-trips on a task
    # whose own file already disqualifies it. The hotfix path has its own gate
    # (Get-HotfixRefusalReason) below: it needs the PR's head branch, so it can
    # only run after the gh view.
    $refusal = Get-LocalRefusalReason -TaskId $taskId -AgentTask $env:AGENT_TASK `
        -PrNumber $prNumber -MergedStamp (Get-TaskMergedStamp -Content $content)
    if ($refusal) { throw "Refusing to merge task ${taskId}: $refusal" }
}

# The PR's own state + its position against the base branch. ConvertFrom-Json is
# safe here: all three fields are plain strings/bools, no dates to mangle.
# --repo pin (bootstrap review): gh resolves the target repo from the cwd's
# git remote. Without the pin, running this from any other checkout (e.g. the
# LIVE conductor repo) would evaluate -- and MERGE -- that repo's same-numbered
# PR. Every gh pr call in this script and close-task.ps1 carries the pin.
# The hotfix path also needs headRefName: the branch is what proves the PR
# belongs to the named task.
$ghRepo = 'inwenis/decompile-sc'
$viewFields = if ($hotfix) { 'state,mergeStateStatus,headRefName' } else { 'state,mergeStateStatus' }
$viewRaw = gh pr view $prNumber --repo $ghRepo --json $viewFields 2>&1
if ($LASTEXITCODE -ne 0) { throw "gh pr view $prNumber failed: $viewRaw" }
$view = ("$viewRaw" | Out-String) | ConvertFrom-Json

if ($hotfix) {
    $refusal = Get-HotfixRefusalReason -TaskId $taskId -AgentTask $env:AGENT_TASK `
        -Pr $Pr -TaskPrNumber $taskPrNumber -HeadRefName $view.headRefName
    if ($refusal) { throw "Refusing to merge PR #$Pr as a task $taskId hotfix: $refusal" }
}

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
    # Every reason a receipt may not stand in for CI, in one testable place
    # (lib/ci-local.ps1) -- including the two task 023 added: a receipt that
    # skipped a REQUIRED step, and a receipt written before skip tracking,
    # which cannot tell us whether it skipped anything at all.
    $receiptRefusal = Get-CiReceiptRefusalReason -Receipt $receipt -HeadSha $headSha
    if ($receiptRefusal) { throw "local CI receipt cannot substitute for CI: $receiptRefusal ($LocalCiReceipt)" }

    # What the receipt did NOT run is printed next to the pass, every time. A
    # substitution is only as good as the evidence it names.
    $skipLine = Format-CiReceiptSkips -Receipt $receipt
    Write-Host "task ${taskId}: cloud CI verdict '$verdict' SUBSTITUTED by local receipt $($receipt.sha) ($($receipt.ranAt)) -- $LocalCiReceipt"
    if ($skipLine) { Write-Host "task ${taskId}: $skipLine" }
    $script:localCiNote = "Cloud CI could not run (GitHub Actions billing). Merged on a local reproduction of ci.yml: sha $($receipt.sha), ran $($receipt.ranAt), verdict pass." +
        $(if ($skipLine) { " $skipLine." } else { '' }) + " See scripts/run-ci-local.ps1."
    $verdict = 'pass'
}

# Full gate now that every fact is in hand. -RequireHumanOk is left off: the
# conductor is the human's delegate for merges (pass it here when that changes).
# Hotfix mode already passed Get-HotfixRefusalReason above; the PR-side half of
# the gate (OPEN, position, CI) is the same for both modes.
$refusal = if ($hotfix) {
    Get-RemoteRefusalReason -PrNumber $prNumber -PrState $view.state `
        -MergeStateStatus $view.mergeStateStatus -ChecksVerdict $verdict
} else {
    Get-MergeRefusalReason -TaskId $taskId -AgentTask $env:AGENT_TASK `
        -PrNumber $prNumber -PrState $view.state `
        -MergedStamp (Get-TaskMergedStamp -Content $content) `
        -MergeStateStatus $view.mergeStateStatus -ChecksVerdict $verdict -HumanOk:$HumanOk
}
if ($refusal) { throw "Refusing to merge task ${taskId}: $refusal" }

Write-Host "task ${taskId}: PR #$prNumber OPEN, $($view.mergeStateStatus), checks $verdict -- merging (squash)"
if ($script:localCiNote) {
    # Leave the substitution on the PR itself, so the record lives where a
    # reviewer looks rather than only in this console.
    gh pr comment $prNumber --repo $ghRepo --body $script:localCiNote | Out-Host
}
gh pr merge $prNumber --repo $ghRepo --squash | Out-Host
if ($LASTEXITCODE -ne 0) { throw "gh pr merge $prNumber --squash failed -- nothing was closed." }

if ($hotfix) {
    # The whole point of -Pr (issue #107): the task is NOT closed. Say so in
    # as many words -- a board reader looking at an open task with a merged PR
    # against it must find this line, not a mystery.
    Write-Host "task ${taskId}: merged hotfix PR #$prNumber ($($view.headRefName)) WITHOUT closing task $taskId -- no merged: stamp written, task $taskId stays OPEN$(if ($taskPrNumber) { " (its own deliverable PR #$taskPrNumber is untouched)" })"

    # USER RULE (2026-07-15): keep the main checkout current with remote main.
    # The hotfix just advanced origin/main; unlike the close path there is no
    # local commit to make, so a diverged checkout is a warning, not a failure.
    git -C $repo pull --ff-only 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Warning 'git pull --ff-only failed -- main checkout diverged; pull by hand.' }

    # Board freshness rides the merge (other open PRs may now be BEHIND) --
    # never fail the merge over a refresh hiccup.
    try {
        $prStatusOut = & (Join-Path $PSScriptRoot 'refresh-pr-status.ps1') -RepoRoot $repo 2>&1 | Select-Object -Last 1
        Write-Host "pr-status refreshed: $prStatusOut"
    } catch { Write-Warning "refresh-pr-status failed: $_" }
}
else {
    # Hand off: close-task.ps1 owns pulling main, stamping merged:, and committing.
    $closeArgs = @{ Task = $taskId }
    if ($StopAgent) { $closeArgs.StopAgent = $true }
    & (Join-Path $PSScriptRoot 'close-task.ps1') @closeArgs
}
