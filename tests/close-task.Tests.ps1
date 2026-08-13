#Requires -Version 7
<#
Pester cases for scripts/lib/close-task.ps1's close gate (task 069, issue #96).

WHY THESE EXIST. board-lint class 2 flags a finished report-only task ("no PR, no
stamp, but a report exists") while close-task refused to stamp it, claiming it was
"already completed by the status mapping" -- false: completion derives ONLY from the
merged: stamp (scripts/lib/derived-status.ps1), so 044/049/052 sat lint-red forever
with the two scripts disagreeing about what "done" means. The gate now accepts a
no-PR task WITH a report (the report is the deliverable) and still refuses one with
nothing delivered. The report-only cases fail against the pre-069 gate by
construction.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../scripts/lib/close-task.ps1')
    . (Join-Path $PSScriptRoot '../scripts/lib/derived-status.ps1')
    . (Join-Path $PSScriptRoot '../scripts/lib/board-lint.ps1')
}

Describe 'Get-CloseRefusalReason' {

    It 'allows closing a no-PR task that delivered a report (the board-lint class 2 remedy)' {
        Get-CloseRefusalReason -PrNumber $null -PrState $null -ReportExists $true |
            Should -BeNullOrEmpty
    }

    It 'refuses a no-PR task with NO report -- nothing was delivered' {
        $r = Get-CloseRefusalReason -PrNumber $null -PrState $null -ReportExists $false
        $r | Should -Match 'no report'
        $r | Should -Match 'nothing was delivered'
        # And it no longer asserts the false "already completed" claim.
        $r | Should -Not -Match 'already completed'
    }

    It 'still refuses an unmerged PR regardless of any report' {
        Get-CloseRefusalReason -PrNumber '12' -PrState 'OPEN' -ReportExists $true |
            Should -Match 'not MERGED'
    }

    It 'still allows a merged PR' {
        Get-CloseRefusalReason -PrNumber '12' -PrState 'MERGED' -ReportExists $false |
            Should -BeNullOrEmpty
    }
}

Describe 'the report-only stamp is a real completion observable' {

    It 'produces a merged: line that Test-HasMergedStamp accepts and the status derivation completes on' {
        $content = "# Task 049 - x`r`n`r`nagent: 049`r`npr: -`r`n"
        $stamped = Add-MergedStamp -Content $content -Date '2026-08-13 (report-only; no PR)'
        $stamped | Should -Match '(?m)^merged: 2026-08-13 \(report-only; no PR\)'
        Test-HasMergedStamp -Content $stamped | Should -BeTrue
        # The board's own rule table: a stamp value means completed.
        Get-DerivedTaskStatus -MergedStamp '2026-08-13' | Should -Be 'completed'
    }

    It 'clears the board-lint class 2 finding that demanded it' {
        $before = "# Task 049 - x`r`n`r`nagent: 049`r`npr: -`r`n"
        (Get-Class2Finding -Task '049' -Content $before -ReportExists $true) | Should -Not -BeNullOrEmpty
        $after = Add-MergedStamp -Content $before -Date '2026-08-13 (report-only; no PR)'
        (Get-Class2Finding -Task '049' -Content $after -ReportExists $true) | Should -BeNullOrEmpty
    }

    It 'names close-task as the remedy in the class 2 evidence, so the lint asks for an action that exists' {
        $f = Get-Class2Finding -Task '049' -Content "pr: -`r`n" -ReportExists $true
        $f.Evidence | Should -Match 'close-task\.ps1 -Task 049'
    }
}

Describe 'New-CloseCommitMessage' {

    It 'keeps the PR close subject' {
        New-CloseCommitMessage -Task '34' -PrNumber '12' |
            Should -Be 'chore(tasks): close task 034 (PR #12 merged)'
    }

    It 'spells out the report-only close instead of claiming a merge' {
        New-CloseCommitMessage -Task '49' -PrNumber $null |
            Should -Be 'chore(tasks): close task 049 (report-only; no PR)'
    }
}
