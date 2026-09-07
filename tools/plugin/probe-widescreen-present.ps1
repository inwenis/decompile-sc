#Requires -Version 7
<#
.SYNOPSIS
Does the windowed-mode helper PRESENT the engine's extra columns, or only the left 640?

.DESCRIPTION
An engine read-back cannot answer that: what reaches the monitor goes through the packed
WMode.dll, whose behaviour off 640x480 can only be established by running it
(research/renderer-viewport.md 10 item 2; the WMode answer is 12.6).
inject (scinject --early-dll) and ddraw (copied in as ddraw.dll, research/launch-baseline.md)
are distinct vectors, so both run in a widescreen and a stock arm. The verdict is structural:
CROP = arms identical, so the extra columns are composed and thrown away; SCALE = arms differ,
and the rightmost non-black column gives the ratio; FOLLOW = the client area is the new width.

.EXAMPLE
./tools/plugin/probe-widescreen-present.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    [string]$FrameDir = 'C:\sc-work\logs\034-frames',
    [ValidateSet('inject', 'ddraw', 'both')][string]$Vector = 'both',
    # Which DLL the ddraw vector installs. Empty = WMode.dll. Point it at cnc-ddraw's
    # ddraw.dll (fetch-cnc-ddraw.ps1) and -Vector both weighs a candidate replacement
    # against the WMode control in one run, on one instrument.
    [string]$WindowedHelperDll = '',
    # >0 takes a SECOND capture of the same window N seconds after the first and prints
    # the same-arm band match. The main menu ANIMATES, so the cross-arm CROP threshold
    # (95%) carries animation noise inside it; the same-arm delta measures that noise
    # instead of assuming it.
    [int]$BracketSeconds = 0,
    # Which widescreen stage to run under. Stage 0 is the interesting one for THIS
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
    else {
        $launchArgs['Windowed'] = $true
        if ($WindowedHelperDll) { $launchArgs['WindowedHelperDll'] = $WindowedHelperDll }
    }

    Write-Host ''
    Write-Host "probe-present: vector=$Vec widescreen=$Widescreen stage=$Stage"
    $unhealthy = $null
    try {
        & (Join-Path $scriptDir 'run-with-plugin.ps1') @launchArgs 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
        if (-not $gamePid) { throw "probe-present: no pid for $name" }
        # research/launch-baseline.md: as a ddraw proxy the window comes up MINIMISED at
        # the off-screen sentinel, and a minimised window has no client area to capture.
        # Restoring it is the documented recipe.
        $h = Get-ScGameWindow -ProcessId $gamePid
        Set-ScWindowActive -Hwnd $h -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 4

        # The CLIENT area, not the window: the client is what the helper presents into,
        # and the border would add pixels that are not the game's.
        $c = [ScDrive.Native]::ClientSize($h)
        $winW = $c[0]; $winH = $c[1]
        Write-Host "       client $winW x $winH"

        # A game frame reproduces game artwork (AGENTS.md § "Screenshots"), so no frame
        # is ever committed or put through `pr-image`; only pixel counts and column
        # indices are reported. Save-ScWindowImage refuses to write inside the repo, so
        # the gitignored diagnostic path is enforced rather than remembered.
        $png = Join-Path $FrameDir "present-$name-menu.png"
        Save-ScWindowImage -Hwnd $h -Path $png | Out-Null
        $b = [System.Drawing.Bitmap]::new($png)
        Write-Host "       client capture $($b.Width) x $($b.Height) -> $png"
        $b.Dispose()
        $frames[$name] = $png
        $windows[$name] = "$winW x $winH"

        if ($BracketSeconds -gt 0) {
            Start-Sleep -Seconds $BracketSeconds
            $png2 = Join-Path $FrameDir "present-$name-menu2.png"
            Save-ScWindowImage -Hwnd $h -Path $png2 | Out-Null
            $frames["$name-b2"] = $png2
            $sameArm = Get-BandMatch -A $png -B $png2 -Y0 0 -Y1 480
            Write-Host ("       same-arm delta ($BracketSeconds s apart, same window, nothing changed but time): " +
                        "$($sameArm.Pct)% identical ($($sameArm.Same)/$($sameArm.N)) -> $png2")
        }
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
        # The widescreen frame keeps the 480-row height and every HUD dialog's stock
        # coordinates (research/renderer-viewport.md 12.1), so pixels identical across the
        # whole client can only mean columns 0..639 presented 1:1 with the rest discarded --
        # a squeeze into the same window would move every HUD pixel to 0.8x its x.
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
    # -Windowed COPIES WMode.dll into the shared working copy as ddraw.dll. Left there it
    # would silently put every other worker's launch into windowed mode, so it comes out
    # on every path, inside the lock that serialises the shared game dir.
    if ($Vector -ne 'inject') {
        try {
            & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch `
                -NoLaunchLock -GameDir $GameDir | Write-Host
        }
        catch { Write-Host "  warn: could not remove the ddraw shim: $($_.Exception.Message)" }
    }
    if ($launchLock) { try { Exit-ScLaunchLock -Lock $launchLock } catch { } }
}
