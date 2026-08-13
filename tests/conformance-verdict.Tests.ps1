#Requires -Version 7
<#
Pester coverage for Get-ScConformanceVerdict (tools/plugin/conformance-verdict.ps1) --
issue #68.

THE BUGS THIS PINS. test-random-conformance.ps1 could print `PASS` and exit 0 for two
kinds of run that had tested nothing:

  a) EVERY EPISODE SKIPPED BEFORE ACTING. `$script:episodesRun++` sat at the top of the
     loop, above the four `continue` paths (SELECT, empty selection, SUPPLY, QUEUE), so a
     run in which all six episodes bailed still printed `episodes run: 6 of 6` and
     `PASS N checks, 0 failures, 6 episode(s)`. No exception was involved, so task 041's
     INCOMPLETE protection -- which keys off the loop finishing -- never saw it.

  b) THE SEAM NEVER REACHED. A burst only tests task 038's bug if it drives a
     MULTI-BUILDING selection past the engine's five slots; below that a plugin with the
     bug behaves identically to one without it. The harness knew this and printed a loud
     COVERAGE warning for it -- with PASS and exit 0 printed underneath, so nothing had to
     act on it.

Each test below states the OLD rule beside the new one and asserts they disagree, so the
file records what was broken rather than only what is expected now. `Test-OldVerdict` is
the pre-fix logic, transcribed from the four inline elseifs it replaced.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'conformance-verdict.ps1')

    # The rule as it stood before issue #68, verbatim in behaviour: the only way to be
    # anything other than PASS/FAIL was for the episode loop not to finish.
    function Test-OldVerdict {
        param([bool]$Finished, [int]$EpisodesRun, [int]$SeamCounter, [int]$FailureCount)
        if (-not $Finished)          { return 'INCOMPLETE' }
        if ($FailureCount -eq 0)     { return 'PASS' }
        return 'FAIL'
    }
}

Describe 'Get-ScConformanceVerdict' {

    Context 'issue #68 (a): a run in which every episode skipped before acting' {
        # Six episodes entered, none dispatched, nothing thrown, no failures recorded --
        # because nothing ran to record one.
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
        # The positive control for the clause above. Without this, a rule that returned
        # INCOMPLETE for everything would pass both tests above and be useless.
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
        # Deliberate ordering. A run with findings is a FAIL: reporting INCOMPLETE would
        # bury the findings behind a complaint about coverage, and the findings are the
        # more actionable half.
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
        # acted > entered means the two increments have drifted apart in the runner, which
        # would silently weaken every clause above. Fail loudly instead.
        { Get-ScConformanceVerdict -Finished $true -EpisodesEntered 2 -EpisodesActed 5 `
            -SeamReached 1 -FailureCount 0 } | Should -Throw -ExpectedMessage '*exceeds entered*'
    }
}
