<#
.SYNOPSIS
Cross-worker launch/deploy serialisation: an exclusive OS file handle, not a
check-then-write on file contents.

.DESCRIPTION
task018: two workers launching StarCraft concurrently is not hypothetical -- it happened
live during this task's own development (a second worker's cleanup logic mistook one
launch for its own leftover and closed it mid-test), and deploy.ps1's running-game
preflight check has the same race across its own build+mirror window. Both take this lock
for the duration of the section that touches the shared working copy / shared game
process.

Deliberately an exclusive `[IO.File]::Open(..., FileShare.None)` handle, not a
check-then-write of JSON content to a plain file: a verifier produced a concrete
two-winner interleaving against the check-then-write version (read "is anyone holding
it", then write "I am holding it" -- another process can do the same read in between). An
OS-level exclusive handle has no such window; the open call itself is the atomic
test-and-acquire. It also deletes the staleness problem for free: if the holder crashes
or is killed, Windows releases the handle the instant the process dies, so a lock that
outlives its holder cannot exist -- no separate pid-liveness bookkeeping needed.

THE FILE IS NOT THE LOCK, AND READERS TREAT IT AS ONE (issue #103, task 069). The
handle is the lock; the file only carries diagnostic content. Until task 069 the release
closed the handle and left the file behind, so EVERY finished run left a lock file naming
its own dead pid -- two workers in one hour read that as "the machine is held" and had to
correct their own "machine is free" messages. Exit-ScLaunchLock therefore now removes the
file after closing the handle (and says which halves succeeded), so an existing file
means one of exactly two things: a live holder (its handle makes the file unopenable and
this function's timeout path fire), or a holder that died without releasing (crash/kill)
-- which Enter-ScLaunchLock reports before reusing the file, so the leak is never
silently absorbed.

Deliberately NOT under work/scratch/: that directory is worktree-local (each worker's own
worktree has its own, unshared copy), which would not serialise anything between workers
at all. C:\sc-work\logs\ is the one location every launch already treats as the shared
scratch root.

This lock is for WORKERS ONLY. Callers must gate taking it on something that is never
true for the user's own deployed play (e.g. $env:AGENT_TASK) -- see run-with-plugin.ps1's
-NoLaunchLock and its "Launch lock" .DESCRIPTION section for why a held/wedged lock must
never be reachable from the desktop shortcut.

Dot-source this file; it defines Enter-ScLaunchLock / Exit-ScLaunchLock in the caller's
scope.
#>

function Enter-ScLaunchLock {
    [CmdletBinding()]
    param(
        [string]$LockPath = 'C:\sc-work\logs\sc-launch.lock',
        [string]$TaskId = $(if ($env:AGENT_TASK) { $env:AGENT_TASK } else { "pid$PID" }),
        [int]$TimeoutMinutes = 5
    )
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
                # holder is a LIVE process -- and the same handle makes the file's
                # content unreadable from outside until it releases or dies. Say that,
                # rather than sending the reader to a Get-Content that must fail.
                throw ("Enter-ScLaunchLock: could not acquire $LockPath within $TimeoutMinutes minute(s). " +
                       'A live process holds the exclusive handle (only a running process can -- the OS drops it at death). ' +
                       "The file's content is unreadable while held; if the holder crashes or finishes, the next acquire here reports who it was.")
            }
            Start-Sleep -Seconds 2
        }
    }
    # The open above succeeded, so nothing holds the lock -- but a file that already
    # has content means the PREVIOUS holder never removed it (Exit-ScLaunchLock does):
    # it crashed, was killed, or its removal failed. Report what the file says before
    # overwriting it, so reclaiming the file never hides the leak (issue #103).
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
    # Diagnostic content only -- the exclusive handle above is the actual lock, this is
    # just so a human (or a later Enter's leftover-file report) can see who held it.
    try {
        $payload = [Text.Encoding]::UTF8.GetBytes((
            [pscustomobject]@{ task = $TaskId; pid = $PID; startedUtc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json))
        $stream.SetLength(0)
        $stream.Write($payload, 0, $payload.Length)
        $stream.Flush()
    }
    catch {
        # Never let a diagnostic-write failure stop the caller from proceeding with a
        # lock it has already genuinely acquired.
    }
    Write-Host "Enter-ScLaunchLock: acquired $LockPath ($TaskId, pid $PID)"
    return $stream
}

function Exit-ScLaunchLock {
    [CmdletBinding()]
    param([System.IO.FileStream]$Lock)
    if (-not $Lock) { return }
    $path = $Lock.Name
    $Lock.Close()
    # The handle was the lock; the file is only diagnostic content. Leaving it behind
    # is issue #103: every later reader sees this run's (by then dead) pid and
    # concludes the machine is held. Remove it, and never claim more than happened.
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
