#Requires -Version 7
<#
.SYNOPSIS
Measure what the game actually needs the FOREGROUND for -- input, or drawing.

.DESCRIPTION
Ghidra, StarCraft.exe FUN_004d1d70: the WM_MOUSEMOVE case records the "moved" bit and x/y
clamped to 0x27f/0x1df with no foreground and no active check, and the binary's only
GetForegroundWindow call site (0x004eddf0) is a diagnostic, so a posted move should land while
the window sits in the background. Activation gates DRAWING instead -- 0x0041d710 returns 0
while DAT_0051bfa8 is 0, a global the window procedure writes from its WM_ACTIVATEAPP case
(0x1c) -- so a frame oracle cannot tell a lost move from an undrawn one. E1 separates the two
by raising the window only for the read-back; E2, with foreground control E3, measures the
freeze itself.

Working copy only, offline, single-player, commits nothing; the frames it saves are
diagnostics outside the repo (AGENTS.md § "Hard rules").

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

# The foreground owner before launch is the user's own window, and losing it is the bug
# under study; GetForegroundWindow() around every step keeps "did not steal focus" a
# measurement rather than a claim.
$victim = Fg
Write-Host ("[0] foreground before launch: hwnd=0x{0:X}" -f [int64]$victim)

function Restore-Victim {
    # Hand the foreground back the same way the harness takes it (AGENTS.md § "Foreground").
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

# Single Player on the main menu, client coordinates at 640x480 (the point every suite
# clicks), boxed wide enough to hold the highlight and the game's own drawn cursor.
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
