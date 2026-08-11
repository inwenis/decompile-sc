#Requires -Version 7
<#
.SYNOPSIS
Record the foreground window before something steals it, and hand it back afterwards.
Dot-sourced by run-with-plugin.ps1; issue #30.

.DESCRIPTION
Task 027 removed the per-input foreground raise from the harness, so a suite no longer
takes the user's window on every click. It did not cover THE LAUNCH, and the launch is
where the game takes the foreground: StarCraft activates its own window when it creates
it, and nothing hands it back.

That gap is invisible on a busy desktop and total on an idle one. Task 029 measured both,
same branch, twenty minutes apart:

  * desktop busy  -- three brief game-foreground intervals, ~9s total; the terminal and
    the user's Chrome kept reclaiming it.
  * desktop IDLE  -- the game took the foreground at window creation and HELD IT FOR 72
    SECONDS, until it exited. The whole run.

Nothing "hands it back" on the idle desktop because nothing else asks for it. Worse, it
poisons the one legitimate borrow: Send-ScDropdownPick raises for one pick and returns
the foreground to whatever had it before -- and on an idle desktop, by then, that is the
game. The borrow-and-return is behaving exactly as documented; the launch is the
uncovered part, and AGENTS.md's "exactly one borrow-and-return pair" expectation is
simply false until it is covered.

So: record the foreground window BEFORE the launch, restore it once the game's window
exists. One SetForegroundWindow on a recorded handle, symmetric with what
Send-ScDropdownPick already does per pick.

WHY THIS IS ITS OWN FILE. run-with-plugin.ps1 is copied into the deploy tree and must
keep working with no repo present (tools/deploy.ps1 "self-contained, not a thin repo
pointer"), and drive-game.ps1 -- which owns the equivalent MakeForeground for the
dropdown borrow -- is 120KB of input machinery that a launch has no business loading.
This is the same shape as sc-canonical-path.ps1 / sc-launch-lock.ps1: one small file,
dot-sourced by both callers, copied by deploy.ps1. tests/deploy-runtime.Tests.ps1 fails
if a dependency of run-with-plugin.ps1 is ever left out of that copy list.

WHO GETS THE RESTORE. Workers, and only workers. A human double-clicking their shortcut
launched the game in order to play it, and shoving it behind their editor would be a
worse bug than the one this fixes -- so Restore-ScForeground is called only under the
same $env:AGENT_TASK gate the launch lock uses, with -NoForegroundRestore as an
independent second guard that the deployed launcher bakes in. $env:SCDRIVE_RAISE=1 (the
existing "a human wants to watch this run" knob, drive-game.ps1 Set-ScWindowActive) also
turns it off: someone watching a run wants to see it.
#>

if (-not ('ScFg.Native' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ScFg {
  public static class Native {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] private static extern IntPtr SetActiveWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();

    public static uint PidOf(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
    public static string TitleOf(IntPtr h) { var sb = new StringBuilder(256); GetWindowTextW(h, sb, 256); return sb.ToString(); }

    // Windows refuses SetForegroundWindow from a process that does not already own the
    // foreground: it returns TRUE and only flashes the taskbar. Attaching this thread's
    // input queue to the CURRENT foreground thread first is the documented way to be
    // allowed, and the attachment is undone immediately. The return value is a re-READ
    // of GetForegroundWindow, not the API's own optimistic bool -- callers assert on
    // what actually happened.
    public static bool MakeForeground(IntPtr h) {
      IntPtr fg = GetForegroundWindow();
      if (fg == h) return true;
      uint pFg; uint tFg = GetWindowThreadProcessId(fg, out pFg);
      uint tMe = GetCurrentThreadId();
      bool attached = (tFg != 0 && tFg != tMe) ? AttachThreadInput(tMe, tFg, true) : false;
      try {
        BringWindowToTop(h);
        SetForegroundWindow(h);
        SetActiveWindow(h);
        SetFocus(h);
      } finally {
        if (attached) AttachThreadInput(tMe, tFg, false);
      }
      return GetForegroundWindow() == h;
    }
  }
}
"@
}

function Get-ScForegroundWindow {
    <# .SYNOPSIS The current foreground window handle, or IntPtr.Zero if there is none. #>
    [CmdletBinding()]
    param()
    [ScFg.Native]::GetForegroundWindow()
}

function Test-ScForegroundIsGame {
    <#
    .SYNOPSIS
    Does this window belong to a StarCraft process?
    .DESCRIPTION
    Used twice, for opposite reasons: a recorded handle that is already a game window must
    NOT be restored (that would raise another worker's run -- see Restore-ScForeground),
    and the post-launch check wants to say whether the game is still holding it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    if ($Hwnd -eq [IntPtr]::Zero) { return $false }
    $procId = [ScFg.Native]::PidOf($Hwnd)
    if ($procId -eq 0) { return $false }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    return ($null -ne $p -and $p.ProcessName -like 'StarCraft*')
}

function Restore-ScForeground {
    <#
    .SYNOPSIS
    Give the foreground back to a window recorded earlier. NEVER throws.
    .DESCRIPTION
    Cosmetic by nature: by the time this runs the launch has already succeeded, and a
    window that has since closed, or a shell that refuses to give the foreground up, must
    not fail a good launch. Same reasoning as Send-ScDropdownPick's own hand-back, which
    is deliberately non-fatal for the same reason.

    RETRIED, because the race is real. The game activates its window when it creates it,
    and under the windowed-mode helper it is still settling for a second or so afterwards
    -- a single SetForegroundWindow issued into the middle of that can be undone by the
    game's own next activation. So this restores, re-reads the foreground, and tries
    again while the game is still the one holding it.

    Returns $true if the recorded window ended up foreground.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [int]$Tries = 4,
        [int]$SettleMs = 350
    )
    if ($Hwnd -eq [IntPtr]::Zero) { return $false }
    try {
        if (-not [ScFg.Native]::IsWindow($Hwnd)) { return $false }
        for ($i = 1; $i -le $Tries; $i++) {
            if ([ScFg.Native]::MakeForeground($Hwnd)) { return $true }
            Start-Sleep -Milliseconds $SettleMs
        }
        # One last read: MakeForeground compares immediately, and an activation that
        # arrives a beat later still counts as success.
        return ([ScFg.Native]::GetForegroundWindow() -eq $Hwnd)
    }
    catch { return $false }
}

function Get-ScForegroundLabel {
    <# .SYNOPSIS 'pid=N proc=X title=...' for one handle, for a log line a human can read. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    if ($Hwnd -eq [IntPtr]::Zero) { return '(none)' }
    $procId = [ScFg.Native]::PidOf($Hwnd)
    $name = try { (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { '?' }
    "hwnd=0x{0:X8} pid={1} proc={2} title='{3}'" -f [int64]$Hwnd, $procId, $name, [ScFg.Native]::TitleOf($Hwnd)
}
