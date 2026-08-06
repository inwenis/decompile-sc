# PreToolUse hook: deny out-of-lane WRITES (ground rule 8 + the "worktree edit,
# silent green" incident class -- see reports/055-agentsmd-scriptability.md
# PROPOSAL 4 / P3). Modelled on guard-done-gate.ps1's structure.
#
# Input: hook JSON on stdin (tool_name, tool_input.file_path for Edit/Write,
# tool_input.notebook_path for NotebookEdit).
# Output: permissionDecision deny JSON when the write falls outside the
# caller's lane; nothing (exit 0) otherwise -> normal permission flow
# continues. Fails OPEN on any malformed input (a guard bug must never brick
# every write) -- caught below, logged, exit 0.
#
# SCOPE (v1): Edit / Write / NotebookEdit file paths only. Bash/PowerShell
# redirection (`>`, `Out-File`, `Set-Content`, `Add-Content`, ...) is NOT
# covered -- a shell command can still write anywhere the caller's shell
# permissions allow. guard-destructive.ps1 covers destructive shell PATTERNS
# but not scope. Closing the shell-redirection gap is follow-up work.
#
# LANES (EXPLORER_RUN_DIR checked first and unconditionally -- see below):
#   explorer (EXPLORER_RUN_DIR set):
#     - its run dir              <EXPLORER_RUN_DIR>/**
#     everything else -> DENY. Narrower than a worker on purpose: the
#     explorer is an unattended LLM agent with no task file, no report, no
#     legitimate reason to touch messages/ or another run's scratch dir --
#     "record a finding, don't act" (explorer/AGENT.md) is enforced here,
#     not just asserted in the prompt. Checked before AGENT_TASK, and wins
#     even if AGENT_TASK is also set: only run-explorer.ps1 ever sets
#     EXPLORER_RUN_DIR, so its presence is authoritative even if AGENT_TASK
#     leaked in from a calling worker's environment (task 102) -- it must
#     never fall through to the worker lane's wider worktree access.
#   worker (AGENT_TASK=NNN set, EXPLORER_RUN_DIR unset):
#     - its worktree            C:/git/decompile-sc-taskNNN/**
#     - its task file           C:/git/decompile-sc/work/tasks/NNN-*.md
#     - its report              C:/git/decompile-sc/work/reports/NNN-*.md
#     - messaging (any spelling) **/messages/**
#     - scratch (any spelling)  **/scratch/**
#     everything else -> DENY.
#   conductor (no AGENT_TASK, no EXPLORER_RUN_DIR):
#     - product code in the MAIN checkout: C:/git/decompile-sc/src/**,
#       C:/git/decompile-sc/e2e/** -> DENY ("cut a task", ground rule 8)
#     - everything else (orchestration: work/tasks/, work/reports/,
#       work/messages/, scripts/, config/, docs, ...) -> passes.

# Log path derives from this script's own location (config/ -> repo root) so the
# guard also runs from a checkout that is not C:/git/decompile-sc -- e.g. the CI
# runner, where a hard-coded path would throw into the fail-open catch below and
# silently turn every deny into an allow. Writes are best-effort: a checkout
# without scratch/ must not disable the guard. (task 059)
$logPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'work/scratch/guard-invocations.log'

function Test-PathUnder {
    param([string]$Path, [string]$Root)
    # Normalize slashes + case for a Windows-safe prefix check -- no regex on
    # raw backslashes (traps like \t, \s being read as regex escapes).
    $p = $Path.Replace('\', '/').ToLowerInvariant().TrimEnd('/')
    $r = $Root.Replace('\', '/').ToLowerInvariant().TrimEnd('/')
    return ($p -eq $r) -or $p.StartsWith("$r/")
}

try {
    $inp = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $toolName = [string]$inp.tool_name

    $filePath = switch ($toolName) {
        'NotebookEdit' { [string]$inp.tool_input.notebook_path }
        default { [string]$inp.tool_input.file_path }
    }

    Add-Content -Path $logPath -Value "$([DateTime]::UtcNow.ToString('o')) tool=$toolName file=$filePath (scope)" -ErrorAction SilentlyContinue

    if ($toolName -ne 'Edit' -and $toolName -ne 'Write' -and $toolName -ne 'NotebookEdit') { exit 0 }
    if (-not $filePath) { exit 0 }

    $normalized = $filePath.Replace('\', '/').ToLowerInvariant()
    $repoRoot = 'C:/git/decompile-sc'
    $agentTask = $env:AGENT_TASK

    if ($env:EXPLORER_RUN_DIR) {
        # Explorer mode (task 102): the run dir is the ENTIRE write surface --
        # no task file, no report, no messages/, no other run's scratch.
        # Checked before AGENT_TASK and wins regardless of it (see LANES above).
        $runDirNorm = $env:EXPLORER_RUN_DIR.Replace('\', '/').ToLowerInvariant().TrimEnd('/')
        if (Test-PathUnder -Path $normalized -Root $runDirNorm) { exit 0 }

        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = "guard-scope: the explorer may only write under its run dir ($($env:EXPLORER_RUN_DIR)/). '$filePath' is outside it."
            }
        } | ConvertTo-Json -Depth 5
        exit 0
    }
    elseif ($agentTask) {
        # Worker mode.
        $worktreeRoot = "C:/git/decompile-sc-task$agentTask"
        $taskFilePattern = "^" + [regex]::Escape("$repoRoot/work/tasks/$agentTask-") + "[^/]*\.md$"
        $reportFilePattern = "^" + [regex]::Escape("$repoRoot/work/reports/$agentTask-") + "[^/]*\.md$"

        $inLane = (Test-PathUnder -Path $normalized -Root $worktreeRoot) `
            -or ($normalized -match $taskFilePattern) `
            -or ($normalized -match $reportFilePattern) `
            -or ($normalized -match '(^|/)messages/') `
            -or ($normalized -match '(^|/)scratch/')

        if ($inLane) { exit 0 }

        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = "guard-scope: task $agentTask may only write under its worktree ($worktreeRoot/), its task file (tasks/$agentTask-*.md), its report (reports/$agentTask-*.md), messages/, or scratch/. '$filePath' is none of those."
            }
        } | ConvertTo-Json -Depth 5
        exit 0
    }
    else {
        # Conductor mode: product code in the MAIN checkout is off limits.
        $srcRoot = "$repoRoot/src"
        $e2eRoot = "$repoRoot/e2e"

        $isProductWrite = (Test-PathUnder -Path $normalized -Root $srcRoot) -or (Test-PathUnder -Path $normalized -Root $e2eRoot)

        if (-not $isProductWrite) { exit 0 }

        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = "guard-scope: conductor dispatches — cut a task (ground rule 8). '$filePath' is product code in the main checkout."
            }
        } | ConvertTo-Json -Depth 5
        exit 0
    }
}
catch {
    # A guard bug must never brick every write -- fail open.
    try { Add-Content -Path $logPath -Value "$([DateTime]::UtcNow.ToString('o')) guard-scope ERROR: $_" -ErrorAction SilentlyContinue } catch {}
    exit 0
}
