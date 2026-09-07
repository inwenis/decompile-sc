#Requires -Version 7
<#
Takes the launch lock the way a real suite takes it: drive-game.ps1 dot-sourced
first, so `Set-StrictMode -Version Latest` is in force. Under strict mode a bare
read of an unset global throws, so a test that exercises the lock DIRECTLY can
stay green while every lock-taking suite on the machine is broken.

Its own file, deliberately: the strict mode leaks to everything after it in the
same session state, and no other Describe should inherit it by accident.
#>

BeforeAll {
    $script:pluginDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/plugin'
}

Describe 'the launch lock survives a real suite''s strict mode (task 070)' {

    It 'Enter + re-enter guard + Exit all work after drive-game.ps1 set StrictMode Latest' {
        . (Join-Path $script:pluginDir 'drive-game.ps1')      # sets StrictMode Latest
        . (Join-Path $script:pluginDir 'sc-launch-lock.ps1')

        $tmp = Join-Path $TestDrive 'strictmode-test.lock'
        # The strict-mode oracle: if the held-map global is read bare, this call
        # throws under strict mode before any file is touched.
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
        Test-Path -LiteralPath $tmp | Should -BeFalse

        # Exit must also clear the held-map entry, or the next Enter in this
        # process hits the self-deadlock guard instead of taking the lock.
        $lock2 = Enter-ScLaunchLock -TaskId 'pester-strictmode-2' -LockPath $tmp -TimeoutMinutes 1
        $lock2 | Should -Not -BeNullOrEmpty
        Exit-ScLaunchLock -Lock $lock2
    }
}
