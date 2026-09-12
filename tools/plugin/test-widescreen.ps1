#Requires -Version 7
<#
.SYNOPSIS
Runs the wider-playfield patch set in a real game and READS THE GEOMETRY BACK OUT
OF THE ENGINE, in two arms, so "the screen is 800 wide" is a measurement.

.DESCRIPTION
research/renderer-viewport.md 9.3 stages a wider screen; this suite instruments
stages 0-2. The control arm (-Widescreen 0) and the widescreen arm run the same
oracle and the assertion is on the DIFFERENCE: a one-armed run cannot tell "the
descriptor says 800x480 because we patched it" from "it always said that", so
the control is half the result. The oracle is the `SCREEN` scan -- framebuffer
descriptor 0x006CEFF0 and the eight graphic-layer rectangles, read out of the
running process -- and not a screenshot: a game frame reproduces game artwork,
which hard rule 1 forbids committing (AGENTS.md § "Screenshots").

.EXAMPLE
./tools/plugin/test-widescreen.ps1 -Stage 0

.EXAMPLE
./tools/plugin/test-widescreen.ps1 -Stage 1 -SkipInGame
#>
[CmdletBinding()]
param(
    [ValidateSet('0', '1', '2')][string]$Stage = '1',
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    # This suite's own fixture folder (AGENTS.md § "Test fixtures").
    [string]$FixtureDir,
    # Menu reading only. Stages 0 and 1 are fully decided at the menu; skipping the
    # walk removes the one part that depends on how the windowed helper maps a
    # click at a non-stock size.
    [switch]$SkipInGame,
    # Widescreen arm only -- for iterating. The control is what makes the result
    # mean anything, so this is for development, not for a result.
    [switch]$NoControl,
    # List the captured frames at the end, for a HUMAN to open: the read-back cannot
    # answer "does the windowed helper actually PRESENT the extra columns", and
    # nothing in a log can. One in-game PNG per arm is written to $FrameDir either
    # way -- the playfield-interior comparison needs both frames. A game frame
    # reproduces game artwork, so it stays on the gitignored diagnostic path, is
    # never committed and never goes through pr-image (AGENTS.md § "Screenshots");
    # Save-ScWindowImage refuses to write inside the repo, so that is enforced
    # rather than remembered.
    [switch]$CaptureFrames,
    [string]$FrameDir = 'C:\sc-work\logs\034-frames',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')
. (Join-Path $scriptDir 'sc-wsprobe.ps1')

if (-not $FixtureDir) { $FixtureDir = Join-Path $GameDir 'Maps\BroodWar\00-t034' }
# Named for the SUITE, not for the run (AGENTS.md § "Test fixtures").
$mapName = 'widescreen.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'

# The geometry the patch table was generated for, read out of the generated header
# rather than duplicated here, so a regenerated table at a different size cannot
# leave this suite asserting stale numbers.
$patchHeader = (Get-ScWideGeometry).Header
if (-not (Test-Path -LiteralPath $patchHeader)) {
    throw "test-widescreen: $patchHeader not found -- run tools/renderer_patch_sites.py first."
}
function Get-WsDefine([string]$Name) {
    $m = Select-String -LiteralPath $patchHeader -Pattern "^#define\s+$Name\s+(\d+)" |
         Select-Object -First 1
    if (-not $m) { throw "test-widescreen: $Name not found in $patchHeader" }
    [int]$m.Matches[0].Groups[1].Value
}
$WS_W = Get-WsDefine 'SC_WS_SCREEN_W'
$WS_H = Get-WsDefine 'SC_WS_SCREEN_H'
$WS_PF_W = Get-WsDefine 'SC_WS_PLAYFIELD_W'
$WS_PF_H = Get-WsDefine 'SC_WS_PLAYFIELD_H'
$STOCK_W = Get-WsDefine 'SC_WS_STOCK_W'
$STOCK_H = Get-WsDefine 'SC_WS_STOCK_H'
$STOCK_PF_W = 640
$STOCK_PF_H = 400

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$script:failures = 0
$script:step = 0
$launchLock = $null
$fixtures = $null
$arms = @{}

function Report-Finding {
    param([string]$What)
    Write-Host "  ---- FINDING: $What"
}

# One reading: write a marker, wait for the plugin's SCREEN lines carrying that
# exact tag, parse them. Same synchronisation every oracle in this repo uses.
function Read-ScreenLayout {
    param([Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)][string]$LogPath)

    $from = Get-ScLogLineCount -LogPath $LogPath
    # Set-ScMarker, not Set-Content: the latter opens the marker FileShare.None and
    # throws whenever the observer holds it, and the marker must carry NO trailing
    # newline -- PollMarker compares its content against the whole line.
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    Wait-ScLogMatch -LogPath $LogPath -Pattern "SCREEN \[$Tag\] origin=" -TimeoutSec 30 -FromLine $from | Out-Null
    $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $from |
               Where-Object { $_ -match "SCREEN \[$Tag\]" -or $_ -match 'DIALOGS ' })

    $r = @{ Tag = $Tag; Layers = @(); Bitmap = $null; Dialogs = $null; Origin = $null }
    foreach ($l in $lines) {
        if ($l -match 'bitmap@(0x[0-9A-Fa-f]+) w=(\d+) h=(\d+) data=(0x[0-9A-Fa-f]+) bytes=(\d+)') {
            $r.Bitmap = @{ At = $Matches[1]; W = [int]$Matches[2]; H = [int]$Matches[3]
                           Data = $Matches[4]; Bytes = [int]$Matches[5] }
        }
        elseif ($l -match 'origin=\((\d+),(\d+)\)') {
            $r.Origin = "$($Matches[1]),$($Matches[2])"
        }
        elseif ($l -match 'layer=(\d+) used=(\d+) flags=(0x[0-9A-Fa-f]+) rect=\((-?\d+),(-?\d+) (\d+)x(\d+)\) param=(0x[0-9A-Fa-f]+) draw=(0x[0-9A-Fa-f]+) drawStatic=(0x[0-9A-Fa-f]+)') {
            $r.Layers += [pscustomobject]@{
                Index = [int]$Matches[1]; Used = [int]$Matches[2]
                Left = [int]$Matches[4]; Top = [int]$Matches[5]
                Width = [int]$Matches[6]; Height = [int]$Matches[7]
                DrawStatic = $Matches[10]
            }
        }
    }
    $r
}

