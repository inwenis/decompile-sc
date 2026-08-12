#Requires -Version 7
<#
Pester coverage for scripts/lib/ci-local.ps1 -- the receipt logic that decides whether a
local CI run may substitute for the cloud verdict while GitHub Actions is down.

THE BUG THESE PIN (task 023 review, 2026-08-09). run-ci-local.ps1 derived its verdict from
"did any step throw", and a step that SKIPPED had not thrown. So "ruff not installed --
skipped" and "no tests/ -- skipped" both produced a receipt reading `pass`, byte-identical
in every field that mattered to one where those steps actually ran. merge-task.ps1 accepted
it. With Actions down those receipts gate every merge, so a hollow pass is a merge waved
through on evidence nobody collected.

The rule, and every case below is one edge of it: A SKIPPED GATE IS NOT A PASSED GATE.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'lib' 'ci-local.ps1')

    function New-Receipt {
        param(
            [string]$Sha = 'abc1234',
            [string]$Verdict = 'pass',
            [string[]]$Failed = @(),
            [string[]]$Skipped = @(),
            [string[]]$RequiredSkipped = @(),
            [switch]$Legacy,     # a receipt written before skip tracking existed
            [bool]$Dirty = $false,
            [string[]]$DirtyFiles = @(),
            [switch]$LegacyDirty # a receipt written after skip tracking but before dirty tracking
        )
        $o = [ordered]@{ branch = 'b'; sha = $Sha; ranAt = '2026-08-09T18:00:00Z'
                         verdict = $Verdict; failed = $Failed }
        if (-not $Legacy) {
            $o.skipped = $Skipped; $o.requiredSkipped = $RequiredSkipped
            if (-not $LegacyDirty) { $o.dirty = $Dirty; $o.dirtyFiles = $DirtyFiles }
        }
        [pscustomobject]$o
    }
}

Describe 'ci receipt verdict' {

    It 'is pass only when nothing failed and no required step was skipped' {
        Get-CiReceiptVerdict -Failed @() -RequiredSkipped @() | Should -Be 'pass'
    }

    It 'is fail when a step threw' {
        Get-CiReceiptVerdict -Failed @('pester') -RequiredSkipped @() | Should -Be 'fail'
    }

    It 'is INCOMPLETE -- not pass -- when a required step was skipped' {
        # The whole point: nothing failed, and it still is not a pass.
        Get-CiReceiptVerdict -Failed @() -RequiredSkipped @('pester') | Should -Be 'incomplete'
    }

    It 'keeps fail ahead of incomplete when both are true' {
        Get-CiReceiptVerdict -Failed @('parse-ps1') -RequiredSkipped @('pester') | Should -Be 'fail'
    }

    It 'treats an optional skip as a pass -- it is recorded, not fatal' {
        # ruff being uninstalled is a fact about the machine, not about the code.
        Get-CiReceiptVerdict -Failed @() -RequiredSkipped @() | Should -Be 'pass'
    }
}

