#Requires -Version 7
<#
.SYNOPSIS
Measures whether a DirectDraw EXCLUSIVE|FULLSCREEN mode switch made on an
INVISIBLE desktop leaves the user's real desktop untouched -- the open question
in research/renderer-viewport.md 12.10, and the gate on true fullscreen as a test vehicle.
.DESCRIPTION
Per-desktop or per-adapter is unknown, so a child launches the game off-screen
while this parent samples the VISIBLE desktop's mode every 250 ms.
SAFETY. The only display write this probe can make is ChangeDisplaySettings(NULL)
-- re-apply the registry mode -- and only once a sample shows the real desktop
already changed. A leak can rearrange desktop icons, which are live user state
(AGENTS.md § "Hard rules"), so the restore runs the instant the child exits.
.EXAMPLE
./tools/plugin/probe-fullscreen-desktop.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\decompile-sc-data\sc-work\1161-base',
    [string]$LogDir = 'C:\decompile-sc-data\sc-work\logs',
    [int]$HoldSec = 20,
    [int]$TimeoutMinutes = 6
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

if (-not ('ScFsProbe.Native' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

namespace ScFsProbe {
  public static class Native {
    // DEVMODEA, ANSI, fixed offsets (winuser.h): dmSize @36, dmBitsPerPel @104,
    // dmPelsWidth @108, dmPelsHeight @112, dmDisplayFrequency @120.
    [StructLayout(LayoutKind.Explicit, Size=156, CharSet=CharSet.Ansi)]
    public struct DEVMODEA {
      [FieldOffset(36)]  public ushort dmSize;
      [FieldOffset(104)] public uint dmBitsPerPel;
      [FieldOffset(108)] public uint dmPelsWidth;
      [FieldOffset(112)] public uint dmPelsHeight;
      [FieldOffset(120)] public uint dmDisplayFrequency;
    }

    [DllImport("user32.dll", CharSet=CharSet.Ansi)]
    private static extern bool EnumDisplaySettingsA(string device, int mode, ref DEVMODEA dm);
    [DllImport("user32.dll")]
    private static extern int ChangeDisplaySettingsA(IntPtr dm, uint flags);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);

    // The mode of the primary display as one comparable string.
    public static string CurrentMode() {
      var dm = new DEVMODEA();
      dm.dmSize = 156;
      if (!EnumDisplaySettingsA(null, -1 /*ENUM_CURRENT_SETTINGS*/, ref dm)) return "enum-failed";
      return dm.dmPelsWidth + "x" + dm.dmPelsHeight + "x" + dm.dmBitsPerPel + "@" + dm.dmDisplayFrequency;
    }

    // Re-apply the REGISTRY mode -- restores whatever the user had, writes nothing new.
    public static int RestoreRegistryMode() { return ChangeDisplaySettingsA(IntPtr.Zero, 0); }
  }
}
'@
}

function Get-RealDesktopMode {
    # GetSystemMetrics beside EnumDisplaySettings: two independent readers of the
    # same fact, so a stale cache in one cannot silently pass for "no change".
    "$([ScFsProbe.Native]::CurrentMode()) sm=$([ScFsProbe.Native]::GetSystemMetrics(0))x$([ScFsProbe.Native]::GetSystemMetrics(1))"
}

$launchLock = $null
$runOut = Join-Path $LogDir '063-fullscreen-offscreen.txt'
$failures = 0
$modeEvents = @()
$childProc = $null

