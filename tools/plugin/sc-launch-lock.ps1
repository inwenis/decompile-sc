<#
.SYNOPSIS
Cross-worker launch/deploy serialisation: an exclusive OS file handle, not a
check-then-write on file contents.

.DESCRIPTION
Two workers launching StarCraft concurrently close each other's games (one worker's
cleanup mistakes the other's launch for its own leftover), and deploy.ps1's running-game
preflight races over its build+mirror window. Both take this lock around the section that
touches the shared working copy or the shared game process.

The handle IS the lock. A check-then-write of file content has a demonstrated two-winner
interleaving (read "is anyone holding it", then write "I am holding it" -- another process
reads in between); FileShare.None makes the open itself the atomic test-and-acquire.
Windows drops the handle the instant the holder dies, so no lock can outlive its holder
and no pid-liveness bookkeeping is needed.

Not under work/scratch/: that directory is worktree-local, so each worker would lock its
own private copy and nothing would serialise. C:\decompile-sc-data\sc-work\logs\ is the scratch root every
launch already shares.

WORKERS ONLY: callers must gate taking it on something never true of the user's own
deployed play (e.g. $env:AGENT_TASK), so a held or wedged lock is unreachable from the
desktop shortcut -- see AGENTS.md § "Launch lock".

Dot-source this file; it defines Enter-ScLaunchLock / Exit-ScLaunchLock in the caller's
scope.
#>

function Enter-ScLaunchLock {
    [CmdletBinding()]
    param(
        [string]$LockPath = 'C:\decompile-sc-data\sc-work\logs\sc-launch.lock',
        [string]$TaskId = $(if ($env:AGENT_TASK) { $env:AGENT_TASK } else { "pid$PID" }),
        [int]$TimeoutMinutes = 5
    )
    # SELF-DEADLOCK GUARD. The lock is not re-entrant: a process that holds it
    # and Enters again waits on ITSELF for the whole timeout (the shape is a
    # caller holding the lock, then invoking a helper that takes it too). The OS
    # handle cannot tell the waiter who holds it -- the holder's share mode
    # blocks even a read -- but this process knows what it holds, so track it and
    # fail fast with the real reason. Nested lock-taking helpers get -NoLaunchLock.
    # Get-Variable, not a bare $global: read: suites dot-source drive-game.ps1,
    # which sets StrictMode Latest, where reading an unset global throws.
    if ($null -eq (Get-Variable -Name ScLaunchLockHeld -Scope Global -ValueOnly -ErrorAction SilentlyContinue)) {
        $global:ScLaunchLockHeld = @{}
    }
    $norm = [IO.Path]::GetFullPath($LockPath)
    if ($global:ScLaunchLockHeld.ContainsKey($norm)) {
        $held = $global:ScLaunchLockHeld[$norm]
        throw ("Enter-ScLaunchLock: THIS PROCESS already holds $LockPath (acquired as '$($held.Task)' at $($held.AcquiredUtc)). " +
               'Waiting would deadlock against ourselves for the whole timeout. A caller that already holds the lock must pass ' +
               '-NoLaunchLock to nested helpers that also take it (the -RemoveWindowed shape), or release before re-entering.')
    }
    New-Item -ItemType Directory -Path (Split-Path $LockPath -Parent) -Force | Out-Null
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $stream = $null
    while (-not $stream) {
        try {
            $stream = [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            if ((Get-Date) -ge $deadline) {
                # The holder's FileShare.None handle is what refused this open, so the
                # holder is a LIVE process -- and that same handle keeps the file's
                # content unreadable from outside. Say so, rather than sending the
                # reader to a Get-Content that must fail.
                throw ("Enter-ScLaunchLock: could not acquire $LockPath within $TimeoutMinutes minute(s). " +
                       'A live process holds the exclusive handle (only a running process can -- the OS drops it at death). ' +
                       "The file's content is unreadable while held; if the holder crashes or finishes, the next acquire here reports who it was.")
            }
            Start-Sleep -Seconds 2
        }
    }
    # The open succeeded, so nothing holds the lock -- but content in the file means the
    # prior holder never removed it (Exit-ScLaunchLock does): it crashed, was killed, or
    # its removal failed. Report what the file says before overwriting, so reclaiming it
    # never absorbs the leak silently.
    try {
        if ($stream.Length -gt 0) {
            $buf = [byte[]]::new([int]$stream.Length)
            $null = $stream.Read($buf, 0, $buf.Length)
            $stream.Position = 0
            $previous = [Text.Encoding]::UTF8.GetString($buf)
            $prev = $null
            try { $prev = $previous | ConvertFrom-Json } catch { }
            if ($prev -and $prev.pid) {
                $prevAlive = [bool](Get-Process -Id $prev.pid -ErrorAction SilentlyContinue)
                $pidNote = if ($prevAlive) { "a process with pid $($prev.pid) is running (possibly a reused pid)" }
                           else { "pid $($prev.pid) is not running" }
                Write-Warning ("Enter-ScLaunchLock: $LockPath already existed, naming task '$($prev.task)' pid $($prev.pid) started $($prev.startedUtc) -- $pidNote. " +
                               'Nothing holds the OS handle, so that run is over; it left its lock file behind (died without releasing, or its removal failed). Reusing the file for this run.')
            }
            else {
                Write-Warning ("Enter-ScLaunchLock: $LockPath already existed with unparseable content ($previous) -- " +
                               'nothing holds the OS handle, so whatever wrote it is done with it. Reusing the file for this run.')
            }
        }
    }
    catch {
        # Reporting a leftover file must never stop an acquire that already succeeded.
    }
    # Diagnostic content only -- the exclusive handle above is the actual lock. This is
    # what a human (or a later Enter's leftover-file report) reads to see who held it.
    try {
        $payload = [Text.Encoding]::UTF8.GetBytes((
            [pscustomobject]@{ task = $TaskId; pid = $PID; startedUtc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json))
        $stream.SetLength(0)
        $stream.Write($payload, 0, $payload.Length)
        $stream.Flush()
    }
    catch {
        # A failed diagnostic write must not stop a caller that genuinely holds the lock.
    }
    $global:ScLaunchLockHeld[$norm] = @{ Task = $TaskId; AcquiredUtc = [DateTime]::UtcNow.ToString('o') }
    Write-Host "Enter-ScLaunchLock: acquired $LockPath ($TaskId, pid $PID)"
    return $stream
}

function Exit-ScLaunchLock {
    [CmdletBinding()]
    param([System.IO.FileStream]$Lock)
    if (-not $Lock) { return }
    $path = $Lock.Name
    $Lock.Close()
    $heldMap = Get-Variable -Name ScLaunchLockHeld -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($heldMap) { $heldMap.Remove([IO.Path]::GetFullPath($path)) }
    # The handle was the lock; the file is only diagnostic content. A file left behind
    # makes every later reader see this run's (by then dead) pid and conclude the machine
    # is held. Remove it, and report exactly which half succeeded.
    try {
        [IO.File]::Delete($path)
        Write-Host "Exit-ScLaunchLock: released, removed $path"
    }
    catch [IO.IOException] {
        # Between Close and Delete another worker can acquire; its FileShare.None
        # handle makes this delete fail. Benign: the file's content is now THEIRS.
        Write-Host "Exit-ScLaunchLock: released; $path was not removed because another process holds it now (its content names the new holder)"
    }
    catch {
        Write-Warning ("Exit-ScLaunchLock: released the handle, but removing $path failed ($($_.Exception.Message)). " +
                       "The file still names pid $PID and will be stale once this process exits; the next Enter-ScLaunchLock will report it.")
    }
}
