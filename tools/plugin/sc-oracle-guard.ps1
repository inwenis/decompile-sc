#Requires -Version 7
<#
.SYNOPSIS
Five predicates for the five ways an assertion in this repo passes without being able to
fail. Issues #45, #66, #68, #69, #70 -- and task 052 section 4, which argued this is
structural rather than five unlucky authors.

.DESCRIPTION
These are deliberately tiny. The point is not the arithmetic -- every one of them is an
expression somebody could inline in ten seconds, and that is exactly how the repo ended up
with the sites these were extracted from. The point is that they have NAMES, so a reviewer
reading a suite can see which rule is being applied, and that they live somewhere Pester
can reach, so each one has been WATCHED FAILING against a fixture that makes its claim
false (tests/oracle-guard.Tests.ps1).

An inline `-and $samples -gt 0` cannot be watched failing without a game. That asymmetry --
task 052's finding, that a falsifiable oracle costs a task while a vacuous one costs a line
-- is the thing this file exists to move, one notch, for the cases it covers.

WHAT EACH ONE IS FOR, with the site that motivated it:

  Test-ScReached        a comparison that can be SKIPPED must count what reached it, and
                        zero must not read as agreement.
                        test-sunken-acquire.ps1: `if (-not $f -or -not $o) { continue }`
                        silently skipped the entire plugin-vs-stock comparison and exited 0.
                        test-upgrade-queue.ps1: "the engine never ran two at once (0 of N
                        samples)" is trivially true at N=0.

  Test-ScWitnessed      a claim is only asserted once the thing that would make it
                        meaningful is known to have happened.
                        test-sunken-acquire.ps1: "plugin and stock agree on whether the
                        Sunken attacked" passes when both arms are $false -- two no-ops
                        agree -- and nothing asserted the provocation landed.
                        test-building-parity.ps1: a MIXED-selection refusal asserted
                        after.N == before.N with no evidence the shift-click hit the
                        Barracks. A click on empty ground passes identically.

  Test-ScChanged        a round-trip or before/after comparison must be able to tell a
                        successful operation from a no-op.
                        test-building-parity.ps1: the rally assertion's own comment says the
                        bucket "must have MOVED", and the assertion checked only that there
                        was one bucket -- which unrallied buildings, sharing a default packed
                        value, also satisfy.

  Test-ScExactRefund    "the money came back ($back -gt 0)" is not "refunds EXACTLY", and
                        `refunded -eq $paid` is vacuous when nothing was paid.
                        test-upgrade-queue.ps1:615.

  Get-ScOverlap         a NEGATIVE must be intersected with its POSITIVE, or the two sets
                        never meet and the assertion cannot fail in either direction.
                        Issue #45's shape. test-combat-death.ps1: `$missing` came from a
                        fresh drag box and was never intersected with `$deadTags`, so a
                        survivor shoved out of the box rectangle passed as "dead and
                        dropped".

Every one of them returns $false (or an empty set) for the DEGENERATE input as well as for
the false one -- a null reading, a zero count, an empty witness set. "The probe never ran"
must never be indistinguishable from "the thing did not happen"; that is the same rule
AGENTS.md states for -1 baselines and blind ink probes.
#>

function Test-ScReached {
    <#
    .SYNOPSIS
    True when at least $Count things actually reached the comparison. Zero is never a pass.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Count,
        # Raise for a comparison that needs more than one sample to mean anything -- a
        # min-over-samples reading, a before/after pair.
        [int]$AtLeast = 1
    )
    if ($null -eq $Count) { return $false }
    $n = 0
    if ($Count -is [array] -or $Count -is [System.Collections.ICollection]) { $n = @($Count).Count }
    else { $n = [int]$Count }
    return ($n -ge $AtLeast)
}

function Test-ScWitnessed {
    <#
    .SYNOPSIS
    True when the claim holds AND the witness that makes it meaningful landed.
    .DESCRIPTION
    $Witness is the thing whose absence would make $Claim true for the wrong reason: the
    provocation that had to reach the target, the click that had to land, the arm that had
    to run. A claim with no witness is not a weaker result, it is a different one, so this
    returns $false rather than letting it read as a pass.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$Claim,
        [Parameter(Mandatory)][bool]$Witness
    )
    return ($Witness -and $Claim)
}

function Test-ScChanged {
    <#
    .SYNOPSIS
    True when $After differs from $Before, and both are actually readings.
    .DESCRIPTION
    The no-op trap: any `A == B` assertion passes when the operation did nothing, and any
    "it is still consistent" assertion passes when nothing moved. Where the operation was
    supposed to MOVE something, that movement is the assertion.
    A null on either side is a missing reading, not a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Before,
        [Parameter(Mandatory)][AllowNull()][object]$After
    )
    if ($null -eq $Before -or $null -eq $After) { return $false }
    return ($Before -ne $After)
}

function Test-ScExactRefund {
    <#
    .SYNOPSIS
    True when exactly what was charged came back. Nothing charged is not a refund.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Paid,
        [Parameter(Mandatory)][AllowNull()][object]$Refunded
    )
    if ($null -eq $Paid -or $null -eq $Refunded) { return $false }
    if ([int]$Paid -le 0) { return $false }     # 0 -eq 0 is the vacuity, not the pass
    return ([int]$Refunded -eq [int]$Paid)
}

function Get-ScOverlap {
    <#
    .SYNOPSIS
    The members of $Set that are also in $Against. The intersection a negative assertion
    has to be taken over.
    .DESCRIPTION
    Returned as an array so the caller can both assert on its count AND name its members in
    the failure detail -- "which ones" is the whole diagnostic value, and a bare bool
    throws it away.
    #>
    [CmdletBinding()]
    param(
        # AllowEmptyCollection, not just AllowNull: an empty set is the NORMAL input here --
        # "nothing vanished", "no verdicts" -- and Mandatory refuses @() without it. Caught
        # by its own test, which is the point of having one.
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Set,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Against
    )
    if ($null -eq $Set -or $null -eq $Against) { return @() }
    , @(@($Set) | Where-Object { @($Against) -contains $_ })
}
