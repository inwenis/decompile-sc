#Requires -Version 7
<#
.SYNOPSIS
Spawn a worker Claude Code agent in a new Windows Terminal tab, pointed at a task file.

.DESCRIPTION
Opens the tab, then records the tab's pwsh PID in the agent registry
(work/scratch/agents/<taskNNN>.json) so stop-agent.ps1 / resume-agent.ps1 can
find and control the tab later.

.EXAMPLE
./scripts/spawn-agent.ps1 -TaskFile tasks/001-smoke-test.md -Model haiku

.EXAMPLE
./scripts/spawn-agent.ps1 -TaskFile tasks/002-fix-x.md -WorkDir C:\git\decompile-sc-task002 -Model opus
#>
param(
    [Parameter(Mandatory)][string]$TaskFile,
    [string]$WorkDir = 'C:\git\decompile-sc',
    [string]$Title,
    # HUMAN'S STANDING INSTRUCTION (2026-07-11, mechanized task 063 / report
    # 055 patch C): bypass is the default -- the full-mode ask-list froze
    # workers mid-task (rm node_modules, freeing ports) with nobody watching
    # to answer the prompt. Pass -Permissions full when a human IS watching
    # the tab and the ask-list should fire.
    [ValidateSet('full', 'default', 'acceptEdits', 'plan', 'bypass')]
    [string]$Permissions = 'bypass',
    [string]$Model,
    [switch]$Chrome,
    [hashtable]$Env,
    [switch]$NewWindow
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/spawn-agent-args.ps1')
. (Join-Path $PSScriptRoot 'lib/agent-lifecycle.ps1')
. (Join-Path $PSScriptRoot 'lib/agent-proc.ps1')
. (Join-Path $PSScriptRoot 'lib/data-root.ps1')

$taskPath = (Resolve-Path $TaskFile).Path
$conductorRepo = Split-Path $PSScriptRoot -Parent
$taskId = Get-TaskIdFromPath -Path $taskPath
# Subject rotation (2026-07-18, user caught a day-stale subject): doing a
# thing IS the subject - never fail the real operation over it.
try { & (Join-Path $PSScriptRoot 'set-conductor-status.ps1') -State processing -Subject "spawning task $taskId" | Out-Null } catch {}
if (-not $Title) { $Title = [IO.Path]::GetFileNameWithoutExtension($taskPath) }

# ground rule 6: a worktree is one command from working -- if WorkDir is a
# worktree that has never been set up, run setup.ps1 there before the worker
# starts so it opens productive instead of discovering the gap itself.
$nodeModulesExists = Test-Path -LiteralPath (Join-Path $WorkDir 'node_modules')
if (Test-NeedsSetup -WorkDir $WorkDir -ConductorRepo $conductorRepo -NodeModulesExists $nodeModulesExists) {
    Write-Host "spawn-agent: $WorkDir has no node_modules -- running setup.ps1 there first"
    Push-Location $WorkDir
    try { & (Join-Path $WorkDir 'setup.ps1') }
    finally { Pop-Location }
}

# forward slashes -> no escaping problems inside the prompt
$taskPathFwd = $taskPath -replace '\\', '/'

# keep the prompt free of quotes and semicolons; the task file carries the real content
$prompt = "You are a worker agent. Your task file is $taskPathFwd. Read it now and execute it exactly. The task file is your full contract."

# pin the session id up front so resume-agent.ps1 can reopen THIS exact session
# later without scanning transcripts (worktree cwds canonicalize to the main
# repo's projects dir, so newest-jsonl heuristics are unreliable)
$sessionId = [guid]::NewGuid().ToString()

$claudeArgs = Build-ClaudeArgs -Prompt $prompt -SessionId $sessionId -ConductorRepo $conductorRepo -Permissions $Permissions -Model $Model -Chrome:$Chrome

# AGENT_TASK marks the tab's pwsh (human-readable in the decoded command); the
# encoded string is the actual PID-match key. User -Env wins on collision.
$envForSpawn = @{ AGENT_TASK = $taskId }
if ($Env) { foreach ($k in $Env.Keys) { $envForSpawn[$k] = $Env[$k] } }
$envPrefix = Format-EnvPrefix -Env $envForSpawn

# task 129: launch via the sentinel-polling wrapper (not a bare `claude ...`
# line) so reap-agent.ps1 can close this tab gracefully later. ClaudePath is
# resolved here (live lookup) -- the wrapper's ProcessStartInfo skips pwsh's
# own PATH/shim resolution, so it needs the real exe path, not a bare name.
$claudeCmd = Get-Command claude -ErrorAction Stop
$sentinelPath = Get-AgentCloseSentinelPath -Root (Get-DataRoot -RepoRoot $conductorRepo) -Task $taskId
$command = Build-WorkerWrapperCommand -ClaudeArgs $claudeArgs -SentinelPath $sentinelPath -ClaudePath $claudeCmd.Source -EnvPrefix $envPrefix

# -EncodedCommand dodges wt/pwsh nested quoting and wt's ';' command splitting
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

$pwshPid = Start-WtTabResolvePid -Title $Title -WorkDir $WorkDir -Encoded $encoded -NewWindow:$NewWindow

# record the tab so it can be stopped/resumed later
$regPath = Get-AgentRegistryPath -Root (Get-DataRoot -RepoRoot $conductorRepo) -Task $taskId
Write-AgentRegistryEntry -Path $regPath -Entry @{
    task      = $taskId
    taskFile  = $taskPathFwd
    workDir   = ($WorkDir -replace '\\', '/')
    pwshPid   = $pwshPid
    sessionId = $sessionId
    spawnedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

Write-Host "spawned tab '$Title'"
Write-Host "  task:        $taskPathFwd"
Write-Host "  workdir:     $WorkDir"
Write-Host "  permissions: $Permissions"
Write-Host "  model:       $(if ($Model) { $Model } else { '(user default)' })"
Write-Host "  chrome:      $($Chrome.IsPresent)"
Write-Host "  pwshPid:     $(if ($pwshPid) { $pwshPid } else { '(UNRESOLVED -- stop/resume need it; check the tab)' })"
Write-Host "  sessionId:   $sessionId"
Write-Host "  registry:    $($regPath -replace '\\', '/')"
Write-Host "  sentinel:    $($sentinelPath -replace '\\', '/')"
Write-Host "  wrapper command:"
($command -split "`n") | ForEach-Object { Write-Host "    $_" }
