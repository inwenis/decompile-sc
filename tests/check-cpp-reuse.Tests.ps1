#Requires -Version 7
<#
Pester cases for tools/check-cpp-reuse.py.
The gate's whole value is that it FAILS on a new copy, and a gate that cannot fail is
the house defect this repo guards against (tests/vacuous-assertion-guard.Tests.ps1), so
the cases plant a duplicate in a throwaway tree and require exit 1, then remove it and
require exit 0. The last case runs the gate over the real tools/plugin/src, as CI does.
#>

# Pester v5 evaluates -Skip while it is DISCOVERING, so a $script: variable set in
# BeforeAll is still $null there and every case would skip.
$script:HasPython = $null -ne (Get-Command python -ErrorAction SilentlyContinue)

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:checker  = Join-Path $script:repoRoot 'tools/check-cpp-reuse.py'

    # The layout the checker expects, so a planted duplicate never touches real sources.
    function New-ReuseSandbox {
        $root = Join-Path ([IO.Path]::GetTempPath()) "cppreuse-$([guid]::NewGuid().ToString('N'))"
        $src = Join-Path $root 'tools/plugin/src'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Copy-Item -LiteralPath $script:checker -Destination (Join-Path $root 'tools')
        @{ Root = $root; Src = $src }
    }

    function Invoke-Checker {
        param([string]$Root, [string[]]$CheckerArgs = @())
        Push-Location $Root
        try {
            $out = & python 'tools/check-cpp-reuse.py' @CheckerArgs 2>&1 | Out-String
            [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
        } finally { Pop-Location }
    }

    # Seven lines, two over MIN_BLOCK, so it is a finding wherever it lands.
    $script:dupBody = @'
static int Twin(int a, int b) {
    int total = 0;
    for (int i = a; i < b; ++i) {
        total += i * 3;
    }
    return total;
}
'@
}

Describe 'check-cpp-reuse fails on a NEW copy and passes without one' -Skip:(-not $script:HasPython) {

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
        $r.Out | Should -Match 'NEW block'
        $r.Out | Should -Match 'sc_alpha.cpp'
        $r.Out | Should -Match 'sc_beta.cpp'
    }

    It 'reports the copy ONCE, at its full length, not as overlapping windows' {
        $r = Invoke-Checker -Root $script:box.Root -CheckerArgs @('--list')
        @($r.Out -split "`n" | Where-Object { $_ -match '^block' }).Count | Should -Be 1
        $r.Out | Should -Match '7 identical lines'
    }

    It 'accepts the copy once it is in the baseline, and says so' {
        (Invoke-Checker -Root $script:box.Root -CheckerArgs @('--update-baseline')).Exit | Should -Be 0
        $r = Invoke-Checker -Root $script:box.Root
        $r.Exit | Should -Be 0 -Because $r.Out
        $r.Out | Should -Match 'all in the baseline'
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

Describe 'the real tools/plugin/src is at or under its baseline' -Skip:(-not $script:HasPython) {

    It 'has no duplication outside tools/check-cpp-reuse.baseline' {
        $r = Invoke-Checker -Root $script:repoRoot
        $r.Exit | Should -Be 0 -Because $r.Out
    }
}
