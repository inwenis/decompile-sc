#Requires -Version 7
<#
.SYNOPSIS
The assertion helpers every suite and probe in this directory writes its output with.

.DESCRIPTION
WHY THIS IS SAFE TO SHARE, and the one thing to know about it. Every function here writes to
`$script:failures` / `$script:step`, which belong to the SUITE, not to this file. That
works because this file is DOT-SOURCED: dot-sourcing runs it in the caller's scope, so the
functions are defined there and their `$script:` is the caller's script scope. It would
NOT work if a suite ran this with `&` instead of `.`. tests/sc-suite.Tests.ps1 pins that
behaviour by watching a fake suite's own counter move.

WHAT IS DELIBERATELY NOT HERE. Some suites keep their own variant, defined after the
dot-source so it wins:

  test-production-queue.ps1   Step takes -SweepPerturbed, and skips the step loudly when
                              the hold sweep has consumed its preconditions
  test-random-conformance.ps1 Step prints "== <name>" and does not number its steps
  test-building-groups.ps1,   Assert-ScAllOneType prints "all N are T", without the word
  test-building-parity.ps1    "units" the shared one prints

The `finally` half of each suite's epilogue is NOT here and should not be: it reads
$gamePid, $KeepOpen, $mapDir and the suite's own fixture list, so sharing it means passing
four things in. Its `catch` half IS here, because that half only ever needed the error
record and a noun.

.EXAMPLE
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'sc-suite.ps1')
#>

# One assertion line. `$Detail` is for the numbers a reader needs when it FAILS -- the
# expected and the actual -- and is printed only then, so a passing run stays scannable.
function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

# One numbered step, with a blank line before it so a long run reads as sections rather
# than as a wall. The number comes from the caller's own $script:step.
function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    & $Body
}

# The `catch` every suite and probe ends with. `$What` is the caller's own noun, so the
# line reads "a test step threw" or "a probe step threw": the wording a human scanning a
# failed run looks for.
function Write-ScStepFailure {
    param([Parameter(Mandatory)]$Err, [string]$What = 'a step')
    Write-Host "  FAIL $What threw: $($Err.Exception.Message)"
    Write-Host "       $($Err.ScriptStackTrace)"
    $script:failures++
}

# AGENTS.md § "Hard rules": patching is in-process only, so StarCraft.exe on disk must stay
# byte-identical to pristine 1.16.1 -- hashed before and after every run, not attested.
# tools/make-working-copy.ps1 verifies the working copy against the same value.
$ScPristineExeSha256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'

# Before the run. `$Label` goes verbatim between "[0] " and "StarCraft.exe". Returns the
# hash for Assert-ScExeUnchanged.
function Assert-ScExePristine {
    param([Parameter(Mandatory)][string]$GameDir, [string]$Label = '')
    $exe = Join-Path $GameDir 'StarCraft.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw "$exe not found." }
    $h = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    Write-Host "[0] ${Label}StarCraft.exe SHA-256 before: $h"
    Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
        ($h -eq $ScPristineExeSha256) "(got $h)"
    $h
}

# After the run: a code path that wrote to StarCraft.exe shows up as a failed assertion.
function Assert-ScExeUnchanged {
    param([Parameter(Mandatory)][string]$GameDir, [string]$Before)
    $h = (Get-FileHash -LiteralPath (Join-Path $GameDir 'StarCraft.exe') -Algorithm SHA256).Hash
    Write-Host "  StarCraft.exe SHA-256 after:  $h"
    Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($h -eq $Before)
    Assert-That 'and still byte-identical to pristine 1.16.1' ($h -eq $ScPristineExeSha256)
}

# "Every live unit is of exactly one type, and it is this one." Single-bucket on purpose:
# a histogram whose largest bucket is 20 of 36 says nothing about the other sixteen.
function Assert-ScAllOneType {
    param([string]$What, $State, [string]$ExpectedType)
    $only = @($State.Types.Keys)
    $ok = ($only.Count -eq 1) -and ($State.Types[$only[0]] -eq $State.Live) -and
          ($only[0] -eq $ExpectedType)
    Assert-That "$What`: all $($State.Live) units are $ExpectedType" $ok "(got $($State.TypesText))"
}

# The stock arm of a plugin-vs-stock comparison must really be stock. Each pattern is
# proved POSITIVE against the plugin arm's log before it is required absent from the stock
# arm's (AGENTS.md § "Oracles: absence and defect-era checks"): 'HOOK install' is a string
# the plugin never writes (the real ones are `HOOK %s: installed at %p` and
# `HOOK: %d/%d installed`), so an absence check on it passes on any log.
function Assert-ScStockArm {
    param([Parameter(Mandatory)][string]$PluginLogPath, [Parameter(Mandatory)][string]$StockLogPath)
    $obsLog = Get-Content -LiteralPath $StockLogPath
    $fanLog = Get-Content -LiteralPath $PluginLogPath
    foreach ($probe in @(
        @{ What = 'a hook installation line'; Pattern = 'HOOK .*installed' },
        @{ What = 'an intercepted command';   Pattern = 'CMD id=' },
        @{ What = 'a fan-out';                Pattern = 'FANOUT start' }
    )) {
        $inFanout = @($fanLog | Select-String -Pattern $probe.Pattern).Count
        $inObserve = @($obsLog | Select-String -Pattern $probe.Pattern).Count
        Assert-That "the plugin arm DOES show $($probe.What) -- so its absence below means something" `
            ($inFanout -gt 0) "(pattern '$($probe.Pattern)' matched nothing in the fanout log either)"
        Assert-That "the stock arm shows no $($probe.What)" ($inObserve -eq 0) `
            "(found $inObserve line(s) matching '$($probe.Pattern)')"
    }
    # And a POSITIVE statement about what the stock arm is, not just what it is not.
    Assert-That 'the stock arm ran in observe mode' `
        (@($obsLog | Select-String -Pattern 'mode=observe').Count -gt 0)
    Assert-That 'and it still produced the same oracle (WORLD lines)' `
        (@($obsLog | Select-String -Pattern 'WORLD \[').Count -gt 0)
}
