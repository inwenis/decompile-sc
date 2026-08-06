#Requires -Version 7
<#
.SYNOPSIS
Resume a stopped worker agent in a fresh Windows Terminal tab, continuing its
previous Claude Code session (full context intact).

.DESCRIPTION
Reads work/scratch/agents/<taskNNN>.json for the recorded workDir, finds the newest
session transcript under ~/.claude/projects/<mangled workDir>/*.jsonl, and opens
a new tab running `claude --resume <sessionId>` with the SAME hooks-only+bypass
settings a worker spawns with (Build-ClaudeArgs). The registry entry is updated
with the new PID and session id.

-Prompt injects an optional follow-up user turn into the resumed session (used by
the task 027 live probe to make the agent replay its pre-kill nonce).

.EXAMPLE
./scripts/resume-agent.ps1 -Task 027

.EXAMPLE
./scripts/resume-agent.ps1 -Task 027 -Model opus
#>
param(
    [Parameter(Mandatory)][string]$Task,
    [string]$Model,
    [string]$Prompt,
    [ValidateSet('full', 'default', 'acceptEdits', 'plan', 'bypass')]
    [string]$Permissions = 'bypass',
    [switch]$NewWindow
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/spawn-agent-args.ps1')
. (Join-Path $PSScriptRoot 'lib/agent-lifecycle.ps1')
. (Join-Path $PSScriptRoot 'lib/agent-proc.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')

$repo = Split-Path $PSScriptRoot -Parent
$taskId = Format-TaskId -Task $Task
$regPath = Get-AgentRegistryPath -Root (Get-DataRoot -RepoRoot $repo) -Task $taskId
$entry = Read-AgentRegistryEntry -Path $regPath
if (-not $entry) {
    throw "No registry entry for task $taskId at $($regPath -replace '\\','/'). Cannot resume."
}
$workDir = [string]$entry.workDir
if (-not $workDir) { throw "Registry entry for task $taskId has no workDir." }

# prefer the id spawn pinned (deterministic). Fall back to newest-transcript
# scan only for legacy entries that predate the recorded sessionId.
$sessionId = [string]$entry.sessionId
if ($sessionId) {
    Write-Host "resuming recorded session id $sessionId"
}
else {
    $projectsRoot = Join-Path $HOME '.claude/projects'
    $sessionId = Resolve-NewestSessionId -ProjectsRoot $projectsRoot -WorkDir $workDir
    if (-not $sessionId) {
        throw "No sessionId in registry and no transcript under $projectsRoot/$(ConvertTo-ClaudeProjectDirName -Path $workDir)/*.jsonl for workDir $workDir."
    }
    Write-Host "resuming newest transcript (fallback) session id $sessionId"
}

# PREFLIGHT (incident 2026-07-17): interactive sessions flush their transcript
# to ~/.claude/projects/**/<sessionId>.jsonl only on graceful exit. Worker tabs
# die by taskkill, so their transcripts usually never hit disk — `claude
# --resume` then prints "No conversation found" and exits INSTANTLY, leaving a
# dead or idle tab that looks resumed but is not (stranded 041+044 twice each).
# Refuse up front instead of manufacturing a zombie; fresh spawn in the same
# worktree is the recovery path (task file + inbox = full context).
$transcript = Get-ChildItem (Join-Path $HOME '.claude/projects') -Recurse -Filter "$sessionId.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $transcript) {
    throw "No transcript on disk for session $sessionId — this session was hard-killed and cannot be resumed. Fresh-spawn instead: ./scripts/spawn-agent.ps1 -TaskFile $($entry.taskFile) -WorkDir $workDir -Model <m> -Permissions bypass (brief the new session via its inbox first)."
}

# A resume WITHOUT a prompt opens the session and leaves it sitting at the CLI
# prompt: no inbox monitor, no heartbeat, no work — alive-looking but inert.
# Never resume silent; default to a wake-up instruction when the caller
# doesn't supply one.
if (-not $Prompt) {
    $Prompt = "You were resumed. First: arm your inbox monitor (AGENTS.md section Messaging), then read C:/git/decompile-sc/work/messages/$taskId/inbox/ and act on anything unread, then continue your task file."
}

$claudeArgs = Build-ClaudeArgs -ResumeSessionId $sessionId -Prompt $Prompt -ConductorRepo $repo -Permissions $Permissions -Model $Model

$envForSpawn = @{ AGENT_TASK = $taskId }
$envPrefix = Format-EnvPrefix -Env $envForSpawn

# task 129: same sentinel-polling wrapper spawn-agent.ps1 uses, so a resumed
# tab is reap-agent.ps1-closeable too, not just a freshly spawned one.
$claudeCmd = Get-Command claude -ErrorAction Stop
$sentinelPath = Get-AgentCloseSentinelPath -Root (Get-DataRoot -RepoRoot $repo) -Task $taskId
$command = Build-WorkerWrapperCommand -ClaudeArgs $claudeArgs -SentinelPath $sentinelPath -ClaudePath $claudeCmd.Source -EnvPrefix $envPrefix
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

$title = "$taskId-resumed"
$pwshPid = Start-WtTabResolvePid -Title $title -WorkDir $workDir -Encoded $encoded -NewWindow:$NewWindow

Write-AgentRegistryEntry -Path $regPath -Entry @{
    task      = $entry.task
    taskFile  = $entry.taskFile
    workDir   = $workDir
    pwshPid   = $pwshPid
    spawnedAt = $entry.spawnedAt
    sessionId = $sessionId
    resumedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

Write-Host "resumed task $taskId"
Write-Host "  workdir:   $workDir"
Write-Host "  session:   $sessionId"
Write-Host "  model:     $(if ($Model) { $Model } else { '(user default)' })"
Write-Host "  pwshPid:   $(if ($pwshPid) { $pwshPid } else { '(UNRESOLVED -- check the tab)' })"
Write-Host "  registry:  $($regPath -replace '\\','/')"
Write-Host "  sentinel:  $($sentinelPath -replace '\\', '/')"
Write-Host "  wrapper command:"
($command -split "`n") | ForEach-Object { Write-Host "    $_" }
