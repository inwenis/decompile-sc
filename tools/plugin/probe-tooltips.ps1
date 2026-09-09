#Requires -Version 7
<#
.SYNOPSIS
Does a tooltip sit by its control, stay in the buffer for every one of a burst
of dumps while the cursor rests, and reach the glass? Four hover arms at the
shipped widescreen config: a command-card button (the card path 0x00459030
places the box directly ABOVE the button), the Stat_F10 Menu button (the
generic path 0x00481510, whose stock clamps push the box to y<=479 unless
patched), and the minimap and resource bar as negative controls (stock draws
no tooltip there; they may pass only while the card arm's detector said YES).

The tooltip is graphic layer 1 (0x006CEF64); the composer redraws it only on
its show frame or when a dirty cell lies under it, while the buffer-resident
console recomposites under it every frame. -TipFix 0 turns the plugin's
always-draw off so the presence assertion can be watched failing.

.EXAMPLE
$env:AGENT_TASK = '156'; ./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-tooltips.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\156',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\156-frames',
    [string]$WindowedHelperDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    # Consecutive dumps per hover and their spacing. The plugin polls the marker
    # every -PollMs; a marker overwritten before a poll is lost, so the count
    # that LANDED is asserted (>= $MinLanded), not the count written.
    [int]$Dumps = 12,
    [int]$DumpGapMs = 100,
    [int]$MinLanded = 8,
    [int]$PollMs = 60,
    # %SCPLUGIN_TIPFIX%: '0' disables the plugin's layer-1 always-draw, the arm
    # under which the presence assertion is expected to FAIL.
    [ValidateSet('0', '1')][string]$TipFix = '1',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
. (Join-Path $scriptDir 'sc-suite.ps1')
. (Join-Path $scriptDir 'sc-wsprobe.ps1')
. (Join-Path $scriptDir 'sc-oracle-guard.ps1')

$ws = Get-ScWideGeometry
$SCREEN_W = $ws.W; $SCREEN_H = $ws.H; $PF_W = $ws.PfW; $PF_H = $ws.PfH
$SHIFT_Y = $ws.ConsoleShiftY
$NEXUS_TYPE = 154          # units.dat 154, 'Protoss Nexus'
$CARD_STOCK_TOP = 354      # the command card root's stock top (research/renderer-viewport.md)
$FILL_SHARE = 0.45         # one palette index owning this much of a rect is a tooltip fill, not animation

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t156' -Suite 'tooltips' }
$mapName = 'tooltips.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$log = Join-Path $LogDir '156-tooltips.log'
Initialize-ScWsProbe -LogDir $LogDir -FrameDir $FrameDir

# ---- the detector ---------------------------------------------------------
# frame-capture.py diffbox: the bounding box of what dump B shows that dump A
# does not, inside a rect, and how SOLID that patch is (the modal index share).
# A tooltip is a one-index fill with a 1-px border; sprite animation is not.
# Absent lines read -1 (never 0), so a detector that never ran cannot pass.
function ConvertFrom-DiffBoxLines {
    param([string[]]$Lines)
    $r = [ordered]@{ Px = -1; L = -1; T = -1; R = -1; B = -1; W = 0; H = 0; ModeFrac = -1.0 }
    foreach ($l in $Lines) {
        if ("$l" -match '^diffbox_px=(\d+)$') { $r.Px = [int]$Matches[1] }
        if ("$l" -match '^diffbox=(\d+),(\d+)[-,](\d+),(\d+)$') {
            $r.L = [int]$Matches[1]; $r.T = [int]$Matches[2]; $r.R = [int]$Matches[3]; $r.B = [int]$Matches[4]
            $r.W = $r.R - $r.L + 1; $r.H = $r.B - $r.T + 1
        }
        if ("$l" -match '^(?:diffbox_)?mode_frac=(.+)$') { $r.ModeFrac = [double]$Matches[1] }
    }
    [pscustomobject]$r
}
function Get-DiffBox {
    param([string]$A, [string]$B, [int]$X0, [int]$Y0, [int]$X1, [int]$Y1)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') diffbox --a $A --b $B --x0 $X0 --y0 $Y0 --x1 $X1 --y1 $Y1 2>&1
    ConvertFrom-DiffBoxLines -Lines @($out | ForEach-Object { "$_" })
}
# The box verdict on one diffbox: enough changed pixels, plausible size, solid fill.
function Test-IsTooltipBox {
    param($D)
    ($D.Px -ge 200) -and ($D.W -ge 40) -and ($D.W -le 420) -and ($D.H -ge 12) -and ($D.H -le 140) -and ($D.ModeFrac -ge $FILL_SHARE)
}
# frame-capture.py band over a rect: its pixel count and the modal index with
# its count (band_top's first idx:count pair).
function ConvertFrom-BandLines {
    param([string[]]$Lines)
    $r = [ordered]@{ Px = -1; TopIdx = -1; TopCount = 0 }
    foreach ($l in $Lines) {
        if ("$l" -match '^band_px=(\d+)$') { $r.Px = [int]$Matches[1] }
        if ("$l" -match '^band_top=(\d+):(\d+)') { $r.TopIdx = [int]$Matches[1]; $r.TopCount = [int]$Matches[2] }
    }
    [pscustomobject]$r
}
function Get-BoxBand {
    param([string]$Dump, $Box)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') band --dump $Dump --x0 $Box.L --x1 ($Box.R + 1) --y0 $Box.T --y1 ($Box.B + 1) 2>&1
    ConvertFrom-BandLines -Lines @($out | ForEach-Object { "$_" })
}
# Is the fill index $Idx still dominant over the box in this band reading.
function Test-BandDominant {
    param($Band, [int]$Idx)
    ($Band.Px -gt 0) -and ($Idx -ge 0) -and ($Band.TopIdx -eq $Idx) -and (($Band.TopCount / $Band.Px) -ge $FILL_SHARE)
}
# How many of the burst's band readings still carry the fill.
function Measure-BoxPresence {
    param([object[]]$Bands, [int]$Idx)
    @(@($Bands) | Where-Object { Test-BandDominant -Band $_ -Idx $Idx }).Count
}

Add-Type -AssemblyName System.Drawing
# Glass, over one rect: how DARK the patch is (a tooltip fill renders near-black),
# how much LIGHT there is (its text), and how much differs from another capture.
function Get-PngRectStats {
    param([Parameter(Mandatory)][string]$Path, [string]$Against, [int]$X0, [int]$Y0, [int]$X1, [int]$Y1)
    $bmp = [System.Drawing.Bitmap]::new($Path)
    $other = if ($Against) { [System.Drawing.Bitmap]::new($Against) } else { $null }
    try {
        $n = 0; $dark = 0; $light = 0; $diff = 0
        $xe = [Math]::Min($X1, $bmp.Width); $ye = [Math]::Min($Y1, $bmp.Height)
        for ($y = $Y0; $y -lt $ye; $y++) {
            for ($x = $X0; $x -lt $xe; $x++) {
                $c = $bmp.GetPixel($x, $y); $n++
                $s = [int]$c.R + [int]$c.G + [int]$c.B
                if ($s -lt 90) { $dark++ } elseif ($s -gt 300) { $light++ }
                if ($other) {
                    $o = $other.GetPixel($x, $y)
                    if ([Math]::Abs($s - ([int]$o.R + [int]$o.G + [int]$o.B)) -gt 24) { $diff++ }
                }
            }
        }
        if ($n -eq 0) { return [pscustomobject]@{ Px = 0; Dark = -1.0; Light = -1.0; Diff = -1.0 } }
        [pscustomobject]@{ Px = $n; Dark = [Math]::Round($dark / $n, 4); Light = [Math]::Round($light / $n, 4); Diff = $(if ($other) { [Math]::Round($diff / $n, 4) } else { -1.0 }) }
    } finally { $bmp.Dispose(); if ($other) { $other.Dispose() } }
}
function Get-GlassStats {
    param($Arm, $Box)
    $rect = @{ X0 = $Box.L; Y0 = $Box.T; X1 = $Box.R + 1; Y1 = $Box.B + 1 }
    [pscustomobject]@{
        On  = @($Arm.GOn | ForEach-Object { Get-PngRectStats -Path $_ -Against $Arm.GBase @rect })
        Off = Get-PngRectStats -Path $Arm.GOff -Against $Arm.GBase @rect
    }
}

# A dump that must come back with both halves, or the probe cannot judge it.
function Get-Dump {
    param([string]$Tag)
    $d = Get-ScBufferDump -LogPath $log -MarkerPath $markerPath -Tag $Tag
    if (-not ($d.Path -and $d.Cam)) { throw "probe-tooltips: dump '$Tag' came back without a path or a camera (path=$($d.Path))." }
    $d
}
# N markers fired $GapMs apart WITHOUT waiting on each (Get-ScBufferDump's own
# wait is >= 300 ms per dump, too slow for a 100 ms cadence); then wait for the
# last one and collect every FRAMEDUMP line that landed, in tag order. A tag the
# poll skipped is simply absent.
function Get-DumpBurst {
    param([string]$Prefix, [int]$N, [int]$GapMs)
    $from = Get-ScLogLineCount -LogPath $log
    $tags = 1..$N | ForEach-Object { '{0}-{1:d2}' -f $Prefix, $_ }
    foreach ($t in $tags) { Set-ScMarker -MarkerPath $markerPath -Label $t; Start-Sleep -Milliseconds $GapMs }
    try { [void](Wait-ScLogMatch -LogPath $log -Pattern "FRAMEDUMP \[$([regex]::Escape($tags[-1]))\] " -TimeoutSec 30 -FromLine $from) }
    catch { Write-Host "       burst '$Prefix': the last marker's dump never landed ($($_.Exception.Message))" }
    $lines = @(Get-Content -LiteralPath $log | Select-Object -Skip $from)
    $paths = @()
    foreach ($t in $tags) {
        $hit = @($lines | Where-Object { $_ -match "FRAMEDUMP \[$([regex]::Escape($t))\] .* path=(.+)$" }) | Select-Object -First 1
        if ($hit -and $hit -match 'path=(.+)$') { $paths += $Matches[1].Trim() }
    }
    , $paths
}
function Get-Glass {
    param([string]$Name)
    Save-ScWindowImage -Hwnd $h -Path (Join-Path $FrameDir "$Name.png") -ClientByGeometry
}
function Move-Away {
    param([int]$SettleMs)
    Send-ScMouseMove -Hwnd $h -X $AWAY.X -Y $AWAY.Y -DelayMs 300
    Start-Sleep -Milliseconds $SettleMs
}
# One hover arm: park away, baseline dump+glass, hover, burst of dumps with two
# glass captures around it, leave, an 'off' dump+glass. Returns everything.
function Invoke-HoverArm {
    param([string]$Name, [int]$X, [int]$Y)
    Move-Away -SettleMs 500
    $base = Get-Dump -Tag "tt-$Name-base"
    $gBase = Get-Glass -Name "tt-$Name-base"
    Send-ScMouseMove -Hwnd $h -X $X -Y $Y -DelayMs 400
    $first = Get-Dump -Tag "tt-$Name-first"
    $gOn1 = Get-Glass -Name "tt-$Name-on1"
    $burst = Get-DumpBurst -Prefix "tt-$Name" -N $Dumps -GapMs $DumpGapMs
    $gOn2 = Get-Glass -Name "tt-$Name-on2"
    Move-Away -SettleMs 100
    $off = Get-Dump -Tag "tt-$Name-off"
    $gOff = Get-Glass -Name "tt-$Name-off"
    [pscustomobject]@{ Name = $Name; Base = $base; First = $first; Burst = $burst; Off = $off; GBase = $gBase; GOn = @($gOn1, $gOn2); GOff = $gOff }
}
function Test-CameraHeld {
    param($A, $B)
    -not (Test-ScChanged "$($A.Cam.X),$($A.Cam.Y)" "$($B.Cam.X),$($B.Cam.Y)")
}
# The judgement every positive arm gets: a box in the window, placed where
# $PlaceOk says, present in every landed dump, gone once the cursor leaves,
# on the glass while hovered and off it after. Returns whether the box was found.
function Test-PositiveArm {
    param($Arm, [hashtable]$Win, [string]$PlaceWhat, [scriptblock]$PlaceOk)
    $n = $Arm.Name
    Assert-True "$n arm: the camera did not move between the base dump and the first hover dump (screen-space diff is valid)" `
        (Test-CameraHeld $Arm.Base $Arm.First) "(cam $($Arm.Base.Cam.X),$($Arm.Base.Cam.Y) -> $($Arm.First.Cam.X),$($Arm.First.Cam.Y))"
    $box = Get-DiffBox -A $Arm.Base.Path -B $Arm.First.Path @Win
    Report-Finding "$n arm: diffbox px=$($box.Px) bbox=($($box.L),$($box.T))-($($box.R),$($box.B)) $($box.W)x$($box.H) mode_frac=$($box.ModeFrac)"
    $found = Test-IsTooltipBox $box
    Assert-True "$n arm: a solid tooltip box appeared in the search window (>=200 px changed, 40..420 x 12..140, one index >= $FILL_SHARE)" $found "(px=$($box.Px) $($box.W)x$($box.H) mode_frac=$($box.ModeFrac))"
    Assert-True "$n arm: $PlaceWhat" ($found -and (& $PlaceOk $box)) "(bbox bottom=$($box.B))"
    if (-not $found) { return $false }
    # The fill index is read off the FIRST hover dump; every later reading must
    # keep that same index dominant, so a repaint by the console underneath (a
    # different index) counts as absent.
    $fill = Get-BoxBand -Dump $Arm.First.Path -Box $box
    $bands = @($Arm.Burst | ForEach-Object { Get-BoxBand -Dump $_ -Box $box })
    $landed = @($Arm.Burst).Count
    $present = Measure-BoxPresence -Bands $bands -Idx $fill.TopIdx
    Report-Finding "$n arm: fill idx=$($fill.TopIdx) share=$([Math]::Round($fill.TopCount / [Math]::Max(1, $fill.Px), 3)); burst of $Dumps markers $DumpGapMs ms apart -> $landed dumps landed, box present in $present"
    Assert-True "$n arm: enough consecutive dumps landed to judge persistence (>= $MinLanded of $Dumps)" (Test-ScReached $landed -AtLeast $MinLanded) "(landed=$landed)"
    Assert-True "$n arm: the box is present in EVERY landed dump while the cursor rests (no strobe in the buffer)" `
        ((Test-ScReached $landed -AtLeast $MinLanded) -and (Test-BandDominant -Band $fill -Idx $fill.TopIdx) -and $present -eq $landed) "(present=$present of $landed)"
    Assert-True "$n arm: the box is GONE from the buffer once the cursor leaves (the detector can say no)" `
        (-not (Test-BandDominant -Band (Get-BoxBand -Dump $Arm.Off.Path -Box $box) -Idx $fill.TopIdx))
    $g = Get-GlassStats -Arm $Arm -Box $box
    Report-Finding "$n arm GLASS over the bbox: on1 dark=$($g.On[0].Dark) light=$($g.On[0].Light) diff-vs-base=$($g.On[0].Diff); on2 dark=$($g.On[1].Dark) light=$($g.On[1].Light) diff=$($g.On[1].Diff); off diff-vs-base=$($g.Off.Diff)"
    Assert-True "$n arm: the tooltip reaches the GLASS in both captures (bbox differs from the no-hover glass >= 30%, dark >= 40%, some light text)" `
        (@($g.On | Where-Object { $_.Diff -ge 0.30 -and $_.Dark -ge 0.40 -and $_.Light -ge 0.01 }).Count -eq 2) "(diff=$($g.On[0].Diff)/$($g.On[1].Diff) dark=$($g.On[0].Dark)/$($g.On[1].Dark))"
    Assert-True "$n arm: the glass returns to the no-hover picture after the cursor leaves (bbox diff-vs-base <= 10%)" `
        ($g.Off.Px -gt 0 -and $g.Off.Diff -le 0.10) "(diff=$($g.Off.Diff))"
    $true
}
function Get-DialogCentre {
    param($Dlg)
    @{ X = [int](($Dlg.Left + $Dlg.Right) / 2); Y = [int](($Dlg.Top + $Dlg.Bottom) / 2) }
}

try {
    Write-Host 'probe-tooltips: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '156-tooltips'

    Write-Host 'probe-tooltips: generating the fixture (one Nexus, explored start)'
    $fixtures = New-ScNexusFixture -RepoRoot $repoRoot -FixtureDir $FixtureDir -MapName $mapName -Noun 'probe-tooltips'

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    Write-Host "probe-tooltips: launching (stage 3, cnc-ddraw, card scan, $PollMs ms poll, TipFix=$TipFix)"
    # The DLL reads %SCPLUGIN_TIPFIX% once at attach, so the variable only has to
    # live for the launch itself.
    $env:SCPLUGIN_TIPFIX = $TipFix
    try {
        $gamePid = Start-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -LogPath $log -FrameDir $FrameDir `
            -WindowedHelperDll $WindowedHelperDll -CardScan 1 -PollMs $PollMs -Noun 'probe-tooltips'
    } finally { Remove-Item Env:SCPLUGIN_TIPFIX -ErrorAction SilentlyContinue }
    $h = Connect-ScWideGame -GamePid $gamePid -LogPath $log -ScreenW $SCREEN_W -ScreenH $SCREEN_H
    Assert-True 'storm present is armed as WIDEN (the whole-frame mirror is what puts the buffer on glass)' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'STORM present: WIDEN armed' }).Count -gt 0)

    Write-Host 'probe-tooltips: walking to a loaded game'
    Walk-ToScGame -Hwnd $h -LogPath $log -Fixtures $fixtures -MapPath $mapPath -GameDir $GameDir -Noun 'probe-tooltips'
    $mv = @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'CONSOLE moved ' })
    Assert-True 'the ten bottom-console roots were moved (CONSOLE moved lines = 10)' ($mv.Count -eq 10) "(got $($mv.Count))"

    # ---- select the Nexus by a point derived from memory (client = map - viewport)
    $w = Get-ScWorldState -LogPath $log -Tag 'aim' -MarkerPath $markerPath
    $nx = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $NEXUS_TYPE }) | Select-Object -First 1
    Assert-True 'the world scan reports the fixture Nexus and a viewport origin' ($null -ne $nx -and $null -ne $w.Screen)
    if (-not $nx -or -not $w.Screen) { throw 'probe-tooltips: no Nexus / no viewport in the WORLD scan.' }
    $cx = $nx.X - $w.Screen.Left; $cy = $nx.Y - $w.Screen.Top
    if ($cx -lt 0 -or $cx -ge $PF_W -or $cy -lt 0 -or $cy -ge $PF_H) { throw "probe-tooltips: the Nexus is off the playfield at client ($cx,$cy)." }
    # A posted playfield click does not select here (the engine reads that button from
    # its own poll, not from the message); the console module's marker-driven select aid
    # picks the player's first completed unit, which in this fixture is the Nexus.
    Set-ScMarker -MarkerPath $markerPath -Label 'conedge-select'; Start-Sleep -Seconds 2
    $card = Get-ScCardState -LogPath $log -Tag 'sel' -MarkerPath $markerPath
    Assert-True 'selecting the Nexus put a command card up with buttons (CARD slots shown >= 1)' `
        ($card.Ok -and (Test-ScReached $card.Shown)) "(shown=$($card.Shown) cardId=$($card.CardId))"
    Assert-True "the card root sits at its MOVED rect (top >= $($CARD_STOCK_TOP + $SHIFT_Y - 4))" `
        ($card.RootRect[1] -ge ($CARD_STOCK_TOP + $SHIFT_Y - 4)) "(rootrect=$($card.RootRect -join ','))"
    # Explored map beside the Nexus, away from every hovered control.
    $AWAY = [pscustomobject]@{ X = [Math]::Min($PF_W - 40, $cx + 160); Y = [Math]::Max(40, $cy - 120) }

    # ---- ARM 1: a card button (the card tooltip path 0x00459030) ----------------
    $slot = @($card.Slots | Where-Object { $_.Visible -and $_.HasButton -and -not $_.Disabled }) | Select-Object -First 1
    if (-not $slot) { throw 'probe-tooltips: the card has no visible enabled button to hover.' }
    $pt = Get-ScCardSlotPoint -Card $card -Slot $slot.Index
    $ctrlTop = $card.RootRect[1] + $slot.Rect[1]
    Report-Finding "card arm: slot $($slot.Index) ctrl abs rect=($($card.RootRect[0] + $slot.Rect[0]),$ctrlTop)-($($card.RootRect[0] + $slot.Rect[2]),$($card.RootRect[1] + $slot.Rect[3])) hover point=($($pt.X),$($pt.Y))"
    $arm = Invoke-HoverArm -Name 'card' -X $pt.X -Y $pt.Y
    # The search window: 140 rows ABOVE the button (0x00458850 puts the box's
    # bottom at ctrl.top-1), ending at the button's top so the cursor (hotspot
    # at/below the point) can never join the bbox; 200 columns either side.
    $win = @{ X0 = [Math]::Max(0, $card.RootRect[0] - 200); Y0 = [Math]::Max(0, $ctrlTop - 140); X1 = [Math]::Min($SCREEN_W, $card.RootRect[2] + 200); Y1 = $ctrlTop }
    $cardBox = Test-PositiveArm -Arm $arm -Win $win `
        -PlaceWhat "the box sits directly above the button (bbox bottom within 2 px of ctrl.top-1 = $($ctrlTop - 1))" `
        -PlaceOk { param($b) [Math]::Abs($b.B - ($ctrlTop - 1)) -le 2 }

    # ---- ARM 2: a StatData icon (the GENERIC path 0x00481510) --------------------
    # The status pane's labelled icons (armour, shields; type 9 with a text label)
    # carry a tooltip; the F10 Menu button carries none. 0x00481510 puts the box at
    # (ctrl.right + parent.left, ctrl.top + parent.top), so the window is everything
    # right of the icon, from 400 rows above it to the screen bottom: the stock
    # 0x00481620 clamp lands the box at bottom <= 479, the fix beside the icon, and
    # the Nexus animation higher up stays out of the window.
    $sd = @(Get-ScDialogs -LogPath $log | Where-Object { $_.Name -eq 'StatData' }) | Select-Object -First 1
    $icon = if ($sd) { @($sd.Controls | Where-Object { $_.Type -eq 9 -and $_.Text }) | Select-Object -First 1 } else { $null }
    Assert-True 'the DIALOGS line carries StatData and one labelled icon control (type 9) at runtime' ($null -ne $icon) "(root=$($sd.Left),$($sd.Top) ctrl='$($icon.Text)')"
    if ($icon) {
        $iL = $sd.Left + $icon.Left; $iT = $sd.Top + $icon.Top; $iR = $sd.Left + $icon.Right; $iB = $sd.Top + $icon.Bottom
        $ip = Get-DialogCentre @{ Left = $iL; Top = $iT; Right = $iR; Bottom = $iB }
        Report-Finding "icon arm: '$($icon.Text)' abs rect=($iL,$iT)-($iR,$iB) hover point=($($ip.X),$($ip.Y))"
        $arm2 = Invoke-HoverArm -Name 'icon' -X $ip.X -Y $ip.Y
        $win2 = @{ X0 = [Math]::Min($SCREEN_W - 1, $iR + 1); Y0 = [Math]::Max(0, $iT - 400); X1 = [Math]::Min($SCREEN_W, $iR + 300); Y1 = $SCREEN_H }
        [void](Test-PositiveArm -Arm $arm2 -Win $win2 `
            -PlaceWhat "the box sits BESIDE its icon (bbox top within 24 px of the icon top $iT); the stock 0x00481620 clamp gives bottom <= 479" `
            -PlaceOk { param($b) [Math]::Abs($b.T - $iT) -le 24 })
    }

    # ---- ARMS 3/4: minimap and resource bar (negative controls) -----------------
    # Stock draws no tooltip for either; the detector that just found the card's
    # box must say NO here, and may pass only because it said YES above.
    foreach ($neg in @(@{ Name = 'minimap'; Root = 'Minimap' }, @{ Name = 'resbar'; Root = 'StatRes' })) {
        $root = @(Get-ScDialogs -LogPath $log | Where-Object { $_.Name -eq $neg.Root }) | Select-Object -First 1
        if (-not $root) { Assert-True "$($neg.Name) arm: the '$($neg.Root)' root is in the DIALOGS line" $false; continue }
        $p = Get-DialogCentre $root
        Move-Away -SettleMs 400
        $nb = Get-Dump -Tag "tt-$($neg.Name)-base"
        Send-ScMouseMove -Hwnd $h -X $p.X -Y $p.Y -DelayMs 600
        $nh = Get-Dump -Tag "tt-$($neg.Name)-hover"
        $camSame = Test-CameraHeld $nb $nh
        # Everything within 300 px of the point except the rows at and below the
        # hotspot, so the cursor's own blit cannot read as a box.
        $nwin = @{ X0 = [Math]::Max(0, $p.X - 300); Y0 = [Math]::Max(0, $p.Y - 300); X1 = [Math]::Min($SCREEN_W, $p.X + 300); Y1 = [Math]::Max(0, $p.Y - 1) }
        $nbox = Get-DiffBox -A $nb.Path -B $nh.Path @nwin
        Report-Finding "$($neg.Name) arm: hover at ($($p.X),$($p.Y)) root=($($root.Left),$($root.Top))-($($root.Right),$($root.Bottom)) diffbox px=$($nbox.Px) $($nbox.W)x$($nbox.H) mode_frac=$($nbox.ModeFrac) cam-same=$camSame"
        Assert-True "$($neg.Name) arm: NO tooltip box over the $($neg.Root) (witnessed by the same detector finding the card's box)" `
            (Test-ScWitnessed -Claim ($camSame -and -not (Test-IsTooltipBox $nbox)) -Witness $cardBox) "(px=$($nbox.Px) mode_frac=$($nbox.ModeFrac))"
    }

    $completed = $true
}
catch {
    Write-ScStepFailure -Err $_ -What 'a probe step'
}
finally {
    Stop-ScWideGame -ScriptDir $scriptDir -GameDir $GameDir -GamePid $gamePid -KeepOpen:$KeepOpen -Fixtures $fixtures -LaunchLock $launchLock
}

Write-Host ''
if ($script:findings.Count) { Write-Host 'probe-tooltips: FINDINGS:'; $script:findings | ForEach-Object { Write-Host "  - $_" } }
Write-Host ''
if (-not $completed) { Write-Host "probe-tooltips: INCOMPLETE -- the run did not reach its end; $script:failures failure(s) so far"; exit 1 }
elseif ($script:failures -gt 0) { Write-Host "probe-tooltips: FAIL ($script:failures failure(s)) -- a tooltip is misplaced, strobes, or misses the glass"; exit 1 }
else { Write-Host 'probe-tooltips: PASS (0 failures) -- tooltips sit by their controls, persist across every dump, and reach the glass'; exit 0 }
