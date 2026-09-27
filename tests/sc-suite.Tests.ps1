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
and read its counters back, and the negative control watches the `&` form fail to do so.
#>

BeforeAll {
    $script:suiteLib = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'sc-suite.ps1')).Path

    # A throwaway "suite" run in its own pwsh: loads the library with $Loader, runs $Body,
    # and returns everything it printed. The counters are the library's to zero.
    function Invoke-LibScript {
        param([string]$Body, [string]$Loader = '.')
        $p = Join-Path $TestDrive "$(New-Guid).ps1"
        "$Loader ('$($script:suiteLib -replace "'", "''")')`n$Body" |
            Set-Content -LiteralPath $p -Encoding utf8
        & pwsh -NoProfile -NonInteractive -File $p 2>&1 | Out-String
    }
}

Describe 'sc-suite.ps1 counts the SUITE''s failures, not its own' {

    BeforeAll {
        $script:dottedOut = Invoke-LibScript @'
$ErrorActionPreference = 'Stop'
Step 'first step' { Assert-That 'a true thing' $true }
Step 'second step' { Assert-That 'a false thing' $false '(expected 1, got 2)' }
Step 'third step' { Assert-That 'another false thing' $false }
'@
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
        $out = Invoke-LibScript @'
Assert-That 'one' $false
Assert-That 'two' $false
Assert-That 'three' $true
Write-Host "COUNTED=$failures"
'@
        $out | Should -Match 'COUNTED=2'
    }
}

Describe 'sc-suite.ps1 is the whole prelude a suite needs' {

    It 'loads drive-game, the launch lock and the oracle guard, and sets $repoRoot, into the suite' {
        $out = Invoke-LibScript @'
foreach ($fn in 'Send-ScClick', 'Enter-ScLaunchLock', 'Test-ScReached') {
    Write-Host "$fn=$([bool](Get-Command $fn -ErrorAction SilentlyContinue))"
}
Write-Host "REPO=$repoRoot"
'@
        $out | Should -Match 'Send-ScClick=True'
        $out | Should -Match 'Enter-ScLaunchLock=True'
        $out | Should -Match 'Test-ScReached=True'
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $out | Should -Match ('(?m)^REPO=' + [regex]::Escape($repo) + '\r?$')
    }
}

Describe 'the negative control: running it with & instead of . loses the count' {

    It 'does NOT reach the suite''s counter, which is why every suite dot-sources it' {
        $dotted = Invoke-LibScript @'
Assert-That 'one' $false
Write-Host "DOTTED=$failures"
'@
        $amped = Invoke-LibScript -Loader '&' @'
if (Get-Command Assert-That -ErrorAction SilentlyContinue) {
    Assert-That 'one' $false
    Write-Host "AMPED=$failures"
} else {
    Write-Host 'AMPED=no-function'
}
'@
        $dotted | Should -Match 'DOTTED=1'
        $amped  | Should -Not -Match 'AMPED=1'
        # A crashed script also lacks AMPED=1: require the & branch to have run.
        $amped  | Should -Match 'AMPED=no-function'
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
        $out = Invoke-LibScript @'
try { throw 'a planted explosion' } catch { Write-ScStepFailure $_ 'a test step' }
Write-Host "COUNTED=$failures"
'@
        $out | Should -Match '  FAIL a test step threw: a planted explosion'
        $out | Should -Match 'COUNTED=1'
        # the stack trace line is what makes a thrown failure actionable
        ($out -split "`n" | Where-Object { $_ -match '^\s{7}\S' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Assert-ScExePristine and Assert-ScExeUnchanged hash StarCraft.exe against the pin' {

    BeforeAll {
        $script:gameDir = Join-Path $TestDrive 'game'
        New-Item -ItemType Directory -Path $script:gameDir | Out-Null
        Set-Content -LiteralPath (Join-Path $script:gameDir 'StarCraft.exe') -Value 'not the real exe'
        $script:fakeHash = (Get-FileHash -LiteralPath (Join-Path $script:gameDir 'StarCraft.exe') -Algorithm SHA256).Hash
    }

    It 'FAILs a working copy that is not pristine, and returns its hash as one string' {
        $out = Invoke-LibScript @"
`$h = Assert-ScExePristine -GameDir '$($script:gameDir)' -Label 'arm=x  '
Write-Host "COUNTED=`$failures TYPE=`$(`$h.GetType().Name) HASH=`$h"
"@
        $out | Should -Match '\[0\] arm=x  StarCraft\.exe SHA-256 before: '
        $out | Should -Match '  FAIL the working copy starts out byte-identical to pristine 1\.16\.1 \(got '
        $out | Should -Match "COUNTED=1 TYPE=String HASH=$($script:fakeHash)"
    }

    It 'passes a copy that matches the pin, and fails each after-run comparison on its own' {
        $out = Invoke-LibScript @"
`$ScPristineExeSha256 = '$($script:fakeHash)'
`$h = Assert-ScExePristine -GameDir '$($script:gameDir)'
Assert-ScExeUnchanged -GameDir '$($script:gameDir)' -Before `$h
Write-Host "CLEAN=`$failures"
Assert-ScExeUnchanged -GameDir '$($script:gameDir)' -Before 'SOMETHING ELSE'
Write-Host "CHANGED=`$failures"
`$ScPristineExeSha256 = 'SOMETHING ELSE'
Assert-ScExeUnchanged -GameDir '$($script:gameDir)' -Before `$h
Write-Host "NOT-PRISTINE=`$failures"
"@
        $out | Should -Match 'CLEAN=0'
        $out | Should -Match '  FAIL StarCraft\.exe on disk is byte-identical to before the run'
        $out | Should -Match 'CHANGED=1'
        $out | Should -Match '  FAIL and still byte-identical to pristine 1\.16\.1'
        $out | Should -Match 'NOT-PRISTINE=2'
    }
}

