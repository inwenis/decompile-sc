#Requires -Version 7
<#
.SYNOPSIS
Task 063, the OFF-SCREEN half of probe-fullscreen-desktop.ps1. Launches the game
in TRUE FULLSCREEN (no windowed helper) on the desktop this process was born on,
holds it up briefly, reports what happened, closes it.

.DESCRIPTION
Run this ONLY through run-offscreen.ps1 -- probe-fullscreen-desktop.ps1 does,
and it is the only caller. On the visible desktop this launch would be exactly
the mode switch hard rule 5 forbids running unattended; the parent probe exists
to measure whether an invisible desktop CONTAINS it, and the measurement is
taken by the parent from the visible side while this child runs.

Every observation is printed as a `CHILD key=value` line for the parent to parse
out of the run-offscreen transcript. This child never touches display settings
itself -- it only launches the game, which does whatever the engine's video init
(0x0041D930: SetCooperativeLevel EXCLUSIVE|FULLSCREEN, SetDisplayMode 640x480x8,
on failure SetDisplayMode(GetSystemMetrics(0/1), 8)) does on this desktop.
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    [int]$HoldSec = 20
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'sc-desktop.ps1')

$log = Join-Path $LogDir '063-fullscreen.log'
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

Write-Host "CHILD desktop=$(Get-ScThreadDesktopName)"

$gamePid = 0
$healthErr = $null
try {
    # No -InjectWindowedHelper and no -Windowed: the whole point is the stock
    # DirectDraw fullscreen path. -NoLaunchLock: the PARENT holds the lock for
    # the probe's whole duration.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode observe -ScreenScan 1 -NoLaunchLock `
        -GameDir $GameDir -LogPath $log 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
}
catch {
    # An unhealthy launch (e.g. a DirectDraw error box) is a RESULT of this
    # probe, not a crash of it -- exactly probe-widescreen-present's stance.
    $healthErr = $_.Exception.Message
    if (-not $gamePid) {
        $p = @(Get-Process StarCraft -ErrorAction SilentlyContinue)
        if ($p.Count -eq 1) { $gamePid = $p[0].Id }
    }
}

Write-Host "CHILD pid=$gamePid"
if ($healthErr) { Write-Host "CHILD unhealthy=$healthErr" }

if ($gamePid -gt 0) {
    Start-Sleep -Seconds 5
    # The window inventory, from THIS desktop (EnumWindows is desktop-scoped):
    # an SWarClass rect says what mode the fullscreen window believes it has; a
    # #32770 dialog is the DirectDraw error box.
    try { & (Join-Path $scriptDir 'check-game-windows.ps1') -ProcessId $gamePid | ForEach-Object { Write-Host "       $_" } }
    catch { Write-Host "CHILD checkwindows-error=$($_.Exception.Message)" }

    Write-Host "CHILD holding=$HoldSec"
    Start-Sleep -Seconds $HoldSec

    try {
        & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | ForEach-Object { Write-Host "       $_" }
        Write-Host 'CHILD closed=1'
    }
    catch {
        Write-Host "CHILD closed=0 close-error=$($_.Exception.Message)"
    }
}
else {
    Write-Host 'CHILD closed=1'   # nothing to close
}
Write-Host 'CHILD done=1'
exit 0
