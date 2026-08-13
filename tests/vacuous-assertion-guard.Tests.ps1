#Requires -Version 7
<#
Two vacuities a PARSER can find, so nobody has to. Task 055, issues #69 and #70.

Most of the checks-that-cannot-fail in this repo need a human to notice that two sets are
disjoint, or that a witness was never asserted. Two of them do not:

  1. A SELF-COMPARISON. `$x -eq $x`. test-upgrade-queue.ps1:554 carried the money claim
     as `$script:mineralsAfterFirst -eq $script:mineralsAfterFirst` and read green for
     three tasks (issue #69). Nothing about that needs judgement: the two operands are the
     same source text.

  2. A LITERAL `$true` HANDED TO AN ASSERTION. `Assert-That '...' $true` is a check that
     cannot fail by construction, and both times it appeared here it was standing in for a
     SKIP -- an arm that could not be measured, recorded as a pass (task 052 section 6.5).
     A skipped check is not a passed check; that rule has been in run-ci-local.ps1 since
     task 023 and the suites had not caught up. `$false` is deliberately NOT flagged: it is
     the correct way to record a definite failure in an else branch, and this file would be
     worth nothing if it pushed authors away from that.

Run against the tree as it stood before this task (3db4eef), the first scan finds
test-upgrade-queue.ps1:554 and the second finds test-production-queue.ps1:1392 -- the two
sites issue #69 and task 052 named by hand. That is the whole argument for having it: the
same two findings, for free, on every run, for every suite written afterwards.

WHAT IT DOES NOT CLAIM. It is a lint, not a proof. `$a.X -eq $b.X` where $a and $b are the
same object, a witness nobody asserted, two sets that cannot intersect -- none of those are
visible to a parser, and the rest of this task was fixing exactly those by hand. It catches
the cheapest tenth of the class, which is the tenth that should never have cost anybody a
review.
#>

BeforeAll {
    $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin')).Path

    # Every assertion helper in the suites. They are 25 separate copies of the same idea
    # (task 052 section 4.2), which is why this is a list rather than one name.
    $script:AssertNames = @('Assert-That', 'Assert-Feature', 'Assert-Inv', 'Assert-Every', 'Check')

    function Find-VacuousAssertion {
        param([Parameter(Mandatory)][string]$Root)

        $hits = @()
        foreach ($file in Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
            if ($errors.Count) { throw "guard could not parse $($file.Name): $($errors[0].Message)" }

            # 1. `$x <cmp> $x` -- identical source text on both sides of a comparison.
            $cmp = @('Ieq', 'Ine', 'Ige', 'Ile', 'Igt', 'Ilt', 'Ceq', 'Cne')
            foreach ($b in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)) {
                if ($b.Operator -notin $cmp) { continue }
                if ($b.Left.Extent.Text -ne $b.Right.Extent.Text) { continue }
                $hits += [pscustomobject]@{
                    Kind = 'self-comparison'; File = $file.Name
                    Line = $b.Extent.StartLineNumber; Text = ($b.Extent.Text -replace '\s+', ' ')
                }
            }

            # 2. a bare $true passed to an assertion helper.
            foreach ($c in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                if ($c.GetCommandName() -notin $script:AssertNames) { continue }
                foreach ($e in $c.CommandElements) {
                    if ($e -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                    if ($e.VariablePath.UserPath -ne 'true') { continue }
                    $t = ($c.Extent.Text -replace '\s+', ' ')
                    $hits += [pscustomobject]@{
                        Kind = 'literal-true'; File = $file.Name
                        Line = $c.Extent.StartLineNumber
                        Text = $t.Substring(0, [Math]::Min(120, $t.Length))
                    }
                }
            }
        }
        , $hits
    }
}

Describe 'No assertion in tools/plugin is vacuous by inspection (issues #69, #70)' {

    It 'POSITIVE CONTROL: both scans find a planted instance' {
        # Without this the guard could pass by finding nothing, forever, over any tree --
        # which is the exact failure mode it exists to catch, so it would be funny rather
        # than acceptable to skip it.
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("sc-vac-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            @'
function Test-Thing {
    Assert-That 'a real check' ($after -eq $before)
    Assert-That 'the tautology' ($mineralsAfter -eq $mineralsAfter)
    Assert-That 'the skip marker' $true "(not measured)"
    Assert-That 'a definite failure in an else branch' $false "(this is CORRECT and must not be flagged)"
}
'@ | Set-Content -LiteralPath (Join-Path $dir 'planted.ps1') -NoNewline

            $found = Find-VacuousAssertion -Root $dir
            @($found | Where-Object { $_.Kind -eq 'self-comparison' }).Count | Should -Be 1
            @($found | Where-Object { $_.Kind -eq 'literal-true' }).Count | Should -Be 1
            @($found | Where-Object { $_.Text -match 'else branch' }).Count |
                Should -Be 0 -Because '$false records a definite failure and is not vacuous'
        }
        finally { Remove-Item $dir -Recurse -Force }
    }

    It 'tools/plugin has no self-comparison and no literal-true assertion' {
        $found = Find-VacuousAssertion -Root $script:PluginRoot
        $report = ($found | ForEach-Object { "  [$($_.Kind)] $($_.File):$($_.Line)  $($_.Text)" }) -join "`n"
        $found.Count | Should -Be 0 -Because @"
these assertions cannot fail as written:
$report
A self-comparison needs a second, independently sourced reading on one side.
A literal `$true` handed to an assertion is a SKIP -- record it as one, and print the
skip count beside the verdict, so it is not counted as a check that passed.
"@
    }
}
