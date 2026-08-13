#Requires -Version 7
<#
.SYNOPSIS
Task 073. THE experiment for both blockers of the console move at 800 wide, in
one driven cnc-ddraw session:

  BLOCKER 1 (pixels): -ConsoleEdge 1 translates StatRes + StatBtn +160 on the
  game thread once their surfaces exist, marking old AND new rects dirty. The
  static reading this task took (layer-2 composite 0x0041C810 -> 0x004EF440 ->
  0x004172F0: blit dest = the dirty rect, src = rect - the dialog's LIVE +0x04
  bounds) predicts the pixels FOLLOW the bounds wherever a dirty rect covers
  them -- 071's unmoving picture was a repaint-scheduling fact, not a separate
  position source. The proof is a cnc-ddraw window capture (the only honest
  visual instrument -- WMode crops x>=640) plus a pixel count over the new and
  old regions, with the unmoved minimap as the instrument's positive control.

  BLOCKER 2 (clicks): with the card drawn at (656,354)-(799,479), a posted
  click on its Train button must put wire command 0x1F through queueCommand and
  an item in the building's OWN ring. 071 measured "0 commands at (682,374)"
  under WMode -- where a posted x>639 is out of the shim's contract (070
  17.2) -- so whether a stock router drops x>=640 console clicks, or the
  harness dropped them, is exactly what this run separates: under cnc-ddraw the
  window IS 800 wide and console-dialog clicks demonstrably register off-screen
  (probe-widescreen-drive's minimap clicks). -ConsoleTrace 1 wraps every root
  dialog's interact, so whatever happens, the CTRACE lines name the dialog that
  claimed (or none claimed) the click.

Selection uses the plugin's marker-driven aid ('conedge-select': the engine's
own 0x0049AE40 + CMDACT_Select pair on the game thread), because a posted
PLAYFIELD click does not register under off-screen cnc-ddraw (070: 0/8). The
clean-slate rule holds: the selection read starts from a verified-empty
selection (fresh game), and the measured act -- the card click -- is a real
posted click.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-console-edge.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogDir = 'C:\sc-work\logs\073',
    [string]$FixtureDir,
    [string]$FrameDir = 'C:\sc-work\logs\073-frames',
    [string]$WindowedHelperDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$NEXUS_TYPE = 154
# The moved rects the plugin's +160 predicts from 070's measured stock ones.
$STATRES_MOVED = @(380, 0, 799, 19)
$STATBTN_MOVED = @(656, 354, 799, 479)
$MINIMAP_STOCK = @(0, 315, 137, 479)

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t073' -Suite 'conedge' }
$mapName = 'conedge.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$log = Join-Path $LogDir '073-conedge.log'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null

$script:failures = 0
$script:step = 0
$script:findings = @()
$launchLock = $null
$fixtures = $null
$gamePid = 0
$completed = $false

function Assert-True {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    $script:step++
    if ($Ok) { Write-Host "  [$script:step] OK   $What $Detail" }
    else { Write-Host "  [$script:step] FAIL $What $Detail"; $script:failures++ }
}
function Report-Finding {
    param([string]$What)
    $script:findings += $What
    Write-Host "  ---- FINDING: $What"
}

# Count non-black pixels of a saved window PNG inside a client-coordinate rect.
# The window capture is the ONE honest instrument for "what the user sees"
# through cnc-ddraw (renderer-viewport.md 18's oracle rule); this quantifies it
# so the claim is a number beside the picture, not an adjective.
Add-Type -AssemblyName System.Drawing
function Get-PngRectNonzero {
    param([Parameter(Mandatory)][string]$Path,
          [int]$X0, [int]$Y0, [int]$X1, [int]$Y1)
    $bmp = [System.Drawing.Bitmap]::new($Path)
    try {
        $n = 0; $nz = 0
        $xe = [Math]::Min($X1, $bmp.Width); $ye = [Math]::Min($Y1, $bmp.Height)
        for ($y = $Y0; $y -lt $ye; $y += 2) {
            for ($x = $X0; $x -lt $xe; $x += 2) {
                $c = $bmp.GetPixel($x, $y); $n++
                if (([int]$c.R + [int]$c.G + [int]$c.B) -gt 24) { $nz++ }
            }
        }
        if ($n -eq 0) { return -1.0 }
        [Math]::Round($nz / $n, 4)
    }
    finally { $bmp.Dispose() }
}