# The HUD's own dialogs, for the "nothing moved" comparison. Taken from the WHOLE
# log rather than from a marker window: the DIALOGS line is emitted on CHANGE, so
# the window around a marker frequently holds no dialog line at all (or only the
# empty `n=0` of a screen transition). Two filters make the line comparable between
# arms: it must carry StatBtn, i.e. the in-game HUD is actually up, and it must NOT
# carry Tips_Dlg, whose tip string is chosen at random and so differs between two
# runs of the same build.
function Get-HudDialogLine {
    param([Parameter(Mandatory)][string]$LogPath)
    $hit = @(Get-Content -LiteralPath $LogPath |
             Where-Object { $_ -match 'DIALOGS n=\d+' -and $_ -match 'StatBtn' -and $_ -notmatch 'Tips_Dlg' })
    if (-not $hit.Count) { return $null }
    ($hit[-1] -replace '^\[[^\]]*\]\s*', '')
}

function Show-Reading {
    param($R, [string]$Arm)
    Write-Host ""
    Write-Host "  ---- $Arm / $($R.Tag) ----"
    if ($R.Bitmap) {
        Write-Host ("       framebuffer {0}x{1}, data={2}, {3} bytes" -f
                    $R.Bitmap.W, $R.Bitmap.H, $R.Bitmap.Data, $R.Bitmap.Bytes)
    } else { Write-Host '       framebuffer: NOT READ' }
    foreach ($l in $R.Layers | Sort-Object Index) {
        if ($l.Used -eq 0 -and $l.Width -eq 0) { continue }
        Write-Host ("       layer {0} used={1} rect=({2},{3} {4}x{5}) draw={6}" -f
                    $l.Index, $l.Used, $l.Left, $l.Top, $l.Width, $l.Height, $l.DrawStatic)
    }
}

