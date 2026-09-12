#Requires -Version 7
<#
.SYNOPSIS
Measures whether picking a menu DROPDOWN entry -- the one posted input a no-raise
harness cannot do -- needs the window raised, or only the input queues attached.

.DESCRIPTION
Candidate mechanism: the dropdown is a PRESS-AND-HOLD control and the game calls
`SetCapture` on button-down (`0x004d1a76`); Windows grants the mouse capture only to the
FOREGROUND window. A world drag-box is also a held-button move and works in the background
(measured), so capture dependence is specific to this dialog control. Three arms on the
Create Game screen: A background; B background + attach; C foreground, the positive control.

.EXAMPLE
./tools/plugin/probe-quiet-dropdown.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\027-probe-dropdown.log',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')

function Fg { [ScDrive.Native]::GetForegroundWindow() }
$victim = Fg
Write-Host ("[0] foreground before launch: 0x{0:X}" -f [int64]$victim)

function Restore-Victim {
    if ($victim -ne [IntPtr]::Zero) { [void][ScDrive.Native]::MakeForeground($victim) }
    Start-Sleep -Milliseconds 500
    Fg
}

# Attach to the GAME's thread -- not, as Set-ScWindowActive does, to whatever holds the
# foreground -- then SetActiveWindow/SetFocus inside that shared input queue: an attach
# without a raise only means anything against the thread that owns the dropdown.
if (-not ('ScProbe.Attach' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace ScProbe {
  public static class Attach {
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] static extern IntPtr SetActiveWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetActiveWindow();
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

    // Returns the attachment token so the caller can undo it; 0 means "not attached".
    public static uint Grab(IntPtr h) {
      uint tGame = GetWindowThreadProcessId(h, IntPtr.Zero);
      uint tMe = GetCurrentThreadId();
      if (tGame == 0 || tGame == tMe) return 0;
      if (!AttachThreadInput(tMe, tGame, true)) return 0;
      SetActiveWindow(h);
      SetFocus(h);
      return tGame;
    }
    public static void Release(uint tGame) {
      if (tGame != 0) AttachThreadInput(GetCurrentThreadId(), tGame, false);
    }
  }
}
"@ -ReferencedAssemblies System.Runtime, System.Runtime.InteropServices
}

$gamePid = 0
$hwnd = [IntPtr]::Zero
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

function Try-Pick([string]$arm) {
    # Set-ScGameType is the oracle: it READS the selected entry out of the engine's dialog
    # list and requires the pick to have produced the wanted one by name, a sharper verdict
    # than "some pixels changed".
    #
    # -Force because the whole question is whether a pick TAKES under three foreground
    # arms. Without it the sticky remembered value lets Set-ScGameType skip the pick and
    # report success having driven nothing -- the experiment measuring its own shortcut.
    try {
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Tries 1 -Force
        Write-Host "       ARM ${arm}: PICK TOOK"
        return $true
    } catch {
        Write-Host "       ARM ${arm}: pick did not take"
        return $false
    }
}

try {
    Wait-ScNoGameRunning
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode observe -InjectWindowedHelper WMode `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Write-Host ''
    Write-Host '[1] menus: Single Player -> Expansion -> Play Custom -> a stock campaign map'
    Enter-ScCustomGame -Hwnd $hwnd -LogPath $LogPath -MapPath (Join-Path $GameDir 'Maps\campaign\(1)Enslavers02b.scm') -GameDir $GameDir -StopAt Map -Noun 'probe'
    # NO "Ok" click here: the Game Type combo lives on THIS screen and every suite calls
    # Set-ScGameType before Ok. Past Ok the 'Create' dialog is out of the engine's dialog
    # list, so all three arms score the same whatever the foreground did -- arms that cannot
    # disagree measure nothing.
    Start-Sleep -Seconds 2

    Write-Host ''
    Write-Host '[2] ARM A: background, no raise, no attach'
    $fg = Restore-Victim
    Write-Host ("       foreground: 0x{0:X} (user's window: {1})" -f [int64]$fg, ($fg -eq $victim))
    $a = Try-Pick 'A'

    Write-Host ''
    Write-Host '[3] ARM B: background + AttachThreadInput(game) + SetActiveWindow, still no raise'
    $fg = Restore-Victim
    $tok = [ScProbe.Attach]::Grab($hwnd)
    Write-Host ("       attached={0} activeWindowInSharedQueue=0x{1:X} foreground=0x{2:X} (user's: {3})" -f `
                ($tok -ne 0), [int64][ScProbe.Attach]::GetActiveWindow(), [int64](Fg), ((Fg) -eq $victim))
    $b = $false
    try { $b = Try-Pick 'B' } finally { [ScProbe.Attach]::Release($tok) }
    Write-Host ("       foreground after arm B: 0x{0:X} (never left the user: {1})" -f [int64](Fg), ((Fg) -eq $victim))

    Write-Host ''
    Write-Host '[4] ARM C: foreground (the old behaviour) -- positive control'
    Assert-ScWindowActive -Hwnd $hwnd -Because 'the arm C control' -RaiseWindow
    $c = Try-Pick 'C'

    Write-Host ''
    Write-Host "VERDICT  A(background)=$a  B(attach, no raise)=$b  C(foreground)=$c"
    if ($c -and -not $a -and $b) { Write-Host 'VERDICT  attach-without-raise is enough: the harness never has to raise.' }
    elseif ($c -and -not $a -and -not $b) { Write-Host 'VERDICT  only a real raise works for the dropdown; scope it to that one primitive.' }
    elseif ($a) { Write-Host 'VERDICT  the background pick worked here -- the suite failures have another cause.' }
    else { Write-Host 'VERDICT  even the foreground control failed; the oracle or the screen state is wrong.' }
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid
    }
}
