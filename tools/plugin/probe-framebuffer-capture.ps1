#Requires -Version 7
<#
.SYNOPSIS
Task 063. Answers: can we see the engine's FULL composed frame without presenting
it and without touching the user's display? Positive control first, on a stock
640-wide game, then the 800-wide stage-1 build.

.DESCRIPTION
Task 034 judged stage 2 undevelopable because "every frame this task has ever
captured shows only the left 640 columns" -- but those frames went through the
PRESENTED window, and WMode.dll presents columns 0..639 whatever it is asked
(research/renderer-viewport.md 12.6/12.10). The engine's own framebuffer is a
flat 8-bit surface described at 0x006CEFF0 and at stage 1 it is demonstrably
800 wide. This probe reads THAT, via the plugin's FRAMEDUMP (scplugin.cpp,
task 063), and validates the instrument before believing it:

  ARM 1 -- stock (the positive control, and it is not optional). The dump must
  reproduce a KNOWN-GOOD 640x480 frame. "Reproduce" is measured, not eyeballed:
  the dump holds palette indices and the presented window holds the RGB those
  indices were painted as, at 1:1 (12.6) -- so over pixels the window shows
  UNCHANGED across two captures bracketing the dump, every occurrence of index
  i must land on ONE RGB. frame-capture.py `check` builds that mapping and
  reports its consistency; a torn, misaligned or wrong-pitch dump collapses it
  (proved offline against synthetic dumps: a 160-byte row shift scores 0.58).
  The mapping doubles as the scene's palette, which renders the dump into a
  PNG a human can open next to the window capture.

  ARM 2 -- stage 1 (-Widescreen 1 -WidescreenStage 1, the known-good 800-pitch
  build). Same consistency check over the 640 columns the window can vouch for:
  it can only hold if the dump's rows were extracted at the TRUE pitch of 800,
  so it is also the proof that the instrument reads the full-width geometry
  correctly. The dump's right 160 columns are then the columns NO instrument
  in this repo has ever seen; they are reported (band stats) and rendered.

  CROSS-CHECK -- the two arms' in-game dumps compare index-for-index over the
  playfield they share (same fixture, same start), with frame-diff's row-span
  discriminator: stage 1's left 640 columns must match stock (wide_rows=0),
  which re-proves 034's stage-1 verdict through the new instrument.

READ-ONLY toward the game in the stock arm (-Mode observe); the stage-1 arm
patches geometry in-process exactly as test-widescreen.ps1 does. StarCraft.exe
on disk is untouched in both. Dumps and PNGs reproduce game artwork: they stay
on the gitignored diagnostic path and are never committed (hard rule 1); what
this suite prints is counts and fractions.

.EXAMPLE
./tools/plugin/probe-framebuffer-capture.ps1

.EXAMPLE
./tools/plugin/probe-framebuffer-capture.ps1 -StockOnly
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\063-frames',
    # One arm only, for iterating. A RESULT needs both: the stock arm is the
    # instrument's positive control, the stage-1 arm is the question.
    [switch]$StockOnly,
    [switch]$Stage1Only,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

if (-not $FixtureDir) {
    $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t063-framecap' -Suite 'framecap'
}
$mapName = 'framecap.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$py = 'python'
$tool = Join-Path $scriptDir 'frame-capture.py'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null

$script:failures = 0
$script:step = 0
$launchLock = $null
$fixtures = $null
$arms = @{}

function Assert-True {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    $script:step++
    if ($Ok) { Write-Host "  [$script:step] OK   $What $Detail" }
    else { Write-Host "  [$script:step] FAIL $What $Detail"; $script:failures++ }
}

function Report-Finding {
    param([string]$What)
    Write-Host "  ---- FINDING: $What"
}

