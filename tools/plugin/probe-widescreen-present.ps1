#Requires -Version 7
<#
.SYNOPSIS
Task 034. Answers the one question a read-back cannot: does the windowed-mode
helper actually PRESENT the extra columns the engine composes, or only the
left 640 of them?

.DESCRIPTION
tools/plugin/test-widescreen.ps1 proves the ENGINE composes an 800x480 frame and
draws an 800x400 playfield into it -- read straight out of the running process.
It cannot prove anybody sees that, because what reaches the monitor goes through
`WMode.dll`, which is packed (research/launch-baseline.md) and whose behaviour at
a non-640x480 mode research/renderer-viewport.md 10 item 2 records as UNMEASURED.

There are two ways this repo runs that helper and they are NOT the same vector:

  inject   scinject --early-dll WMode.dll   (what every suite uses)
  ddraw    WMode.dll copied in as ddraw.dll (research/launch-baseline.md's recipe)

This probe measures both, in a widescreen arm and a stock arm, and decides
between three outcomes STRUCTURALLY -- by comparing frames, never by looking at
one:

  CROP    the helper shows columns 0..639 of an 800-wide frame. Then the HUD band
          is pixel-identical between the arms, because the console really is at
          the same place in both framebuffers, and the extra columns are composed
          and thrown away.
  SCALE   the helper shows all 800 columns squeezed into its window. Then the HUD
          band is NOT identical -- every HUD pixel has moved to 0.8x its x -- and
          the frame's rightmost non-black column tells the ratio.
  FOLLOW  the helper's client area is itself 800 wide. Then the feature is simply
          visible, and there is nothing to decide.

WHY THIS IS ALLOWED TO TOUCH FRAMES AT ALL. It never commits one and never puts
one through `pr-image` -- a game frame reproduces game artwork and hard rule 1
forbids that (AGENTS.md "Screenshots vs hard rule 1"). It writes to the
gitignored diagnostic path, and what it REPORTS is a count of matching pixels and
a column index, which reproduce nothing. Save-ScWindowImage refuses to write
inside the repo, so that is enforced rather than remembered.

.EXAMPLE
./tools/plugin/probe-widescreen-present.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    [string]$FrameDir = 'C:\sc-work\logs\034-frames',
    [ValidateSet('inject', 'ddraw', 'both')][string]$Vector = 'both',
    # Which 9.3 stage to run under. Stage 0 is the interesting one for THIS
    # question: it changes the display mode and nothing else, so a failure is
    # unambiguously the presentation half rather than anything the engine draws.
    [ValidateSet('0', '1', '2')][string]$Stage = '2',
    # A launch that ends in a DirectDraw error box is a RESULT here, not a crash:
    # "the helper will not take this mode" is exactly what this probe measures. So
    # the unhealthy-launch throw is caught per arm instead of ending the run.
    [switch]$StopOnUnhealthy
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null

$launchLock = $null
$frames = @{}
$windows = @{}
$script:results = @{}

# Sampled every 2nd pixel: the question is "are these the same image or a rescaled
# one", and that is not a subtle difference. A full compare costs 4x for no answer.
function Get-BandMatch {
    param([string]$A, [string]$B, [int]$Y0, [int]$Y1)
    $p = [System.Drawing.Bitmap]::new($A)
    $q = [System.Drawing.Bitmap]::new($B)
    try {
        $w = [math]::Min($p.Width, $q.Width)
        $y1 = [math]::Min($Y1, [math]::Min($p.Height, $q.Height))
        $same = 0; $n = 0
        for ($y = $Y0; $y -lt $y1; $y += 2) {
            for ($x = 0; $x -lt $w; $x += 2) {
                $n++
                if ($p.GetPixel($x, $y).ToArgb() -eq $q.GetPixel($x, $y).ToArgb()) { $same++ }
            }
        }
        [pscustomobject]@{ Same = $same; N = $n; Pct = ($n ? [math]::Round(100 * $same / $n, 1) : 0) }
    }
    finally { $p.Dispose(); $q.Dispose() }
}

# The rightmost column that is not pure black, as a fraction of the width. If the
# helper scaled an 800-wide frame into a 640-wide window, the stock 640-wide menu
# art inside it stops at 80% of the way across and the rest is black.
function Get-ContentRightEdge {
    param([string]$Path)
    $p = [System.Drawing.Bitmap]::new($Path)
    try {
        $black = ([System.Drawing.Color]::FromArgb(255, 0, 0, 0)).ToArgb()
        for ($x = $p.Width - 1; $x -ge 0; --$x) {
            for ($y = 0; $y -lt $p.Height; $y += 4) {
                if ($p.GetPixel($x, $y).ToArgb() -ne $black) {
                    return [pscustomobject]@{ Edge = $x; Width = $p.Width
                                              Pct = [math]::Round(100 * ($x + 1) / $p.Width, 1) }
                }
            }
        }
        [pscustomobject]@{ Edge = -1; Width = $p.Width; Pct = 0 }
    }
    finally { $p.Dispose() }
}

function Invoke-PresentArm {
    param([string]$Vec, [string]$Widescreen)

    $name = "$Vec-ws$Widescreen"
    $log = Join-Path $LogDir "034-present-$name.log"
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $gamePid = 0
    $winW = 0; $winH = 0

    $launchArgs = @{
        Mode = 'hooktest'; ScreenScan = '1'; NoLaunchLock = $true
        Widescreen = $Widescreen; WidescreenStage = $Stage
        GameDir = $GameDir; LogPath = $log
    }
    if ($Vec -eq 'inject') { $launchArgs['InjectWindowedHelper'] = 'WMode' }
    else { $launchArgs['Windowed'] = $true }

    Write-Host ''
    Write-Host "probe-present: vector=$Vec widescreen=$Widescreen stage=$Stage"
    $unhealthy = $null
    try {
        & (Join-Path $scriptDir 'run-with-plugin.ps1') @launchArgs 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
        if (-not $gamePid) { throw "probe-present: no pid for $name" }
        # research/launch-baseline.md: as a ddraw proxy the window comes up MINIMISED
        # at the off-screen sentinel. Restoring it is the documented recipe, and it is
        # the one place this probe raises anything -- a minimised window has no client
        # area to capture at all.
        $h = Get-ScGameWindow -ProcessId $gamePid
        Set-ScWindowActive -Hwnd $h -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 4

        # The CLIENT area, not the window: the client is what the helper actually
        # presents into, and the window's border would only add pixels that are not
        # the game's (drive-game.ps1 warns about exactly this confusion).
        $c = [ScDrive.Native]::ClientSize($h)
        $winW = $c[0]; $winH = $c[1]
        Write-Host "       client $winW x $winH"

        $png = Join-Path $FrameDir "present-$name-menu.png"
        Save-ScWindowImage -Hwnd $h -Path $png | Out-Null
        $b = [System.Drawing.Bitmap]::new($png)
        Write-Host "       client capture $($b.Width) x $($b.Height) -> $png"
        $b.Dispose()
        $frames[$name] = $png
        $windows[$name] = "$winW x $winH"
    }
    catch {
        $unhealthy = $_.Exception.Message
        Write-Host "       LAUNCH NOT HEALTHY: $unhealthy"
        $script:results[$name] = $unhealthy
        if ($StopOnUnhealthy) { throw }
    }
    finally {
        if ($gamePid -gt 0) {
            try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host } catch { }
            Start-Sleep -Seconds 2
        }
    }
}

