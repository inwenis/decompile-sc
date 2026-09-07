#Requires -Version 7
<#
.SYNOPSIS
Get the Create Game screen's Game Type combo to read 'Use Map Settings' -- nothing else.
No fixture, no gameplay, no assertions about a map: launch, one pick, verify, quit.

.DESCRIPTION
'Custom Type' in HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft is ONE machine-wide
value shared with the user's real play (task 050 -- its own 'Recent Maps' entries held
real user map paths, read-only, which is what proves the key is live and shared rather
than something this harness owns). Every suite that wants Use Map Settings reads this
value first (Set-ScGameType, issue #29) and skips the pick when it already matches -- but
the pick itself needs the foreground (task 027 half 2, `Send-ScDropdownPick`'s own
SetCapture requirement), and the only sanctioned writer of the value is the game's own
UI: hard rule 5 forbids writing the key directly, and there is no keyboard-only path
around the capture requirement (probed, task 050 -- see AGENTS.md).

So when the user's own play has left 'Custom Type' on something else, ONE visible pick
is the only way to clear it -- and it clears it for every suite, not just whichever one
happens to run next. Spending a WHOLE suite's fixture-generate-play-teardown cycle on
that one pick is a bad trade (three minutes of the user's screen to buy two seconds of
foreground); this script is only the pick. It launches VISIBLE (unavoidable -- the pick
needs the foreground), walks to Create Game against a STOCK map already shipped with the
working copy (nothing generated, nothing to declare, nothing to clean up -- this run owns
no file), calls Set-ScGameType once, reads the combo back out of the engine's own dialog
list to prove it landed, and quits without ever pressing Start -- no game is played.

Per Send-ScDropdownPick's own docstring the raise lasts exactly one pick and the
foreground is handed straight back afterwards (task 035 / issue #30), so the user's
KEYBOARD FOCUS is theirs again within a couple of seconds; what they see for those few
seconds is a StarCraft window, not their own input going somewhere else.

Re-run this any time an off-screen suite throws the 'Custom Type' mismatch Set-ScGameType
now names explicitly -- expected to keep happening, because the user's own games write
this value too.

.EXAMPLE
./tools/plugin/prime-game-type.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\050-prime-game-type.log'
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0

# A STOCK map already shipped with the working copy -- nothing generated, no fixture-
# folder bookkeeping (hard rule, 2026-08-09): this run owns no file, so none of that
# machinery applies. Deterministic pick (sorted, first) rather than a hardcoded name, so
# this does not depend on exactly which stock maps a given working copy carries.
$stock = @(Get-ChildItem -LiteralPath (Join-Path $GameDir 'Maps\BroodWar') -File `
    -Include '*.scm', '*.scx' -ErrorAction SilentlyContinue | Sort-Object Name)
if ($stock.Count -eq 0) { throw "prime-game-type: no stock map found under $GameDir\Maps\BroodWar." }
$mapPath = $stock[0].FullName
Write-Host "prime-game-type: using stock map '$mapPath' (no fixture, nothing to clean up)"

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

$gamePid = 0
& (Join-Path $scriptDir 'run-with-plugin.ps1') `
    -InjectWindowedHelper WMode -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
        Write-Host $_
        if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
    }
if (-not $gamePid) { throw 'prime-game-type: could not parse the game pid from scinject output.' }
$hwnd = Get-ScGameWindow -ProcessId $gamePid

try {
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
    Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
    Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
    Start-Sleep -Seconds 2
    Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null

    # No -Force: if 'Custom Type' already reads Use Map Settings this is a genuine no-op,
    # no raise at all -- the best case, and still worth running to CONFIRM that case.
    Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2

    # The oracle is the engine's own dialog list, not "Set-ScGameType returned without
    # throwing" -- AGENTS.md "read a dialog's CONTENT from memory; never trust a return".
    $now = Get-ScGameTypeControl -LogPath $LogPath
    Assert-That "the engine's own combo now reads 'Use Map Settings'" `
        ($now -and $now.Value -eq 'Use Map Settings') "(got '$(if ($now) { $now.Value } else { '<no dialog>' })')"
}
finally {
    # Never started a game -- Start was never clicked -- so this always closes from the
    # lobby screen. WM_CLOSE to every top-level window of the pid, same as every suite.
    if ($gamePid) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Warning "prime-game-type: close-game.ps1 failed: $_" }
    }
}

if ($failures -gt 0) {
    Write-Host "prime-game-type: $failures failure(s)"
    exit 1
}
Write-Host 'prime-game-type: OK -- Custom Type is Use Map Settings; every suite skips the pick until the user''s own play changes it again.'
exit 0
