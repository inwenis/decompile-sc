#Requires -Version 7
<#
.SYNOPSIS
Record the foreground window before the launch steals it, and hand it back afterwards.
.DESCRIPTION
StarCraft activates its own window when it creates it and nothing hands the foreground back;
on an idle desktop, where nothing else asks for it, it held the foreground for a measured 72s
-- a whole run. That also poisons the borrow in Send-ScDropdownPick, which hands the
foreground back to whatever held it (AGENTS.md § "Foreground").

Its own file because run-with-plugin.ps1 is copied into the deploy tree and must work with no
repo present, while drive-game.ps1 -- owner of the equivalent MakeForeground -- is the whole
input machinery a launch has no business loading; deploy-runtime.Tests.ps1 fails if one of
run-with-plugin.ps1's dependencies is missing from deploy.ps1's copy list. Callers restore
only under $env:AGENT_TASK, and never when $env:SCDRIVE_RAISE=1: a human who launched or is
watching the game wants to see it.
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
    A recorded handle that is already a game window must NOT be restored: that would raise
    another worker's run (see Restore-ScForeground).
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
    Cosmetic: the launch has already succeeded by the time this runs, so a window that has
    since closed, or a shell that refuses to give the foreground up, must not fail a good
    launch. Retried because the race is real -- the game keeps re-activating its own window
    for a second or so after creating it under the windowed-mode helper, and a single
    SetForegroundWindow issued into the middle of that gets undone.

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
