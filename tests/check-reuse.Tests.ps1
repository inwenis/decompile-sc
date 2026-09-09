#Requires -Version 7
<#
Pester cases for tools/check-reuse.py.
The gate's whole value is that it FAILS on a new copy, and a gate that cannot fail is
the house defect this repo guards against (tests/vacuous-assertion-guard.Tests.ps1), so
the cases plant a duplicate in a throwaway tree and require exit 1, then remove it and
require exit 0 -- once for the C++ target and once for the PowerShell one. A copy that
is re-indented and re-commented must still fail: that is what the token scan buys over
a line scan. The last case runs the gate over the real tree, as CI does.
#>

# Pester v5 evaluates -Skip while it is DISCOVERING, so a $script: variable set in
# BeforeAll is still $null there and every case would skip.
$script:HasTools = ($null -ne (Get-Command python -ErrorAction SilentlyContinue)) -and
                   ($null -ne (Get-Command npx -ErrorAction SilentlyContinue))

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:checker  = Join-Path $script:repoRoot 'tools/check-reuse.py'

    # The layout the checker expects, so a planted duplicate never touches real sources.
    function New-ReuseSandbox {
        $root = Join-Path ([IO.Path]::GetTempPath()) "reuse-$([guid]::NewGuid().ToString('N'))"
        $src = Join-Path $root 'tools/plugin/src'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Copy-Item -LiteralPath $script:checker -Destination (Join-Path $root 'tools')
        @{ Root = $root; Src = $src; Suites = (Join-Path $root 'tools/plugin') }
    }

    function Invoke-Checker {
        param([string]$Root, [string[]]$CheckerArgs = @())
        Push-Location $Root
        try {
            $out = & python 'tools/check-reuse.py' @CheckerArgs 2>&1 | Out-String
            [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
        } finally { Pop-Location }
    }

    # Seven lines, two over MIN_LINES, so it is a finding wherever it lands.
    $script:dupBody = @'
static int Twin(int a, int b) {
    int total = 0;
    for (int i = a; i < b; ++i) {
        total += i * 3;
    }
    return total;
}
'@

    # The same tokens, laid out and commented differently.
    $script:dupBodyReformatted = @'
static int Twin(int a,
                int b)
{
  /* summing helper */
  int total = 0;
  for (int i = a; i < b; ++i)
  {
      total += i * 3;   // triple
  }
  return total;
}
'@

    $script:dupSuite = @'
function Get-Twin {
    param([int]$A, [int]$B)
    $total = 0
    for ($i = $A; $i -lt $B; $i++) {
        $total += $i * 3
    }
    Write-Host "twin $total"
    $total
}
'@

    $script:dupSuiteReformatted = @'
function Get-Twin
{
  # summing helper
  param([int]$A,
        [int]$B)

  $total = 0
  for ($i = $A; $i -lt $B; $i++)
  {
      $total += $i * 3   # triple
  }
  Write-Host "twin $total"
  $total
}
'@
}

