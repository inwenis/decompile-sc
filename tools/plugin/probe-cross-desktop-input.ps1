#Requires -Version 7
<#
.SYNOPSIS
The decisive measurement for task 043: does a POSTED window message drive the game when the
game is on a desktop that is not the one on the monitor?

.DESCRIPTION
Task 040 proved the game RENDERS and can be CAPTURED off-screen. It did not prove the game
can be DRIVEN off-screen, and said so: `PostMessage` and `PrintWindow` are both
handle-operations and `research/automated-testing-options.md` §4.1/§9 established that
posted messages need neither focus nor foreground -- "so there is good reason to expect
this works, but it was not measured". Argued is not measured. Everything else in task 043
stands on this one answer, so it is taken first and on its own.

THE ORACLE IS TEXTUAL, not a picture. The plugin walks the engine's own active-dialog list
every tick and logs one line per CHANGE of the set (`DIALOGS n=... dlg='...'`,
scplugin.cpp ScanDialogs). A posted click that navigates the menu changes that set, and the
change is read out of the game's own memory through the plugin log -- no frame anywhere in
the decision. That matters here specifically: if posted messages did NOT cross desktops,
the answer must not arrive filtered through a second mechanism (frame capture) that could
itself be the thing failing.

A frame IS captured, at the end, as CORROBORATION and as a re-check of task 040's result
in this harness. It is never the oracle, and it lands outside the repo (hard rule 1).

## Both arms, and why

Run it off-screen and visible:

    ./tools/plugin/run-offscreen.ps1 -Command '& ./tools/plugin/probe-cross-desktop-input.ps1'
    ./tools/plugin/run-offscreen.ps1 -Visible -Command '& ./tools/plugin/probe-cross-desktop-input.ps1'

The visible arm is the POSITIVE CONTROL and it is not optional. "The dialog set changed
after the click" is worth nothing until the same probe, reading the same line, has been
shown to observe the same change where everyone already agrees clicks work -- AGENTS.md
§ "Absence assertions must first be proved positive". If the off-screen arm sees no change
and the visible arm sees none either, the probe is broken, not the mechanism.

## What it also records, without asserting on it

Whether the game's window ends up FOREGROUND on its own desktop. That predicts the one
primitive this repo allows to raise -- `Send-ScDropdownPick`, which needs the foreground
because the game calls `SetCapture` on button-down and Windows grants capture only to the
foreground window (AGENTS.md § "Foreground", half 2). Recorded here, not decided here.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Command '& ./tools/plugin/probe-cross-desktop-input.ps1'
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\043\probe-cross-desktop.log',
    # Outside the repo: a frame reproduces game artwork (hard rule 1).
    [string]$ShotDir = 'C:\sc-work\logs\043\probe-frames',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-desktop.ps1')

$failures = 0
function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

# --- where are we ------------------------------------------------------------
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
    # --- launch ---------------------------------------------------------------
    # The REAL production launcher, with the same flags every existing suite uses. Task 040
    # learned this the expensive way: its first attempt used an older ddraw.dll-copy trick
    # and produced a 0x0 window on the visible desktop too, which looked like the desktop
    # failing when it was the shortcut failing.
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

    # --- can this process even SEE the window ---------------------------------
    # Get-ScGameWindow is EnumWindows underneath, and EnumWindows is scoped to the calling
    # thread's desktop. In the off-screen arm this succeeding is itself a result: it means
    # the harness's window discovery followed the game across without a single change.
    Write-Host ''
    Write-Host '[2] find the game window from this process'
    $hwnd = Get-ScGameWindow -ProcessId $gamePid
    $sz = Get-ScClientSize -Hwnd $hwnd
    Assert-That "the window was found by enumeration on this desktop (hwnd=0x$('{0:X}' -f [int64]$hwnd))" ($hwnd -ne [IntPtr]::Zero)
    Assert-That "it has a real client area ($($sz.Width)x$($sz.Height))" ($sz.Width -gt 0 -and $sz.Height -gt 0)

    # Recorded, not asserted -- see .DESCRIPTION. On the invisible desktop there is no
    # competing application, so the game may simply keep its own desktop's foreground.
    $fg = [ScDrive.Native]::GetForegroundWindow()
    Write-Host ("    GetForegroundWindow() on this desktop = 0x{0:X}{1}" -f [int64]$fg,
        $(if ($fg -eq $hwnd) { '  <- the game itself' } elseif ($fg -eq [IntPtr]::Zero) { '  <- nothing is foreground here' } else { '  <- some other window' }))

    # --- the oracle, before ---------------------------------------------------
    Write-Host ''
    Write-Host '[3] the engine''s own dialog list, before any input'
    $before = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'DIALOGS n=' -TimeoutSec 30)
    $beforeLine = $before[-1].Trim()
    $beforeNames = ([regex]::Matches($beforeLine, "dlg='([^']*)'") | ForEach-Object { $_.Groups[1].Value }) -join ','
    Write-Host "    dialogs: $beforeNames"
    Assert-That 'the plugin is reporting the engine''s dialog list' ($beforeNames -ne '')

    # --- THE MEASUREMENT ------------------------------------------------------
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

    # The plugin logs this line ONLY on a change of the set, so a new line after the click
    # IS the engine having navigated. Asserting on the change rather than on a name keeps
    # this independent of what the Single Player screen happens to be called.
    Assert-That "the posted click changed the engine's dialog set ($beforeNames -> $afterNames)" $changed `
        '(no new DIALOGS line within 3s of the click)'

    # --- corroboration, explicitly not the oracle -----------------------------
    Write-Host ''
    Write-Host '[5] frame capture (corroboration only -- re-checks task 040 in this harness)'
    try {
        $png = Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $ShotDir ("{0}-after-click.png" -f $(if ($offScreen) { 'offscreen' } else { 'visible' }))) -FullWindow
        $fi = Get-Item -LiteralPath $png
        Assert-That "PrintWindow produced a frame ($([int]$fi.Length) bytes)" ($fi.Length -gt 1000)
        Write-Host "    frame (diagnostic, NOT committable): $png"
    }
    catch {
        # A failed capture does NOT invalidate the measurement above -- the oracle is the
        # log. Recorded as a failure of its own so it cannot be missed either.
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
