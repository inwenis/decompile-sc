#Requires -Version 7
<#
Two vacuities a PARSER can find, so nobody has to; the rest of the class needs a human.
  1. SELF-COMPARISON. `$x -eq $x` -- the same source text on both sides. A money claim
     written that way reads green forever, and spotting it needs no judgement.
  2. A LITERAL `$true` HANDED TO AN ASSERTION. Cannot fail by construction, and it stands
     in for a SKIP: an arm that could not be measured, recorded as a pass. A skipped check
     is not a passed check.  -> AGENTS.md § "Oracles: what counts as a read-back"

`$false` is deliberately NOT flagged: it is the correct way to record a definite failure in
an else branch, and this file would be worth nothing if it pushed authors away from that.

A lint, not a proof. `$a.X -eq $b.X` over one object, a witness nobody asserted, two sets
that cannot intersect are invisible to a parser and still cost a human a review.
#>

BeforeAll {
    $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin')).Path

    # The suites carry 25 separate copies of the same assertion idea under different names,
    # so the guard has to match a list rather than one name.
    $script:AssertNames = @('Assert-That', 'Assert-Feature', 'Assert-Inv', 'Assert-Every', 'Check')

    function Find-VacuousAssertion {
        param([Parameter(Mandatory)][string]$Root)

        $hits = @()
        foreach ($file in Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
            if ($errors.Count) { throw "guard could not parse $($file.Name): $($errors[0].Message)" }

            $cmp = @('Ieq', 'Ine', 'Ige', 'Ile', 'Igt', 'Ilt', 'Ceq', 'Cne')
            foreach ($b in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)) {
                if ($b.Operator -notin $cmp) { continue }
                if ($b.Left.Extent.Text -ne $b.Right.Extent.Text) { continue }
                $hits += [pscustomobject]@{
                    Kind = 'self-comparison'; File = $file.Name
                    Line = $b.Extent.StartLineNumber; Text = ($b.Extent.Text -replace '\s+', ' ')
                }
            }

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
        # Without a planted instance the guard passes by finding nothing, over any tree --
        # the exact failure mode it exists to catch.
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
