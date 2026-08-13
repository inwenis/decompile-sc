#Requires -Version 7
<#
Regression coverage for the #105 strict-mode regression (task 070, 2026-08-13).

sc-launch-lock.ps1's self-deadlock guard read `$global:ScLaunchLockHeld` bare.
#105's own lock tests exercised the lock DIRECTLY and passed -- but no test took
the lock the way every real suite takes it: after dot-sourcing drive-game.ps1,
which sets `Set-StrictMode -Version Latest` for the whole session state. Under
strict mode a bare read of an unset global THROWS, so every lock-taking suite
on the machine broke on #105's first day while 282 tests stayed green.

So this file takes the lock exactly the way a suite does: drive-game.ps1 first,
strict mode and all. It lives in its own file, deliberately -- the strict mode
it turns on leaks to everything after it in the same session state, and no
other Describe should inherit that by accident.
#>

BeforeAll {
    $script:pluginDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/plugin'
}

Describe 'the launch lock survives a real suite''s strict mode (task 070)' {

    It 'Enter + re-enter guard + Exit all work after drive-game.ps1 set StrictMode Latest' {
        . (Join-Path $script:pluginDir 'drive-game.ps1')      # sets StrictMode Latest
        . (Join-Path $script:pluginDir 'sc-launch-lock.ps1')

        $tmp = Join-Path $TestDrive 'strictmode-test.lock'
        # The #105 regression threw right here, before any file was touched.
        $lock = Enter-ScLaunchLock -TaskId 'pester-strictmode' -LockPath $tmp -TimeoutMinutes 1
        try {
            $lock | Should -Not -BeNullOrEmpty

            # The self-deadlock guard must FIRE (its own named throw), not strict-throw.
            { Enter-ScLaunchLock -TaskId 'pester-strictmode-again' -LockPath $tmp -TimeoutMinutes 1 } |
                Should -Throw -ExpectedMessage '*THIS PROCESS already holds*'
        }
        finally {
            Exit-ScLaunchLock -Lock $lock
        }
        # #103's fix: the file is deleted on release.
        Test-Path -LiteralPath $tmp | Should -BeFalse

        # And the held-map bookkeeping was cleaned up: re-entering now succeeds.
        $lock2 = Enter-ScLaunchLock -TaskId 'pester-strictmode-2' -LockPath $tmp -TimeoutMinutes 1
        $lock2 | Should -Not -BeNullOrEmpty
        Exit-ScLaunchLock -Lock $lock2
    }
}