Describe 'Assert-ScAllOneType wants ONE bucket, of the expected type' {

    It 'passes a pure State and FAILs a mixed one' {
        $out = Invoke-LibScript @'
Assert-ScAllOneType 'pure' @{ Types = @{ '0x67' = 3 }; Live = 3; TypesText = '0x67:3' } '0x67'
Assert-ScAllOneType 'mixed' @{ Types = @{ '0x67' = 3; '0x40' = 1 }; Live = 4; TypesText = '0x67:3 0x40:1' } '0x67'
Write-Host "COUNTED=$failures"
'@
        $out | Should -Match '  ok   pure: all 3 units are 0x67'
        $out | Should -Match '  FAIL mixed: all 4 units are 0x67 \(got 0x67:3 0x40:1\)'
        $out | Should -Match 'COUNTED=1'
    }
}

Describe 'Assert-ScStockArm proves each absence pattern positive before requiring it absent' {

    BeforeAll {
        $script:pluginLog = Join-Path $TestDrive 'plugin.log'
        $script:stockLog = Join-Path $TestDrive 'stock.log'
        $script:leakyLog = Join-Path $TestDrive 'leaky.log'
        $script:emptyLog = Join-Path $TestDrive 'empty.log'
        Set-Content -LiteralPath $script:pluginLog -Value 'HOOK btnTrain: installed at 0x1', 'CMD id=0x14', 'FANOUT start units=36'
        Set-Content -LiteralPath $script:stockLog -Value 'mode=observe', 'WORLD [0]'
        Set-Content -LiteralPath $script:leakyLog -Value 'mode=observe', 'WORLD [0]', 'CMD id=0x14'
        New-Item -ItemType File -Path $script:emptyLog | Out-Null
    }

    It 'counts nothing for a clean pair, the leak for a stock log with a command, and every probe for an empty plugin log' {
        $out = Invoke-LibScript @"
Assert-ScStockArm -PluginLogPath '$($script:pluginLog)' -StockLogPath '$($script:stockLog)'
Write-Host "CLEAN=`$failures"
`$failures = 0
Assert-ScStockArm -PluginLogPath '$($script:pluginLog)' -StockLogPath '$($script:leakyLog)'
Write-Host "LEAKY=`$failures"
`$failures = 0
Assert-ScStockArm -PluginLogPath '$($script:emptyLog)' -StockLogPath '$($script:stockLog)'
Write-Host "EMPTY=`$failures"
"@
        $out | Should -Match 'CLEAN=0'
        $out | Should -Match '  FAIL the stock arm shows no an intercepted command'
        $out | Should -Match 'LEAKY=1'
        $out | Should -Match '  FAIL the plugin arm DOES show a fan-out'
        $out | Should -Match 'EMPTY=3'
    }
}

