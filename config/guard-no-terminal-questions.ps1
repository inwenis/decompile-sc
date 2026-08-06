# PreToolUse hook: deny AskUserQuestion so a worker cannot block execution
# by asking an interactive question in its terminal tab.
# Input: hook JSON on stdin (tool_name).
# Output: permissionDecision deny JSON when tool_name == 'AskUserQuestion';
# nothing (exit 0) otherwise -> normal permission flow continues.

$inp = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = [string]$inp.tool_name

# Repo root from this script's own location (config/ -> repo root): the guard
# must also work from a checkout that is not C:/git/decompile-sc (CI runner).
$repoRoot = Split-Path $PSScriptRoot -Parent
Add-Content -Path (Join-Path $repoRoot 'work/scratch/guard-invocations.log') -Value "$([DateTime]::UtcNow.ToString('o')) tool=$toolName (no-terminal-questions)" -ErrorAction SilentlyContinue

if ($toolName -ne 'AskUserQuestion') { exit 0 }

@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = "workers must not ask questions in the terminal — send a question message instead (AGENTS.md § Messaging: type: question / options: ...) or message the conductor."
    }
} | ConvertTo-Json -Depth 5
exit 0