function Invoke-Arm {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Widescreen,
        [Parameter(Mandatory)][string]$LogPath
    )

    if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    $gamePid = 0
    $result = @{ Name = $Name; Menu = $null; InGame = $null; Log = $LogPath
                 Widescreen = $Widescreen; Walked = $false; WalkError = $null
                 WindowW = 0; WindowH = 0; Frame = $null }

    Write-Host ''
    Write-Host "test-widescreen: ARM '$Name' (-Widescreen $Widescreen, stage $Stage)"
    try {
        # -Mode hooktest, not observe: observe is the plugin's off switch and ignores
        # every feature that writes game memory, this one included. hooktest is the
        # LEAST invasive mode that is not the off switch -- one logging-only detour on
        # queueCommand -- so the geometry is the only thing differing between the arms.
        & (Join-Path $scriptDir 'run-with-plugin.ps1') `
            -Mode hooktest -ScreenScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
            -Widescreen $Widescreen -WidescreenStage $Stage `
            -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
                Write-Host "       $_"
                if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
                # The PRESENTED size, which the read-back cannot see. The engine
                # composing a wider frame into its own buffer and the windowed helper
                # still showing a 640-wide window are DIFFERENT OUTCOMES, and only this
                # line separates them -- research/renderer-viewport.md 10 item 2 records
                # the packed helper's behaviour at a non-stock mode as unmeasured.
                if ("$_" -match "class='SWarClass'.*rect=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") {
                    $result.WindowW = [int]$Matches[3] - [int]$Matches[1]
                    $result.WindowH = [int]$Matches[4] - [int]$Matches[2]
                }
            }
        if (-not $gamePid) { throw "test-widescreen: could not parse the game pid for arm '$Name'." }
        $result.Pid = $gamePid
        $h = Get-ScGameWindow -ProcessId $gamePid
        Start-Sleep -Seconds 3

        # The framebuffer is allocated and described by the video init, so stages 0
        # and 1 are already decided at the menu, before any map is loaded.
        $result.Menu = Read-ScreenLayout -Tag "$Name-menu" -LogPath $LogPath
        Show-Reading $result.Menu $Name

        if (-not $SkipInGame) {
            try {
                Write-Host "       walking to a loaded game"
                Send-ScClick -Hwnd $h -X 215 -Y 119
                Send-ScClick -Hwnd $h -X 373 -Y 300
                Start-Sleep -Seconds 1
                Send-ScClick -Hwnd $h -X 75  -Y 111
                Send-ScClick -Hwnd $h -X 516 -Y 392
                Start-Sleep -Seconds 2
                Send-ScClick -Hwnd $h -X 327 -Y 415
                Start-Sleep -Seconds 2
                Assert-ScFixtureStillMine -Run $script:fixtures -MapPath $mapPath
                Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $mapPath | Out-Null
                Set-ScGameType -Hwnd $h -Index 2 -LogPath $LogPath
                Send-ScClick -Hwnd $h -X 516 -Y 393
                Start-Sleep -Seconds 6
                Send-ScClick -Hwnd $h -X 544 -Y 387
                Start-Sleep -Seconds 10
                Dismiss-ScTipsDialog -Hwnd $h -LogPath $LogPath | Out-Null
                Start-Sleep -Seconds 3
                $result.InGame = Read-ScreenLayout -Tag "$Name-ingame" -LogPath $LogPath
                # A reading is only "in game" if the playfield layer is there: the walk
                # can complete every click and still be sitting in a menu.
                $l5 = $result.InGame.Layers | Where-Object Index -eq 5
                $result.Walked = ($null -ne $l5 -and $l5.Used -ne 0)
                if (-not $result.Walked) { $result.WalkError = 'every click was sent but the playfield layer is still not installed' }
                Show-Reading $result.InGame $Name
                if ($true) {
                    New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null
                    $png = Join-Path $FrameDir "s$Stage-$Name-ingame.png"
                    # Client area, not -FullWindow: the question is what the game
                    # PRESENTS, and the border adds pixels that are not the game's.
                    Save-ScWindowImage -Hwnd $h -Path $png | Out-Null
                    $result.Frame = $png
                    Write-Host "       frame captured: $png"
                }
            }
            catch {
                $result.WalkError = $_.Exception.Message
                Write-Host "       walk FAILED: $($result.WalkError)"
            }
        }
    }
    finally {
        if (-not $KeepOpen -and $gamePid -gt 0) {
            try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
            catch { Write-Host "  warn close-game: $($_.Exception.Message)" }
            Start-Sleep -Seconds 2
        }
    }
    $result
}

