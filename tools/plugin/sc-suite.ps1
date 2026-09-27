#Requires -Version 7
<#
.SYNOPSIS
The suite prelude: loads drive-game.ps1, sc-launch-lock.ps1 and sc-oracle-guard.ps1, sets
$repoRoot, zeroes $failures and $step, and defines the assertion and epilogue helpers every
suite and probe in this directory writes its output with.

.DESCRIPTION
WHY THIS IS SAFE TO SHARE, and the one thing to know about it. This file is DOT-SOURCED:
that runs it in the caller's scope, so the libraries it loads, the counters it zeroes and
the `$script:` inside every function here all belong to the SUITE, not to this file. It
would NOT work if a suite ran this with `&` instead of `.`. tests/sc-suite.Tests.ps1 pins
that behaviour by watching a fake suite's own counter move.

WHAT IS DELIBERATELY NOT HERE. Some suites keep their own variant, defined after the
dot-source so it wins:

  test-production-queue.ps1   Step takes -SweepPerturbed, and skips the step loudly when
                              the hold sweep has consumed its preconditions
  test-random-conformance.ps1 Step prints "== <name>" and does not number its steps
  test-building-groups.ps1,   Assert-ScAllOneType prints "all N are T", without the word
  test-building-parity.ps1    "units" the shared one prints

Both halves of a suite's epilogue are here: Write-ScStepFailure is the `catch`,
Stop-ScSuiteGame the `finally`. What stays at the call site is the launch-lock release,
which must come after the game is closed, and any fixture rule of the suite's own.

.EXAMPLE
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'sc-suite.ps1')
#>

. (Join-Path $PSScriptRoot 'drive-game.ps1')
. (Join-Path $PSScriptRoot 'sc-launch-lock.ps1')
. (Join-Path $PSScriptRoot 'sc-oracle-guard.ps1')
$script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$script:failures = 0
$script:step = 0

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

# The `finally` every game-driving suite ends with. -ProcessId, always: close-game.ps1
# resolving the game by NAME throws whenever any other StarCraft is running -- including the
# user's own playable install -- and would close the wrong game. close-game escalates to
# Stop-Process and throws only when the game is STILL alive afterwards, so a stranded game
# fails the run rather than warning about it (AGENTS.md § "Stopping a run / orphaned games").
# -Fixtures is the suite's New-ScFixtureRun: its declared files go, then its folder if that
# is now empty -- an empty folder still pushes every browser row below it down. -KeepOpen
# leaves both the game and its map for a human.
function Stop-ScSuiteGame {
    param([int]$GamePid, [switch]$KeepOpen, $Fixtures)
    if (-not $KeepOpen -and $GamePid -gt 0) {
        try { & (Join-Path $PSScriptRoot 'close-game.ps1') -ProcessId $GamePid | Write-Host }
        catch {
            Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"
            $script:failures++
        }
        Start-Sleep -Seconds 2
    }
    elseif (-not $KeepOpen) {
        Write-Host '  FAIL no pid was ever parsed, so nothing could be closed'
        $script:failures++
    }
    if ($Fixtures -and -not $KeepOpen) {
        Remove-ScOwnFixture -Run $Fixtures
        Remove-ScOwnFixtureDir -Dir $Fixtures.Dir
    }
}

# The whole-run fan-out check: every FANOUT start in the log must name an id the policy
# table marks fanout (research/data/command-opcodes.tsv; src/hooktest.cpp asserts the same
# 19 ids on its side). One stray id is a policy bug no per-case step can see. Returns the
# ids that fanned out, for a suite's own follow-up checks.
function Assert-ScFanoutPolicy {
    param([Parameter(Mandatory)][string]$LogPath)
    $allowed = @('0x14', '0x15', '0x1A', '0x1B', '0x1C', '0x1D', '0x1E', '0x21',
                 '0x22', '0x25', '0x26', '0x28', '0x2A', '0x2B', '0x2C', '0x2D',
                 '0x2E', '0x36', '0x5A')
    $ids = @(Get-Content -LiteralPath $LogPath |
             Select-String -Pattern 'FANOUT start: cmd=(0x[0-9A-F]{2})' |
             ForEach-Object { [regex]::Match($_.Line, 'cmd=(0x[0-9A-F]{2})').Groups[1].Value } |
             Sort-Object -Unique)
    Write-Host "       ids fanned out this run: $($ids -join ' ')"
    $stray = @($ids | Where-Object { $allowed -notcontains $_ })
    Assert-That 'every fanned-out id is in the policy set' ($stray.Count -eq 0) `
        ($stray.Count -gt 0 ? "(stray: $($stray -join ' '))" : '')
    $ids
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
