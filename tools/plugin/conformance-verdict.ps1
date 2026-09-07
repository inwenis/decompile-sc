#Requires -Version 7
<#
.SYNOPSIS
The one place test-random-conformance.ps1 decides what a run WAS.

.DESCRIPTION
A pure function of five numbers, so the rule is testable without launching StarCraft, and
the caller prints from what this returns rather than keeping a second copy. Clause order
is load-bearing:
  1. loop did not finish -> INCOMPLETE: an exception past the summary otherwise prints
     PASS over a run that executed no episodes, and `| Tee-Object` -- which every run is
     piped through -- swallows the non-zero exit that would have contradicted it.
  2. nothing acted -> INCOMPLETE: episodes that all skip before acting throw nothing, so
     clause 1 cannot catch them.
  3. something failed -> FAIL, ahead of the seam clause: burying real failures under
     INCOMPLETE hides them behind a coverage complaint.
  4. seam not reached -> INCOMPLETE: a burst only exercises the plugin when it drives a
     MULTI-BUILDING selection past the engine's five slots; below that a buggy plugin and
     a correct one behave identically, and a coverage warning that gates nothing is ignored.
  5. otherwise -> PASS. Exit code always agrees with the word.
#>

function Get-ScConformanceVerdict {
    [CmdletBinding()]
    param(
        # False when anything unwound past the episode loop.
        [Parameter(Mandatory)][bool]$Finished,
        [Parameter(Mandatory)][int]$EpisodesEntered,
        # Got past every skip and dispatched to a driver: what clause 2 counts.
        [Parameter(Mandatory)][int]$EpisodesActed,
        # MEASURED after the burst off the engine's own logical queue, not the planned
        # press count: a planned burst can fall short of the ring and still look reached.
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
