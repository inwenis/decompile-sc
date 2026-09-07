#Requires -Version 7
<#
.SYNOPSIS
The OFF-SCREEN half of probe-fullscreen-desktop.ps1: launches the game in TRUE
FULLSCREEN (no windowed helper) on the desktop this process was born on, holds
it up briefly, reports what happened, closes it.

.DESCRIPTION
Run this ONLY through run-offscreen.ps1: on the visible desktop this launch is
the unattended mode switch AGENTS.md § "Hard rules" forbids, and the parent
measures from the visible side whether an invisible desktop CONTAINS it.
Observations print as `CHILD key=value` lines for the parent to parse out of the
run-offscreen transcript. This child never touches display settings -- the
engine's video init does (0x0041D930: SetCooperativeLevel EXCLUSIVE|FULLSCREEN,
SetDisplayMode 640x480x8, on failure SetDisplayMode(GetSystemMetrics(0/1), 8)).
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
    # No -InjectWindowedHelper and no -Windowed: the measurement needs the stock
    # DirectDraw fullscreen path. -NoLaunchLock: the PARENT holds the launch lock.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode observe -ScreenScan 1 -NoLaunchLock `
        -GameDir $GameDir -LogPath $log 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
}
catch {
    # An unhealthy launch (e.g. a DirectDraw error box) is a RESULT of this
    # probe, not a crash of it: report it, do not rethrow.
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
    # EnumWindows is desktop-scoped, so only this child can inventory the windows:
    # an SWarClass rect gives the mode, a #32770 dialog is the DirectDraw error box.
    try { & (Join-Path $scriptDir 'check-game-windows.ps1') -ProcessId $gamePid | ForEach-Object { Write-Host "       $_" } }
    catch { Write-Host "CHILD checkwindows-error=$($_.Exception.Message)" }

    Write-Host "CHILD holding=$HoldSec"
    # The parent samples the visible desktop only while this child lives, so the
    # hold is the window in which a real-desktop mode change can be caught.
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
    Write-Host 'CHILD closed=1'
}
Write-Host 'CHILD done=1'
exit 0
