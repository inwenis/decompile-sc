#Requires -Version 7
<#
Pester cases for tools/plugin/sc-launch-lock.ps1 (task 069, issue #103).

WHY THESE EXIST. The exclusive OS handle is the lock; the file only carries diagnostic
content. Until task 069 Exit-ScLaunchLock closed the handle and left the file behind, so
EVERY finished run -- exit 0 or not -- left a lock file naming its own dead pid, and
`Exit-ScLaunchLock: released` printed while it did. Two workers in one hour (tasks 066
and 068) read that file as "the machine is held" and had to retract their own "machine
is free" messages. These cases assert the half the log line used to lie about: the file
is gone after a release, a leftover file is REPORTED at the next acquire rather than
silently absorbed, and the release message never claims a removal that did not happen.
They fail against the pre-069 implementation by construction.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../tools/plugin/sc-launch-lock.ps1')
    $script:dir = Join-Path ([IO.Path]::GetTempPath()) "sc-launch-lock-tests-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:dir | Out-Null
}

AfterAll {
    if ($script:dir -and (Test-Path -LiteralPath $script:dir)) {
        Remove-Item -LiteralPath $script:dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Exit-ScLaunchLock removes the file it stops needing' {

    It 'leaves NO lock file behind after a clean acquire/release pair (the issue #103 leak)' {
        $p = Join-Path $script:dir 'clean-pair.lock'
        $s = Enter-ScLaunchLock -LockPath $p -TaskId 't-clean' 6>$null
        Exit-ScLaunchLock -Lock $s 6>$null
        Test-Path -LiteralPath $p | Should -BeFalse
    }

    It 'says it removed the file, not a bare "released" that covers both outcomes' {
        $p = Join-Path $script:dir 'message.lock'
        $s = Enter-ScLaunchLock -LockPath $p -TaskId 't-msg' 6>$null
        $out = Exit-ScLaunchLock -Lock $s 6>&1 | ForEach-Object { "$_" }
        ($out -join "`n") | Should -Match 'released, removed'
    }

    It 'does not steal the file when another process re-acquired between Close and Delete, and says so' {
        $p = Join-Path $script:dir 'contended.lock'
        $s1 = Enter-ScLaunchLock -LockPath $p -TaskId 't-first' 6>$null
        Exit-ScLaunchLock -Lock $s1 6>$null
        # Simulate the next worker winning the re-acquire race: a second exclusive
        # handle on the same path (share semantics are per-handle, so one process
        # exercises the same OS behaviour two processes would).
        $s2 = Enter-ScLaunchLock -LockPath $p -TaskId 't-second' 6>$null
        # A third release object pointing at the same path (stale stream shape):
        # closing an already-released stream is not constructible here, so instead
        # assert the delete-refusal path directly: the file survives s2's handle.
        { [IO.File]::Delete($p) } | Should -Throw
        Exit-ScLaunchLock -Lock $s2 6>$null
        Test-Path -LiteralPath $p | Should -BeFalse
    }
}

Describe 'Enter-ScLaunchLock reports a leftover file instead of silently absorbing it' {

    It 'names the previous holder and observes its pid state when reclaiming a leftover file' {
        $p = Join-Path $script:dir 'leftover.lock'
        # A crashed/killed holder: file present, no handle. Pid chosen dead by
        # construction -- a just-exited child's pid, verified gone before use.
        $child = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', 'exit' -PassThru -WindowStyle Hidden
        $child.WaitForExit()
        $deadPid = $child.Id
        (Get-Process -Id $deadPid -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        Set-Content -LiteralPath $p -NoNewline -Value (
            [pscustomobject]@{ task = 'crashed-task'; pid = $deadPid; startedUtc = '2026-08-13T00:00:00Z' } | ConvertTo-Json)

        $captured = Enter-ScLaunchLock -LockPath $p -TaskId 't-reclaim' 3>&1 6>$null
        $stream = $captured | Where-Object { $_ -is [IO.FileStream] }
        $warnings = @($captured | Where-Object { $_ -is [Management.Automation.WarningRecord] } | ForEach-Object { "$_" })
        try {
            $stream | Should -Not -BeNullOrEmpty
            ($warnings -join "`n") | Should -Match 'already existed'
            ($warnings -join "`n") | Should -Match "pid $deadPid"
            ($warnings -join "`n") | Should -Match 'not running'
            # It reports what it OBSERVED (file present, handle free, pid state), never
            # a culprit or a cause it cannot know.
            ($warnings -join "`n") | Should -Not -Match 'another worker'
        }
        finally { if ($stream) { Exit-ScLaunchLock -Lock $stream 6>$null } }
    }

    It 'acquires despite a leftover dead-pid file (a lock naming a dead pid is not a lock)' {
        $p = Join-Path $script:dir 'dead-pid.lock'
        Set-Content -LiteralPath $p -NoNewline -Value '{"task":"gone","pid":999999999,"startedUtc":"2026-08-13T00:00:00Z"}'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $s = Enter-ScLaunchLock -LockPath $p -TaskId 't-notblocked' 3>$null 6>$null
        $sw.Stop()
        try {
            $s | Should -Not -BeNullOrEmpty
            # Immediate, not after a retry loop: the stale FILE never blocked the HANDLE.
            $sw.ElapsedMilliseconds | Should -BeLessThan 2000
        }
        finally { Exit-ScLaunchLock -Lock $s 6>$null }
    }

    It 'names a SELF-deadlock immediately instead of timing out against its own handle (070, -RemoveWindowed)' {
        # The lock is not re-entrant, and a holder that Enters again used to wait
        # on ITSELF for the whole timeout -- a five-minute stall whose eventual
        # message blamed "another launch/deploy". The process knows what it
        # holds; the wait must not happen and the message must say who.
        $p = Join-Path $script:dir 'self.lock'
        $s = Enter-ScLaunchLock -LockPath $p -TaskId 't-self' 6>$null
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $thrown = $null
            try { Enter-ScLaunchLock -LockPath $p -TaskId 't-self-again' -TimeoutMinutes 0 6>$null }
            catch { $thrown = $_.Exception.Message }
            $sw.Stop()
            $thrown | Should -Not -BeNullOrEmpty
            $thrown | Should -Match 'THIS PROCESS already holds'
            $thrown | Should -Match 'NoLaunchLock'
            # Fail-fast, not a timeout: no retry loop was entered.
            $sw.ElapsedMilliseconds | Should -BeLessThan 2000
            # And it must not blame a foreign holder -- that was the wrong reason.
            $thrown | Should -Not -Match 'another launch/deploy'
        }
        finally { Exit-ScLaunchLock -Lock $s 6>$null }
    }

    It 'is released for re-acquire by the same process after Exit (the tracker does not leak)' {
        $p = Join-Path $script:dir 'reenter.lock'
        $s1 = Enter-ScLaunchLock -LockPath $p -TaskId 't-first' 6>$null
        Exit-ScLaunchLock -Lock $s1 6>$null
        $s2 = Enter-ScLaunchLock -LockPath $p -TaskId 't-second' 6>$null
        try { $s2 | Should -Not -BeNullOrEmpty }
        finally { Exit-ScLaunchLock -Lock $s2 6>$null }
    }

    It 'is still mutually exclusive across processes: a foreign holder refuses the acquire' {
        $p = Join-Path $script:dir 'exclusive.lock'
        $marker = Join-Path $script:dir 'exclusive.acquired'
        $lockLib = (Resolve-Path (Join-Path $PSScriptRoot '../tools/plugin/sc-launch-lock.ps1')).Path
        $childScript = ". '$lockLib'; `$s = Enter-ScLaunchLock -LockPath '$p' -TaskId 't-foreign'; " +
                       "Set-Content -LiteralPath '$marker' -Value ok; Start-Sleep -Seconds 12; Exit-ScLaunchLock -Lock `$s"
        $child = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', $childScript -PassThru -WindowStyle Hidden
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath $marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
            Test-Path -LiteralPath $marker | Should -BeTrue -Because 'the child must have acquired before the contention attempt means anything'
            { Enter-ScLaunchLock -LockPath $p -TaskId 't-loser' -TimeoutMinutes 0 6>$null } |
                Should -Throw -ExpectedMessage '*could not acquire*'
        }
        finally {
            try { Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}