# Run frame-capture.py, echo its lines, hand back the key=value map.
function Invoke-FrameTool {
    param([Parameter(Mandatory)][string[]]$ToolArgs)
    $out = & $py $tool @ToolArgs 2>&1
    $m = @{}
    foreach ($line in $out) {
        Write-Host "         $line"
        if ("$line" -match '^([a-z_]+)=(.*)$') { $m[$Matches[1]] = $Matches[2] }
    }
    $m
}

# One captured point: window PNG, marker-driven dump, window PNG again. The two
# window captures BRACKET the dump so `check` can restrict its mapping to pixels
# stable across the whole interval -- that is what makes menu/doodad animation
# noise instead of poison.
function Get-CapturePoint {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$LogPath
    )
    $before = Join-Path $FrameDir "$Tag-before.png"
    $after = Join-Path $FrameDir "$Tag-after.png"
    $from = Get-ScLogLineCount -LogPath $LogPath
    Save-ScWindowImage -Hwnd $Hwnd -Path $before | Out-Null
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    $lines = Wait-ScLogMatch -LogPath $LogPath -Pattern "FRAMEDUMP \[$Tag\] " -TimeoutSec 30 -FromLine $from
    Save-ScWindowImage -Hwnd $Hwnd -Path $after | Out-Null

    $r = @{ Tag = $Tag; Before = $before; After = $after
            Dump = $null; W = 0; H = 0; Reads = 0; Stable = 0; Refused = $null }
    foreach ($l in $lines) {
        if ($l -match 'FRAMEDUMP \[[^\]]+\] w=(\d+) h=(\d+) bytes=\d+ reads=(\d+) stable=(\d) path=(.+)$') {
            $r.W = [int]$Matches[1]; $r.H = [int]$Matches[2]
            $r.Reads = [int]$Matches[3]; $r.Stable = [int]$Matches[4]
            $r.Dump = $Matches[5].Trim()
        }
        elseif ($l -match 'FRAMEDUMP \[[^\]]+\] refused: (.+)$') { $r.Refused = $Matches[1] }
    }
    # The SCREEN scan fires on the same marker; keep the camera origin so the
    # cross-arm diff can prove both arms were looking at the same place.
    $originHit = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $from |
                   Where-Object { $_ -match "SCREEN \[$Tag\] origin=\((\d+),(\d+)\)" })
    if ($originHit.Count -and $originHit[0] -match 'origin=\((\d+),(\d+)\)') {
        $r.Origin = "$($Matches[1]),$($Matches[2])"
    }
    Write-Host ("       $Tag : dump=$(if ($r.Dump) { Split-Path $r.Dump -Leaf } else { 'NONE' }) " +
                "w=$($r.W) h=$($r.H) reads=$($r.Reads) stable=$($r.Stable)" +
                $(if ($r.Refused) { " REFUSED: $($r.Refused)" } else { '' }))
    $r
}

