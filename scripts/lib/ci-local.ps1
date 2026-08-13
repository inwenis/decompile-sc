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

function Get-CiStepSkip {
    <#
    .SYNOPSIS
    Classifies a step body's raw pipeline output as a Skip-Step marker or a normal result.
    .DESCRIPTION
    ISSUE #72 HOLE 3b. PowerShell collects every unconsumed pipeline value a script block
    produces into ONE ARRAY the moment the block emits more than a single object -- so a step
    that writes output (an accidental bare expression, an uncaptured cmdlet result) before
    `return Skip-Step '...'` hands the caller an array with the marker as its LAST element, not
    the marker itself. The classifier this replaces checked `$out -is [psobject]` against the
    whole array: System.Object[] is NOT [psobject], so the check was false, the skip's Reason
    was never read, and the step was recorded as an ordinary pass with `detail` set to the
    array's stringified junk. Measured: a step that runs `"stray"; return (Skip-Step 'x')`
    produces `$out -is [array]` = $true, `$out -is [psobject]` = $false, `$out[-1] -is [psobject]`
    = $true with `ScStepSkipped`/`Reason` intact. So classify from the LAST element, not the
    whole value.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Out)
    $candidate = if ($Out -is [array]) { if ($Out.Count -gt 0) { $Out[-1] } else { $null } } else { $Out }
    $isSkip = ($null -ne $candidate) -and ($candidate -is [psobject]) -and
              (@($candidate.PSObject.Properties.Name) -contains 'ScStepSkipped')
    [pscustomobject]@{
        IsSkip = $isSkip
        Reason = if ($isSkip) { "$($candidate.Reason)" } else { $null }
    }
}

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
        [Parameter(Mandatory)][AllowEmptyString()][string]$HeadSha,
        # ISSUE #72 HOLE 2. `$HeadSha.StartsWith($sha)` alone accepts any prefix, including a
        # one-character one that matches thousands of commits. run-ci-local.ps1 always writes a
        # `git rev-parse --short HEAD` sha (7+ chars), so a shorter one can only come from a
        # hand-edited or truncated file -- refuse it rather than trust a coincidence.
        [int]$MinShaLength = 7
    )
    if ($null -eq $Receipt) { return 'the receipt file held no JSON object' }

    $fields = @($Receipt.PSObject.Properties.Name)
    if ($fields -notcontains 'skipped') {
        return 'the receipt predates skip tracking (no `skipped` field), so it cannot say whether a gate was skipped -- re-run scripts/run-ci-local.ps1 on the current head'
    }
    # ISSUE #72 HOLE 2. Same belt-and-braces reasoning as skip tracking above: a receipt
    # written before dirty-worktree tracking existed cannot say whether the sha it names is
    # what actually got tested, so "we cannot tell" is refused rather than assumed clean.
    if ($fields -notcontains 'dirty') {
        return 'the receipt predates dirty-worktree tracking (no `dirty` field), so it cannot say whether uncommitted changes were tested -- re-run scripts/run-ci-local.ps1 on the current head'
    }
    if ($Receipt.dirty) {
        $files = @($Receipt.dirtyFiles | Where-Object { $_ }) -join ', '
        return "the receipt was taken against a DIRTY worktree ($files) -- it may not reflect sha $($Receipt.sha) -- commit or stash, then re-run scripts/run-ci-local.ps1"
    }

    $verdict = "$($Receipt.verdict)"
    if ($verdict -ne 'pass') { return "the receipt verdict is '$verdict', not pass" }

    $sha = "$($Receipt.sha)"
    if (-not $sha) { return 'the receipt names no sha' }
    if ($sha.Length -lt $MinShaLength) {
        return "the receipt's sha '$sha' is shorter than the minimum $MinShaLength-character prefix -- too short to safely match against the PR head"
    }
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