Describe 'ci receipt substitution for the cloud verdict' {

    It 'accepts a clean receipt whose sha prefixes the PR head' {
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -Sha 'abc1234') -HeadSha 'abc1234def567' |
            Should -BeNullOrEmpty
    }

    It 'refuses a receipt that skipped a REQUIRED step even though it says pass' {
        # A receipt on disk can disagree with its own verdict; this is the claim that matters.
        $r = New-Receipt -Verdict 'pass' -Skipped @('pester') -RequiredSkipped @('pester')
        Get-CiReceiptRefusalReason -Receipt $r -HeadSha 'abc1234def567' |
            Should -BeLike '*SKIPPED required step(s): pester*'
    }

    It 'refuses an incomplete verdict' {
        $r = New-Receipt -Verdict 'incomplete' -Skipped @('pester') -RequiredSkipped @('pester')
        Get-CiReceiptRefusalReason -Receipt $r -HeadSha 'abc1234def567' |
            Should -BeLike "*verdict is 'incomplete'*"
    }

    It 'refuses a receipt that predates skip tracking rather than assuming it skipped nothing' {
        # "We cannot tell whether a gate ran" is not "the gate ran".
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -Legacy) -HeadSha 'abc1234def567' |
            Should -BeLike '*predates skip tracking*'
    }

    It 'still refuses a receipt for the wrong sha' {
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -Sha 'dead999') -HeadSha 'abc1234def567' |
            Should -BeLike '*but the PR head is*'
    }

    It 'still refuses a failing receipt, and a missing one' {
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -Verdict 'fail' -Failed @('pester')) -HeadSha 'abc1234def567' |
            Should -BeLike "*verdict is 'fail'*"
        Get-CiReceiptRefusalReason -Receipt $null -HeadSha 'abc1234def567' |
            Should -BeLike '*no JSON object*'
    }

    It 'accepts an OPTIONAL skip but names it, so the merge prints what did not run' {
        $r = New-Receipt -Skipped @('ruff', 'hooktest')
        Get-CiReceiptRefusalReason -Receipt $r -HeadSha 'abc1234def567' | Should -BeNullOrEmpty
        Format-CiReceiptSkips -Receipt $r | Should -Be 'NOT RUN by this receipt: ruff, hooktest'
    }

    It 'says nothing when nothing was skipped -- a receipt with a skip line differs from one without' {
        Format-CiReceiptSkips -Receipt (New-Receipt) | Should -Be ''
    }

    It 'refuses a receipt taken against a dirty worktree even though it says pass' {
        $r = New-Receipt -Dirty $true -DirtyFiles @(' M scripts/run-ci-local.ps1')
        Get-CiReceiptRefusalReason -Receipt $r -HeadSha 'abc1234def567' |
            Should -BeLike '*DIRTY worktree*'
    }

    It 'accepts a clean receipt that explicitly records dirty=false' {
        $r = New-Receipt -Dirty $false
        Get-CiReceiptRefusalReason -Receipt $r -HeadSha 'abc1234def567' | Should -BeNullOrEmpty
    }

    It 'refuses a receipt that predates dirty-worktree tracking rather than assuming it was clean' {
        # Same "we cannot tell" reasoning task 023 applied to skip tracking, one field over.
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -LegacyDirty) -HeadSha 'abc1234def567' |
            Should -BeLike '*predates dirty-worktree tracking*'
    }

    It 'refuses a sha prefix shorter than the minimum length' {
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -Sha 'abc12') -HeadSha 'abc1234def567' |
            Should -BeLike '*shorter than the minimum*'
    }

    It 'accepts a sha prefix at exactly the minimum length' {
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -Sha 'abc1234') -HeadSha 'abc1234def567' |
            Should -BeNullOrEmpty
    }

    It 'honours a caller-supplied minimum length' {
        Get-CiReceiptRefusalReason -Receipt (New-Receipt -Sha 'abc1234') -HeadSha 'abc1234def567' -MinShaLength 10 |
            Should -BeLike '*shorter than the minimum 10-character prefix*'
    }
}

Describe 'ci step skip classification (Get-CiStepSkip)' {
    # ISSUE #72 HOLE 3b. run-ci-local.ps1's Step function used to check `$out -is [psobject]`
    # directly against a step body's raw output. That is correct for the ordinary case -- a step
    # that returns ONLY `Skip-Step '...'` -- and silently wrong the moment the body emits any
    # other pipeline output first, because PowerShell then hands back an ARRAY, and
    # `[object[]] -is [psobject]` is $false. A skipped step was recorded as an ordinary pass with
    # its Reason unread. Get-CiStepSkip is the extracted, testable classifier.

    BeforeAll {
        function New-SkipMarker { param([string]$Why = 'because') [pscustomobject]@{ ScStepSkipped = $true; Reason = $Why } }
    }

    It 'recognises a bare Skip-Step marker' {
        $r = Get-CiStepSkip -Out (New-SkipMarker -Why 'no tests/ directory')
        $r.IsSkip | Should -BeTrue
        $r.Reason | Should -Be 'no tests/ directory'
    }

    It 'recognises a Skip-Step marker that arrives as the LAST element of an array -- THE BUG' {
        # Reproduces a step body that writes output before returning Skip-Step, e.g.
        # `"some diagnostic line"; return Skip-Step 'no python'`. PowerShell collects both
        # into one System.Object[], which the old inline check could not see into.
        $out = @('some diagnostic line', (New-SkipMarker -Why 'no python'))
        $out.GetType().IsArray | Should -BeTrue   # sanity: this really is the array shape
        $r = Get-CiStepSkip -Out $out
        $r.IsSkip | Should -BeTrue
        $r.Reason | Should -Be 'no python'
    }

    It 'does not classify an ordinary scalar result as a skip' {
        $r = Get-CiStepSkip -Out '42 passed'
        $r.IsSkip | Should -BeFalse
        $r.Reason | Should -BeNullOrEmpty
    }

    It 'does not classify an ordinary array result (no marker anywhere) as a skip' {
        $r = Get-CiStepSkip -Out @('line one', 'line two')
        $r.IsSkip | Should -BeFalse
    }

    It 'does not classify a plain object that merely resembles one as a skip' {
        $r = Get-CiStepSkip -Out ([pscustomobject]@{ Name = 'not a skip marker' })
        $r.IsSkip | Should -BeFalse
    }

    It 'treats $null and an empty array as not-a-skip rather than throwing' {
        Get-CiStepSkip -Out $null | ForEach-Object { $_.IsSkip } | Should -BeFalse
        Get-CiStepSkip -Out @() | ForEach-Object { $_.IsSkip } | Should -BeFalse
    }
}