try {
    Write-Host 'probe-fullscreen: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '063-fullscreen'

    # A leftover ddraw.dll shim forces windowed mode, leaving nothing to measure.
    # Removal runs under the launch lock that serialises the shared game dir.
    if (Test-Path -LiteralPath (Join-Path $GameDir 'ddraw.dll')) {
        Write-Host 'probe-fullscreen: removing a leftover ddraw.dll shim (would force windowed mode)'
        & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch -NoLaunchLock -GameDir $GameDir | Write-Host
    }

    $baseline = Get-RealDesktopMode
    Write-Host "probe-fullscreen: REAL desktop baseline mode: $baseline"

    # Started async so this side keeps sampling the real desktop while
    # run-offscreen owns the invisible desktop's whole life cycle.
    $childArgs = @('-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass',
                   '-File', (Join-Path $scriptDir 'run-offscreen.ps1'),
                   '-Suite', (Join-Path $scriptDir 'probe-fullscreen-desktop-child.ps1'),
                   '-TimeoutMinutes', "$TimeoutMinutes")
    $childProc = Start-Process pwsh -ArgumentList $childArgs -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $runOut -RedirectStandardError (Join-Path $LogDir '063-fullscreen-offscreen.err.txt')
    Write-Host "probe-fullscreen: off-screen run started (pid $($childProc.Id)); sampling the REAL desktop mode every 250 ms"

    $last = $baseline
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes + 1)
    while (-not $childProc.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $now = Get-RealDesktopMode
        if ($now -ne $last) {
            $ev = "$(Get-Date -Format 'HH:mm:ss.fff') $last -> $now"
            $modeEvents += $ev
            Write-Host "probe-fullscreen: REAL DESKTOP MODE CHANGED: $ev"
            $last = $now
        }
    }
    if (-not $childProc.HasExited) {
        Write-Warning 'probe-fullscreen: off-screen run exceeded its timeout; killing it (its teardown may not have run)'
        $childProc.Kill()
    }

    $final = Get-RealDesktopMode
    if ($final -ne $baseline) {
        Write-Host "probe-fullscreen: the run ENDED with the real desktop in a changed mode ($final); re-applying the registry mode"
        $rc = [ScFsProbe.Native]::RestoreRegistryMode()
        Start-Sleep -Seconds 2
        Write-Host "probe-fullscreen: ChangeDisplaySettings(NULL) -> $rc; mode now $(Get-RealDesktopMode)"
    }

    $transcript = (Test-Path -LiteralPath $runOut) ? (Get-Content -LiteralPath $runOut) : @()
    Write-Host ''
    Write-Host 'probe-fullscreen: off-screen transcript (child lines):'
    $childLines = @($transcript | Where-Object { $_ -match 'CHILD |class=|run-offscreen' })
    $childLines | ForEach-Object { Write-Host "       $_" }

    $childPid = 0
    if (($transcript -join "`n") -match 'CHILD pid=(\d+)') { $childPid = [int]$Matches[1] }
    $unhealthy = ($transcript -join "`n") -match 'CHILD unhealthy='
    $gameCameUp = $childPid -gt 0 -and -not $unhealthy
    $childRan = ($transcript -join "`n") -match 'CHILD done=1'

    Write-Host ''
    Write-Host 'probe-fullscreen: verdict'
    if (-not $childRan) {
        Write-Host '  the off-screen child never completed -- NO verdict; read the transcript before believing anything above'
        $failures++
    }
    Write-Host "  real desktop mode changes observed while the child ran: $($modeEvents.Count)"
    $modeEvents | ForEach-Object { Write-Host "    $_" }
    Write-Host "  game process: $(if ($childPid) { "pid $childPid" } else { 'NEVER SEEN' }); healthy launch: $gameCameUp"

    if ($childRan -and $modeEvents.Count -eq 0 -and $gameCameUp) {
        Write-Host '  => CONTAINED: the game ran fullscreen on the invisible desktop and the real desktop mode never moved.'
    }
    elseif ($childRan -and $modeEvents.Count -eq 0) {
        Write-Host '  => REFUSED: the launch did not come up healthy off-screen, and the real desktop never moved.'
        Write-Host '     Exclusive fullscreen is not grantable off the input desktop; it cannot be exercised invisibly.'
    }
    elseif ($modeEvents.Count -gt 0) {
        Write-Host '  => LEAKED: the mode switch is PER-ADAPTER. A fullscreen launch touches the user''s real screen'
        Write-Host '     from ANY desktop, so true fullscreen is disqualified as an unattended test vehicle.'
        $failures++   # not a probe failure logically, but loud is right: user state was touched
    }
}
catch {
    Write-Host "  FAIL probe: $($_.Exception.Message)"
    $failures++
}
finally {
    # Stop only the pid the child recorded, never a game matched by name: the
    # user's own play takes no launch lock and a name match would hit it
    # (AGENTS.md § "Stopping a run / orphaned games").
    $t = (Test-Path -LiteralPath $runOut) ? (Get-Content -LiteralPath $runOut -Raw) : ''
    if ($t -match 'CHILD pid=(\d+)' -and [int]$Matches[1] -gt 0) {
        $orphan = [int]$Matches[1]
        if ($t -notmatch 'CHILD closed=1' -and (Get-Process -Id $orphan -ErrorAction SilentlyContinue)) {
            Write-Warning "probe-fullscreen: the child did not close its game (pid $orphan, launched by this probe under this lock); stopping it directly. Its desktop is gone, so WM_CLOSE cannot reach it and the plugin's detach line will be missing."
            Stop-Process -Id $orphan -Force -ErrorAction SilentlyContinue
        }
    }
    if ($launchLock) { try { Exit-ScLaunchLock -Lock $launchLock } catch { } }
}

Write-Host ''
if ($failures -eq 0) { Write-Host 'probe-fullscreen: PASS (0 failures)' }
else { Write-Host "probe-fullscreen: FAIL ($failures failures)" }
exit ($failures -gt 0 ? 1 : 0)