function Count-CmdLines {
    param([string]$Id)
    @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue |
      Where-Object { $_ -match "CMD id=$Id " }).Count
}

# A marker-driven copy of the 800-wide screen BUFFER (0x6CEFF0 bits). The one
# oracle that can say whether a buffer-path (flag 0x10000000) dialog's pixels
# were ever COMPOSITED, independent of whether they were ever PRESENTED.
function Get-BufferDump {
    param([string]$Tag)
    $from = Get-ScLogLineCount -LogPath $log
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    $lines = Wait-ScLogMatch -LogPath $log -Pattern "FRAMEDUMP \[$([regex]::Escape($Tag))\] " -TimeoutSec 20 -FromLine $from
    foreach ($l in $lines) {
        if ($l -match 'FRAMEDUMP \[[^\]]+\] w=(\d+) h=(\d+) bytes=\d+ reads=\d+ stable=\d path=(.+)$') {
            return $Matches[3].Trim()
        }
    }
    $null
}

function Get-DumpBand {
    param([string]$Dump, [int]$X0, [int]$X1, [int]$Y0, [int]$Y1)
    $out = & python (Join-Path $scriptDir 'frame-capture.py') band --dump $Dump `
        --x0 $X0 --x1 $X1 --y0 $Y0 --y1 $Y1 2>&1
    foreach ($l in $out) { if ("$l" -match '^band_nonzero_frac=(.+)$') { return [double]$Matches[1] } }
    -1.0
}

function Get-SelectionNow {
    param([string]$Tag)
    $from = Get-ScLogLineCount -LogPath $log
    Set-ScMarker -MarkerPath $markerPath -Label $Tag
    [void](Wait-ScLogMatch -LogPath $log -Pattern ("SELSNAP \[" + [regex]::Escape($Tag) + "\] ") -TimeoutSec 10 -FromLine $from)
    $line = @(Get-Content -LiteralPath $log | Select-Object -Skip $from |
              Where-Object { $_ -match 'SELSNAP clientSelectionGroup' }) | Select-Object -First 1
    if (-not $line) { return @() }
    [regex]::Matches($line, '=0x([0-9A-Fa-f]+)') |
        ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } |
        Where-Object { $_ -ne '00000000' }
}

try {
    Write-Host 'probe-conedge: waiting for the machine'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '073-conedge'

    if (-not (Test-Path -LiteralPath $WindowedHelperDll)) {
        throw "probe-conedge: $WindowedHelperDll not found; run fetch-cnc-ddraw.ps1 first."
    }

    Write-Host 'probe-conedge: generating the fixture (one Nexus, 500 minerals -- 071''s shape)'
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount 1 -UnitType 'nexus' -Player 0 -ClearPlayerUnits `
        -Race 'protoss' -StartingMinerals 500 -StartingGas 0 -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }
    if (-not (Test-Path -LiteralPath $mapPath)) {
        throw 'probe-conedge: the fixture was never generated; nothing was launched.'
    }

    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    # Glue-screen posted input is activation-gated under off-screen cnc-ddraw
    # (AGENTS.md; probe-widescreen-drive measured the fix) -- nudge before every
    # posted input during the menu walk, and turn it OFF in game.
    $env:SCDRIVE_POST_ACTIVATE = '1'

    Write-Host 'probe-conedge: launching (stage 3 + ConsoleEdge + ConsoleTrace, cnc-ddraw)'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -CardScan 1 -WorldScan 1 -NoLaunchLock `
        -Widescreen 1 -WidescreenStage 3 -ConsoleEdge 1 -ConsoleTrace 1 `
        -FrameDump $FrameDir `
        -Windowed -WindowedHelperDll $WindowedHelperDll `
        -GameDir $GameDir -LogPath $log 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe-conedge: could not parse the game pid.' }
    $h = Get-ScGameWindow -ProcessId $gamePid
    Start-Sleep -Seconds 3

    Assert-True 'the widescreen table is ACTIVE with 0 refused' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'WIDESCREEN ACTIVE' -and $_ -match ', 0 refused' }).Count -gt 0)
    Assert-True 'the console module is ON (edge=1 trace=1)' `
        (@(Get-Content -LiteralPath $log | Where-Object { $_ -match 'CONSOLE: ON edge=1 trace=1' }).Count -gt 0)
    $client = Get-ScClientSize -Hwnd $h
    Assert-True 'cnc-ddraw presents an 800x480 client area' `
        ($client.Width -eq 800 -and $client.Height -eq 480) "(got $($client.Width)x$($client.Height))"

    # ---- the dialog-gated menu walk (probe-widescreen-drive's, verbatim) ----
    function Click-UntilDialog {
        param([int]$X, [int]$Y, [string]$Name, [int]$Tries = 3, [int]$WaitSec = 10)
        for ($i = 1; $i -le $Tries; $i++) {
            Send-ScClick -Hwnd $h -X $X -Y $Y
            $d = Wait-ScDialog -LogPath $log -Name $Name -TimeoutSec $WaitSec
            if ($d) { return $d }
            Write-Host "       walk: '$Name' not up after click $i/$Tries at ($X,$Y); retrying"
        }
        $null
    }

    Write-Host 'probe-conedge: walking to a loaded game (dialog-gated)'
    if (-not (Wait-ScDialog -LogPath $log -Name 'MainMenu' -TimeoutSec 30)) {
        throw 'probe-conedge: the main menu never appeared in the DIALOGS oracle.'
    }
    Start-Sleep -Seconds 3
    if (-not (Click-UntilDialog -X 215 -Y 119 -Name 'Delete')) {
        throw 'probe-conedge: the Original/Expansion chooser never appeared.'
    }
    Send-ScClick -Hwnd $h -X 373 -Y 300
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $h -X 75 -Y 111
    if (-not (Click-UntilDialog -X 516 -Y 392 -Name 'RaceSelection' -WaitSec 15)) {
        throw 'probe-conedge: the campaign (RaceSelection) screen never appeared.'
    }
    if (-not (Click-UntilDialog -X 327 -Y 415 -Name 'Create' -WaitSec 15)) {
        throw 'probe-conedge: the map-browser (Create) screen never appeared.'
    }
    Start-Sleep -Seconds 2
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $mapPath | Out-Null
    Set-ScGameType -Hwnd $h -LogPath $log -Index 2
    Send-ScClick -Hwnd $h -X 516 -Y 393
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $h -X 544 -Y 387
    Start-Sleep -Seconds 10
    Dismiss-ScTipsDialog -Hwnd $h -LogPath $log | Out-Null
    Start-Sleep -Seconds 3
    $env:SCDRIVE_POST_ACTIVATE = '0'   # in game: the nudge re-syncs the cursor, fatal before a click

    # ---- BLOCKER 1: the move happened, the dialog list agrees, the WINDOW shows it
    $moved = @(Get-Content -LiteralPath $log | Where-Object { $_ -match "CONSOLE moved '" })
    Assert-True 'the plugin moved StatRes and StatBtn (CONSOLE moved lines)' `
        (@($moved | Where-Object { $_ -match "'StatRes'" }).Count -gt 0 -and
         @($moved | Where-Object { $_ -match "'StatBtn'" }).Count -gt 0) `
        "($($moved -join ' | '))"
    @(Get-Content -LiteralPath $log | Where-Object { $_ -match 'CONSOLE surf ' }) |
        ForEach-Object { Report-Finding "surface descriptor evidence: $_" }

    [void](Get-ScWorldState -LogPath $log -Tag 'dlgpump' -MarkerPath $markerPath)
    $dialogs = @(Get-ScDialogs -LogPath $log)
    $res = @($dialogs | Where-Object Name -eq 'StatRes')[0]
    $btn = @($dialogs | Where-Object Name -eq 'StatBtn')[0]
    $mini = @($dialogs | Where-Object Name -eq 'Minimap')[0]
    Assert-True "StatRes hit-test rect moved to ($($STATRES_MOVED -join ','))" `
        ($res -and $res.Left -eq $STATRES_MOVED[0] -and $res.Right -eq $STATRES_MOVED[2]) `
        "(measured $(if ($res) { "$($res.Left),$($res.Top),$($res.Right),$($res.Bottom)" } else { 'absent' }))"
    Assert-True "StatBtn hit-test rect moved to ($($STATBTN_MOVED -join ','))" `
        ($btn -and $btn.Left -eq $STATBTN_MOVED[0] -and $btn.Right -eq $STATBTN_MOVED[2]) `
        "(measured $(if ($btn) { "$($btn.Left),$($btn.Top),$($btn.Right),$($btn.Bottom)" } else { 'absent' }))"
    Assert-True "Minimap stays at stock ($($MINIMAP_STOCK -join ','))" `
        ($mini -and $mini.Left -eq $MINIMAP_STOCK[0] -and $mini.Right -eq $MINIMAP_STOCK[2]) `
        "(measured $(if ($mini) { "$($mini.Left),$($mini.Top),$($mini.Right),$($mini.Bottom)" } else { 'absent' }))"

    $shot = Join-Path $FrameDir 'console-800-edge-ingame.png'
    Save-ScWindowImage -Hwnd $h -Path $shot | Out-Null
    Write-Host "       capture: $shot (the AFTER; 071's console-800-ingame.png is the before)"

    # Pixel counts over the capture. Positive control first (the unmoved
    # minimap), then the moved regions, then a known-empty region so the
    # instrument is seen reading both high and low in the same frame.
    $ctrl = Get-PngRectNonzero -Path $shot -X0 4 -Y0 350 -X1 135 -Y1 476
    Assert-True 'instrument positive control: the (unmoved) minimap region reads mostly non-black' `
        ($ctrl -ge 0.30) "(nonzero=$ctrl)"
    $newCard = Get-PngRectNonzero -Path $shot -X0 656 -Y0 400 -X1 799 -Y1 479
    Assert-True 'the NEW card region x=656..799 y=400..479 (dead-black before this task) holds pixels' `
        ($newCard -ge 0.30) "(nonzero=$newCard)"
    $newRes = Get-PngRectNonzero -Path $shot -X0 700 -Y0 1 -X1 798 -Y1 18
    Report-Finding "resource-bar right end x=700..798 y=1..18 on GLASS: nonzero=$newRes (run 2 read 0 here: composited into the buffer, never presented -- the storm present's base region was the 640-wide console image node)"
    $oldCard = Get-PngRectNonzero -Path $shot -X0 496 -Y0 400 -X1 639 -Y1 479
    Report-Finding "OLD card region x=496..639 y=400..479 after the move: nonzero=$oldCard (what fills the vacated strip)"
    $gap = Get-PngRectNonzero -Path $shot -X0 640 -Y0 400 -X1 655 -Y1 479
    Report-Finding "the 16px gap x=640..655 y=400..479: nonzero=$gap (a low reading here is the instrument's own zero)"

    # ---- BLOCKER 2: clean slate -> select via the engine funnel -> card click
    $sel0 = @(Get-SelectionNow -Tag 'slate')
    Assert-True 'clean slate: the fresh game holds NO selection before the aid runs' `
        ($sel0.Count -eq 0) "(selected=[$($sel0 -join ',')])"

    $from = Get-ScLogLineCount -LogPath $log
    Set-ScMarker -MarkerPath $markerPath -Label 'conedge-select'
    [void](Wait-ScLogMatch -LogPath $log -Pattern 'CONSOLE selected unit=' -TimeoutSec 10 -FromLine $from)
    $sel1 = @(Get-SelectionNow -Tag 'postsel')
    Assert-True 'the aid selected exactly one unit (the Nexus)' ($sel1.Count -eq 1) "(selected=[$($sel1 -join ',')])"
    $stat = Get-ScStatusQueue -LogPath $log -Tag 'postsel-statq' -MarkerPath $markerPath
    Assert-True 'the portrait shows the Nexus (the card is up)' `
        ($stat.PortraitType -eq $NEXUS_TYPE) "(ptype $($stat.PortraitType))"
    $shotSel = Join-Path $FrameDir 'console-800-edge-selected.png'
    Save-ScWindowImage -Hwnd $h -Path $shotSel | Out-Null
    Write-Host "       capture: $shotSel (Nexus selected -- the card with its buttons)"

    # The StatRes question, measured from the BUFFER (run 2's lesson: the window
    # PNG includes the shim's caption INSIDE the client rect, and a band probe
    # over it reads the gray caption -- see Save-ScWindowImage's own warning).
    # StatRes is the one flag-0x10000000 dialog: its composite target is the
    # 800-wide buffer, so the buffer says whether its digits were ever
    # composited at the new position, independent of presentation.
    $dump = Get-BufferDump -Tag 'edge-postsel'
    if ($dump) {
        $bNew = Get-DumpBand -Dump $dump -X0 700 -X1 796 -Y0 2 -Y1 17
        $bOld = Get-DumpBand -Dump $dump -X0 560 -X1 648 -Y0 2 -Y1 17
        Report-Finding "BUFFER band, StatRes digits: NEW rect x=700..795 nonzero=$bNew | OLD rect x=560..647 nonzero=$bOld (new>0 & window blank = present gap; both 0 = composite never ran for the moved StatRes; old>0 = a second position source)"
    }
    else { Report-Finding 'BUFFER band: no FRAMEDUMP arrived -- the StatRes diagnosis is missing from this run' }

    # The moved bar ON GLASS -- run 3 proved it composited into the buffer at
    # the new rect while the window stayed black there (the present clip,
    # renderer-viewport.md 19.8); the sliver image node is the repair. Selected
    # Nexus supplies 9, so the supply counter is up and the digits are lit.
    $shotSel2 = Join-Path $FrameDir 'console-800-edge-selected.png'
    $glassRes = (Test-Path -LiteralPath $shotSel2) ? (Get-PngRectNonzero -Path $shotSel2 -X0 700 -Y0 1 -X1 798 -Y1 18) : -1
    Assert-True "the resource bar's right end shows on GLASS at x=700..798 (present sliver carries it)" `
        ($glassRes -ge 0.05) "(nonzero=$glassRes; run 2 measured 0 here with the bar stuck in the buffer)"

    # The MAP's right band on glass -- the real payload of the present repair:
    # runs 2-4 (and 070's own captures, re-read) show glass black past x~648
    # while the buffer held map. The Nexus's vision covers this band at the
    # start origin, so a black reading here is the clip, not fog.
    $glassMap = (Test-Path -LiteralPath $shotSel2) ? (Get-PngRectNonzero -Path $shotSel2 -X0 660 -Y0 80 -X1 790 -Y1 300) : -1
    Assert-True "the MAP's right band shows on GLASS at x=660..790 y=80..300" `
        ($glassMap -ge 0.10) "(nonzero=$glassMap; black here through run 4 -- and in 070's captures -- was the present clip)"

    # The Train (Probe) click at the MOVED card: stock slot-0 centre (522,374)
    # +160. Wire + ring are the oracles; the CTRACE names who claimed the click.
    $trainX = $btn ? ($btn.Left + 26) : 682
    $trainY = 374
    $cmd0 = Count-CmdLines -Id '0x1F'
    $traceFrom = Get-ScLogLineCount -LogPath $log
    $issued = $false
    for ($t = 1; $t -le 3 -and -not $issued; $t++) {
        Send-ScClick -Hwnd $h -X $trainX -Y $trainY -SettleMs 400
        Start-Sleep -Milliseconds 900
        $issued = (Count-CmdLines -Id '0x1F') -gt $cmd0
        if (-not $issued) { Write-Host "       Train click $t/3 at ($trainX,$trainY): no 0x1F yet" }
    }
    $cmd1 = Count-CmdLines -Id '0x1F'
    Assert-True "a Train click at ($trainX,$trainY) put 0x1F on the wire" `
        ($cmd1 -gt $cmd0) "(0x1F count $cmd0 -> $cmd1)"
    $stat2 = Get-ScStatusQueue -LogPath $log -Tag 'postclick-statq' -MarkerPath $markerPath
    # A ring value is only a queued item if it is a REAL unit-type id (< 228, the
    # engine's empty sentinel). The first run of this probe passed this assert on
    # a walk full of 4095s taken with no portrait at all -- a vacuous green
    # (AGENTS.md, task 041's class) -- so the portrait precondition is part of
    # the assert now.
    $engineQ = @($stat2.Engine | Where-Object { $_ -ge 0 -and $_ -lt 228 })
    Assert-True "the ENGINE's own ring holds the queued item (portrait still the Nexus)" `
        ($stat2.PortraitType -eq $NEXUS_TYPE -and $engineQ.Count -ge 1) `
        "(ptype=$($stat2.PortraitType) engine=[$($stat2.Engine -join ',')] head=$($stat2.Head))"

    # The trace's answer, whatever it was: every non-MOUSEMOVE root-interact
    # event since just before the click.
    $trace = @(Get-Content -LiteralPath $log | Select-Object -Skip $traceFrom |
               Where-Object { $_ -match 'CTRACE dlg=' } | Select-Object -First 40)
    Write-Host '       CTRACE around the Train click:'
    $trace | ForEach-Object { Write-Host "         $_" }
    $claimed = @($trace | Where-Object { $_ -match 'type=(4|5|6|7|8) .*-> ret=[^0]' })
    Report-Finding "click route: $(if ($claimed.Count) { "claimed by $($claimed[0])" } else { 'NO root interact returned non-zero for the click events in the window traced' })"

    # ---- minimap still steers (must-not-break) ----------------------------
    $a = Get-ScWorldState -LogPath $log -Tag 'mini-a' -MarkerPath $markerPath
    $p = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 -TileX 20 -TileY 20
    Send-ScClick -Hwnd $h -X $p.X -Y $p.Y -SettleMs 400
    Start-Sleep -Milliseconds 600
    $b = Get-ScWorldState -LogPath $log -Tag 'mini-b' -MarkerPath $markerPath
    Assert-True 'a minimap click still steers the camera at 800 with the console moved' `
        ($null -ne $a.Screen -and $null -ne $b.Screen -and
         ($a.Screen.Left -ne $b.Screen.Left -or $a.Screen.Top -ne $b.Screen.Top)) `
        "($($a.Screen.Left),$($a.Screen.Top) -> $($b.Screen.Left),$($b.Screen.Top))"

    $shot2 = Join-Path $FrameDir 'console-800-edge-after-click.png'
    Save-ScWindowImage -Hwnd $h -Path $shot2 | Out-Null
    Write-Host "       capture: $shot2 (after the Train click + minimap steer)"
    $completed = $true
}
catch {
    $script:failures++
    Write-Host "  FAIL a step threw: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
}
finally {
    Remove-Item Env:SCDRIVE_POST_ACTIVATE -ErrorAction SilentlyContinue
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  warn close-game: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
    }
    try {
        & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch -NoLaunchLock -GameDir $GameDir | Write-Host
    }
    catch { Write-Host "  warn RemoveWindowed: $($_.Exception.Message)" }
    if ($fixtures) {
        try { Remove-ScOwnFixture -Run $fixtures | Out-Null } catch { Write-Host "  warn fixture: $($_.Exception.Message)" }
        try { Remove-ScOwnFixtureDir -Dir $fixtures.Dir | Out-Null } catch { Write-Host "  warn fixture: $($_.Exception.Message)" }
    }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
}

Write-Host ''
if ($script:findings.Count) {
    Write-Host 'probe-conedge: FINDINGS:'
    $script:findings | ForEach-Object { Write-Host "  - $_" }
}
Write-Host ''
if (-not $completed) {
    Write-Host "probe-conedge: INCOMPLETE -- the run did not reach its end; $script:failures failure(s) so far"
    exit 1
}
elseif ($script:failures -gt 0) {
    Write-Host "probe-conedge: FAIL ($script:failures failure(s))"
    exit 1
}
else {
    Write-Host 'probe-conedge: PASS (0 failures) -- pixels at the edge AND the click reached them'
    exit 0
}
