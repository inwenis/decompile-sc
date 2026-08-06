#Requires -Version 7
<#
.SYNOPSIS
Stop a worker agent: kill its Windows Terminal tab (pwsh process tree) using the
PID recorded in the agent registry.

.DESCRIPTION
Reads work/scratch/agents/<taskNNN>.json (written by spawn-agent.ps1), kills the
tab's pwsh process TREE (children include claude/node) -- Windows Terminal then
closes that tab -- and MARKS the registry entry stopped (keeps workDir so
resume-agent.ps1 can bring the agent back later).

-IfDone refuses unless the task's DERIVED status is completed|review|blocked, so
a worker still working is never killed by accident. (Task 071: workers no longer
write `state:` at all, so the gate reads the same observables the console does --
the merged: stamp, the pr-status snapshot, and an unanswered question.)

.EXAMPLE
./scripts/stop-agent.ps1 -Task 027

.EXAMPLE
./scripts/stop-agent.ps1 -Task 027 -IfDone
#>
param(
    [Parameter(Mandatory)][string]$Task,
    [switch]$IfDone
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
    throw "No registry entry for task $taskId at $($regPath -replace '\\','/'). Nothing to stop."
}

if ($IfDone) {
    $status = Get-DerivedStatus -Root $dataRoot -Task $taskId
    if (-not (Test-TaskStatusAllowsStop -Status $status)) {
        throw "-IfDone: task $taskId derives to '$status' (not completed|review|blocked). Refusing to stop a working agent."
    }
    Write-Host "-IfDone: task $taskId derives to '$status' -- OK to stop."
}

$pwshPid = $entry.pwshPid
if ($pwshPid -and (Test-ProcessAlive -ProcessId ([int]$pwshPid))) {
    Write-Host "killing pwsh tree PID $pwshPid (tab closes) ..."
    Stop-ProcessTree -ProcessId ([int]$pwshPid) | ForEach-Object { Write-Host "  $_" }
}
else {
    Write-Host "pwsh PID $pwshPid already gone (or unrecorded) -- nothing to kill."
}

# mark stopped but KEEP workDir/taskFile so resume can find the session later
$marked = @{
    task      = $entry.task
    taskFile  = $entry.taskFile
    workDir   = $entry.workDir
    pwshPid   = $null
    spawnedAt = $entry.spawnedAt
    stoppedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
if ($entry.sessionId) { $marked.sessionId = $entry.sessionId }
Write-AgentRegistryEntry -Path $regPath -Entry $marked

Write-Host "stopped task $taskId; registry marked at $($regPath -replace '\\','/')"