Describe 'check-reuse [cpp] fails on a NEW copy and passes without one' -Skip:(-not $script:HasTools) {

    BeforeAll {
        $script:box = New-ReuseSandbox
        Set-Content -LiteralPath (Join-Path $script:box.Src 'sc_alpha.cpp') -Value $script:dupBody
    }

    AfterAll {
        if ($script:box) {
            Remove-Item -LiteralPath $script:box.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is quiet when nothing is duplicated' {
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 0 -Because $r.Out
    }

    It 'FAILS once the same block exists in a second file' {
        Set-Content -LiteralPath (Join-Path $script:box.Src 'sc_beta.cpp') -Value $script:dupBody
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match '\[cpp\]: NEW block'
        $r.Out | Should -Match 'sc_alpha.cpp'
        $r.Out | Should -Match 'sc_beta.cpp'
    }

    It 'reports the copy ONCE, at its full length, not as overlapping windows' {
        $r = Invoke-Checker -Root $script:box.Root -CheckerArgs @('--list')
        @($r.Out -split "`n" | Where-Object { $_ -match '^block' }).Count | Should -Be 1
        $r.Out | Should -Match '7 identical lines'
    }

    It 'still FAILS when the copy is re-indented and re-commented' {
        Set-Content -LiteralPath (Join-Path $script:box.Src 'sc_beta.cpp') -Value $script:dupBodyReformatted
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match '\[cpp\]: NEW block'
        $r.Out | Should -Match 'sc_beta.cpp'
    }

    It 'accepts the copy once it is in the baseline, and says so' {
        (Invoke-Checker -Root $script:box.Root -CheckerArgs @('--update-baseline')).Exit | Should -Be 0
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match '\[cpp\]: \d+ finding\(s\), all in the baseline'
    }

    It 'notices when a baselined copy is finally removed' {
        Remove-Item -LiteralPath (Join-Path $script:box.Src 'sc_beta.cpp')
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'no longer found'
    }

    It 'does not call an address quoted in a log line a bare VA' {
        Set-Content -LiteralPath (Join-Path $script:box.Src 'sc_gamma.cpp') `
            -Value 'void L(void) { ScLog("the frame hook at 0x0041E280 went in"); }'
        $r = Invoke-Checker -Root $script:box.Root -CheckerArgs @('--list')
        $r.Out | Should -Not -Match '0x0041E280'
    }

    It 'DOES call one dereferenced in code a bare VA' {
        Set-Content -LiteralPath (Join-Path $script:box.Src 'sc_gamma.cpp') `
            -Value 'void U(void) { *(int*)0x0041E280 = 1; }'
        $r = Invoke-Checker -Root $script:box.Root -CheckerArgs @('--list')
        $r.Out | Should -Match 'bare engine address 0x0041E280'
    }
}

Describe 'check-reuse [ps1] polices the suites the same way' -Skip:(-not $script:HasTools) {

    BeforeAll {
        $script:box = New-ReuseSandbox
        Set-Content -LiteralPath (Join-Path $script:box.Suites 'suite-alpha.ps1') -Value $script:dupSuite
    }

    AfterAll {
        if ($script:box) {
            Remove-Item -LiteralPath $script:box.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is quiet when nothing is duplicated' {
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 0 -Because $r.Out
    }

    It 'FAILS once the same block exists in a second suite' {
        Set-Content -LiteralPath (Join-Path $script:box.Suites 'suite-beta.ps1') -Value $script:dupSuite
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match '\[ps1\]: NEW block'
        $r.Out | Should -Match 'suite-alpha.ps1'
        $r.Out | Should -Match 'suite-beta.ps1'
    }

    It 'still FAILS when the copy is re-indented and re-commented' {
        Set-Content -LiteralPath (Join-Path $script:box.Suites 'suite-beta.ps1') -Value $script:dupSuiteReformatted
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 1 -Because $r.Out
        $r.Out | Should -Match '\[ps1\]: NEW block'
        $r.Out | Should -Match 'suite-beta.ps1'
    }

    It 'ignores the same text inside a block comment or behind a comment marker' {
        $commented = ($script:dupSuite -split "`n" | ForEach-Object { "# $_" }) -join "`n"
        Set-Content -LiteralPath (Join-Path $script:box.Suites 'suite-gamma.ps1') -Value $commented
        Set-Content -LiteralPath (Join-Path $script:box.Suites 'suite-delta.ps1') `
            -Value ("<#`n" + $script:dupSuite + "`n#>")
        $r = Invoke-Checker -Root $script:box.Root -CheckerArgs @('--list')
        $r.Out | Should -Not -Match 'suite-gamma'
        $r.Out | Should -Not -Match 'suite-delta'
    }

    It 'keeps its baseline in its own file' {
        (Invoke-Checker -Root $script:box.Root -CheckerArgs @('--update-baseline')).Exit | Should -Be 0
        Get-Content -LiteralPath (Join-Path $script:box.Root 'tools/check-reuse.ps1.baseline') -Raw |
            Should -Match '(?m)^block [0-9a-f]{16}' -Because 'the ps1 copy belongs in the ps1 baseline'
        Get-Content -LiteralPath (Join-Path $script:box.Root 'tools/check-reuse.cpp.baseline') -Raw |
            Should -Not -Match '(?m)^block' -Because 'nothing in this sandbox is C++'
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 0 -Because $r.Out
    }
}

Describe 'the real tree is at or under its baselines' -Skip:(-not $script:HasTools) {

    It 'has no duplication outside tools/check-reuse.*.baseline, in either target' {
        $r = Invoke-Checker -Root $script:repoRoot
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match '\[cpp\]: \d+ finding\(s\), all in the baseline'
        $r.Out | Should -Match '\[ps1\]: \d+ finding\(s\), all in the baseline'
    }
}
