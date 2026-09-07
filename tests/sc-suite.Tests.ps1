#Requires -Version 7
<#
Pester cases for tools/plugin/sc-suite.ps1.

WHY THESE EXIST. `Assert-That` and `Step` were inlined 26 and 23 times because they are
four lines each; sharing them is only safe because of one thing that is easy to get wrong
and impossible to see by reading a suite: `$script:failures` and `$script:step` inside
them must resolve to the SUITE'S counters, not to sc-suite.ps1's. That works because a
suite DOT-SOURCES the file, so the functions are defined in the suite's own scope.

If someone ever changes a suite to `& (Join-Path ... 'sc-suite.ps1')`, every FAIL stops
counting and the suite exits 0 with failures on screen -- the exact shape of defect this
repo's oracle-guard rules exist for. So the cases below drive a FAKE suite file from disk
and read its counters back, and the last one watches the `&` form fail to do so.
#>

BeforeAll {
    $script:suiteLib = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'sc-suite.ps1')).Path

    # A throwaway "suite": dot-sources the library, runs a few assertions, and reports
    # what its own counters ended on.
    function New-FakeSuite {
        param([string]$Loader = '.')
        $path = Join-Path ([IO.Path]::GetTempPath()) "scsuite-$([guid]::NewGuid().ToString('N')).ps1"
        @"
`$ErrorActionPreference = 'Stop'
$Loader ('$($script:suiteLib -replace "'", "''")')
`$failures = 0
`$step = 0
Step 'first step' { Assert-That 'a true thing' `$true }
Step 'second step' { Assert-That 'a false thing' `$false '(expected 1, got 2)' }
Step 'third step' { Assert-That 'another false thing' `$false }
"@ | Set-Content -LiteralPath $path -Encoding utf8
        $path
    }

    function Invoke-FakeSuite {
        param([string]$Path)
        $out = & pwsh -NoProfile -NonInteractive -File $Path 2>&1 | Out-String
        $out
    }
}

