#Requires -Version 7
<#
.SYNOPSIS
Measure what the game actually needs the FOREGROUND for -- input, or drawing.

.DESCRIPTION
Task 027. The harness raises the game window on every posted mouse move
(`Assert-ScWindowActive`), which steals the user's focus on every unattended run.
Task 022 established the rule empirically ("posted WM_MOUSEMOVE is IGNORED while the
window is not foreground") from FRAMES -- and frames are also the thing that stops
updating when a window is not the active app.

Static analysis of the window procedure (task 027, Ghidra, StarCraft.exe FUN_004d1d70)
says the INPUT half of that rule should not be true:

    case 0x200:                                  /* WM_MOUSEMOVE */
      DAT_006cddc0 |= 1;                         /* "the mouse moved" bit */
      _DAT_006cddc4 = lParam & 0xffff;           /* x, clamped to 0x27f */
      _DAT_006cddc8 = lParam >> 16;              /* y, clamped to 0x1df */
      return 1;

-- no foreground check and no active check on the mouse path (the binary's only
GetForegroundWindow call site, 0x004eddf0, is a diagnostic). What IS gated on
activation is DRAWING: 0x0041d710 returns 0 -- do not draw -- while `DAT_0051bfa8` is
0, and that global is written by the window procedure's WM_ACTIVATEAPP case
(`case 0x1c: DAT_0051bfa8 = wParam`).

Two competing explanations for task 022's measurement, with very different fixes:

  H1  a posted move never reaches the game's state while the window is in the
      background -> the raise is load-bearing for INPUT;
  H2  the move IS recorded, but the game stops rendering while it is not the active
      app, so a frame-based oracle cannot see it -> the raise is only needed where the
      HARNESS reads the screen.

This separates them at the MAIN MENU, in one short launch, without walking any menus:

  E1  park the game's cursor away from the Single Player button with the window
      foreground and fingerprint that button. Hand the foreground back to the user's
      window, post a move ONTO the button, then raise and fingerprint again. The
      button highlights under the game's cursor, so:
        - changed after the raise  -> the background move WAS recorded (H2)
        - unchanged                -> the background move was lost (H1)
      The middle sample (taken while still in the background) says whether the game
      also DREW it while inactive.

  E2  fingerprint the whole window twice, three seconds apart, with the window in the
      background. The main menu animates, so identical fingerprints mean rendering is
      frozen while inactive -- which is exactly what makes a frame oracle lie.

The focus oracle is the same one the fix will use: GetForegroundWindow(), sampled
around every step, so "did not steal focus" is a measurement and not a claim.

Hard rules: working copy only, offline, single-player, commits nothing. Frames are
diagnostics on the gitignored path.

.EXAMPLE
./tools/plugin/probe-quiet-input.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\027-probe-quiet.log',
    [string]$ShotDir = 'C:\sc-work\logs\027-probe-frames',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$step = 0
function Note([string]$m) { Write-Host "       $m" }
function Fg { [ScDrive.Native]::GetForegroundWindow() }

# The window that owned the foreground before we touched anything -- the user's own
# window, and the thing whose loss IS the bug this task exists to fix.
$victim = Fg
Write-Host ("[0] foreground before launch: hwnd=0x{0:X}" -f [int64]$victim)

function Restore-Victim {
    # Hand the foreground back to whatever had it, with the same documented dance the
    # harness uses to take it. Returns the resulting foreground handle.
    if ($victim -ne [IntPtr]::Zero) { [void][ScDrive.Native]::MakeForeground($victim) }
    Start-Sleep -Milliseconds 500
    Fg
}

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

# The Single Player button on the main menu, client coordinates at 640x480 (the same
# point every suite clicks), and a box around it big enough to hold the highlight and
# the game's own drawn cursor.
$BTN    = @{ X = 215; Y = 119 }
$BTNBOX = @{ X = 150; Y = 100; Width = 160; Height = 40 }
$PARK   = @{ X = 590; Y = 450 }   # far from the button, still inside the client area

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

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
    Start-Sleep -Seconds 3
    Shot 'main-menu'

    Step 'E1 is a background posted MOVE recorded, or lost?' {
        Assert-ScWindowActive -Hwnd $hwnd -Because 'parking the cursor for E1'
        Send-ScMouseMove -Hwnd $hwnd @PARK -NoActivate
        Start-Sleep -Milliseconds 800
        $parked = Get-ScRegionFingerprint -Hwnd $hwnd @BTNBOX
        Shot 'E1-parked'

        $fg = Restore-Victim
        Note ("foreground handed back: 0x{0:X} (game is 0x{1:X}); user's window has it: {2}" -f `
              [int64]$fg, [int64]$hwnd, ($fg -eq $victim))
        if ($fg -eq $hwnd) { throw 'probe: could not hand the foreground back; E1 would measure nothing.' }

        Send-ScMouseMove -Hwnd $hwnd @BTN -NoActivate
        Start-Sleep -Milliseconds 800
        $bg = Get-ScRegionFingerprint -Hwnd $hwnd @BTNBOX
        $fgAfterPost = Fg
        Note ("foreground after posting the move: 0x{0:X} (unchanged: {1})" -f `
              [int64]$fgAfterPost, ($fgAfterPost -eq $fg))

        Assert-ScWindowActive -Hwnd $hwnd -Because 'reading back the E1 result'
        Start-Sleep -Milliseconds 900
        $raised = Get-ScRegionFingerprint -Hwnd $hwnd @BTNBOX
        Shot 'E1-after-raise'

        Note "button region: parked=$parked  after-background-move=$bg  after-raise=$raised"
        Note ('VERDICT: {0}' -f $(
            if ($raised -ne $parked -and $bg -eq $parked) { 'H2 -- the background move WAS recorded, it just was not DRAWN until the raise' }
            elseif ($raised -ne $parked -and $bg -ne $parked) { 'the background move was recorded AND drawn while inactive' }
            else { 'H1 -- the background move left no trace at all' }))
    }

    Step 'E2 does the game draw while it is not the active app?' {
        $fg = Restore-Victim
        if ($fg -eq $hwnd) { throw 'probe: could not hand the foreground back; E2 would measure nothing.' }
        $whole = @{ X = 0; Y = 0; Width = 640; Height = 400 }
        $f1 = Get-ScRegionFingerprint -Hwnd $hwnd @whole
        Start-Sleep -Seconds 3
        $f2 = Get-ScRegionFingerprint -Hwnd $hwnd @whole
        Note "background frames, 3s apart on the animated main menu: $f1 / $f2"
        Note ('VERDICT: rendering while inactive is {0}' -f $(if ($f1 -eq $f2) { 'FROZEN -- a frame oracle cannot be trusted in the background' } else { 'LIVE' }))
    }

    Step 'E3 control: the same two frames with the game foreground' {
        Assert-ScWindowActive -Hwnd $hwnd -Because 'the E3 control'
        Start-Sleep -Milliseconds 500
        $whole = @{ X = 0; Y = 0; Width = 640; Height = 400 }
        $f1 = Get-ScRegionFingerprint -Hwnd $hwnd @whole
        Start-Sleep -Seconds 3
        $f2 = Get-ScRegionFingerprint -Hwnd $hwnd @whole
        Note "foreground frames, 3s apart: $f1 / $f2"
        Note ('VERDICT: the animation oracle {0}' -f $(if ($f1 -ne $f2) { 'fires with the window foreground, so E2 means what it says' } else { 'DOES NOT FIRE even in the foreground -- E2 is inconclusive' }))
    }

    Write-Host ''
    Write-Host 'probe: done.'
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid
    }
}
