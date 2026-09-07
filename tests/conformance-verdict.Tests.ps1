#Requires -Version 7
<#
Pester coverage for Get-ScConformanceVerdict (tools/plugin/conformance-verdict.ps1).
A conformance run can print `PASS` and exit 0 having tested nothing, in two shapes:

  a) EVERY EPISODE SKIPPED BEFORE ACTING. Episodes count on entry, above the four
     `continue` paths (SELECT, empty selection, SUPPLY, QUEUE), so six episodes that
     all bail still count as six run, and nothing throws -- a verdict keyed on the
     loop finishing cannot see it.

  b) THE SEAM NEVER REACHED. A burst exercises the multi-building selection bug only
     when it drives a selection past the engine's five slots; below that a plugin
     with the bug behaves identically to one without.

The verdict therefore keys on episodes ACTED and on seam reaches, not on finishing.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'conformance-verdict.ps1')

    # The rejected rule: nothing but an unfinished loop could make a run anything other
    # than PASS/FAIL. The tests assert the current verdict disagrees with it, so a
    # regression back to it fails here.
    function Test-OldVerdict {
        param([bool]$Finished, [int]$EpisodesRun, [int]$SeamCounter, [int]$FailureCount)
        if (-not $Finished)          { return 'INCOMPLETE' }
        if ($FailureCount -eq 0)     { return 'PASS' }
        return 'FAIL'
    }
}

Describe 'Get-ScConformanceVerdict' {

    Context 'issue #68 (a): a run in which every episode skipped before acting' {
        BeforeAll {
            $script:v = Get-ScConformanceVerdict -Finished $true -EpisodesEntered 6 `
                -EpisodesActed 0 -SeamReached 0 -FailureCount 0 -EpisodesPlanned 6
        }

        It 'the OLD rule called this a PASS -- this is the defect' {
            Test-OldVerdict -Finished $true -EpisodesRun 6 -SeamCounter 0 -FailureCount 0 |
                Should -Be 'PASS'
        }
        It 'is INCOMPLETE' { $script:v.Verdict | Should -Be 'INCOMPLETE' }
        It 'names the clause that caught it' { $script:v.Clause | Should -Be 'nothing-acted' }
        It 'exits non-zero, so a caller reading only the exit code agrees with the word' {
            $script:v.ExitCode | Should -Not -Be 0
        }
        It 'says how many episodes were entered, so the reader can see the shape of it' {
            $script:v.Why | Should -BeLike '*6 episode(s)*'
        }
    }

    Context 'issue #68 (b): a full run that never reached its seam' {
        # A coverage warning gates nothing and gets ignored while the verdict printed
        # beside it still says PASS, so a missed seam has to move the verdict itself.
        BeforeAll {
            $script:v = Get-ScConformanceVerdict -Finished $true -EpisodesEntered 6 `
                -EpisodesActed 6 -SeamReached 0 -FailureCount 0 -EpisodesPlanned 6
        }

        It 'the OLD rule called this a PASS -- this is the defect' {
            Test-OldVerdict -Finished $true -EpisodesRun 6 -SeamCounter 0 -FailureCount 0 |
                Should -Be 'PASS'
        }
        It 'is INCOMPLETE' { $script:v.Verdict | Should -Be 'INCOMPLETE' }
        It 'names the clause' { $script:v.Clause | Should -Be 'seam-not-reached' }
        It 'exits non-zero' { $script:v.ExitCode | Should -Not -Be 0 }
    }

    Context 'the same run with ONE seam reach' {
        # Positive control for the clause above: without it, a rule that returned
        # INCOMPLETE for everything would pass both contexts above and be useless.
        BeforeAll {
            $script:v = Get-ScConformanceVerdict -Finished $true -EpisodesEntered 6 `
                -EpisodesActed 6 -SeamReached 1 -FailureCount 0 -EpisodesPlanned 6
        }
        It 'is a PASS' { $script:v.Verdict | Should -Be 'PASS' }
        It 'exits 0' { $script:v.ExitCode | Should -Be 0 }
        It 'says what made it one' { $script:v.Why | Should -BeLike '*1 seam reach(es)*' }
    }

    Context 'task 041: the loop did not finish' {
        BeforeAll {
            $script:v = Get-ScConformanceVerdict -Finished $false -EpisodesEntered 3 `
                -EpisodesActed 2 -SeamReached 1 -FailureCount 0 -EpisodesPlanned 6
        }
        It 'is INCOMPLETE even with a seam reach and no failures' {
            $script:v.Verdict | Should -Be 'INCOMPLETE'
        }
        It 'names the clause' { $script:v.Clause | Should -Be 'did-not-finish' }
        It 'reports acted AND entered, not one of them' {
            $script:v.Why | Should -BeLike '*2 acted / 3 entered*'
        }
    }

    Context 'real failures outrank the coverage clauses' {
        # Reporting INCOMPLETE for a run with findings would bury them behind a complaint
        # about coverage, and the findings are the more actionable half.
        BeforeAll {
            $script:v = Get-ScConformanceVerdict -Finished $true -EpisodesEntered 6 `
                -EpisodesActed 6 -SeamReached 0 -FailureCount 3 -EpisodesPlanned 6
        }
        It 'is a FAIL, not INCOMPLETE' { $script:v.Verdict | Should -Be 'FAIL' }
        It 'exits non-zero' { $script:v.ExitCode | Should -Not -Be 0 }
    }

    Context 'a run that did not finish AND acted on nothing' {
        It 'reports not-finishing first -- it is the cause, the other is the symptom' {
            (Get-ScConformanceVerdict -Finished $false -EpisodesEntered 6 -EpisodesActed 0 `
                -SeamReached 0 -FailureCount 0 -EpisodesPlanned 6).Clause |
                Should -Be 'did-not-finish'
        }
    }

    It 'refuses a caller whose counters cannot both be true' {
        # acted > entered means the runner's two counters have drifted apart, which would
        # silently weaken every clause above. Fail loudly instead.
        { Get-ScConformanceVerdict -Finished $true -EpisodesEntered 2 -EpisodesActed 5 `
            -SeamReached 1 -FailureCount 0 } | Should -Throw -ExpectedMessage '*exceeds entered*'
    }
}