Describe 'sc-suite.ps1 counts the SUITE''s failures, not its own' {

    BeforeAll {
        $script:dotted = New-FakeSuite -Loader '.'
        $script:dottedOut = Invoke-FakeSuite -Path $script:dotted
    }

    AfterAll {
        Remove-Item -LiteralPath $script:dotted -ErrorAction SilentlyContinue
    }

    It 'numbers the steps from the suite''s own $step' {
        $script:dottedOut | Should -Match '\[1\] first step'
        $script:dottedOut | Should -Match '\[2\] second step'
        $script:dottedOut | Should -Match '\[3\] third step'
    }

    It 'prints a passing assertion as ok, with no detail' {
        $script:dottedOut | Should -Match '  ok   a true thing'
    }

    It 'prints a failing assertion as FAIL, WITH its detail' {
        $script:dottedOut | Should -Match '  FAIL a false thing \(expected 1, got 2\)'
    }

    It 'increments the SUITE''s $failures -- the whole reason this is dot-sourced' {
        # The fake suite prints nothing itself, so read the counter out of the library's
        # own effect: two FAIL lines must have moved a counter the suite owns. Drive it
        # again with a suite that reports the number.
        $p = Join-Path ([IO.Path]::GetTempPath()) "scsuite-$([guid]::NewGuid().ToString('N')).ps1"
        @"
. ('$($script:suiteLib -replace "'", "''")')
`$failures = 0
`$step = 0
Assert-That 'one' `$false
Assert-That 'two' `$false
Assert-That 'three' `$true
Write-Host "COUNTED=`$failures"
"@ | Set-Content -LiteralPath $p -Encoding utf8
        $out = & pwsh -NoProfile -NonInteractive -File $p 2>&1 | Out-String
        Remove-Item -LiteralPath $p -ErrorAction SilentlyContinue
        $out | Should -Match 'COUNTED=2'
    }
}

Describe 'the negative control: running it with & instead of . loses the count' {

    It 'does NOT reach the suite''s counter, which is why every suite dot-sources it' {
        $p = Join-Path ([IO.Path]::GetTempPath()) "scsuite-$([guid]::NewGuid().ToString('N')).ps1"
        @"
. ('$($script:suiteLib -replace "'", "''")')
`$failures = 0
Assert-That 'one' `$false
Write-Host "DOTTED=`$failures"
"@ | Set-Content -LiteralPath $p -Encoding utf8
        $dotted = & pwsh -NoProfile -NonInteractive -File $p 2>&1 | Out-String

        @"
& ('$($script:suiteLib -replace "'", "''")')
`$failures = 0
if (Get-Command Assert-That -ErrorAction SilentlyContinue) {
    Assert-That 'one' `$false
    Write-Host "AMPED=`$failures"
} else {
    Write-Host 'AMPED=no-function'
}
"@ | Set-Content -LiteralPath $p -Encoding utf8
        $amped = & pwsh -NoProfile -NonInteractive -File $p 2>&1 | Out-String
        Remove-Item -LiteralPath $p -ErrorAction SilentlyContinue

        $dotted | Should -Match 'DOTTED=1'
        $amped  | Should -Not -Match 'AMPED=1'
    }
}

Describe 'every suite that uses the primitives loads them the right way' {

    It 'no .ps1 under tools/plugin calls Assert-That or Step without defining or sourcing them' {
        $dir = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin')).Path
        $bad = @()
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.ps1 -File) {
            if ($f.Name -eq 'sc-suite.ps1') { continue }
            $t = Get-Content -Raw -LiteralPath $f.FullName
            $uses = $t -match '(?m)^\s*(Assert-That|Step)\s'
            if (-not $uses) { continue }
            $has = ($t -match "sc-suite\.ps1") -or ($t -match '(?m)^function\s+(Assert-That|Step)\s')
            if (-not $has) { $bad += $f.Name }
        }
        $bad -join ', ' | Should -BeExactly ''
    }
}

Describe 'Write-ScStepFailure prints the caller''s noun and counts the throw' {

    It 'reports the message, the stack trace, and moves the suite''s counter' {
        $p = Join-Path ([IO.Path]::GetTempPath()) "scsuite-$([guid]::NewGuid().ToString('N')).ps1"
        @"
. ('$($script:suiteLib -replace "'", "''")')
`$failures = 0
try { throw 'a planted explosion' } catch { Write-ScStepFailure `$_ 'a test step' }
Write-Host "COUNTED=`$failures"
"@ | Set-Content -LiteralPath $p -Encoding utf8
        $out = & pwsh -NoProfile -NonInteractive -File $p 2>&1 | Out-String
        Remove-Item -LiteralPath $p -ErrorAction SilentlyContinue
        $out | Should -Match '  FAIL a test step threw: a planted explosion'
        $out | Should -Match 'COUNTED=1'
        # the stack trace line is what makes a thrown failure actionable
        ($out -split "`n" | Where-Object { $_ -match '^\s{7}\S' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'a suite that keeps its OWN Step defines it after the dot-source' {

    It 'so the library cannot silently override the two that are different' {
        # test-production-queue.ps1 keeps a Step with -SweepPerturbed (task 041). If the
        # dot-source ever moves below that definition, the library's plain Step wins and
        # every -HoldSweepClicks run starts asserting on perturbed state without saying so.
        $dir = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin')).Path
        $bad = @()
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.ps1 -File) {
            if ($f.Name -eq 'sc-suite.ps1') { continue }
            $lines = Get-Content -LiteralPath $f.FullName
            $src = ($lines | Select-String -Pattern 'sc-suite\.ps1' | Select-Object -First 1).LineNumber
            if (-not $src) { continue }
            foreach ($fn in 'Step', 'Assert-That') {
                $own = ($lines | Select-String -Pattern "^function\s+$fn\b" | Select-Object -First 1).LineNumber
                if ($own -and $own -lt $src) { $bad += "$($f.Name): $fn at $own, dot-source at $src" }
            }
        }
        $bad -join '; ' | Should -BeExactly ''
    }
}

