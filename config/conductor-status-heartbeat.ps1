# PostToolUse hook for the CONDUCTOR session (wired in .claude/settings.json,
# which is local-only): every conductor tool call refreshes status.json's
# state/updatedAt so the top-bar pill is DERIVED from activity, never from the
# conductor remembering to update it (user request 2026-07-18: "this is
# something that should be scripted"; ground rule 1).
#
# Ownership split: this hook owns state=processing + updatedAt. The subject
# stays whatever set-conductor-status.ps1 last wrote (the conductor still sets
# MEANING at decision points); the statusline tee owns contextPct/effort/model.
# Idle is derived by the READER: the UI's staleness hint says how long ago the
# last activity was — no writer needs to declare idleness.
#
# AGENT_TASK guard (task 080 latent-bug fix): git worktrees share the common
# gitdir, so Claude Code resolves the main checkout's local .claude/settings.json
# for a worker's own worktree cwd too — without this guard a busy worker
# stamps state=processing on the CONDUCTOR's pill while the conductor idles.
# Mirrors the guard conductor-sessionstart.ps1 already uses.
if ($env:AGENT_TASK) { exit 0 }

# Cheap + silent: any failure must never break a conductor tool call.
try {
    $raw = [Console]::In.ReadToEnd()

    $path = if ($env:CONDUCTOR_STATUS_FILE) { $env:CONDUCTOR_STATUS_FILE } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'work/messages/conductor/status.json' }
    $cur = @{}
    if (Test-Path -LiteralPath $path) {
        try { $cur = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable } catch { $cur = @{} }
    }
    $cur.state = 'processing'
    $cur.updatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    if (-not $cur.subject) { $cur.subject = 'orchestrating' }
    $json = $cur | ConvertTo-Json -Compress:$false
    [IO.File]::WriteAllText($path, $json + "`n", [Text.UTF8Encoding]::new($false))

    # Session registration re-assert (task 080 diagnosis b): only the
    # actively-working conductor fires tool calls, so re-asserting here on
    # every one converges work/scratch/conductor-session-id to the true
    # conductor even when a leftover /resume session also ran SessionStart
    # once and registered itself first.
    . (Join-Path $PSScriptRoot 'lib/session-registration.ps1')
    $sid = Get-SessionIdFromHookJson -Raw $raw
    $sessionFile = if ($env:CONDUCTOR_SESSION_FILE) { $env:CONDUCTOR_SESSION_FILE } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'work/scratch/conductor-session-id' }
    Set-ConductorSessionRegistration -SessionId $sid -Path $sessionFile
}
catch {}

# Throttled PR-status refresh (user gap-report 2026-07-18: PRs opened MID-task
# were invisible until the next close/session-start refresh). At most every
# 5 min, fire-and-forget so the conductor's tool call is never delayed.
try {
    $prStatus = if ($env:CONDUCTOR_PR_STATUS_FILE) { $env:CONDUCTOR_PR_STATUS_FILE } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'work/scratch/pr-status.json' }
    $stale = -not (Test-Path -LiteralPath $prStatus) -or
        ([DateTime]::UtcNow - (Get-Item -LiteralPath $prStatus).LastWriteTimeUtc).TotalMinutes -gt 5
    if ($stale) {
        $refresher = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/refresh-pr-status.ps1'
        # ProcessStartInfo + CreateNoWindow (task 080 diagnosis c): on
        # Windows, Start-Process -WindowStyle Hidden still allocates a
        # console that flashes on screen before hiding it. UseShellExecute
        # $false + CreateNoWindow $true never allocates one.
        $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
        $psi.Arguments = "-NoProfile -File `"$refresher`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    }
}
catch {}
exit 0