# One arm: launch, capture at the menu, walk to a game, capture in game, close.
function Invoke-Arm {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Widescreen
    )

    $log = Join-Path $LogDir "063-framecap-$Name.log"
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    $gamePid = 0
    $result = @{ Name = $Name; Log = $log; Menu = $null; InGame = $null
                 Walked = $false; WalkError = $null }

    Write-Host ''
    Write-Host "probe-framecap: ARM '$Name' (-Widescreen $Widescreen)"
    try {
        # Stock arm: -Mode observe -- the plugin's off switch, read-only end to
        # end, same as every observe-mode oracle. Stage-1 arm: hooktest, the
        # least invasive mode that is not the off switch, because the widescreen
        # patch is ignored outright in observe (exactly test-widescreen's choice
        # and reasoning).
        $mode = ($Widescreen -eq '1') ? 'hooktest' : 'observe'
        & (Join-Path $scriptDir 'run-with-plugin.ps1') `
            -Mode $mode -ScreenScan 1 -FrameDump $FrameDir -InjectWindowedHelper WMode `
            -NoLaunchLock -Widescreen $Widescreen -WidescreenStage 1 `
            -GameDir $GameDir -LogPath $log 6>&1 | ForEach-Object {
                Write-Host "       $_"
                if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
            }
        if (-not $gamePid) { throw "probe-framecap: could not parse the game pid for arm '$Name'." }
        $result.Pid = $gamePid
        $h = Get-ScGameWindow -ProcessId $gamePid
        Start-Sleep -Seconds 3

        # CAPTURE 1 -- the main menu. The framebuffer exists as soon as the
        # video init has run, so the instrument is already answerable here.
        $result.Menu = Get-CapturePoint -Hwnd $h -Tag "$Name-menu" -LogPath $log

        try {
            Write-Host '       walking to a loaded game'
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
            Set-ScGameType -Hwnd $h -LogPath $log -Index 2
            Send-ScClick -Hwnd $h -X 516 -Y 393
            Start-Sleep -Seconds 6
            Send-ScClick -Hwnd $h -X 544 -Y 387
            Start-Sleep -Seconds 10
            Dismiss-ScTipsDialog -Hwnd $h -LogPath $log | Out-Null
            Start-Sleep -Seconds 3

            # CAPTURE 2 -- in game, where the playfield layer is installed and
            # the frame carries terrain rather than menu art.
            $result.InGame = Get-CapturePoint -Hwnd $h -Tag "$Name-ingame" -LogPath $log
            $result.Walked = ($null -ne $result.InGame.Dump)
        }
        catch {
            $result.WalkError = $_.Exception.Message
            Write-Host "       walk FAILED: $($result.WalkError)"
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
    Write-Host 'probe-framecap: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '063-framecap'

    Write-Host 'probe-framecap: generating the fixture'
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $script:fixtures = $fixtures
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount 1 -UnitType 'marine' -Player 0 -Race 'terran' -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }

    if (-not $Stage1Only) { $arms['stock'] = Invoke-Arm -Name 'stock' -Widescreen '0' }
    if (-not $StockOnly)  { $arms['s1']    = Invoke-Arm -Name 's1'    -Widescreen '1' }

    Write-Host ''
    Write-Host 'probe-framecap: assertions'

    # ---- ARM 1: the positive control --------------------------------------
    # What the screen Bitmap holds, measured by this suite's first run
    # (2026-08-13) and asserted to stay that way:
    #   * at the MAIN MENU the buffer is ALL INDEX 0 in both arms -- the glue
    #     screens do not compose into 0x006CEFF0 at all. A menu consistency
    #     check is aimed at a scene that is not there, so the menu point only
    #     proves the dump machinery and reports the content.
    #   * IN GAME the buffer holds the playfield composition and the top-strip
    #     counters, but NOT the console/HUD dialogs (they draw into their own
    #     surfaces -- the ones sc_queueind reads) and NOT the cursor. So the
    #     trust check runs over the PURE PLAYFIELD region (128,20)-(512,320),
    #     where the measured consistency is 0.989 in both arms; the ~1%
    #     residue is animated sprites caught A->B->A across the bracket, in
    #     isolated blobs with no row structure. Threshold 0.97: far above the
    #     0.58 a wrong-pitch dump scores, comfortably below the animation
    #     ceiling.
    $PF = @('--x0', '128', '--y0', '20', '--map-w', '512', '--y1', '320')
    if ($arms['stock']) {
        $st = $arms['stock']
        foreach ($pt in @($st.Menu, $st.InGame)) {
            if ($null -eq $pt) { continue }
            Assert-True "[stock/$($pt.Tag)] a dump was written" ($null -ne $pt.Dump) `
                ($pt.Refused ? "(refused: $($pt.Refused))" : '')
            if ($null -eq $pt.Dump) { continue }
            Assert-True "[stock/$($pt.Tag)] the dump is the stock 640x480" `
                ($pt.W -eq 640 -and $pt.H -eq 480) "(got $($pt.W)x$($pt.H))"
            Assert-True "[stock/$($pt.Tag)] the copy settled (two consecutive reads byte-equal)" `
                ($pt.Stable -eq 1) "(reads=$($pt.Reads))"
        }

        if ($st.Menu -and $st.Menu.Dump) {
            Write-Host '       [stock/menu] buffer content (glue screens do not compose into the screen Bitmap):'
            $mb = Invoke-FrameTool -ToolArgs @('band', '--dump', $st.Menu.Dump, '--x0', '0')
            Report-Finding "menu-time screen Bitmap: $($mb['band_distinct']) distinct index value(s), top $($mb['band_top'])"
        }

        if ($st.InGame -and $st.InGame.Dump) {
            $pt = $st.InGame
            Write-Host "       [stock/$($pt.Tag)] index->RGB consistency vs the window, pure playfield:"
            $m = Invoke-FrameTool -ToolArgs (@('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After) + $PF)
            # The window must hold a PICTURE before its vote counts: a dead
            # capture maps every index to black, each one perfectly
            # consistently, and the consistency figure goes vacuous (this
            # repo's house defect).
            Assert-True "[stock/$($pt.Tag)] the window capture holds a picture (>= 32 distinct colours)" `
                ([int]($m['window_distinct_rgb'] ?? 0) -ge 32) "(got $($m['window_distinct_rgb']))"
            Assert-True "[stock/$($pt.Tag)] the dump reproduces the presented playfield (consistency >= 0.97)" `
                ([double]($m['consist_frac'] ?? 0) -ge 0.97) "(got $($m['consist_frac']))"
            Assert-True "[stock/$($pt.Tag)] the mapping had pixels to stand on (stable fraction >= 0.5)" `
                ([double]($m['stable_frac'] ?? 0) -ge 0.5) "(got $($m['stable_frac']))"
            # Second pass, full frame, unasserted: its mapping covers every
            # index on screen, which is what makes the rendered PNG whole.
            Invoke-FrameTool -ToolArgs @('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After,
                    '--render', (Join-Path $FrameDir "$($pt.Tag)-render.png"),
                    '--save-palette', (Join-Path $FrameDir "$($pt.Tag)-palette.json")) | Out-Null
        }
    }

    # ---- ARM 2: the 800-wide frame ----------------------------------------
    if ($arms['s1']) {
        $s1 = $arms['s1']
        foreach ($pt in @($s1.Menu, $s1.InGame)) {
            if ($null -eq $pt) { continue }
            Assert-True "[s1/$($pt.Tag)] a dump was written" ($null -ne $pt.Dump) `
                ($pt.Refused ? "(refused: $($pt.Refused))" : '')
            if ($null -eq $pt.Dump) { continue }
            Assert-True "[s1/$($pt.Tag)] the dump is the FULL stage-1 800x480" `
                ($pt.W -eq 800 -and $pt.H -eq 480) "(got $($pt.W)x$($pt.H))"
            Assert-True "[s1/$($pt.Tag)] the copy settled" ($pt.Stable -eq 1) "(reads=$($pt.Reads))"

            # The columns nothing has ever presented. At stage 1 the engine
            # still COMPOSES 640 wide, so the extra 160 columns hold whatever
            # the (patched, 800-aware) screen clear left there -- the point is
            # that the instrument now SEES them at all, and what it sees is
            # reported rather than guessed.
            Write-Host "       [s1/$($pt.Tag)] the right 160 columns (x=640..799), never presented by anything:"
            $b = Invoke-FrameTool -ToolArgs @('band', '--dump', $pt.Dump, '--x0', '640')
            Assert-True "[s1/$($pt.Tag)] the band was readable end to end" `
                ([int]($b['band_px'] ?? 0) -eq 160 * 480) "(got $($b['band_px']) px)"
        }

        if ($s1.InGame -and $s1.InGame.Dump) {
            $pt = $s1.InGame
            # The consistency check over the window-vouched playfield can only
            # hold if rows were extracted at the TRUE pitch of 800 -- a
            # 640-pitch misread shifts row y by 160*y bytes and lands on 0.58
            # against the synthetic control. So this line is the proof that
            # the instrument reads the full-width geometry, not just more
            # bytes. Same region and threshold as the stock arm, same reasons.
            Write-Host "       [s1/$($pt.Tag)] consistency vs the window, pure playfield, at pitch 800:"
            $m = Invoke-FrameTool -ToolArgs (@('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After) + $PF)
            Assert-True "[s1/$($pt.Tag)] the window capture holds a picture (>= 32 distinct colours)" `
                ([int]($m['window_distinct_rgb'] ?? 0) -ge 32) "(got $($m['window_distinct_rgb']))"
            Assert-True "[s1/$($pt.Tag)] the dump reproduces the presented playfield at pitch 800 (>= 0.97)" `
                ([double]($m['consist_frac'] ?? 0) -ge 0.97) "(got $($m['consist_frac']))"
            Invoke-FrameTool -ToolArgs @('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After, '--map-w', '640',
                    '--render', (Join-Path $FrameDir "$($pt.Tag)-render.png"),
                    '--save-palette', (Join-Path $FrameDir "$($pt.Tag)-palette.json")) | Out-Null
        }

        # ---- the cross-check: stage 1's left 640 vs stock, index for index --
        if ($arms['stock'] -and $arms['stock'].Walked -and $s1.Walked) {
            $sameOrigin = ($null -ne $arms['stock'].InGame.Origin -and
                           $arms['stock'].InGame.Origin -eq $s1.InGame.Origin)
            Assert-True 'both arms have the camera at the same origin (so the dumps are comparable)' `
                $sameOrigin "(stock=$($arms['stock'].InGame.Origin) s1=$($s1.InGame.Origin))"
            if ($sameOrigin) {
                Write-Host '       stage-1 left 640 columns vs stock, index for index (playfield interior):'
                $dm = Invoke-FrameTool -ToolArgs @('diff',
                        '--a', $arms['stock'].InGame.Dump, '--b', $s1.InGame.Dump,
                        '--x0', '0', '--x1', '640', '--y0', '20', '--y1', '400')
                Assert-True 'no playfield row differs across its width (stage 1 composes the same left 640)' `
                    ([int]($dm['wide_rows'] ?? 999) -eq 0) `
                    "(wide_rows=$($dm['wide_rows']), span_max=$($dm['diff_span_max']))"
            }
        }
        elseif ($arms['stock']) {
            Report-Finding 'one arm did not reach a game; the cross-arm playfield diff was not run'
        }
    }

    foreach ($a in $arms.Values) {
        if ($a.WalkError) {
            Report-Finding "arm '$($a.Name)' walk: $($a.WalkError)"
        }
    }
}
catch {
    Write-Host "  FAIL probe: $($_.Exception.Message)"
    $script:failures++
}
finally {
    if ($fixtures) {
        try { Remove-ScOwnFixture -Run $fixtures | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
        try { Remove-ScOwnFixtureDir -Dir $fixtures.Dir | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
    }
    if ($launchLock) { try { Exit-ScLaunchLock -Lock $launchLock } catch { } }
}

Write-Host ''
Write-Host 'probe-framecap: dumps + renders (gitignored diagnostic path, never committed):'
foreach ($a in $arms.Values) {
    foreach ($pt in @($a.Menu, $a.InGame)) {
        if ($pt -and $pt.Dump) {
            Write-Host "       $($pt.Tag) : $($pt.Dump)"
            $render = Join-Path $FrameDir "$($pt.Tag)-render.png"
            if (Test-Path -LiteralPath $render) { Write-Host "       $($pt.Tag) : $render" }
        }
    }
}

Write-Host ''
if ($script:failures -eq 0) { Write-Host 'probe-framecap: PASS (0 failures)' }
else { Write-Host "probe-framecap: FAIL ($script:failures failures)" }
exit ($script:failures -gt 0 ? 1 : 0)
