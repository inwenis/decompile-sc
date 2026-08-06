# Pure/testable helpers for the agent-lifecycle tooling (spawn registry write,
# stop-agent, resume-agent). No process spawning, no WT tabs, no Win32 process
# queries live here -- those side effects stay in the *.ps1 scripts so this
# file can be dot-sourced straight into Pester and exercised on strings and
# temp dirs. See tests/agent-lifecycle.Tests.ps1.

function Format-TaskId {
    # normalize '27' and '027' to the canonical 3-digit id used for filenames
    param([Parameter(Mandatory)][string]$Task)
    return '{0:D3}' -f [int]$Task
}

function Get-TaskIdFromPath {
    # registry key from a task file path: leading 3-digit id of the basename
    param([Parameter(Mandatory)][string]$Path)
    $name = Split-Path -Leaf $Path
    $m = [regex]::Match($name, '^(\d{3})')
    if (-not $m.Success) { throw "No 3-digit task id in filename: $name" }
    return $m.Groups[1].Value
}

function Get-AgentRegistryPath {
    # <root>/scratch/agents/<task>.json -- one file per live worker
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Task
    )
    $id = Format-TaskId -Task $Task
    return Join-Path $Root "scratch/agents/$id.json"
}

function Get-AgentCloseSentinelPath {
    # <root>/scratch/agents/<task>.close -- task 129 graceful-close protocol.
    # reap-agent.ps1 drops this file; the worker wrapper (spawn-agent.ps1's
    # generated launch command) polls for it and, on seeing it, kills its
    # claude child and exits 0 itself so WT's default closeOnExit=graceful
    # auto-closes the tab. Lives next to the registry entry, same lifecycle.
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Task
    )
    $id = Format-TaskId -Task $Task
    return Join-Path $Root "scratch/agents/$id.close"
}

function Write-AgentRegistryEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Entry
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = $Entry | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Read-AgentRegistryEntry {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Remove-AgentRegistryEntry {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
}

function New-StoppedRegistryEntry {
    # The "mark stopped" registry shape shared by stop-agent.ps1 (hard kill)
    # and reap-agent.ps1 (graceful-then-fallback): clear pwshPid, stamp
    # StoppedAt, keep workDir/taskFile/sessionId so resume-agent.ps1 can
    # still find the session later. StoppedAt is a caller-supplied string
    # (not computed here) so this stays pure and testable, same convention
    # as the rest of this file.
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$StoppedAt
    )
    $stopped = @{
        task      = $Entry.task
        taskFile  = $Entry.taskFile
        workDir   = $Entry.workDir
        pwshPid   = $null
        spawnedAt = $Entry.spawnedAt
        stoppedAt = $StoppedAt
    }
    if ($Entry.sessionId) { $stopped.sessionId = $Entry.sessionId }
    return $stopped
}

# Get-TaskState / Test-TaskStateAllowsStop lived here until task 071. Status is
# derived from observables now and no script reads `state:` any more -- the
# -IfDone gate they backed is Test-TaskStatusAllowsStop in lib/derived-status.ps1.

function ConvertTo-ClaudeProjectDirName {
    # claude stores each session under ~/.claude/projects/<mangled workdir>/,
    # where the abs path has : \ / all replaced by '-'
    # (empirical: C:\git\decompile-sc-task006 -> C--git-decompile-sc-task006)
    param([Parameter(Mandatory)][string]$Path)
    return ($Path -replace '[:\\/]', '-')
}

function Resolve-NewestSessionId {
    # newest session transcript for a workdir -> its session id (filename stem).
    # Only top-level *.jsonl files count; subdirs and other files are ignored.
    param(
        [Parameter(Mandatory)][string]$ProjectsRoot,
        [Parameter(Mandatory)][string]$WorkDir
    )
    $projDir = Join-Path $ProjectsRoot (ConvertTo-ClaudeProjectDirName -Path $WorkDir)
    if (-not (Test-Path -LiteralPath $projDir)) { return $null }
    $newest = Get-ChildItem -LiteralPath $projDir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { return $null }
    return [IO.Path]::GetFileNameWithoutExtension($newest.Name)
}
