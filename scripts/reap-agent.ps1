#Requires -Version 7
<#
.SYNOPSIS
Reap a finished worker agent: close its Windows Terminal tab GRACEFULLY (task 129),
falling back to the old hard force-kill only if the worker doesn't respond.

.DESCRIPTION
stop-agent.ps1's taskkill /PID <pwshPid> /T /F yanks the tab's pwsh process abruptly.
Windows Terminal's default closeOnExit=graceful only auto-closes a pane whose hosted
process exits ON ITS OWN with code 0 -- a killed process reads as crashed and the tab
stays open with the exit-code banner (the bug this task fixes).

This script instead drops a sentinel file (Get-AgentCloseSentinelPath) that the
worker's own wrapper script (spawn-agent.ps1 -> Build-WorkerWrapperCommand) polls for
while its claude child runs. Seeing the sentinel, the wrapper kills its own claude
child and calls `exit 0` itself -- a self-directed graceful exit WT auto-closes the
tab for. reap-agent.ps1 waits up to -GraceTimeoutSec for that pwshPid to disappear on
its own; only if it doesn't (a frozen worker, or a pre-129 registry entry whose
wrapper predates the sentinel protocol) does it fall back to the same tree-kill
stop-agent.ps1 always used -- honest about the tab staying open on that path.

-IfDone gates exactly like stop-agent.ps1 -IfDone: refuses unless the task's DERIVED
status is completed|review|blocked, so a working agent is never reaped by accident.

.EXAMPLE
./scripts/reap-agent.ps1 -Task 027

.EXAMPLE
./scripts/reap-agent.ps1 -Task 027 -IfDone
#>
param(
    [Parameter(Mandatory)][string]$Task,
    [switch]$IfDone,
    # how long to wait for the worker's wrapper to notice the sentinel and
    # self-exit before falling back to a hard tree-kill
    [int]$GraceTimeoutSec = 15
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/agent-lifecycle.ps1')
. (Join-Path $PSScriptRoot 'lib/agent-proc.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')
. (Join-Path $PSScriptRoot 'lib/derived-status.ps1')

$repo = Split-Path $PSScriptRoot -Parent
$dataRoot = Get-DataRoot -RepoRoot $repo
$taskId = Format-TaskId -Task $Task
$regPath = Get-AgentRegistryPath -Root $dataRoot -Task $taskId
$entry = Read-AgentRegistryEntry -Path $regPath
if (-not $entry) {
    throw "No registry entry for task $taskId at $($regPath -replace '\\','/'). Nothing to reap."
}

if ($IfDone) {
    $status = Get-DerivedStatus -Root $dataRoot -Task $taskId
    if (-not (Test-TaskStatusAllowsStop -Status $status)) {
        throw "-IfDone: task $taskId derives to '$status' (not completed|review|blocked). Refusing to reap a working agent."
    }
    Write-Host "-IfDone: task $taskId derives to '$status' -- OK to reap."
}

$sentinelPath = Get-AgentCloseSentinelPath -Root $dataRoot -Task $taskId
$pwshPid = $entry.pwshPid
$closedGracefully = $false

if (-not $pwshPid -or -not (Test-ProcessAlive -ProcessId ([int]$pwshPid))) {
    Write-Host "pwsh PID $pwshPid already gone (or unrecorded) -- nothing to reap."
    $closedGracefully = $true
}
else {
    Write-Host "dropping close sentinel for task $taskId -- waiting up to ${GraceTimeoutSec}s for a graceful exit ..."
    New-Item -ItemType File -Path $sentinelPath -Force | Out-Null

    $deadline = [DateTime]::UtcNow.AddSeconds($GraceTimeoutSec)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Test-ProcessAlive -ProcessId ([int]$pwshPid))) { $closedGracefully = $true; break }
        Start-Sleep -Milliseconds 500
    }

    if ($closedGracefully) {
        Write-Host "task $taskId closed gracefully -- tab should already be gone."
    }
    else {
        Write-Warning "task $taskId did not react to the close sentinel within ${GraceTimeoutSec}s -- falling back to a hard tree-kill. The tab will NOT auto-close (WT reads a killed process as crashed); close it by hand or accept the exit-code banner."
        Stop-ProcessTree -ProcessId ([int]$pwshPid) | ForEach-Object { Write-Host "  $_" }
    }
    Remove-Item -LiteralPath $sentinelPath -Force -ErrorAction SilentlyContinue
}

$stoppedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-AgentRegistryEntry -Path $regPath -Entry (New-StoppedRegistryEntry -Entry $entry -StoppedAt $stoppedAt)

Write-Host "reaped task $taskId (graceful: $closedGracefully); registry marked at $($regPath -replace '\\','/')"
