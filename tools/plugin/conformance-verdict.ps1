#Requires -Version 7
<#
.SYNOPSIS
The one place test-random-conformance.ps1 decides what a run WAS. Issue #68.

.DESCRIPTION
The verdict used to be four inline `elseif`s at the bottom of a 1,100-line script, which
is why two of the three ways a run can fail to be a pass were missing from it for a whole
task -- there was nowhere to test it that did not involve launching StarCraft.

It is a pure function of five numbers, so it is a pure function here, and
tests/conformance-verdict.Tests.ps1 drives it through every state issue #68 describes.
The script prints from what this returns; there is no second copy of the rule.

THE RULE, and why each clause exists:

  1. The run did not finish its episode loop         -> INCOMPLETE
     Task 041. An exception unwound past the summary, the summary printed the 13 checks
     that had run, and `| Tee-Object` swallowed the exit code. `PASS 13 checks` for a run
     that executed no episodes.

  2. Not one episode got past a skip                 -> INCOMPLETE
     Issue #68. `episodesRun++` sat above the four `continue` paths, so six episodes that
     all skipped before acting printed `episodes run: 6 of 6` and `PASS ... 6 episode(s)`.
     No exception, so clause 1 never saw it.

  3. Something failed                                -> FAIL
     Above the seam clause deliberately: a run with real failures is a FAIL, and burying
     that under INCOMPLETE would hide the findings behind a coverage complaint.

  4. The run never reached its seam                  -> INCOMPLETE
     Issue #68 again, and task 041's own lesson turned into a gate. A burst only tests
     task 038's bug if it drives a MULTI-BUILDING selection past the engine's five slots;
     below that a buggy plugin and a correct one behave identically. That was already
     printed as a loud COVERAGE warning -- and PASS/exit 0 printed underneath it, so
     nothing had to act on it. A warning nobody must act on is a comment.

  5. Otherwise                                       -> PASS

Exit code agrees with the word, always. They were separate claims before and one of them
was decorative.
#>

function Get-ScConformanceVerdict {
    [CmdletBinding()]
    param(
        # Did the episode loop run to its end (nothing thrown past it)?
        [Parameter(Mandatory)][bool]$Finished,
        # Episodes the loop began.
        [Parameter(Mandatory)][int]$EpisodesEntered,
        # Episodes that got past every skip and dispatched to a driver.
        [Parameter(Mandatory)][int]$EpisodesActed,
        # Episodes that drove a multi-building selection past the engine's ring, MEASURED
        # after the burst off the engine's own logical queue -- not the planned press count.
        [Parameter(Mandatory)][int]$SeamReached,
        [Parameter(Mandatory)][int]$FailureCount,
        [int]$EpisodesPlanned = 0
    )

    if ($EpisodesActed -gt $EpisodesEntered) {
        throw "Get-ScConformanceVerdict: acted ($EpisodesActed) exceeds entered ($EpisodesEntered); the caller is counting one of them wrong."
    }

    if (-not $Finished) {
        return [pscustomobject]@{
            Verdict = 'INCOMPLETE'; ExitCode = 1; Clause = 'did-not-finish'
            Why = "the run stopped after $EpisodesActed acted / $EpisodesEntered entered of $EpisodesPlanned episode(s)"
        }
    }
    if ($EpisodesActed -eq 0) {
        return [pscustomobject]@{
            Verdict = 'INCOMPLETE'; ExitCode = 1; Clause = 'nothing-acted'
            Why = "the loop finished, but NOT ONE of its $EpisodesEntered episode(s) got past a skip"
        }
    }
    if ($FailureCount -gt 0) {
        return [pscustomobject]@{
            Verdict = 'FAIL'; ExitCode = 1; Clause = 'failures'
            Why = "$FailureCount check(s) failed"
        }
    }
    if ($SeamReached -eq 0) {
        return [pscustomobject]@{
            Verdict = 'INCOMPLETE'; ExitCode = 1; Clause = 'seam-not-reached'
            Why = "$EpisodesActed episode(s) acted, but none drove a multi-building selection past the engine's ring"
        }
    }
    return [pscustomobject]@{
        Verdict = 'PASS'; ExitCode = 0; Clause = 'pass'
        Why = "$EpisodesActed episode(s) acted, $SeamReached seam reach(es), 0 failures"
    }
}
