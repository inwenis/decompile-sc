#Requires -Version 7
<#
.SYNOPSIS
Reads the engine's FULL composed frame without presenting it and without
touching the user's display: a stock 640-wide positive control first, then the
wide build.

.DESCRIPTION
A frame captured through the PRESENTED window can only ever show columns 0..639
-- WMode.dll presents that width whatever it is asked, see
research/renderer-viewport.md 12.6/12.10. The engine's own framebuffer is a flat
8-bit surface described at 0x006CEFF0, at the patched width, and the plugin's
FRAMEDUMP reads THAT. Consistency is the check the whole probe rests on: the
dump holds palette indices and the window holds the RGB those indices were
painted as, at 1:1 (12.6), so over the pixels the window shows UNCHANGED across
the two captures bracketing the dump, every occurrence of index i must land on
ONE RGB. The stock arm is the instrument's positive control and is not optional;
the wide arms repeat that check over the 640 columns the window can vouch for,
which holds only if rows were extracted at the TRUE pitch -- the proof that
full-width geometry is read, not just more bytes.

Read-only toward the game in the stock arm (-Mode observe); the wide arms patch
geometry in-process as test-widescreen.ps1 does, leaving StarCraft.exe on disk
untouched. Dumps and PNGs reproduce game artwork: they stay on the gitignored
diagnostic path and are never committed (AGENTS.md § "Hard rules").

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
    # Run stock + STAGE 2 instead of stock + stage 1. The stage-2 arm is
    # captured TWICE in game a few seconds apart -- a single capture cannot
    # tell "changes nothing" from "changes something intermittently".
    [switch]$Stage2,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

# The geometry under test comes from the generated table, never from this file.
$ws = Get-ScWideGeometry
$SCREEN_W = $ws.W; $SCREEN_H = $ws.H; $STOCK_W = $ws.StockW
$BAND_W = $SCREEN_W - $STOCK_W          # the columns nothing presented before widescreen
# The 36-marine fixture's sight explores the terrain to map x ~1332 (measured at
# three origins and a sub-tile scroll, research/renderer-viewport.md 16.4). At
# origin O the explored part of the right band is screen x 640..(1332-O), and
# everything past it is LEGITIMATE shroud -- so the band's expected map fraction
# is derived from that edge, not fixed: at 800 wide 148/160 = 0.925, at 1280
# wide 148/640 = 0.231.
$EXPLORED_EDGE_X = 1332

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

# The two window captures BRACKET the dump so `check` can restrict its mapping
# to pixels stable across the whole interval -- that is what makes menu/doodad
# animation noise instead of poison.
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