try {
    Write-Host 'test-widescreen: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '034-widescreen'

    Write-Host 'test-widescreen: generating the fixture'
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $script:fixtures = $fixtures
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 1 -UnitType 'marine' -Player 0 -Race 'terran' -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }

    $arms['ws'] = Invoke-Arm -Name 'widescreen' -Widescreen '1' `
                             -LogPath (Join-Path $LogDir "034-widescreen-s$Stage-ws.log")
    if (-not $NoControl) {
        $arms['control'] = Invoke-Arm -Name 'control' -Widescreen '0' `
                                      -LogPath (Join-Path $LogDir "034-widescreen-s$Stage-control.log")
    }

    Write-Host ''
    Write-Host "test-widescreen: assertions (stage $Stage)"

    $ws = $arms['ws']
    $wsLog = @(Get-Content -LiteralPath $ws.Log)

    # --- the patch set itself ------------------------------------------------
    # Proved POSITIVE before anything is asserted absent: the log must show the
    # install line at all, then show it succeeding, because "no WIDESCREEN line
    # appeared" and "the install refused" look identical in a quiet log
    # (AGENTS.md § "Oracles: absence and defect-era checks").
    $installLines = @($wsLog | Where-Object { $_ -match 'WIDESCREEN install:' })
    Assert-True 'the widescreen arm logged an install attempt' ($installLines.Count -eq 1) `
        "(found $($installLines.Count))"
    $refusals = @($wsLog | Where-Object { $_ -match 'WIDESCREEN REFUSED' })
    Assert-True 'no site was refused' ($refusals.Count -eq 0) `
        ($refusals.Count ? "(first: $($refusals[0]))" : '')
    $activeLine = @($wsLog | Where-Object { $_ -match 'WIDESCREEN ACTIVE: (\d+) patch' })
    Assert-True 'the patch set reports ACTIVE' ($activeLine.Count -eq 1) `
        ($activeLine.Count ? "($($activeLine[0] -replace '.*WIDESCREEN ', ''))" : '(no ACTIVE line)')
    $applied = 0
    if ($activeLine.Count -and $activeLine[0] -match 'ACTIVE: (\d+) patch') { $applied = [int]$Matches[1] }
    Assert-True 'at least one instruction was actually rewritten' ($applied -gt 0) "(applied=$applied)"

    if (-not $NoControl) {
        $ctlLog = @(Get-Content -LiteralPath $arms['control'].Log)
        $off = @($ctlLog | Where-Object { $_ -match 'WIDESCREEN off' })
        Assert-True 'the control arm patched nothing' ($off.Count -eq 1) "(found $($off.Count))"
        $ctlPatches = @($ctlLog | Where-Object { $_ -match 'WIDESCREEN patch ' })
        Assert-True 'the control arm wrote no patch line at all' ($ctlPatches.Count -eq 0) `
            "(found $($ctlPatches.Count))"
    }

    # --- the geometry, read out of the engine --------------------------------
    $wsMenu = $ws.Menu
    Assert-True 'the widescreen arm reached the main menu and the framebuffer was readable' `
        ($null -ne $wsMenu -and $null -ne $wsMenu.Bitmap -and $wsMenu.Bitmap.Data -ne '0x00000000')

    if ($Stage -eq '0') {
        # Stage 0 changes the DISPLAY MODE and nothing the engine composes into.
        # The framebuffer must therefore be untouched -- this assertion fails if a
        # stage 1 patch leaked into stage 0's set.
        Assert-True "stage 0 leaves the framebuffer at the stock ${STOCK_W}x${STOCK_H}" `
            ($wsMenu.Bitmap.W -eq $STOCK_W -and $wsMenu.Bitmap.H -eq $STOCK_H) `
            "(got $($wsMenu.Bitmap.W)x$($wsMenu.Bitmap.H))"
        Assert-True 'stage 0 applied exactly the display-mode sites' ($applied -le 4) "(applied=$applied)"
    }
    else {
        Assert-True "the framebuffer descriptor reads ${WS_W}x${WS_H}" `
            ($wsMenu.Bitmap.W -eq $WS_W -and $wsMenu.Bitmap.H -eq $WS_H) `
            "(got $($wsMenu.Bitmap.W)x$($wsMenu.Bitmap.H))"
        Assert-True "the buffer is width*height = $($WS_W * $WS_H) bytes" `
            ($wsMenu.Bitmap.Bytes -eq ($WS_W * $WS_H)) "(got $($wsMenu.Bitmap.Bytes))"

        # Layer 2 is a STAGE 2 site, not a stage 1 one. Stage 1 widens the
        # framebuffer's PITCH and nothing else: every rectangle, clip and dirty
        # bound stays stock, so the engine keeps composing a 640-wide picture into
        # an 800-wide buffer. That separation is what makes stage 1 checkable at
        # all -- its frame must match the control's down to the animation noise floor.
        $l2 = $wsMenu.Layers | Where-Object Index -eq 2
        if ($Stage -eq '2') {
            Assert-True "the dialog layer covers the whole new screen (${WS_W}x${WS_H})" `
                ($null -ne $l2 -and $l2.Width -eq $WS_W -and $l2.Height -eq $WS_H) `
                "(got $($l2.Width)x$($l2.Height))"
        }
        else {
            Assert-True "stage 1 leaves the dialog layer at the stock ${STOCK_W}x${STOCK_H}" `
                ($null -ne $l2 -and $l2.Width -eq $STOCK_W -and $l2.Height -eq $STOCK_H) `
                "(got $($l2.Width)x$($l2.Height))"
        }
    }

    # What the helper PRESENTS, beside what the engine composed: two different
    # claims, and a wider frame that is never shown wider is not the feature.
    $ctlWin = $NoControl ? '(no control arm)' : "$($arms['control'].WindowW)x$($arms['control'].WindowH)"
    Write-Host "       presented window: widescreen arm $($ws.WindowW)x$($ws.WindowH), control arm $ctlWin"
    if (-not $NoControl -and $Stage -ne '0' -and $ws.WindowW -eq $arms['control'].WindowW) {
        Report-Finding ("the windowed helper presented the SAME $($ws.WindowW)-pixel-wide window " +
                        'in both arms, so whatever extra columns the engine composed are not ' +
                        'reaching the screen through it')
    }

    if (-not $NoControl) {
        $ctlMenu = $arms['control'].Menu
        Assert-True "the CONTROL arm reads the stock ${STOCK_W}x${STOCK_H}" `
            ($null -ne $ctlMenu.Bitmap -and $ctlMenu.Bitmap.W -eq $STOCK_W -and $ctlMenu.Bitmap.H -eq $STOCK_H) `
            "(got $($ctlMenu.Bitmap.W)x$($ctlMenu.Bitmap.H))"
        if ($Stage -ne '0') {
            Assert-True 'the two arms disagree about the framebuffer -- the patch is what changed it' `
                ($wsMenu.Bitmap.W -ne $ctlMenu.Bitmap.W)
        }
    }

    # --- in game: the playfield ---------------------------------------------
    if ($SkipInGame) {
        Report-Finding 'in-game reading skipped (-SkipInGame); layer 5 is unmeasured in this run'
    }
    elseif (-not $ws.Walked) {
        # A walk that did not land is a measurement about the WINDOWED HELPER, not
        # about the geometry -- report it as a finding, not as a geometry failure.
        Report-Finding ("the widescreen arm could not be driven into a game: $($ws.WalkError). " +
                        "research/renderer-viewport.md 10 item 2 records how the packed windowed " +
                        "helper maps input at a non-stock size as UNMEASURED; this run is evidence " +
                        "about that, not about the frame geometry.")
        if ($Stage -eq '2') {
            Assert-True 'stage 2 needs an in-game reading and the walk did not land' $false
        }
    }
    else {
        $g = $ws.InGame
        $l5 = $g.Layers | Where-Object Index -eq 5
        Assert-True 'the playfield layer is installed in game' ($null -ne $l5 -and $l5.Used -ne 0)
        Assert-True 'the playfield draw callback is still 0x004BD580' `
            ($null -ne $l5 -and $l5.DrawStatic -ieq '0x004BD580') "(got $($l5.DrawStatic))"

        if ($Stage -eq '2') {
            Assert-True "the playfield reads ${WS_PF_W}x${WS_PF_H} at (0,0)" `
                ($null -ne $l5 -and $l5.Width -eq $WS_PF_W -and $l5.Height -eq $WS_PF_H -and
                 $l5.Left -eq 0 -and $l5.Top -eq 0) `
                "(got ($($l5.Left),$($l5.Top) $($l5.Width)x$($l5.Height)))"
        }
        else {
            # 9.3 says stages 0 and 1 leave the playfield alone. Asserting it
            # POSITIVELY is what makes the stages separable rather than a story.
            Assert-True "stage $Stage leaves the playfield at the stock ${STOCK_PF_W}x${STOCK_PF_H}" `
                ($null -ne $l5 -and $l5.Width -eq $STOCK_PF_W -and $l5.Height -eq $STOCK_PF_H) `
                "(got $($l5.Width)x$($l5.Height))"
        }

        # ---- THE PLAYFIELD INTERIOR ----------------------------------------
        # A layer rect is the plugin's bookkeeping, not the engine's result: the
        # descriptor and every rectangle can read the new size while the playfield
        # between them is shredded, so the geometry read-back alone cannot pass a
        # frame (AGENTS.md § "Oracles: what counts as a read-back").
        # Both arms load the same fixture at the same start location, so the camera
        # origin matches and the LEFT 640 COLUMNS SHOW THE SAME MAP in either arm --
        # at stage 2 the widescreen frame simply draws more to the right, which the
        # windowed helper crops. The control frame is therefore a per-pixel
        # expectation for the shared region, and any disagreement is damage.
        if (-not $NoControl -and $arms['control'].Walked -and $ws.Frame -and $arms['control'].Frame) {
            # Positive first: an identical camera origin is what makes the control
            # frame an expectation rather than a coincidence.
            Assert-True 'both arms have the camera at the same origin (so the frames are comparable)' `
                ($null -ne $g.Origin -and $g.Origin -eq $arms['control'].InGame.Origin) `
                "(ws=$($g.Origin) control=$($arms['control'].InGame.Origin))"

            $diffOut = & python (Join-Path $scriptDir 'frame-diff.py') `
                        $arms['control'].Frame $ws.Frame 2>&1
            $m = @{}
            foreach ($line in $diffOut) {
                if ("$line" -match '^([a-z_]+)=(.*)$') { $m[$Matches[1]] = $Matches[2] }
            }
            $rowMedian = [double]($m['rowmatch_median'] ?? 0)
            $blackDelta = [double]($m['black_delta'] ?? 1)
            $badRows = [int]($m['bad_rows'] ?? 999)
            $rows = [int]($m['rows_sampled'] ?? 1)
            $diffPx = [int]($m['diff_px'] ?? 999999)
            $diffBlocks = [int]($m['diff_blocks'] ?? 9999)
            $wideRows = [int]($m['wide_rows'] ?? 9999)
            $spanMax = [int]($m['diff_span_max'] ?? 9999)
            Write-Host ("       playfield interior {0}: rowmatch median {1}, black delta {2}, bad rows {3}/{4}" -f
                        $m['region'], $rowMedian, $blackDelta, $badRows, $rows)
            Write-Host ("       full resolution: {0} differing pixels in {1} 32x32 block(s), widest row span {2}px, {3} wide row(s)" -f
                        $diffPx, $diffBlocks, $spanMax, $wideRows)
            if ($badRows -gt 0) { Write-Host "       first bad rows: $($m['bad_row_ys'])" }
            if ($wideRows -gt 0) { Write-Host "       wide rows: $($m['wide_row_ys'])" }

            Assert-True 'the playfield interior matches the control frame row by row' `
                ($rowMedian -ge 0.90) "(median $rowMedian, want >= 0.90)"
            Assert-True 'the widescreen frame is not blacker than the control (nothing went undrawn)' `
                ([math]::Abs($blackDelta) -le 0.03) "(delta $blackDelta, want |d| <= 0.03)"
            Assert-True 'almost no row of the playfield disagrees with the control' `
                ($badRows -le [math]::Ceiling($rows * 0.05)) "($badRows of $rows rows bad)"

            # THE DAMAGE SIGNATURE, at full resolution. "Pixel-identical" is not
            # available as a pass condition: two runs of the SAME build differ by a
            # few hundred pixels because animated map doodads are caught at different
            # phases (measured at stage 0, where both arms compose the identical
            # picture: 586 of 307200 pixels, 7 isolated 32x32 blocks). What separates
            # damage from animation is SHAPE, not count -- a wrong pitch damages whole
            # ROWS across the whole width (a broken stage-1 build disagreed on 163 of
            # 190 rows, each spanning x=5..639) while animation spans no row. So the
            # assertion is on the row span, and the pixel count is REPORTED beside the
            # measured noise floor rather than asserted against zero.
            Assert-True 'no row of the playfield is damaged across its width (the stride-error signature)' `
                ($wideRows -eq 0) "($wideRows row(s) with a diff span over half the width; span max ${spanMax}px)"
            if ($diffPx -gt 3000) {
                Report-Finding ("$diffPx pixels differ in $diffBlocks block(s) -- far above the ~600-pixel " +
                                'animation noise floor measured at stage 0, so this is unlikely to be animation')
            }
        }

        # The HUD must not move. Its dialogs carry absolute coordinates
        # (research/hud-selection-row.md, research/command-card.md) and the premise of
        # the wider screen is that they stay put, with the extra screen blank beside.
        if (-not $NoControl -and $arms['control'].Walked) {
            $wsDlg = Get-HudDialogLine -LogPath $ws.Log
            $ctlDlg = Get-HudDialogLine -LogPath $arms['control'].Log
            # Positive first: the line has to exist in both arms before its equality
            # is worth anything (AGENTS.md § "Oracles: absence and defect-era checks").
            Assert-True 'both arms logged the in-game HUD dialog set' `
                ($null -ne $wsDlg -and $null -ne $ctlDlg)
            Assert-True 'the HUD dialogs are at identical coordinates in both arms' `
                ($null -ne $wsDlg -and $wsDlg -eq $ctlDlg) `
                ($wsDlg -eq $ctlDlg ? '' : "(differs)")
            if ($null -ne $wsDlg -and $wsDlg -ne $ctlDlg) {
                Write-Host "       ws     : $wsDlg"
                Write-Host "       control: $ctlDlg"
            }
        }
    }
}
catch {
    Write-Host "  FAIL suite: $($_.Exception.Message)"
    $script:failures++
}
finally {
    if ($fixtures) {
        try { Remove-ScOwnFixture -Run $fixtures | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
        try { Remove-ScOwnFixtureDir -Dir $fixtures.Dir | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
    }
    if ($launchLock) { try { Exit-ScLaunchLock -Lock $launchLock } catch { } }
}

if ($CaptureFrames) {
    Write-Host ''
    Write-Host 'test-widescreen: frames for a human to open (gitignored path, never committed):'
    foreach ($k in @('ws', 'control')) {
        if ($arms[$k] -and $arms[$k].Frame) { Write-Host "       $($arms[$k].Name): $($arms[$k].Frame)" }
    }
}

Write-Host ''
if ($script:failures -eq 0) { Write-Host "test-widescreen: PASS (0 failures, stage $Stage)" }
else { Write-Host "test-widescreen: FAIL ($script:failures failures, stage $Stage)" }
exit ($script:failures -gt 0 ? 1 : 0)
