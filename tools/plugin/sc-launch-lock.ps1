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
                throw "Enter-ScLaunchLock: could not acquire $LockPath within $TimeoutMinutes minute(s) -- another launch/deploy is still using it. Check C:\sc-work\logs\sc-launch.lock's content for who."
            }
            Start-Sleep -Seconds 2
        }
    }
    # Diagnostic content only -- the exclusive handle above is the actual lock, this is
    # just so a human (or the timeout error above) can see who holds it.
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
    if ($Lock) {
        $Lock.Close()
        Write-Host 'Exit-ScLaunchLock: released'
    }
}
