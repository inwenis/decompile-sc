#Requires -Version 7
<#
.SYNOPSIS
Sample the foreground window while something else runs, and report whether the game ever
took it. This is how "the test run did not steal focus" is measured rather than claimed.

.DESCRIPTION
Run this in one shell, the suite in another. Watching GetForegroundWindow() for the whole
run is the only honest evidence for AGENTS.md § "Foreground": a run must complete without
the game taking foreground or input focus from the user's active window. Output is one line
per CHANGE, so a quiet run is a single baseline line; exit 1 if a StarCraft window was ever
foreground, so this gates a run rather than only logging it.

.EXAMPLE
./tools/plugin/watch-foreground.ps1 -Seconds 900
#>
[CmdletBinding()]
param(
    [int]$Seconds = 600,
    [int]$PollMs = 250
)

$ErrorActionPreference = 'Stop'

if (-not ('ScWatch.Native' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace ScWatch {
  public static class Native {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    public static string TitleOf(IntPtr h) { var sb = new StringBuilder(512); GetWindowTextW(h, sb, 512); return sb.ToString(); }
  }
}
"@
}

$deadline = (Get-Date).AddSeconds($Seconds)
$last = [IntPtr]::Zero
$stolen = $false

Write-Host "watch-foreground: sampling every ${PollMs}ms for ${Seconds}s. One line per change."
while ((Get-Date) -lt $deadline) {
    $h = [ScWatch.Native]::GetForegroundWindow()
    if ($h -ne $last) {
        $last = $h
        $pid2 = 0
        [void][ScWatch.Native]::GetWindowThreadProcessId($h, [ref]$pid2)
        $proc = try { (Get-Process -Id $pid2 -ErrorAction Stop).ProcessName } catch { '?' }
        $title = [ScWatch.Native]::TitleOf($h)
        $flag = ''
        if ($proc -like 'StarCraft*') { $stolen = $true; $flag = '   <-- THE GAME TOOK THE FOREGROUND' }
        Write-Host ("{0:HH:mm:ss}  hwnd=0x{1:X8} pid={2} proc={3} title='{4}'{5}" -f (Get-Date), [int64]$h, $pid2, $proc, $title, $flag)
    }
    Start-Sleep -Milliseconds $PollMs
}

if ($stolen) { Write-Host 'watch-foreground: FAIL -- the game held the foreground at least once.'; exit 1 }
Write-Host 'watch-foreground: OK -- no StarCraft window was ever foreground during the watch.'
exit 0
