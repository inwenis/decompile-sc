#Requires -Version 7
# SessionStart hook (conductor sessions only): print the live board so a fresh
# or restarted conductor session starts oriented and re-arms its watchers.
# Ground rule 1: mechanism, not memory. Workers skip (AGENT_TASK set by
# spawn-agent.ps1, or non-main cwd).

$repo = if ($env:CONDUCTOR_REPO_ROOT) { $env:CONDUCTOR_REPO_ROOT } else { 'C:\git\decompile-sc' }
if ($env:AGENT_TASK) { exit 0 }
if ((Get-Location).Path -ne $repo) { exit 0 }

# Register this session as THE conductor (task 080 diagnosis b: contextPct
# was flapping because idle leftover /resume sessions also hit this cwd/
# AGENT_TASK-guarded line). Only conductor-status-heartbeat.ps1's PostToolUse
# re-assert (every tool call) actually settles the race in favor of the
# session that is doing the work — this SessionStart write is just the
# bootstrap so a fresh session isn't unregistered until its first tool call.
try {
    $raw = [Console]::In.ReadToEnd()
    . (Join-Path $PSScriptRoot 'lib/session-registration.ps1')
    $sid = Get-SessionIdFromHookJson -Raw $raw
    $sessionFile = if ($env:CONDUCTOR_SESSION_FILE) { $env:CONDUCTOR_SESSION_FILE } else { Join-Path $repo 'work/scratch/conductor-session-id' }
    Set-ConductorSessionRegistration -SessionId $sid -Path $sessionFile
}
catch {}

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/derived-status.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/data-root.ps1')
$dataRoot = Get-DataRoot -RepoRoot $repo

$lines = @('=== CONDUCTOR BOARD (SessionStart hook) ===')

# Unfinished tasks, by DERIVED status (task 071 -- no task file reports what it
# is doing any more, so the board reads the same observables the console does:
# the agent registry, pr-status.json, the merged: stamp, and open questions).
$blockedIds = Get-BlockedTaskIds -Root $dataRoot   # one messages/ scan for the whole board
$open = Get-ChildItem "$dataRoot\tasks\0*.md" | ForEach-Object {
    $id = [regex]::Match($_.BaseName, '^(\d{3})').Groups[1].Value
    if (-not $id) { return }
    $status = Get-DerivedStatus -Root $dataRoot -Task $id -BlockedIds $blockedIds
    if ($status -ne 'completed') { "{0}: {1}" -f $_.BaseName, $status }
}
$lines += if ($open) { 'Open tasks:'; $open } else { 'Open tasks: none' }

# conductor inbox
$inbox = @(Get-ChildItem "$dataRoot\messages\conductor\inbox\*.md" -ErrorAction SilentlyContinue)
$lines += "Conductor inbox: $($inbox.Count) unread" + ($(if ($inbox) { ' — ' + (($inbox | Select-Object -First 5).Name -join ', ') } else { '' }))

# registry agents: recorded PID alive?
$agents = @(Get-ChildItem "$dataRoot\scratch\agents\*.json" -ErrorAction SilentlyContinue)
foreach ($a in $agents) {
    try {
        $e = Get-Content $a.FullName -Raw | ConvertFrom-Json
        if ($e.stopped) { continue }
        $alive = [bool](Get-Process -Id $e.pwshPid -ErrorAction SilentlyContinue)
        $lines += "Agent $($e.task): pid $($e.pwshPid) " + ($(if ($alive) { 'ALIVE' } else { 'DEAD (resume-agent.ps1 -Task ' + $e.task + '?)' }))
    } catch {}
}

# open PRs
try {
    $prs = gh pr list --repo inwenis/decompile-sc --state open --json number,title 2>$null | ConvertFrom-Json
    $lines += if ($prs) { 'Open PRs:'; ($prs | ForEach-Object { "  #$($_.number) $($_.title)" }) } else { 'Open PRs: none' }
} catch { $lines += 'Open PRs: (gh unavailable)' }

# messages backup on every session start (2026-07-17 incident: stale backup)
try {
    $backup = & (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/backup-messages.ps1') 2>&1 6>&1 | Select-Object -Last 1
    $lines += "Messages backup: $backup"
} catch { $lines += "Messages backup FAILED: $_" }

# pr-status cache freshness (report 055 P10 -- nothing else scheduled this;
# the console's PR panel was showing 3-day-stale data before this)
try {
    $prStatus = & (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/refresh-pr-status.ps1') 2>&1 | Select-Object -Last 1
    $lines += "PR status refreshed: $prStatus"
} catch { $lines += "PR status refresh FAILED: $_" }

# Board-consistency lint (task 131): drift between task-file state and
# reality, surfaced every session so it can't quietly reaccumulate (USER
# 2026-08-06, after 10 finished tasks sat unstamped for two weeks). Runs
# right after the PR status refresh above so its class-1 check (merged/closed
# PR, no merged: stamp) reads the cache that call just wrote -- zero extra gh
# calls in the common case. Never let a board-lint failure block the rest of
# the board.
try {
    $lintOut = & (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/board-lint.ps1') -Repo $repo
    $lines += 'Board lint:'
    $lines += if ($lintOut) { $lintOut -split "`n" } else { '  (no output)' }
} catch { $lines += "Board lint FAILED: $_" }

# GR7 claims this hook surfaces drift -- make that true (report 055 P9 / patch B).
git -C $repo fetch --quiet 2>$null
$c = @((git -C $repo rev-list --left-right --count origin/main...main 2>$null) -split '\s+' | Where-Object { $_ })
if ($c.Count -ge 2 -and ($c[0] -ne '0' -or $c[1] -ne '0')) {
    $lines += "main DRIFT: behind $($c[0]), ahead $($c[1]) -- pull/push before dispatching"
} else { $lines += 'main: in sync with origin' }
$lines += "worktrees: $((@(git -C $repo worktree list) | Measure-Object).Count - 1) registered"

# Duplicate-conductor watchdog: NOT ported (bootstrap review). Upstream's
# arm-watchdog.ps1/watchdog-daemon.ps1 were a temporary experiment whose
# hardcoded retirement date (2026-08-03) has passed; the whole watchdog family
# (check-conductors.ps1, lib/conductor-watchdog.ps1, lib/watchdog-arming.ps1,
# lib/conductor-live-report.ps1, lib/process-cwd.ps1) was dropped with it so
# the board never prints a permanent, non-actionable FAILED line.

$lines += 'RE-ARM NOW: conductor inbox Monitor (AGENTS.md § Messaging).'
$lines -join "`n"
