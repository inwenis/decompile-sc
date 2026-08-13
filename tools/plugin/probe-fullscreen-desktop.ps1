#Requires -Version 7
<#
.SYNOPSIS
Task 063. Measures whether a DirectDraw EXCLUSIVE|FULLSCREEN mode switch, made by
a game on an INVISIBLE desktop, leaves the user's real desktop untouched -- the
question research/renderer-viewport.md 12.10 and task 063's route (2).1 need
answered before true fullscreen can even be considered as a TEST vehicle.

.DESCRIPTION
Whether a fullscreen mode switch is per-desktop or per-adapter is UNKNOWN and
this probe measures it rather than assumes it (task 063's own instruction). The
blast radius argument: a `CreateDesktop` object is not the user's desktop, so if
the switch is contained there, nobody sees it; if it is per-adapter, the real
monitor changes mode -- which is why this probe WATCHES the real desktop the
whole time and restores the registry mode the moment the run ends wrong.

Two halves, running concurrently:

  child   (probe-fullscreen-desktop-child.ps1, via run-offscreen.ps1) launches
          the game with NO windowed helper on an invisible desktop -- the stock
          DirectDraw path: SetCooperativeLevel(EXCLUSIVE|FULLSCREEN),
          SetDisplayMode(640,480,8), engine fallback on failure. Holds ~20 s,
          reports the game's window inventory from that desktop, closes it.

  parent  (this script) samples the VISIBLE desktop's current display mode
          (EnumDisplaySettings ENUM_CURRENT_SETTINGS + GetSystemMetrics) every
          250 ms from before the launch to after the close, and logs every
          change with a timestamp.

Verdicts this separates, structurally:

  CONTAINED  the game came up (or its window exists) and the real desktop's
             mode never moved -- the switch (or its refusal) stayed on the
             invisible desktop. True fullscreen might be usable as a TEST
             vehicle; whether the game is actually presentable there is a
             separate question the window inventory begins to answer.
  LEAKED     the real desktop's mode changed while the child ran: the switch
             is per-adapter. True fullscreen touches the user's screen from
             ANY desktop and is disqualified as an unattended test vehicle.
             The probe restores the registry mode and says so loudly.
  REFUSED    the game never got a fullscreen surface (DirectDraw error box /
             unhealthy launch) and the mode never moved: exclusive mode is
             not grantable off the input desktop. Same practical consequence
             as LEAKED for testing -- fullscreen cannot be exercised
             invisibly -- but by refusal rather than by leak.

SAFETY. This probe itself never calls SetDisplayMode / ChangeDisplaySettings to
CHANGE anything; the one write it can ever make is ChangeDisplaySettings(NULL)
-- "re-apply the registry mode" -- and only on the path where the child's run
demonstrably left the real desktop in a changed mode. Icon layout is live user
state that a real leak may damage (hard rule 5's icon-rearrangement warning);
that risk exists for the LEAKED outcome only, lasts seconds, and is the reason
the sample loop restores the moment the child exits rather than at leisure.

.EXAMPLE
./tools/plugin/probe-fullscreen-desktop.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
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

    # A leftover ddraw.dll shim would put this launch in windowed mode and the
    # probe would measure nothing. Removing it is the documented recipe and it
    # happens under the lock that serialises the shared game dir.
    if (Test-Path -LiteralPath (Join-Path $GameDir 'ddraw.dll')) {
        Write-Host 'probe-fullscreen: removing a leftover ddraw.dll shim (would force windowed mode)'
        & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch -NoLaunchLock -GameDir $GameDir | Write-Host
    }

    $baseline = Get-RealDesktopMode
    Write-Host "probe-fullscreen: REAL desktop baseline mode: $baseline"

    # The child, via run-offscreen (which creates the invisible desktop, births
    # the run on it, tails its transcript into $runOut and tears the desktop
    # down afterwards). Started async so this side can sample while it runs.
    $childArgs = @('-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass',
                   '-File', (Join-Path $scriptDir 'run-offscreen.ps1'),
                   '-Suite', (Join-Path $scriptDir 'probe-fullscreen-desktop-child.ps1'),
                   '-TimeoutMinutes', "$TimeoutMinutes")
    $childProc = Start-Process pwsh -ArgumentList $childArgs -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $runOut -RedirectStandardError (Join-Path $LogDir '063-fullscreen-offscreen.err.txt')
    Write-Host "probe-fullscreen: off-screen run started (pid $($childProc.Id)); sampling the REAL desktop mode every 250 ms"

    # ---- the measurement ---------------------------------------------------
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

    # ---- what the child saw ------------------------------------------------
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

    # ---- verdict -----------------------------------------------------------
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
    # The one process this probe launched is the child's game. If it survived
    # (child died mid-run), its desktop may already be gone, so WM_CLOSE from
    # here cannot reach it -- say so and stop the process, with the pid taken
    # from the child's own transcript, never by name alone.
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
