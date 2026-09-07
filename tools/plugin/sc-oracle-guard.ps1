#Requires -Version 7
<#
.SYNOPSIS
Five named predicates for the five ways an assertion passes without being able to fail.

.DESCRIPTION
Each is one expression a caller could inline, but an inline `-and $samples -gt 0` cannot be
watched failing without a game; named and reachable from Pester, each has a fixture that
makes its claim false (tests/oracle-guard.Tests.ps1).

Every one returns $false (or an empty set) for DEGENERATE input as well as for false input
-- a null reading, a zero count, an empty witness set. "The probe never ran" must never be
indistinguishable from "the thing did not happen", the rule that also governs -1 baselines
and blind ink probes (AGENTS.md § "Oracles: what counts as a read-back").
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
    provocation that had to reach the target, the click that had to land. Two arms that both
    did nothing agree, which is a different result and not a pass, so this returns $false.
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
    True when $After differs from $Before, and both are actually readings. A null on either
    side is a missing reading, not a change.
    .DESCRIPTION
    Any `A == B` assertion passes when the operation did nothing: unrallied buildings share
    a default packed rally value, so "one bucket exists" is satisfied by a no-op. Where the
    operation was supposed to MOVE something, that movement is the assertion.
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
    The members of $Set that are also in $Against -- the intersection a negative assertion
    has to be taken over, or the two sets never meet and it cannot fail in either direction.
    .DESCRIPTION
    Returned as an array so the caller can both assert on its count AND name its members in
    the failure detail: "which ones" is the diagnostic value a bare bool throws away.
    #>
    [CmdletBinding()]
    param(
        # AllowEmptyCollection, not just AllowNull: an empty set is the NORMAL input here --
        # "nothing vanished", "no verdicts" -- and Mandatory refuses @() without it.
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Set,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Against
    )
    if ($null -eq $Set -or $null -eq $Against) { return @() }
    , @(@($Set) | Where-Object { @($Against) -contains $_ })
}
