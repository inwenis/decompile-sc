# Pure helpers for building the claude command lines run-explorer.ps1 launches
# (the agent driver and the layer-3 judge). No side effects (no Start-Process,
# no env/filesystem writes) so tests can dot-source this file directly and
# exercise the launch-building logic without ever spawning a real agent
# (precedent: scripts/lib/spawn-agent-args.ps1 / agent-proc.ps1 split).
#
# Both callers get their working directory AND their argument list from the
# same object, so a test on the returned launch is a test on what
# run-explorer.ps1 actually passes to Start-Process -- there is no second,
# untested copy of "which directory does this run in" to drift out of sync.

function Get-ExplorerSettingsPath {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return (Join-Path $RepoRoot 'config/explorer-settings.json') -replace '\\', '/'
}

function Get-ExplorerAgentLaunch {
    # The agent driver: a headless `claude -p` session with Playwright MCP,
    # confined to its own run dir.
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$McpConfigPath,
        [string]$Model = 'sonnet'
    )
    $settingsPath = Get-ExplorerSettingsPath -RepoRoot $RepoRoot
    return [ordered]@{
        WorkingDirectory = $RunDir
        ArgumentList     = @(
            '-p',
            '--model', $Model,
            '--mcp-config', $McpConfigPath,
            '--strict-mcp-config',
            '--permission-mode', 'bypassPermissions',
            '--allowedTools', 'mcp__playwright__*,Read,Write,Edit',
            '--settings', $settingsPath,
            '--add-dir', $RunDir
        )
    }
}

function Get-ExplorerJudgeLaunch {
    # Layer-3 judgement: a second, narrower headless `claude -p` call (Read +
    # Write only, no MCP) that looks at flagged screenshots. Same run dir,
    # same settings file -- it is a second unattended agent in the same repo
    # and gets the same containment.
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Model = 'sonnet'
    )
    $settingsPath = Get-ExplorerSettingsPath -RepoRoot $RepoRoot
    return [ordered]@{
        WorkingDirectory = $RunDir
        ArgumentList     = @(
            '--model', $Model,
            '--permission-mode', 'bypassPermissions',
            '--allowedTools', 'Read,Write',
            '--settings', $settingsPath,
            '--add-dir', $RunDir
        )
    }
}

function Get-ExplorerEnvOverrides {
    # What run-explorer.ps1 must set on its OWN process env before spawning
    # either claude call, and restore afterward. AGENT_TASK is explicitly
    # cleared ($null), not just left alone: run-explorer.ps1 can itself be
    # invoked from inside a worker's session (AGENT_TASK=NNN already set in
    # that process's environment), and Start-Process children inherit the
    # parent's env block -- an unset AGENT_TASK would otherwise leak the
    # calling worker's task id into the explorer child, and guard-scope would
    # then confine it to that worker's WORKTREE instead of its run dir,
    # letting an off-script explorer agent edit product code there.
    param([Parameter(Mandatory)][string]$RunDir)
    return @{
        AGENT_TASK       = $null
        EXPLORER_RUN_DIR = $RunDir
    }
}
