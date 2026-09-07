#Requires -Version 7
<#
.SYNOPSIS
The two primitives every suite and probe in this directory writes its output with.

.DESCRIPTION
`Assert-That` existed 26 times and `Step` 23 times, character for character, one copy per
suite. They were copied because the first suite had them inline and every suite after it
started from a copy of the last -- the same reason twelve modules under src/ each had
their own `Rt()` before #133.

WHY THIS IS SAFE TO SHARE, and the one thing to know about it. Both functions write to
`$script:failures` / `$script:step`, which belong to the SUITE, not to this file. That
works because this file is DOT-SOURCED: dot-sourcing runs it in the caller's scope, so the
functions are defined there and their `$script:` is the caller's script scope. It would
NOT work if a suite ran this with `&` instead of `.`. tests/sc-suite.Tests.ps1 pins that
behaviour by watching a fake suite's own counter move.

WHAT IS DELIBERATELY NOT HERE. Two suites have a `Step` that is genuinely different and
they keep their own:

  test-production-queue.ps1   takes -SweepPerturbed, and skips the step loudly when the
                              hold sweep has consumed its preconditions (task 041)
  test-random-conformance.ps1 prints "== <name>" and does not number its steps

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

# The `catch` seventeen suites and probes end with. `$What` is the caller's own noun, so
# the line reads exactly as it did when this was copied into each of them -- "a test step
# threw", "a probe step threw" -- because that wording is what a human scanning a failed
# run looks for.
function Write-ScStepFailure {
    param([Parameter(Mandatory)]$Err, [string]$What = 'a step')
    Write-Host "  FAIL $What threw: $($Err.Exception.Message)"
    Write-Host "       $($Err.ScriptStackTrace)"
    $script:failures++
}
