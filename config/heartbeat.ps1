#Requires -Version 7
# Heartbeat hook (task 032; PreToolUse bracket added task 073). Wired on both
# PreToolUse and PostToolUse so a beat fires either side of every worker tool
# call -- a long-RUNNING tool (not just a completed one) still reads as alive.
# Must be FAST and must NEVER fail the tool. It touches
# work/scratch/agents/<NNN>.heartbeat next to the agent registry; the console then
# DERIVES liveness from that file's mtime instead of trusting the task file's
# `state:` line, which workers forget to keep current. The file's CONTENT is
# irrelevant -- existence + mtime is the whole protocol.
param(
    # Pre = bracket beat only (touch the file, stay output-silent). Post =
    # today's full behavior, INCLUDING the unread-inbox injection -- gated to
    # Post only so a worker never gets the same "UNREAD INBOX" context twice
    # per tool call (once from Pre, once from Post) now that both fire.
    [ValidateSet('Pre', 'Post')]
    [string]$Phase = 'Post'
)
try {
    $raw = [Console]::In.ReadToEnd()

    . (Join-Path $PSScriptRoot 'lib/worker-id.ps1')
    $cwd = Get-CwdFromHookJson -Raw $raw
    if (-not $cwd) { exit 0 }
    $id = Get-WorkerIdFromCwd -Cwd $cwd
    if (-not $id) { exit 0 }

    # CONDUCTOR_HEARTBEAT_DIR lets the Pester test redirect output. In production
    # the dir is derived from THIS script's own location (config/), so the
    # heartbeat always lands beside the registry in the MAIN checkout regardless
    # of the worker's cwd (a worktree).
    $dir = if ($env:CONDUCTOR_HEARTBEAT_DIR) {
        $env:CONDUCTOR_HEARTBEAT_DIR
    }
    else {
        Join-Path (Split-Path $PSScriptRoot -Parent) 'work/scratch/agents'
    }

    [IO.Directory]::CreateDirectory($dir) | Out-Null
    # WriteAllText refreshes the mtime (and creates the file if absent). The
    # timestamp text is a human-debug convenience only; nothing parses it.
    [IO.File]::WriteAllText((Join-Path $dir "$id.heartbeat"), [DateTime]::UtcNow.ToString('o'))

    # Unread-inbox injection (report 055 P4 / issue #33): a worker that is
    # WORKING fires this hook on every tool call, so it cannot stay deaf past
    # its next one -- even with no monitor armed. CONDUCTOR_MESSAGES_DIR lets
    # the Pester test redirect this like CONDUCTOR_HEARTBEAT_DIR above; in
    # production it is the main checkout's work/messages/ dir, independent of
    # the worker's worktree cwd.
    # Post-phase only (task 073): the bracket now fires this script on BOTH
    # PreToolUse and PostToolUse for the same tool call. Emitting the
    # injection from both would double it in the worker's context every call.
    if ($Phase -eq 'Post') {
        $messagesDir = if ($env:CONDUCTOR_MESSAGES_DIR) {
            $env:CONDUCTOR_MESSAGES_DIR
        }
        else {
            Join-Path (Split-Path $PSScriptRoot -Parent) 'work/messages'
        }
        $inboxDir = Join-Path $messagesDir "$id/inbox"
        $unreadCount = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue).Count
        if ($unreadCount -gt 0) {
            @{
                hookSpecificOutput = @{
                    hookEventName     = 'PostToolUse'
                    additionalContext = "UNREAD INBOX: $unreadCount message(s) - read work/messages/$id/inbox/ now"
                }
            } | ConvertTo-Json -Depth 5
        }
    }
}
catch {
    # A heartbeat must never break a worker's tool call.
}
exit 0
