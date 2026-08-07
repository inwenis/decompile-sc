#Requires -Version 7
<#
.SYNOPSIS
Enumerate the top-level windows owned by a StarCraft process and flag modal error
dialogs.

.DESCRIPTION
A failed launch does not always look like a failed launch: StarCraft can put up a
modal DirectDraw error dialog and keep the process alive, so an exit code of 0 and
a live process both say "fine" while a message box sits on the user's screen. This
script checks from OUTSIDE the process, which is the only place that failure is
visible to an automated run.

Window class '#32770' is the standard Win32 dialog class; any visible window of that
class belonging to the game is treated as an error dialog and makes this script exit
non-zero.

.PARAMETER ProcessId
Process to inspect. Defaults to the single running StarCraft process.

.EXAMPLE
./tools/plugin/check-game-windows.ps1
#>
[CmdletBinding()]
param(
    [int]$ProcessId = 0,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

if (-not ('SCWin.Enum' -as [type])) {
    Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace SCWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

  public class WinInfo {
    public IntPtr Handle; public uint Pid; public string ClassName; public string Title;
    public bool Visible; public int L, T, R, B; public int Style;
  }

  public static class Enum {
    private delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] private static extern int GetClassNameA(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] private static extern int GetWindowTextA(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] private static extern int GetWindowLongA(IntPtr h, int i);

    public static List<WinInfo> ForPid(uint want) {
      var list = new List<WinInfo>();
      EnumWindows((h, p) => {
        uint pid; GetWindowThreadProcessId(h, out pid);
        if (pid != want) return true;
        var cls = new StringBuilder(256); GetClassNameA(h, cls, 256);
        var txt = new StringBuilder(512); GetWindowTextA(h, txt, 512);
        RECT r; GetWindowRect(h, out r);
        list.Add(new WinInfo {
          Handle = h, Pid = pid, ClassName = cls.ToString(), Title = txt.ToString(),
          Visible = IsWindowVisible(h), L = r.L, T = r.T, R = r.R, B = r.B,
          Style = GetWindowLongA(h, -16)
        });
        return true;
      }, IntPtr.Zero);
      return list;
    }
  }
}
"@
}

if ($ProcessId -eq 0) {
    $procs = @(Get-Process StarCraft -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { Write-Host 'check-game-windows: no StarCraft process running'; exit 3 }
    if ($procs.Count -gt 1) { throw "check-game-windows: $($procs.Count) StarCraft processes running; pass -ProcessId." }
    $ProcessId = $procs[0].Id
}

$wins = [SCWin.Enum]::ForPid([uint32]$ProcessId)
if (-not $Quiet) {
    Write-Host "check-game-windows: pid=$ProcessId  top-level windows=$($wins.Count)"
    foreach ($w in $wins) {
        Write-Host ("  hwnd=0x{0:X8} class='{1}' visible={2} rect={3},{4}-{5},{6} style=0x{7:X8} title='{8}'" -f `
            [int64]$w.Handle, $w.ClassName, $w.Visible, $w.L, $w.T, $w.R, $w.B, $w.Style, $w.Title)
    }
}

$dialogs = @($wins | Where-Object { $_.ClassName -eq '#32770' -and $_.Visible })
if ($dialogs.Count -gt 0) {
    Write-Host ''
    Write-Host "check-game-windows: FAIL — $($dialogs.Count) modal dialog(s) open. The launch is NOT healthy:"
    foreach ($d in $dialogs) { Write-Host ("  DIALOG '{0}' at {1},{2}-{3},{4}" -f $d.Title, $d.L, $d.T, $d.R, $d.B) }
    exit 1
}

$minimized = @($wins | Where-Object { ($_.Style -band 0x20000000) -ne 0 })
if (-not $Quiet -and $minimized.Count -gt 0) {
    Write-Host "check-game-windows: note — $($minimized.Count) window(s) minimized (WS_MINIMIZE); restore before screenshotting."
}

Write-Host 'check-game-windows: OK — no error dialogs'
exit 0
