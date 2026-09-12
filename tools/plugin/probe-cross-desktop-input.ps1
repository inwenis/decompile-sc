#Requires -Version 7
<#
.SYNOPSIS
Measures whether a POSTED window message drives the game while the game sits on a desktop
other than the one the monitor shows.

.DESCRIPTION
Posted messages are handle operations that need neither focus nor foreground
(`research/automated-testing-options.md` §4.1/§9) -- an argument, not a measurement.
The oracle is TEXTUAL: the plugin logs one line per CHANGE of the engine's active-dialog set
(`DIALOGS n=... dlg='...'`, scplugin.cpp ScanDialogs), so the answer is read out of the
game's own memory with no frame capture -- which could itself be the failing mechanism -- in
the decision path. Run both arms: -Visible is the positive control, because "the dialog set
changed" is worth nothing until the same probe is seen observing that change where clicks
already work (AGENTS.md § "Oracles: absence and defect-era checks").
.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Command '& ./tools/plugin/probe-cross-desktop-input.ps1'
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\043\probe-cross-desktop.log',
    # Outside the repo: a frame reproduces game artwork (AGENTS.md § "Hard rules").
    [string]$ShotDir = 'C:\sc-work\logs\043\probe-frames',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-desktop.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0

$here  = Get-ScThreadDesktopName
$shown = Get-ScInputDesktopName
$offScreen = ($here -ne $shown)
Write-Host "[0] this process is on desktop '$here'; the monitor is showing '$shown'"
Write-Host ("    arm: {0}" -f $(if ($offScreen) { 'OFF-SCREEN (the measurement)' } else { 'VISIBLE (the positive control)' }))

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

$gamePid = 0
$hwnd = [IntPtr]::Zero
try {
    # The real production launcher, with the flags every suite uses. Do not substitute an
    # older ddraw.dll-copy trick: it yields a 0x0 window on the visible desktop too, so a
    # broken shortcut reads as a broken desktop.
    Write-Host ''
    Write-Host '[1] launch through run-with-plugin.ps1 (it picks up this desktop by itself)'
    $t0 = Get-Date
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode observe -InjectWindowedHelper WMode -GameDir $GameDir -LogPath $LogPath 6>&1 |
        ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    $launchSec = ((Get-Date) - $t0).TotalSeconds
    Assert-That 'the launcher reported a game pid' ($gamePid -gt 0)
    if (-not $gamePid) { throw 'probe: no pid, nothing to drive.' }
    Write-Host ("    launch took {0:n1}s" -f $launchSec)

    # Get-ScGameWindow is EnumWindows underneath, and EnumWindows is scoped to the calling
    # thread's desktop. In the off-screen arm this succeeding is itself a result: window
    # discovery follows the game across desktops unchanged.
    Write-Host ''
    Write-Host '[2] find the game window from this process'
    $hwnd = Get-ScGameWindow -ProcessId $gamePid
    $sz = Get-ScClientSize -Hwnd $hwnd
    Assert-That "the window was found by enumeration on this desktop (hwnd=0x$('{0:X}' -f [int64]$hwnd))" ($hwnd -ne [IntPtr]::Zero)
    Assert-That "it has a real client area ($($sz.Width)x$($sz.Height))" ($sz.Width -gt 0 -and $sz.Height -gt 0)

    # Recorded, not asserted: it predicts Send-ScDropdownPick, the one primitive allowed to
    # raise -- the game calls SetCapture on button-down and Windows grants capture only to the
    # foreground window (AGENTS.md § "Foreground"). An invisible desktop has no competing
    # application, so the game may simply hold that desktop's foreground.
    $fg = [ScDrive.Native]::GetForegroundWindow()
    Write-Host ("    GetForegroundWindow() on this desktop = 0x{0:X}{1}" -f [int64]$fg,
        $(if ($fg -eq $hwnd) { '  <- the game itself' } elseif ($fg -eq [IntPtr]::Zero) { '  <- nothing is foreground here' } else { '  <- some other window' }))

    Write-Host ''
    Write-Host '[3] the engine''s own dialog list, before any input'
    $before = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'DIALOGS n=' -TimeoutSec 30)
    $beforeLine = $before[-1].Trim()
    $beforeNames = ([regex]::Matches($beforeLine, "dlg='([^']*)'") | ForEach-Object { $_.Groups[1].Value }) -join ','
    Write-Host "    dialogs: $beforeNames"
    Assert-That 'the plugin is reporting the engine''s dialog list' ($beforeNames -ne '')

    Write-Host ''
    Write-Host '[4] post ONE click at the main menu''s Single Player button and watch the engine'
    $mark = Get-ScLogLineCount -LogPath $LogPath
    Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player -- the same point every suite uses
    Start-Sleep -Seconds 3

    $after = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
               Select-String -Pattern 'DIALOGS n=')
    $changed = $after.Count -gt 0
    if ($changed) {
        $afterLine = $after[-1].Line.Trim()
        $afterNames = ([regex]::Matches($afterLine, "dlg='([^']*)'") | ForEach-Object { $_.Groups[1].Value }) -join ','
        Write-Host "    dialogs: $afterNames"
    }
    else { $afterNames = '(unchanged)' }

    # The plugin logs this line ONLY on a change of the set, so a new line after the click is
    # the engine having navigated. Asserting on the change rather than on a name keeps this
    # independent of what the Single Player screen happens to be called.
    Assert-That "the posted click changed the engine's dialog set ($beforeNames -> $afterNames)" $changed `
        '(no new DIALOGS line within 3s of the click)'

    Write-Host ''
    Write-Host '[5] frame capture (corroboration only -- re-checks task 040 in this harness)'
    try {
        $png = Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $ShotDir ("{0}-after-click.png" -f $(if ($offScreen) { 'offscreen' } else { 'visible' }))) -FullWindow
        $fi = Get-Item -LiteralPath $png
        Assert-That "PrintWindow produced a frame ($([int]$fi.Length) bytes)" ($fi.Length -gt 1000)
        Write-Host "    frame (diagnostic): $png"
    }
    catch {
        # A failed capture does not invalidate the measurement above -- the oracle is the log.
        # Still counted as a failure of its own so it cannot pass unnoticed.
        Assert-That 'PrintWindow captured a frame' $false "($($_.Exception.Message))"
    }
}
catch {
    Write-Host "  FAIL the probe threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game: $($_.Exception.Message)"; $failures++ }
    }
}

Write-Host ''
Write-Host ("probe-cross-desktop-input [{0}]: {1} failure(s)" -f $(if ($offScreen) { 'off-screen' } else { 'visible' }), $failures)
exit ($failures -eq 0 ? 0 : 1)