function Invoke-Arm {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Widescreen,
        [string]$Stage = '1',
        # After the in-game capture, move the camera by minimap click and
        # capture at each stop -- scrolled (+4 tiles right), mid (back near
        # start), scrolled2 (same click as scrolled, so a same-origin pair
        # exists). The seam's zeroruns across these discriminate a screen-space
        # defect (stays at the same x) from a map-space one (moves with the map).
        [switch]$ScrollCaptures,
        # Deliberately incoherent %SCPLUGIN_WS_ONLY% subset -- the DEFECT arm,
        # dense_rows' live positive control: a new oracle must be seen failing
        # on real damage before its green is trusted.
        [string]$WsOnly = ''
    )

    $log = Join-Path $LogDir "063-framecap-$Name.log"
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    $gamePid = 0
    $result = @{ Name = $Name; Log = $log; Menu = $null; InGame = $null
                 Scrolled = $null; Mid = $null; Scrolled2 = $null; ScrollMid = $null
                 WsVerdict = $null; WsFilter = $null
                 Walked = $false; WalkError = $null }

    Write-Host ''
    Write-Host "probe-framecap: ARM '$Name' (-Widescreen $Widescreen)"
    try {
        # Stock arm: -Mode observe -- the plugin's off switch, read-only end to
        # end. Wide arm: hooktest, the least invasive mode that is not the off
        # switch, because the widescreen patch is ignored outright in observe
        # (test-widescreen.ps1 chooses it for the same reason).
        $mode = ($Widescreen -eq '1') ? 'hooktest' : 'observe'
        # The defect arm's filter travels by environment; set it for THIS arm
        # only and clear it in finally -- an unannounced leftover subset is the
        # exact mistake the plugin's filter log line exists to catch.
        if ($WsOnly) { $env:SCPLUGIN_WS_ONLY = $WsOnly }
        & (Join-Path $scriptDir 'run-with-plugin.ps1') `
            -Mode $mode -ScreenScan 1 -FrameDump $FrameDir -InjectWindowedHelper WMode `
            -NoLaunchLock -Widescreen $Widescreen -WidescreenStage $Stage `
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
            if ($ScrollCaptures) {
                # The fixture map is 128x96 tiles and the game centres the start
                # location at origin (544,416) = tile (17,13). Minimap
                # click-to-centre (stock 20/13-tile arithmetic) puts a click at
                # tile (31,19) at origin x = (31-10)*32 = 672 (+4 tiles right),
                # and a click at (27,19) back at x = 544. y lands at 400, not
                # 416 -- the 13-tile half-extent is 6.5 tiles, so the exact
                # start origin is unreachable by minimap; the same-origin pair
                # is therefore scrolled vs scrolled2, two identical clicks.
                $right = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 -TileX 31 -TileY 19
                $back = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 -TileX 27 -TileY 19
                Send-ScClick -Hwnd $h -X $right.X -Y $right.Y
                Start-Sleep -Seconds 3
                $result.Scrolled = Get-CapturePoint -Hwnd $h -Tag "$Name-scrolled" -LogPath $log
                Send-ScClick -Hwnd $h -X $back.X -Y $back.Y
                Start-Sleep -Seconds 3
                $result.Mid = Get-CapturePoint -Hwnd $h -Tag "$Name-mid" -LogPath $log
                Send-ScClick -Hwnd $h -X $right.X -Y $right.Y
                Start-Sleep -Seconds 3
                $result.Scrolled2 = Get-CapturePoint -Hwnd $h -Tag "$Name-scrolled2" -LogPath $log

                # Every minimap capture rests at a TILE-ALIGNED origin --
                # click-to-centre lands on multiples of 32 -- leaving the fog
                # cell pipeline's sub-tile alignment terms ((origin>>3)&3 in the
                # renderer, &0x1F in the change detector) unexercised. A held
                # arrow key drives the smooth stepper scroll and can stop
                # between tile boundaries; whether a posted WM_KEYDOWN reaches
                # the engine's scroll is empirical (drive-game.ps1's KNOWN LIMIT
                # note), so the origin assertion downstream decides and a
                # failure means "scroll it another way", not "done". The scroll
                # runs >= 850 px/s: a 420ms hold reaches the tile-aligned left
                # clamp, so VK_RIGHT for 100ms from origin (704,416) stops
                # ~80-90 px right, almost never on a multiple of 32.
                Send-ScKey -Hwnd $h -VirtualKey 0x27 -HoldMs 100 -SettleMs 500
                $result.ScrollMid = Get-CapturePoint -Hwnd $h -Tag "$Name-scrollmid" -LogPath $log
            }
            # The WIDESCREEN install verdict, read from the plugin's own log --
            # an arm whose table was REFUSED runs a stock geometry and every
            # downstream diff would pass vacuously (absence must be proved
            # positive; the ACTIVE line is the positive). The filter line is the
            # same proof for the SUBSET question: the full arm must say
            # "(unset, whole stage applied)", the defect arm must name its
            # subset with a non-zero skip count.
            $wsLines = @(Get-Content -LiteralPath $log |
                         Where-Object { $_ -match 'WIDESCREEN (ACTIVE|INCOMPLETE|REFUSED)' })
            if ($wsLines.Count) { $result.WsVerdict = $wsLines[0] }
            $fLines = @(Get-Content -LiteralPath $log |
                        Where-Object { $_ -match 'WIDESCREEN filter:' })
            if ($fLines.Count) { $result.WsFilter = $fLines[0] }
        }
        catch {
            $result.WalkError = $_.Exception.Message
            Write-Host "       walk FAILED: $($result.WalkError)"
        }
    }
    finally {
        if ($WsOnly) { Remove-Item Env:SCPLUGIN_WS_ONLY -ErrorAction SilentlyContinue }
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
    # Stage-2 runs spread 36 marines on a 64px grid: their combined sight
    # (~7 tiles beyond a ~384px block) explores the terrain under screen
    # x=640..799, so the right band holds MAP rather than legitimate shroud.
    # With a single marine that band is legitimately SHROUD-black even in a
    # correct build, and the band assertions would be vacuously failable.
    $unitCount = $Stage2 ? 36 : 1
    $spacing = 64
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $unitCount -GridSpacing $spacing -UnitType 'marine' `
            -Player 0 -Race 'terran' -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }
    # A generation that failed leaves no file, and the browser walk's re-check
    # then reports the map "gone between generation and launch -- another
    # worker's cleanup took it": a wrong CULPRIT asserted from no evidence.
    # Refuse here, where the generator's own traceback is still on the screen.
    if (-not (Test-Path -LiteralPath $mapPath)) {
        throw "probe-framecap: the fixture was never generated ($mapPath does not exist) -- read the generator output above; nothing was launched."
    }

    if ($Stage2) {
        $arms['stock'] = Invoke-Arm -Name 'stock' -Widescreen '0'
        # The DEFECT arm: stage 2 filtered to the 12 MEGATILE READ OFFSETS alone
        # (terrain.mt.rNcM). They step the terrain-scratch read by the widened
        # pitch while the scratch is still WRITTEN at the stock 672 pitch (its
        # size/pitch/rows are not in the subset), so every megatile sub-cell is
        # read from the wrong scratch row and the whole playfield renders dense
        # garbage -- known-damaged BY CONSTRUCTION. dense_rows must read RED on it
        # before its green on the full arm is worth anything. It is a READ
        # mismatch only, so the writes stay bounded (the scratch is stock-size)
        # and the damage renders rather than corrupts. This subset is geometry-
        # robust: the read/write pitch mismatch is hard whatever the height,
        # where the whole 'terrain' group is now coherent enough to smear WIDE
        # rather than DENSE.
        $arms['s2defect'] = Invoke-Arm -Name 's2defect' -Widescreen '1' -Stage '2' -WsOnly 'terrain.mt'
        $arms['s2'] = Invoke-Arm -Name 's2' -Widescreen '1' -Stage '2' -ScrollCaptures
    }
    else {
        if (-not $Stage1Only) { $arms['stock'] = Invoke-Arm -Name 'stock' -Widescreen '0' }
        if (-not $StockOnly)  { $arms['s1']    = Invoke-Arm -Name 's1'    -Widescreen '1' }
    }

    Write-Host ''
    Write-Host 'probe-framecap: assertions'

    # ---- ARM 1: the positive control --------------------------------------
    # What the screen Bitmap holds, measured and asserted to stay that way:
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
            # Alignment is pinned: auto-search mislocks on the 36-marine fixture
            # (0.33867 auto vs 0.98477 pinned over the same brackets).
            Write-Host "       [stock/$($pt.Tag)] index->RGB consistency vs the window, pure playfield, align pinned (5,32):"
            $m = Invoke-FrameTool -ToolArgs (@('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After,
                    '--align-dx', '5', '--align-dy', '32') + $PF)
            # The window must hold a PICTURE before its vote counts: a dead
            # capture maps every index to black, each one perfectly
            # consistently, and the consistency figure goes vacuous.
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
            Assert-True "[s1/$($pt.Tag)] the dump is the FULL stage-1 $($SCREEN_W)x$($SCREEN_H)" `
                ($pt.W -eq $SCREEN_W -and $pt.H -eq $SCREEN_H) "(got $($pt.W)x$($pt.H))"
            if ($pt.Tag -match 'menu') {
                Write-Host "       [s1/$($pt.Tag)] settle REPORTED not asserted (reads=$($pt.Reads)): an animating menu over a $($SCREEN_W)x$($SCREEN_H) buffer does not settle, and no diff reads it"
            } else {
                Assert-True "[s1/$($pt.Tag)] the copy settled" ($pt.Stable -eq 1) "(reads=$($pt.Reads))"
            }

            # At stage 1 the engine still COMPOSES 640 wide, so the extra
            # columns hold whatever the (patched, width-aware) screen clear
            # left there: nothing presents them, so what the dump holds there
            # is reported rather than guessed.
            Write-Host "       [s1/$($pt.Tag)] the right $BAND_W columns (x=$STOCK_W..$($SCREEN_W - 1)), never presented by anything:"
            $b = Invoke-FrameTool -ToolArgs @('band', '--dump', $pt.Dump, '--x0', "$STOCK_W")
            Assert-True "[s1/$($pt.Tag)] the band was readable end to end" `
                ([int]($b['band_px'] ?? 0) -eq $BAND_W * $SCREEN_H) "(got $($b['band_px']) px)"
        }

        if ($s1.InGame -and $s1.InGame.Dump) {
            $pt = $s1.InGame
            # The consistency check over the window-vouched playfield can only
            # hold if rows were extracted at the TRUE pitch of 800 -- a
            # 640-pitch misread shifts row y by 160*y bytes and lands on 0.58
            # against the synthetic control. Same region and threshold as the
            # stock arm, same reasons.
            Write-Host "       [s1/$($pt.Tag)] consistency vs the window, pure playfield, at pitch ${SCREEN_W}:"
            $m = Invoke-FrameTool -ToolArgs (@('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After) + $PF)
            Assert-True "[s1/$($pt.Tag)] the window capture holds a picture (>= 32 distinct colours)" `
                ([int]($m['window_distinct_rgb'] ?? 0) -ge 32) "(got $($m['window_distinct_rgb']))"
            Assert-True "[s1/$($pt.Tag)] the dump reproduces the presented playfield at pitch $SCREEN_W (>= 0.97)" `
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

    # ---- ARM 3: the defect arm, dense_rows' live positive control ----------
    if ($arms['s2defect']) {
        $sd = $arms['s2defect']
        Assert-True '[s2defect] the (filtered) table is ACTIVE with 0 refused' `
            ($null -ne $sd.WsVerdict -and $sd.WsVerdict -match 'WIDESCREEN ACTIVE' -and
             $sd.WsVerdict -match ', 0 refused') "($($sd.WsVerdict))"
        Assert-True '[s2defect] the filter line names the terrain subset with sites skipped' `
            ($null -ne $sd.WsFilter -and $sd.WsFilter -match 'WS_ONLY%=terrain' -and
             $sd.WsFilter -notmatch ' 0 stage-2 site\(s\) skipped') "($($sd.WsFilter))"
        if ($sd.InGame -and $sd.InGame.Dump) {
            Assert-True "[s2defect] the dump is the full $($SCREEN_W)x$($SCREEN_H), settled" `
                ($sd.InGame.W -eq $SCREEN_W -and $sd.InGame.H -eq $SCREEN_H -and $sd.InGame.Stable -eq 1) `
                "(got $($sd.InGame.W)x$($sd.InGame.H) reads=$($sd.InGame.Reads))"
            if ($arms['stock'] -and $arms['stock'].Walked) {
                Write-Host '       DEFECT arm vs stock, left 640: dense_rows must fire on real damage'
                $dd = Invoke-FrameTool -ToolArgs @('diff',
                        '--a', $arms['stock'].InGame.Dump, '--b', $sd.InGame.Dump,
                        '--x0', '0', '--x1', '640', '--y0', '20', '--y1', '400')
                Assert-True '[s2defect] dense_rows reads RED on the known-damaged frame (> 0)' `
                    ([int]($dd['dense_rows'] ?? 0) -gt 0) `
                    "(dense_rows=$($dd['dense_rows']), wide_rows=$($dd['wide_rows']), diff_px=$($dd['diff_px']))"
            }
        }
        else {
            Assert-True '[s2defect] reached a game and captured' $false "($($sd.WalkError))"
        }
    }

    # ---- ARM 4: stage 2, full table ---------------------------------------
    if ($arms['s2']) {
        $s2 = $arms['s2']
        Assert-True '[s2] the widescreen table is ACTIVE with 0 refused' `
            ($null -ne $s2.WsVerdict -and $s2.WsVerdict -match 'WIDESCREEN ACTIVE' -and
             $s2.WsVerdict -match ', 0 refused') "($($s2.WsVerdict))"
        Assert-True '[s2] the whole stage applied (no leftover %SCPLUGIN_WS_ONLY%)' `
            ($null -ne $s2.WsFilter -and $s2.WsFilter -match 'unset, whole stage applied') `
            "($($s2.WsFilter))"
        foreach ($pt in @($s2.Menu, $s2.InGame, $s2.Scrolled, $s2.Mid, $s2.Scrolled2, $s2.ScrollMid)) {
            if ($null -eq $pt) { continue }
            Assert-True "[s2/$($pt.Tag)] a dump was written" ($null -ne $pt.Dump) `
                ($pt.Refused ? "(refused: $($pt.Refused))" : '')
            if ($null -eq $pt.Dump) { continue }
            Assert-True "[s2/$($pt.Tag)] the dump is the full $($SCREEN_W)x$($SCREEN_H)" `
                ($pt.W -eq $SCREEN_W -and $pt.H -eq $SCREEN_H) "(got $($pt.W)x$($pt.H))"
            # The MENU animates every frame and a taller/wider buffer copy is slow enough
            # that two whole-buffer reads always straddle a compose, so its stability is not
            # achievable and not load-bearing -- no diff below reads the menu dump.
            if ($pt.Tag -match 'menu') {
                Write-Host "       [s2/$($pt.Tag)] settle REPORTED not asserted (reads=$($pt.Reads)): an animating menu over a $($SCREEN_W)x$($SCREEN_H) buffer does not settle, and no diff reads it"
            } else {
                Assert-True "[s2/$($pt.Tag)] the copy settled" ($pt.Stable -eq 1) "(reads=$($pt.Reads))"
            }
            # The seam tracker: reported, not asserted -- the zero-run
            # positions ARE the experiment's reading.
            if ($pt.Tag -ne "$($s2.Name)-menu") {
                Write-Host "       [s2/$($pt.Tag)] zero-column runs (seam tracker), origin=$($pt.Origin):"
                $zr = Invoke-FrameTool -ToolArgs @('zeroruns', '--dump', $pt.Dump,
                        '--x0', '0', '--x1', "$SCREEN_W", '--y0', '20', '--y1', '320')
                # Regression tooth for the 25-px seam class, which sits at
                # 672..695 at EVERY origin (screen-anchored). At the start
                # origin the fixture's explored edge is map x 1332 = screen x
                # 788, so a zero run touching 660..700 there is that class,
                # never legitimate shroud. (Proved able to fail: the defect
                # build reads 671-695 here, research/renderer-viewport.md 15.4.)
                if ($pt.Tag -eq "$($s2.Name)-ingame") {
                    $seam = @()
                    foreach ($run in ("$($zr['zeroruns'])" -split ';')) {
                        if ($run -match '^(\d+)-(\d+)$' -and [int]$Matches[1] -le 700 -and [int]$Matches[2] -ge 660) {
                            $seam += $run
                        }
                    }
                    Assert-True "[s2/$($pt.Tag)] no zero-column run intersects the old seam band x=660..700" `
                        ($seam.Count -eq 0) "(intersecting: $($seam -join ','); all runs: $($zr['zeroruns']))"
                }
            }
        }
        foreach ($pt in @($s2.InGame, $s2.Scrolled2)) {
            if ($null -eq $pt -or $null -eq $pt.Dump) { continue }
            # WMode still presents columns 0..639 at 1:1 under stage 2 (12.6),
            # so the window-vouched mapping can only hold at true pitch 800.
            # ALIGNMENT IS PINNED at the measured (5,32) for the asserted pass:
            # a mislock on sprite noise at (8,36) reads a perfect dump as 0.34.
            # The render pass below keeps the auto-search, and a disagreement
            # between the two is REPORTED as a finding rather than smoothed away.
            Write-Host "       [s2/$($pt.Tag)] consistency vs the window, pure playfield, pitch $SCREEN_W, align pinned (5,32):"
            $m = Invoke-FrameTool -ToolArgs (@('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After,
                    '--align-dx', '5', '--align-dy', '32') + $PF)
            Assert-True "[s2/$($pt.Tag)] the window capture holds a picture (>= 32 distinct colours)" `
                ([int]($m['window_distinct_rgb'] ?? 0) -ge 32) "(got $($m['window_distinct_rgb']))"
            Assert-True "[s2/$($pt.Tag)] the dump reproduces the presented playfield at pitch $SCREEN_W (>= 0.97)" `
                ([double]($m['consist_frac'] ?? 0) -ge 0.97) "(got $($m['consist_frac']))"
            # The right 160 columns over playfield rows: y=20..320 keeps clear
            # of the top strip and the console region, and the fixture's marine
            # grid has explored the terrain there, so index 0 is damage rather
            # than legitimate shroud.
            Write-Host "       [s2/$($pt.Tag)] the right band x=$STOCK_W..$($SCREEN_W - 1), playfield rows y=20..320:"
            $b = Invoke-FrameTool -ToolArgs @('band', '--dump', $pt.Dump,
                    '--x0', "$STOCK_W", '--x1', "$SCREEN_W", '--y0', '20', '--y1', '320')
            Assert-True "[s2/$($pt.Tag)] the right band was readable end to end" `
                ([int]($b['band_px'] ?? 0) -eq $BAND_W * 300) "(got $($b['band_px']) px)"
            # The band assertion is ORIGIN-DEPENDENT. At the start origin
            # (544,416) the marines' sight has explored most of the band, so it
            # must hold MAP. At the scrolled origin (704,416) the band is map x
            # 1400..1503, provably beyond the fixture's exploration (explored
            # edge measured at map x 1332, research/renderer-viewport.md 15.4
            # and 16.4, against the CHK's unit records), so a CORRECT fog paints
            # it black.
            if ($pt.Tag -eq "$($s2.Name)-scrolled2") {
                Assert-True "[s2/$($pt.Tag)] fog HIDES the unexplored right band (nonzero frac <= 0.02)" `
                    ([double]($b['band_nonzero_frac'] ?? 1) -le 0.02) `
                    "(got $($b['band_nonzero_frac']), distinct=$($b['band_distinct']), top=$($b['band_top']))"
            }
            else {
                # Two-sided, derived from the exploration edge (see $EXPLORED_EDGE_X):
                # too little map is the black-seam class (15.4), too MUCH is the fog
                # leak (16.3, raw terrain over unexplored map). Do not flatten it to
                # ">= 0.30": that holds only while the 160-px band is 92% explored,
                # it demands the leak's own signature past the edge, and at 1280 the
                # same edge explores 23% of a 640-px band.
                $originX = if ($pt.Origin -match '^(\d+),') { [int]$Matches[1] } else { -1 }
                $explored = ($originX -ge 0) ? ([Math]::Max(0, [Math]::Min($SCREEN_W, $EXPLORED_EDGE_X - $originX) - $STOCK_W) / $BAND_W) : -1
                $frac = [double]($b['band_nonzero_frac'] ?? -1)
                Assert-True "[s2/$($pt.Tag)] the right band holds MAP up to the exploration edge and shroud past it (nonzero frac within 0.8x..+0.05 of the predicted $([Math]::Round($explored, 3)))" `
                    ($explored -ge 0 -and $frac -ge 0.8 * $explored -and $frac -le $explored + 0.05) `
                    "(got $frac, predicted $explored from edge $EXPLORED_EDGE_X at origin $originX; distinct=$($b['band_distinct']), top=$($b['band_top']))"
            }
            $r = Invoke-FrameTool -ToolArgs @('check', '--dump', $pt.Dump,
                    '--before', $pt.Before, '--after', $pt.After, '--map-w', '640',
                    '--render', (Join-Path $FrameDir "$($pt.Tag)-render.png"),
                    '--save-palette', (Join-Path $FrameDir "$($pt.Tag)-palette.json"))
            if ("$($r['align_dx']),$($r['align_dy'])" -ne '5,32') {
                Report-Finding "[s2/$($pt.Tag)] auto-search alignment ($($r['align_dx']),$($r['align_dy'])) disagrees with the pinned (5,32) -- the asserted pass used the pin; investigate before trusting either"
            }
        }
        # Cross-arm: a correct stage 2 composes the SAME left 640 the stock
        # build does. dense_rows is the assertable discriminator (proved RED on
        # the defect arm above and on the synthetic stride-640 misread);
        # wide_rows stays reported beside it.
        if ($arms['stock'] -and $arms['stock'].Walked -and $s2.Walked) {
            $sameOrigin = ($null -ne $arms['stock'].InGame.Origin -and
                           $arms['stock'].InGame.Origin -eq $s2.InGame.Origin)
            Assert-True 'both arms have the camera at the same origin (so the dumps are comparable)' `
                $sameOrigin "(stock=$($arms['stock'].InGame.Origin) s2=$($s2.InGame.Origin))"
            if ($sameOrigin) {
                Write-Host '       stage-2 left 640 columns vs stock, index for index (playfield interior):'
                $dm = Invoke-FrameTool -ToolArgs @('diff',
                        '--a', $arms['stock'].InGame.Dump, '--b', $s2.InGame.Dump,
                        '--x0', '0', '--x1', '640', '--y0', '20', '--y1', '400')
                Assert-True 'stage-2 left 640 matches stock: no DENSELY differing row (dense_rows=0)' `
                    ([int]($dm['dense_rows'] ?? 999) -eq 0) `
                    "(dense_rows=$($dm['dense_rows']), wide_rows=$($dm['wide_rows']), diff_px=$($dm['diff_px']), row_max=$($dm['diff_row_max']))"
            }
        }
        elseif ($arms['stock']) {
            Report-Finding 'one arm did not reach a game; the cross-arm playfield diff was not run'
        }
        # Same-origin stability: two captures at the SAME minimap click,
        # separated by a scroll away and back. Sprite-pose diffs expected;
        # a densely differing row is damage.
        if ($s2.Scrolled -and $s2.Scrolled.Dump -and $s2.Scrolled2 -and $s2.Scrolled2.Dump) {
            $sameO = ($null -ne $s2.Scrolled.Origin -and $s2.Scrolled.Origin -eq $s2.Scrolled2.Origin)
            Assert-True '[s2] the two identical minimap clicks landed the camera at one origin' `
                $sameO "(scrolled=$($s2.Scrolled.Origin) scrolled2=$($s2.Scrolled2.Origin))"
            if ($sameO) {
                Write-Host "       stage-2 scrolled vs scrolled2 (same origin, full $SCREEN_W):"
                $dm2 = Invoke-FrameTool -ToolArgs @('diff',
                        '--a', $s2.Scrolled.Dump, '--b', $s2.Scrolled2.Dump,
                        '--x0', '0', '--x1', "$SCREEN_W", '--y0', '20', '--y1', '400')
                Assert-True 'no densely differing row between the same-origin captures (dense_rows=0)' `
                    ([int]($dm2['dense_rows'] ?? 999) -eq 0) `
                    "(dense_rows=$($dm2['dense_rows']), wide_rows=$($dm2['wide_rows']), diff_px=$($dm2['diff_px']))"
            }
        }
        # The scrolled capture must actually have scrolled, or the seam
        # discrimination never ran -- the coverage rule: count the event the
        # run exists to produce, and fail when it is zero.
        if ($s2.InGame -and $s2.Scrolled) {
            Assert-True '[s2] the minimap click moved the camera (origins differ)' `
                ($null -ne $s2.Scrolled.Origin -and $s2.Scrolled.Origin -ne $s2.InGame.Origin) `
                "(ingame=$($s2.InGame.Origin) scrolled=$($s2.Scrolled.Origin))"
        }
        # Whether a posted key drives the engine's scroll at all is empirical,
        # so the event this capture exists for (a NON-tile-aligned origin) is
        # counted, and the alignment is printed beside it either way.
        if ($s2.Scrolled2 -and $s2.ScrollMid) {
            $moved = ($null -ne $s2.ScrollMid.Origin -and
                      $s2.ScrollMid.Origin -ne $s2.Scrolled2.Origin)
            $alignNote = ''
            if ($null -ne $s2.ScrollMid.Origin -and $s2.ScrollMid.Origin -match '^(\d+),(\d+)$') {
                $ax = [int]$Matches[1] % 32
                $alignNote = " originX%32=$ax" + ($ax -ne 0 ? ' (sub-tile: alignment terms exercised)' : ' (tile-aligned: alignment terms NOT exercised this run)')
            }
            Assert-True '[s2] the held arrow key moved the camera (keyboard scroll reached the engine)' `
                $moved "(scrolled2=$($s2.Scrolled2.Origin) scrollmid=$($s2.ScrollMid.Origin)$alignNote)"
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
    foreach ($pt in @($a.Menu, $a.InGame, $a.Scrolled, $a.Mid, $a.Scrolled2, $a.ScrollMid)) {
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
