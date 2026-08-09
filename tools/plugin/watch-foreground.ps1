#Requires -Version 7
<#
.SYNOPSIS
Sample the foreground window while something else runs, and report whether the game ever
took it. This is how "the test run did not steal focus" is measured rather than claimed.

.DESCRIPTION
Task 027. The acceptance bar for that task is "an in-game test run completes WITHOUT the
game window taking foreground or input focus from the user's active window", and the only
honest way to say that is to watch GetForegroundWindow() for the whole run.

Run this in one shell, the suite in another. It prints one line per CHANGE of foreground
window (not per sample), so a quiet run prints one baseline line and nothing else, and any
steal is a line naming the process that took it.

Exit code: 0 if no window belonging to a StarCraft process was ever foreground, 1 if one
was -- so it can be used as a gate and not only as a log.

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
