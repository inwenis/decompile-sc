#Requires -Version 7
<#
.SYNOPSIS
Close a running StarCraft process politely (WM_CLOSE), then verify it is gone.

.DESCRIPTION
Never leave a game process running. WM_CLOSE rather than Stop-Process: the plugin un-splices its
hooks and writes its closing STATS line on DLL_PROCESS_DETACH, and a killed process runs neither.
A timeout falls back to Stop-Process and says so, so a silent kill cannot read as a clean shutdown.
AGENTS.md § "Stopping a run / orphaned games".

.EXAMPLE
./tools/plugin/close-game.ps1 -ProcessId 1234
#>
[CmdletBinding()]
param(
    [int]$ProcessId = 0,
    [int]$TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'

if (-not ('SCClose.Native' -as [type])) {
    Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace SCClose {
  public static class Native {
    private delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] private static extern int GetClassNameA(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] private static extern bool PostMessageA(IntPtr h, uint msg, IntPtr w, IntPtr l);

    public static int CloseTopLevel(uint want) {
      var targets = new List<IntPtr>();
      EnumWindows((h, p) => {
        uint pid; GetWindowThreadProcessId(h, out pid);
        if (pid == want) targets.Add(h);
        return true;
      }, IntPtr.Zero);
      foreach (var h in targets) PostMessageA(h, 0x0010 /*WM_CLOSE*/, IntPtr.Zero, IntPtr.Zero);
      return targets.Count;
    }
  }
}
"@
}

if ($ProcessId -eq 0) {
    $procs = @(Get-Process StarCraft -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { Write-Host 'close-game: no StarCraft process running'; exit 0 }
    if ($procs.Count -gt 1) { throw "close-game: $($procs.Count) StarCraft processes running; pass -ProcessId." }
    $ProcessId = $procs[0].Id
}

$proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if (-not $proc) { Write-Host "close-game: pid $ProcessId is not running"; exit 0 }

$n = [SCClose.Native]::CloseTopLevel([uint32]$ProcessId)
Write-Host "close-game: posted WM_CLOSE to $n window(s) of pid $ProcessId"

if ($proc.WaitForExit($TimeoutSec * 1000)) {
    Write-Host "close-game: pid $ProcessId exited cleanly (DLL_PROCESS_DETACH ran)"
    exit 0
}

Write-Warning "close-game: pid $ProcessId did not exit within ${TimeoutSec}s — falling back to Stop-Process. The plugin's detach path did NOT run, so the log has no DETACH/STATS line for this run."
Stop-Process -Id $ProcessId -Force
Start-Sleep -Milliseconds 500
if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
    throw "close-game: pid $ProcessId is STILL running after Stop-Process."
}
Write-Host "close-game: pid $ProcessId terminated"
exit 0