try {
    Write-Host 'probe-present: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '034-present'

    $vectors = ($Vector -eq 'both') ? @('inject', 'ddraw') : @($Vector)
    foreach ($v in $vectors) {
        Invoke-PresentArm -Vec $v -Widescreen '1'
        Invoke-PresentArm -Vec $v -Widescreen '0'
    }

    Write-Host ''
    Write-Host 'probe-present: verdict'
    foreach ($v in $vectors) {
        $ws = $frames["$v-ws1"]; $ctl = $frames["$v-ws0"]
        if (-not $ws -or -not $ctl) {
            Write-Host "  $v : one arm did not produce a frame"
            foreach ($k in @("$v-ws1", "$v-ws0")) {
                if ($script:results[$k]) { Write-Host "        $k : $($script:results[$k])" }
            }
            continue
        }
        $band = Get-BandMatch -A $ctl -B $ws -Y0 0 -Y1 480
        $edgeWs = Get-ContentRightEdge -Path $ws
        $edgeCtl = Get-ContentRightEdge -Path $ctl
        $verdict = if ($edgeWs.Width -ge 800) { 'FOLLOW -- the client area is itself the new width' }
                   elseif ($band.Pct -ge 95) { 'CROP -- the same pixels, so only columns 0..639 are presented' }
                   else { 'SCALE (or something else) -- the frames differ; compare the right edges' }
        Write-Host "  $v : window ws=$($windows["$v-ws1"]) control=$($windows["$v-ws0"])"
        Write-Host "        frames identical over the whole client: $($band.Pct)% ($($band.Same)/$($band.N))"
        Write-Host "        content right edge: ws x=$($edgeWs.Edge)/$($edgeWs.Width) ($($edgeWs.Pct)%), control x=$($edgeCtl.Edge)/$($edgeCtl.Width) ($($edgeCtl.Pct)%)"
        Write-Host "        => $verdict"
    }
    Write-Host ''
    Write-Host 'probe-present: frames (gitignored diagnostic path, never committed):'
    foreach ($k in $frames.Keys | Sort-Object) { Write-Host "       $k : $($frames[$k])" }
}
finally {
    # -Windowed COPIES WMode.dll into the shared working copy as ddraw.dll. Leaving it
    # there would silently put every other worker's launch into windowed mode, so it
    # comes out on every path, inside the lock that serialises the shared game dir.
    if ($Vector -ne 'inject') {
        try {
            & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch `
                -NoLaunchLock -GameDir $GameDir | Write-Host
        }
        catch { Write-Host "  warn: could not remove the ddraw shim: $($_.Exception.Message)" }
    }
    if ($launchLock) { try { Exit-ScLaunchLock -Lock $launchLock } catch { } }
}
