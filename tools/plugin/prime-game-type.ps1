#Requires -Version 7
<#
.SYNOPSIS
Get the Create Game screen's Game Type combo to read 'Use Map Settings' -- nothing else.
No fixture, no gameplay, no assertions about a map: launch, one pick, verify, quit.

.DESCRIPTION
'Custom Type' in HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft is ONE machine-wide
value shared with the user's real play -- its 'Recent Maps' siblings hold real user map
paths. The running game changes it only through its own UI, and the pick needs the foreground
(Send-ScDropdownPick's SetCapture, no keyboard-only path around it), so one visible
launch here clears it for every suite -- see AGENTS.md § "Game Type / `Custom Type`".
That raise lasts exactly one pick and the foreground is handed straight back, so the
user's keyboard focus is theirs again in a couple of seconds (AGENTS.md § "Foreground").

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

# A stock map ships with the working copy, so this run generates nothing and owns no
# file -- no fixture-folder bookkeeping applies. Sorted-first rather than a hardcoded
# name: which stock maps a working copy carries varies.
$stock = @(Get-ChildItem -LiteralPath (Join-Path $GameDir 'Maps\BroodWar') -File `
    -Include '*.scm', '*.scx' -ErrorAction SilentlyContinue | Sort-Object Name)
if ($stock.Count -eq 0) { throw "prime-game-type: no stock map found under $GameDir\Maps\BroodWar." }
$mapPath = $stock[0].FullName
Write-Host "prime-game-type: using stock map '$mapPath' (no fixture, nothing to clean up)"

# A visible launch: without $env:AGENT_TASK, run-with-plugin.ps1 takes no launch lock and
# gives the user's foreground no hand-back (the same gate as run-offscreen.ps1).
if ($env:AGENT_TASK -notmatch '^\s*\d') {
    throw "prime-game-type: set `$env:AGENT_TASK to your PR or issue number first (e.g. `$env:AGENT_TASK = '125'). Without it the launch takes no launch lock and keeps the user's foreground."
}

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
    # throwing" -- AGENTS.md § "Oracles: what counts as a read-back".
    $now = Get-ScGameTypeControl -LogPath $LogPath
    Assert-That "the engine's own combo now reads 'Use Map Settings'" `
        ($now -and $now.Value -eq 'Use Map Settings') "(got '$(if ($now) { $now.Value } else { '<no dialog>' })')"
}
finally {
    # Start is never pressed, so this always closes from the lobby screen: WM_CLOSE to
    # every top-level window of the pid, same as every suite.
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
