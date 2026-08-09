# Pure/testable helpers for scripts/run-ci-local.ps1 and the local-receipt
# substitution in scripts/merge-task.ps1. No git, no gh, no filesystem work --
# those stay in the scripts, so this file can be dot-sourced straight into
# Pester and exercised on objects. Same split as lib/merge-task.ps1.
# See tests/ci-local.Tests.ps1.
#
# WHY THIS FILE EXISTS (task 023, 2026-08-09). run-ci-local.ps1 derived its
# verdict from "did any step throw", and a step that SKIPPED had not thrown --
# so "ruff not installed -- skipped" and "no tests/ -- skipped" both produced a
# receipt reading `pass`, indistinguishable from one where those steps actually
# ran. With GitHub Actions down, those receipts are what gates every merge, so
# a hollow pass is a merge waved through on evidence that was never collected.
#
# The rule this encodes: A SKIPPED GATE IS NOT A PASSED GATE. Skips are
# recorded by name, a skipped REQUIRED step is its own verdict rather than a
# pass, and the merge path refuses a receipt that predates this tracking
# instead of assuming the best about it.

function Get-CiReceiptVerdict {
    <#
    .SYNOPSIS
    The one word a receipt carries: pass | fail | incomplete.
    .DESCRIPTION
    `incomplete` is the case this exists for -- nothing failed, but a step that
    must run did not, so the run proves less than a pass claims. It is kept
    distinct from `fail` because the two need different reactions: a fail means
    the code is broken, an incomplete means the evidence is missing.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][string[]]$Failed,
        [AllowNull()][string[]]$RequiredSkipped
    )
    if (@($Failed | Where-Object { $_ }).Count -gt 0) { return 'fail' }
    if (@($RequiredSkipped | Where-Object { $_ }).Count -gt 0) { return 'incomplete' }
    'pass'
}

function Get-CiReceiptRefusalReason {
    <#
    .SYNOPSIS
    Why this local receipt may NOT substitute for the cloud CI verdict, or
    $null if it may.
    .DESCRIPTION
    Every check the merge path used to do inline, plus the two this task added:
    a receipt that skipped a REQUIRED step is refused, and a receipt written
    before skip tracking existed is refused rather than trusted. The second is
    the uncomfortable one and it is deliberate -- an old receipt cannot tell us
    whether it skipped anything, and "we cannot tell" is not "it is fine".
    Re-running run-ci-local.ps1 is seconds; a merge on unexamined evidence is
    the thing this whole task is about.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Receipt,
        [Parameter(Mandatory)][AllowEmptyString()][string]$HeadSha
    )
    if ($null -eq $Receipt) { return 'the receipt file held no JSON object' }

    $fields = @($Receipt.PSObject.Properties.Name)
    if ($fields -notcontains 'skipped') {
        return 'the receipt predates skip tracking (no `skipped` field), so it cannot say whether a gate was skipped -- re-run scripts/run-ci-local.ps1 on the current head'
    }

    $verdict = "$($Receipt.verdict)"
    if ($verdict -ne 'pass') { return "the receipt verdict is '$verdict', not pass" }

    $sha = "$($Receipt.sha)"
    if (-not $sha) { return 'the receipt names no sha' }
    if (-not $HeadSha) { return 'the PR head sha could not be read, so the receipt cannot be matched to it' }
    if (-not $HeadSha.StartsWith($sha)) {
        return "the receipt is for sha $sha but the PR head is $HeadSha -- re-run scripts/run-ci-local.ps1 on the current head"
    }

    # Belt and braces: verdict should already be 'incomplete' in this case, but
    # a receipt is a file on disk and this is the claim that actually matters.
    $reqSkipped = @($Receipt.requiredSkipped | Where-Object { $_ })
    if ($reqSkipped.Count -gt 0) {
        return "the receipt says pass but SKIPPED required step(s): $($reqSkipped -join ', ') -- a skipped gate is not a passed gate"
    }
    $null
}

function Format-CiReceiptSkips {
    <#
    .SYNOPSIS
    One line naming what a receipt did NOT run, for printing next to the pass.
    Empty string when nothing was skipped, so the caller can test it directly.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Receipt)
    if ($null -eq $Receipt) { return '' }
    $skipped = @($Receipt.skipped | Where-Object { $_ })
    if ($skipped.Count -eq 0) { return '' }
    "NOT RUN by this receipt: $($skipped -join ', ')"
}
