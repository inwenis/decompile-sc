# PreToolUse hook: force a permission prompt ("ask") for destructive commands.
# Input: hook JSON on stdin (tool_name, tool_input.command).
# Output: permissionDecision ask JSON when a destructive pattern matches;
# nothing (exit 0) otherwise -> normal permission flow continues.

$inp = [Console]::In.ReadToEnd() | ConvertFrom-Json
$cmd = [string]$inp.tool_input.command
# invocation log: proves whether the harness actually runs this hook. Path is
# derived from this script's own location (config/ -> repo root) so the guard
# also works from a checkout that is not C:/git/decompile-sc -- e.g. the CI runner.
# SilentlyContinue: a checkout without scratch/ must not break the hook.
$repoRoot = Split-Path $PSScriptRoot -Parent
Add-Content -Path (Join-Path $repoRoot 'work/scratch/guard-invocations.log') -Value "$([DateTime]::UtcNow.ToString('o')) tool=$($inp.tool_name) cmd=$cmd" -ErrorAction SilentlyContinue
if (-not $cmd) { exit 0 }

# HARD DENY (incident 2026-07-17: a worker's real-repo demo/cleanup deleted all
# of messages/user/, and "ask" is a no-op under bypass permissions): deleting
# anything under a messages/ tree is never a worker's call. Moves (inbox->read)
# don't match; deletes do, in any repo/worktree spelling of the path.
# Anchored to COMMAND POSITION (start / after a separator) so prose inside
# heredocs or grep patterns that merely MENTIONS deleting near a messages
# path no longer trips the deny (worker 071 got blocked twice writing a PR
# body / searching during the wipe investigation, 2026-07-18).
$denyDeletePattern = '(^|[\s;|&(])(rm(\.exe)?\s|rmdir\s|del\s|rd\s|Remove-Item\s|Clear-Content\s|rimraf\s|git\s+clean\b)|[\s.(](fs\.rm|unlinkSync)\s*\('
if ($cmd -match $denyDeletePattern -and $cmd -match '(?i)messages[/\\]') {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = 'deleting under messages/ is banned (2026-07-17 data-loss incident) — move files to read/, or message the conductor if something must truly be removed'
        }
    } | ConvertTo-Json -Depth 5
    exit 0
}

# WORKER MODE (2026-07-17): an "ask" decision OVERRIDES bypass permissions and
# throws a terminal prompt — it froze workers for hours on ROUTINE self-scoped
# ops (killing their own dev server, rm-ing their own fixtures; 048 lost 3h).
# Workers are identified by the AGENT_TASK env var their spawn tab sets.
# Policy per mode:
#   worker    — routine destructive ops pass silently (bypass already grants
#               them; the ask only froze, never protected). Catastrophic /
#               conductor-owned ops are hard-DENIED with a routing message:
#               that also mechanizes "a worker never merges its own PR".
#   conductor — unchanged: everything on the classic list asks.
#   explorer  — narrower than a worker: its contract (explorer/AGENT.md) is
#               "record a finding, don't act" -- it has no self-scoped ops to
#               allow, so EVERY Bash/PowerShell command is hard-denied
#               outright (task 102). Checked first and unconditionally on
#               EXPLORER_RUN_DIR alone (no AGENT_TASK exemption): only
#               run-explorer.ps1 ever sets that var, so its presence is
#               authoritative even if AGENT_TASK leaked in from a calling
#               worker's environment -- it must never fall through to
#               worker mode's silent-pass-routine-ops behavior.
if ($env:EXPLORER_RUN_DIR) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = 'guard-destructive: the explorer never runs shell commands (explorer/AGENT.md: "the runner does all of that") -- record a finding instead'
        }
    } | ConvertTo-Json -Depth 5
    exit 0
}

$isWorker = [bool]$env:AGENT_TASK

$denyWorkerPatterns = @(
    'gh\s+pr\s+merge',
    'gh\s+repo\s+delete',
    'git\s+push(\s+\S+)*\s+(-f|--force(-with-lease)?)\b',
    'Format-Volume',
    'Stop-Computer',
    'Restart-Computer'
)

# AGENTS.md § Rules for workers: unscoped filesystem searches are banned
# (task 031: three orphaned find.exe zombies, a CPU core each, a full day)
# and synthesized OS input / full-screen capture is banned (worker 036
# tabbed into the human's open Gmail and captured their inbox). Task 063 /
# report 055 patch A. Worker mode has nobody watching to answer an "ask", so
# these hard-deny for workers; conductor mode still has a human in the tab,
# so they join the classic "ask" list below instead.
$unscopedOpPatterns = @(
    @{ p = 'find(\.exe)?\s+/\s'; why = 'unscoped filesystem search — search a scoped path (task 031 zombies)' }
    @{ p = 'find(\.exe)?\s+[A-Za-z]:[\\/]?\s'; why = 'unscoped filesystem search — search a scoped path (task 031 zombies)' }
    @{ p = '(Get-ChildItem|gci|ls)\s+[A-Za-z]:[\\/]?\s[^|]*-Recurse'; why = 'unscoped recursive listing of a whole drive — scope the path' }
    @{ p = 'SendKeys|SendInput|nircmd|CopyFromScreen'; why = 'synthesized OS input / full-screen capture is banned — capture your own window or use the browser tool' }
)

if ($isWorker) {
    foreach ($p in $denyWorkerPatterns) {
        if ($cmd -match $p) {
            @{
                hookSpecificOutput = @{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = 'deny'
                    permissionDecisionReason = "conductor-owned operation ('$p') — report to the conductor instead (workers never merge PRs, force-push, or touch the machine)"
                }
            } | ConvertTo-Json -Depth 5
            exit 0
        }
    }
    foreach ($b in $unscopedOpPatterns) {
        if ($cmd -match $b.p) {
            @{
                hookSpecificOutput = @{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = 'deny'
                    permissionDecisionReason = $b.why
                }
            } | ConvertTo-Json -Depth 5
            exit 0
        }
    }
    # Everything else (rm/kill/taskkill/git clean/... in the worker's own
    # scope) passes silently — bypass already permits it, and asking only
    # freezes the tab. messages/ deletion was already denied above.
    exit 0
}

$patterns = @(
    '(^|[\s;|&(])rm(\.exe)?\s',
    '(^|[\s;|&(])rmdir\s',
    '(^|[\s;|&(])del\s',
    '(^|[\s;|&(])rd\s',
    '(^|[\s;|&(])kill\s',
    'Remove-Item',
    'Stop-Process',
    'Clear-Content',
    'Stop-Computer',
    'Restart-Computer',
    'Format-Volume',
    '\btaskkill\b',
    'git\s+push(\s+\S+)*\s+(-f|--force(-with-lease)?)\b',
    'git\s+reset\s+--hard',
    'git\s+clean\b',
    'git\s+branch\s+-D\b',
    'git\s+worktree\s+remove',
    'gh\s+pr\s+merge',
    'gh\s+repo\s+delete',
    'find(\.exe)?\s+/\s',
    'find(\.exe)?\s+[A-Za-z]:[\\/]?\s',
    '(Get-ChildItem|gci|ls)\s+[A-Za-z]:[\\/]?\s[^|]*-Recurse',
    'SendKeys|SendInput|nircmd|CopyFromScreen'
)

foreach ($p in $patterns) {
    if ($cmd -match $p) {
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'ask'
                permissionDecisionReason = "destructive pattern '$p' — conductor guard requires human confirmation"
            }
        } | ConvertTo-Json -Depth 5
        exit 0
    }
}
exit 0