Describe 'Stop-ScSuiteGame closes by pid, FAILs a run that never had one, and cleans only what it declared' {

    It 'FAILs once when no pid was ever parsed, and not at all under -KeepOpen' {
        $out = Invoke-LibScript @'
Stop-ScSuiteGame -GamePid 0
Write-Host "NOPID=$failures"
Stop-ScSuiteGame -GamePid 0 -KeepOpen
Write-Host "KEPT=$failures"
'@
        ([regex]::Matches($out, '  FAIL no pid was ever parsed, so nothing could be closed')).Count | Should -Be 1
        $out | Should -Match 'NOPID=1'
        $out | Should -Match 'KEPT=1'
    }

    It 'runs close-game.ps1 from its own folder, by pid' {
        # Windows pids are multiples of 4, so this one can never name a real process.
        $out = Invoke-LibScript @'
Stop-ScSuiteGame -GamePid 2147483647
Write-Host "COUNTED=$failures"
'@
        $out | Should -Match 'close-game: pid 2147483647 is not running'
        $out | Should -Match 'COUNTED=0'
    }

    It 'removes the declared fixture and keeps a foreign file, its folder, and everything under -KeepOpen' {
        $shared = Join-Path $TestDrive 'shared'; $own = Join-Path $TestDrive 'own'; $kept = Join-Path $TestDrive 'kept'
        foreach ($d in $shared, $own, $kept) { New-Item -ItemType Directory -Path $d | Out-Null; Set-Content (Join-Path $d 'mine.scx') 'x' }
        Set-Content (Join-Path $shared 'theirs.scx') 'x'
        Invoke-LibScript @"
foreach (`$d in '$shared', '$own') { Stop-ScSuiteGame -GamePid 0 -Fixtures (New-ScFixtureRun -Dir `$d -Names 'mine.scx') }
Stop-ScSuiteGame -GamePid 0 -KeepOpen -Fixtures (New-ScFixtureRun -Dir '$kept' -Names 'mine.scx')
"@ | Out-Null
        Join-Path $shared 'mine.scx' | Should -Not -Exist
        Join-Path $shared 'theirs.scx' | Should -Exist
        $own | Should -Not -Exist
        Join-Path $kept 'mine.scx' | Should -Exist
    }
}

Describe 'Assert-ScFanoutPolicy FAILs a fanned-out id outside the policy set' {

    It 'passes an allowed id, returns the ids, and counts a stray one' {
        $ok = Join-Path $TestDrive 'ok.log'; $bad = Join-Path $TestDrive 'bad.log'
        $line = 'FANOUT start: cmd=0x{0} len=2 units=20 (visible 12 + overflow 8) '
        Set-Content -LiteralPath $ok -Value ($line -f '2C'), ($line -f '2C'), 'CMD id=0x13'
        Set-Content -LiteralPath $bad -Value ($line -f '2C'), ($line -f '13')
        $out = Invoke-LibScript @"
`$ids = Assert-ScFanoutPolicy -LogPath '$ok'
Write-Host "OK=`$failures IDS=`$(`$ids -join ',')"
`$null = Assert-ScFanoutPolicy -LogPath '$bad'
Write-Host "BAD=`$failures"
"@
        $out | Should -Match '  ok   every fanned-out id is in the policy set'
        $out | Should -Match 'OK=0 IDS=0x2C\r?\n'
        $out | Should -Match '  FAIL every fanned-out id is in the policy set \(stray: 0x13\)'
        $out | Should -Match 'BAD=1'
    }
}

Describe 'a suite that keeps its OWN variant defines it after the dot-source' {

    It 'so the library cannot silently override the ones that are different' {
        # test-production-queue.ps1 keeps a Step with -SweepPerturbed. If the
        # dot-source ever moves below that definition, the library's plain Step wins and
        # every -HoldSweepClicks run starts asserting on perturbed state without saying so.
        $dir = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'plugin')).Path
        $bad = @()
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.ps1 -File) {
            if ($f.Name -eq 'sc-suite.ps1') { continue }
            $lines = Get-Content -LiteralPath $f.FullName
            $src = ($lines | Select-String -Pattern 'sc-suite\.ps1' | Select-Object -First 1).LineNumber
            if (-not $src) { continue }
            foreach ($fn in 'Step', 'Assert-That', 'Assert-ScAllOneType') {
                $own = ($lines | Select-String -Pattern "^function\s+$fn\b" | Select-Object -First 1).LineNumber
                if ($own -and $own -lt $src) { $bad += "$($f.Name): $fn at $own, dot-source at $src" }
            }
        }
        $bad -join '; ' | Should -BeExactly ''
    }
}

