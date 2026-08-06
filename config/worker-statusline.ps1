#Requires -Version 7
# statusLine command, wired in worker settings (task 073). An interactive
# claude session re-renders its status line repeatedly WHILE the model is
# thinking/generating -- no tool call required -- so this is the densest beat
# available: it closes the "long generation, no tool call yet" silent window
# that neither the PreToolUse nor PostToolUse heartbeat can reach.
#
# Must be INSTANT: no git, no gh, no network -- workers do not get the
# console's fancier combined statusline (context bar, PR links, ...), just a
# beat. Touches the SAME work/scratch/agents/<NNN>.heartbeat file heartbeat.ps1
# uses; the console does not care which of the three call sites refreshed
# the mtime -- existence + mtime is the whole protocol (task 032).
try {
    $raw = [Console]::In.ReadToEnd()

    . (Join-Path $PSScriptRoot 'lib/worker-id.ps1')
    $cwd = Get-CwdFromHookJson -Raw $raw
    $id = Get-WorkerIdFromCwd -Cwd $cwd
    # Non-worker cwd (main checkout / conductor session): no registry entry
    # to beat for -- stay fully silent, same skip heartbeat.ps1 applies.
    if (-not $id) { exit 0 }

    # CONDUCTOR_HEARTBEAT_DIR lets the Pester test redirect output, same as
    # heartbeat.ps1.
    $dir = if ($env:CONDUCTOR_HEARTBEAT_DIR) {
        $env:CONDUCTOR_HEARTBEAT_DIR
    }
    else {
        Join-Path (Split-Path $PSScriptRoot -Parent) 'work/scratch/agents'
    }
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir "$id.heartbeat"), [DateTime]::UtcNow.ToString('o'))

    # A short line is enough -- workers don't need a fancy statusline. The
    # clock proves (in a screenshot/mtime trace) that renders are landing
    # seconds apart, not minutes.
    Write-Output "task $id $([DateTime]::Now.ToString('HH:mm:ss'))"
}
catch {
    # A statusline must never break rendering.
}
exit 0
