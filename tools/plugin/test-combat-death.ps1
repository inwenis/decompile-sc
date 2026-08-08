#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that a generated map can kill the player's units on
demand, and that when one of a >12 selection DIES the task-017 HUD row drops it --
the first IN-GAME exercise of that path (task 019).

.DESCRIPTION
Every fixture up to task 018 was combat-less by design, so every died-while-displayed
code path (the circles module's staleness guards, the HUD row's liveness term and
click gate) was proved OFFLINE only, in hooktest. This test closes that gap with the
combat variant of the map generator: a second, COMPUTER-owned block of Hydralisks
14 tiles east of the player's Lurkers, no triggers, no AI script.

THE ORACLE IS THE GAP BETWEEN TWO IN-PROCESS NUMBERS.

  UNITSTATE n=36 live=36     the shadow list still holds all 36 captured units, and
                             every one still passes sc_fanout's liveness test, which
                             is a UNIQUENESS (CUnit+0xA5) comparison ONLY
  HUDROW    show n=35        the row's display list holds 35, because sc_hudrow's
                             UnitAlive ALSO requires hitpoints (CUnit+0x08) != 0

A damage death does not recycle the slot, so uniqueness still matches -- that is
exactly the case the 0xA5-only test misses (research/selection-circles.md 4.5, and
the task-017 review that put the HP term in). Those two lines are a unit that died and
a row that noticed.

They are NOT one atomic read. The HUDROW line is found by a log poll (500 ms) and the
UNITSTATE line is then requested with a fresh marker, so the second is written between
half a second and a couple of seconds after the first. The conclusion survives because
the gap can only run one way: uniqueness at CUnit+0xA5 changes only when the slot is
RECYCLED, so a live=n read taken LATE is a stronger claim than one taken at the
instant of the drop, not a weaker one. Reading it early is what would be unsound, and
that ordering cannot happen -- the row's drop is what triggers the read.

WHY LURKERS, TWICE OVER. An unburrowed Lurker has no weapon at all, so the enemy
force survives the engagement and the deaths arrive as a trickle instead of being
decided by who wins a fight. The block stays over the 12-unit cap throughout, which is
what keeps the row in its paged mode where the assertion means something.

And a burrowed one cannot be targeted by a Hydralisk, which is not a detector -- so
one keypress ENDS the fight on the spot, without moving anybody. That matters: walking
away does not work (the enemy pursues, the Lurkers keep dying all the way home, and a
page walk over a population that is still moving compares two different lists), and
the row's tag set can only be compared with itself once the population has stopped.

Phase A proves the fixture's two slots spawn EXACTLY what the file places, in
process: the human's 36 Lurkers by drag box, and the enemy block by generating the
same map with --enemy-owner player (identical unit type, count and coordinates,
owned by the human instead), centring the view on it with a minimap click, and
boxing it. Phase B is the combat run.

Frame captures corroborate; they are diagnostics, never the oracle, and never
committed. The maps are generated for the run and deleted afterwards -- generated
maps are game content (AGENTS.md hard rule 1).

.EXAMPLE
./tools/plugin/test-combat-death.ps1

.EXAMPLE
./tools/plugin/test-combat-death.ps1 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\019-combat-death.log',
    [string]$ShotDir = 'C:\sc-work\logs\019-combat-death-frames',
    [int]$UnitCount = 36,
    [int]$EnemyCount = 6,
    # Hit points for the victims, as a percentage of a Lurker's 125. At 100 the first
    # death took roughly two minutes of shooting and the whole run took about eleven;
    # the units absorb about twenty Hydralisk shots each. Lowering it is the one knob
    # that speeds the fixture up without changing anything that matters -- same unit
    # type, same inability to shoot back, same evidence -- so the deaths stay a
    # trickle a test can attribute rather than a volley that wipes the group.
    [ValidateRange(1, 100)]
    [int]$UnitHp = 30,
    # The first death must arrive inside this. It is also the assertion that --unit-hp
    # reached the engine at all: at 100% the same fixture needs far longer than this.
    [int]$FirstDeathTimeoutSec = 90,
    # How long the mission is watched after the losses before it counts as "did not
    # end". Nothing in an empty-TRIG Use Map Settings game can call Victory or Defeat,
    # so this is a soak, not a race; 45s is long enough to catch an end that takes
    # effect after a wait-and-pause action chain (task 016 saw one land nine seconds in).
    [int]$HoldSec = 45,
    # How many disengage-and-regroup attempts may be spent getting the fight to
    # actually stop before the row is compared with itself. One is usually enough; a
    # second is needed when a unit was still walking home, or still dying, when the
    # first pair of boxes was taken. Some runs the enemy pursues rather than holding
    # its post, and then it takes a few.
    [int]$MaxRounds = 5,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')

$failures = 0
$step = 0

$LURKER_TYPE = '0x67'       # units.dat 103
$HYDRALISK_TYPE = '0x26'    # units.dat 38
$HUD_SLOTS = 12

# Where the player's block is ordered to. The camera opens centred on the start
# location and never moves on its own, so a right-click at client x is a move to
# (start.x + x - 320) map pixels. 540 puts the block's centre +220px east: close
# enough to the enemy at +448 to be inside its weapon range, and far enough west
# that the whole block is still inside the drag box below, so it can be re-boxed
# without scrolling.
$WALK_X = 540
$WALK_Y = 240
# 'U', the Lurker command card's Burrow hotkey -- the same key test-burrow-fanout.ps1
# uses. Burrowing is how this test ends the engagement; see the note there.
$BURROW_KEY = 0x55

$mapDir = Join-Path $GameDir 'Maps\BroodWar\00-testmap'
$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    & $Body
}

function Get-ScState {
    param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec
}

# --- the fixture ---------------------------------------------------------------

# Generate one variant and parse the generator's own validation read-back, so the
# geometry this script clicks at comes from the file that was written rather than
# from a constant that could drift away from it.
function New-Fixture {
    param([string]$Name, [string]$EnemyOwner)
    if (Test-Path -LiteralPath $mapDir) { Remove-Item -LiteralPath $mapDir -Recurse -Force }
    $path = Join-Path $mapDir "$Name.scx"
    $out = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount $UnitCount -UnitType lurker -Player 0 -UnitHp $UnitHp `
        -EnemyCount $EnemyCount -EnemyType hydralisk -EnemyOwner $EnemyOwner `
        -OutputPath $path 2>&1
    $rc = $LASTEXITCODE
    # richchk's StormLib loader writes the same "no DLL path was provided" warning to
    # stderr on every archive it opens; it says nothing about the map and buries the
    # generator's own read-back.
    $out = @($out | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' })
    $out | ForEach-Object { Write-Host "       $_" }
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    $fx = @{
        Path = $path
        Exit = $rc
        Ok = ($text -match '(?m)^OK: ')
        Written = (Test-Path -LiteralPath $path)
    }
    if ($text -match 'start location for player \d+ at \((\d+), (\d+)\)') {
        $fx.StartX = [int]$Matches[1]; $fx.StartY = [int]$Matches[2]
    }
    if ($text -match 'terrain (\d+)x(\d+) tiles') {
        $fx.TilesW = [int]$Matches[1]; $fx.TilesH = [int]$Matches[2]
    }
    if ($text -match 'ENEMY (\d+) unit\(s\) of type (\d+) owned by slot (\d+) \((\w+)\), spanning \((\d+),(\d+)\)-\((\d+),(\d+)\) px') {
        $fx.EnemyN = [int]$Matches[1]; $fx.EnemyTypeId = [int]$Matches[2]
        $fx.EnemySlot = [int]$Matches[3]; $fx.EnemyOwner = $Matches[4]
        $fx.EnemyBox = @([int]$Matches[5], [int]$Matches[6], [int]$Matches[7], [int]$Matches[8])
    }
    if ($text -match 'the two are at least (\d+)px') { $fx.GapPx = [int]$Matches[1] }
    $fx
}

# --- launching and driving -----------------------------------------------------

$script:gamePid = 0
$script:hwnd = [IntPtr]::Zero
$script:shotN = 0

function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return $null }
    $script:shotN++
    $p = Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)
    try { Save-ScWindowImage -Hwnd $script:hwnd -Path $p -FullWindow | Out-Null } catch { return $null }
    $p
}

# EVERY process claim in this file is PID-SCOPED, deliberately. Another worker may be
# driving its own StarCraft on this machine at the same time (it happened while this
# test was being written): a by-name "is the game running" check sees theirs, a
# by-name cleanup CLOSES theirs, and a launch that fails because their game holds the
# single-instance claim looks like a broken fixture. So this test only ever asks about
# pids scinject handed IT, and only ever closes those.
$script:launchedPids = @()

# $true when the launch produced a live, injected game. run-with-plugin.ps1 throws on
# a failed injection, and the pid it printed before failing belongs to a process that
# is already gone, so neither the exception nor the pid alone is the answer -- both
# are checked.
function Invoke-Launch {
    # -LogCommands 0: the game emits a sync command (0x37) every frame, and with
    # command logging on it is ~19 log lines a second of noise this test never reads.
    # It also makes the log big enough that the poll loops below spend their time in
    # Get-Content. Nothing here asserts on a CMD line.
    $script:gamePid = 0
    try {
        & (Join-Path $scriptDir 'run-with-plugin.ps1') `
            -Mode fanout -InjectWindowedHelper WMode -LogCommands 0 `
            -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
                Write-Host "       $_"
                if ("$_" -match 'scinject:\s*PID=(\d+)') {
                    $script:gamePid = [int]$Matches[1]
                    $script:launchedPids += $script:gamePid
                }
            }
    }
    catch {
        Write-Host "       (launch failed: $($_.Exception.Message))"
        # run-with-plugin.ps1 throws in two different shapes, and one of them leaves a
        # LIVE game behind. "injection failed" means the process was already gone --
        # nothing to close. But its health check throws "the game has an error dialog
        # open" with the process STILL RUNNING, and by then `scinject: PID=` has
        # already streamed past, so that pid is ours. Zeroing it here without closing
        # it would strand a game sitting on a modal dialog, holding the
        # single-instance claim, on a machine other workers share -- and every retry
        # below would then fail against our own leftover.
        Close-LaunchedGame -Reason 'a failed launch' | Out-Null
        return $false
    }
    if ($script:gamePid -le 0) { return $false }
    $p = Get-Process -Id $script:gamePid -ErrorAction SilentlyContinue
    if ($null -eq $p -or $p.HasExited) { $script:gamePid = 0; return $false }
    $true
}

function Start-Mission {
    <#
    Launch, inject, and walk the menus to the ONE .scx in Maps\BroodWar\00-testmap.
    Exactly one map file is in that folder at a time, so the file row is always the
    same one (row 2; row 1 is the parent entry) -- the same recipe test-hud-row.ps1
    and test-burrow-fanout.ps1 use.

    THE LAUNCH RETRY. A launch can fail with "process exited before injection (code
    0)" / scinject exit 3: the process is gone a moment after being resumed, so there
    is nothing to inject into. On this machine that means another StarCraft already
    holds the game's single-instance claim -- most likely another worker's run, since
    this repo runs its in-game suites in parallel tabs. THAT game is not ours and is
    never touched; the launch is simply retried after a pause, which is enough when
    the collision is a run that is about to finish. What IS cleaned up between
    attempts is our own half-started game, if the failure left one alive -- see the
    catch in Invoke-Launch.
    #>
    if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

    for ($attempt = 1; $attempt -le 4; $attempt++) {
        if (Invoke-Launch) { break }
        Write-Host "       (launch attempt $attempt failed -- another StarCraft most likely holds the single-instance claim; waiting. Anything of OURS left alive was closed above; nothing else is touched)"
        Start-Sleep -Seconds 20
    }
    if (-not $script:gamePid) {
        throw 'test: the game could not be launched with the plugin injected in four attempts. If another StarCraft is running (another worker''s in-game suite, or your own game), wait for it to finish and re-run.'
    }
    $script:hwnd = Get-ScGameWindow -ProcessId $script:gamePid

    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
    Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
    Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 117 -Y 140        # [00-testmap], first row
    Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
    Start-Sleep -Milliseconds 800
    Send-ScClick -Hwnd $hwnd -X 117 -Y 159        # the one map file -- row 2
    Start-Sleep -Milliseconds 500
    Send-ScDropdownPick -Hwnd $hwnd -X 265 -Y 268 -Index 2   # Use Map Settings
    Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
    Start-Sleep -Seconds 10
    Send-ScClick -Hwnd $hwnd -X 200 -Y 261        # dismiss the "StarCraft Tips" dialog
    Start-Sleep -Seconds 2
}

# Shut down the game THIS test launched, if it is still up, and forget it. Returns
# whether the pid is actually gone. One place does this, so every exit -- a clean
# phase end, a step that threw, a launch that failed half-way -- leaves the same
# state behind.
function Close-LaunchedGame {
    param([string]$Reason = '')
    $target = $script:gamePid
    $script:gamePid = 0
    $script:hwnd = [IntPtr]::Zero
    if ($target -le 0) { return $true }

    $p = Get-Process -Id $target -ErrorAction SilentlyContinue
    if ($null -eq $p -or $p.HasExited) { return $true }
    if ($Reason) { Write-Host "       closing the game this test launched (pid $target) -- $Reason" }
    try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $target | Write-Host }
    catch { Write-Host "       (close-game threw for pid ${target}: $($_.Exception.Message))" }

    # close-game waits on the process handle, but the pid can still enumerate for a
    # moment afterwards, so poll rather than take one sample.
    for ($i = 0; $i -lt 20; $i++) {
        $left = Get-Process -Id $target -ErrorAction SilentlyContinue
        if ($null -eq $left -or $left.HasExited) { return $true }
        Start-Sleep -Milliseconds 500
    }
    $false
}

function Stop-Mission {
    $target = $script:gamePid
    if (-not (Close-LaunchedGame)) {
        Write-Host "  FAIL pid $target is still running after close-game"
        $script:failures++
    }
}

function Invoke-BoxSelect {
    Send-ScDrag -Hwnd $script:hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
    Start-Sleep -Seconds 2
}

# --- reading the row back ------------------------------------------------------

function Get-HudShow {
    param([int]$FromLine, [int]$TimeoutSec = 15)
    $hits = @(Wait-ScLogMatch -LogPath $LogPath -FromLine $FromLine -TimeoutSec $TimeoutSec `
        -Pattern 'HUDROW show n=\d+ page=\d+/\d+ slots=\d+')
    $m = [regex]::Match($hits[-1],
        'HUDROW show n=(\d+) page=(\d+)/(\d+) slots=(\d+) \[([0-9A-F ]*)\] indicator="([^"]*)"')
    if (-not $m.Success) { throw "test: unparseable HUDROW show line: $($hits[-1])" }
    @{
        N = [int]$m.Groups[1].Value; Page = [int]$m.Groups[2].Value
        Pages = [int]$m.Groups[3].Value; Slots = [int]$m.Groups[4].Value
        Tags = @($m.Groups[5].Value -split ' ' | Where-Object { $_ })
        Indicator = $m.Groups[6].Value
        Line = $hits[-1]
    }
}

# Button bounds are LOCAL to the dialog's origin; client pixels are root + local.
function Get-HudRects {
    param([int]$TimeoutSec = 15)
    $hits = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'HUDROW rects root=' -TimeoutSec $TimeoutSec)
    $line = $hits[-1]
    $rm = [regex]::Match($line, 'root=\[(-?\d+),(-?\d+),(-?\d+),(-?\d+)\]')
    if (-not $rm.Success) { throw "test: HUDROW rects line has no root: $line" }
    $rootL = [int]$rm.Groups[1].Value; $rootT = [int]$rm.Groups[2].Value
    $rects = @()
    foreach ($m in [regex]::Matches($line, 'b(\d+)=\[(-?\d+),(-?\d+),(-?\d+),(-?\d+)\]')) {
        $rects += , @(($rootL + [int]$m.Groups[2].Value), ($rootT + [int]$m.Groups[3].Value),
                      ($rootL + [int]$m.Groups[4].Value), ($rootT + [int]$m.Groups[5].Value))
    }
    if ($rects.Count -lt $HUD_SLOTS) { throw "test: HUDROW rects line carries $($rects.Count) rects: $line" }
    @{ Rects = $rects; Line = $line }
}

function Get-BtnCenter {
    param($Rects, [int]$Button)   # 1-based
    $r = $Rects.Rects[$Button - 1]
    @{ X = [int](($r[0] + $r[2]) / 2); Y = [int](($r[1] + $r[3]) / 2) }
}

# Walk every page of the row with right-clicks and collect the unit tags the plugin
# reads back out of the live dialog.
#
# Every page is read BY FLIPPING TO IT, never by looking back in the log. The row
# only writes a `show` line when it actually re-fills the twelve buttons -- a flip,
# or a change in what a displayed unit is -- so a row sitting still on an idle map
# writes nothing at all, and "the newest show line" can be a minute old and describe
# a selection that no longer exists. A flip always produces a fresh one.
#
# A flip cycle of `pages` clicks from page 1 visits every page and lands back on
# page 1, which is where every other step expects the row to be.
#
# Stable=$false means the row's own reported population or page count moved while
# walking (another unit died mid-enumeration), so the caller can retry rather than
# compare a tag set against the wrong total.
function Read-RowPages {
    # The per-flip wait is short on purpose. A flip that produces no `show` line means
    # the row is not paging any more (a death among the engine's visible twelve
    # latched it to stock mid-walk), and the caller's answer to that is to re-box and
    # walk again -- so failing in seconds beats waiting out a long timeout while the
    # fixture loses more units.
    param($Rects, [int]$TimeoutSec = 8)
    # Button ONE, not a middle one. The last page fills only as many buttons as it has
    # units left, and a right-click on a button the row is not showing a unit in is not
    # a flip -- it never reaches the row's handler. With 25 units the last page holds
    # exactly one, so flipping on button 5 walked to page 3 and stuck there, and every
    # page walk came back one page short. Button 1 is populated on every page there is.
    $c = Get-BtnCenter $Rects 1
    $seen = @{}
    $pages = 0; $n = -1
    $stable = $true
    $lines = @()
    for ($i = 1; $i -le 12; $i++) {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $script:hwnd -X $c.X -Y $c.Y -Right
        Start-Sleep -Milliseconds 700
        $s = Get-HudShow -FromLine $mark -TimeoutSec $TimeoutSec
        $lines += $s.Line
        if ($pages -eq 0) { $pages = $s.Pages; $n = $s.N }
        elseif ($s.Pages -ne $pages -or $s.N -ne $n) { $stable = $false }
        if (-not $seen.ContainsKey($s.Page)) { $seen[$s.Page] = $s }
        if ($seen.Count -ge $pages -and $s.Page -eq 1) { break }
        if ($i -ge $pages * 2 + 2) { $stable = $false; break }
    }
    $expected = 1..$pages
    if (@($expected | Where-Object { -not $seen.ContainsKey($_) }).Count -gt 0) { $stable = $false }
    $tags = @()
    foreach ($k in $seen.Keys) { $tags += @($seen[$k].Tags) }
    @{
        N = $n; Pages = $pages; Stable = $stable
        Tags = @($tags | Sort-Object -Unique)
        Raw = $tags
        Lines = $lines
        PagesSeen = @($seen.Keys | Sort-Object)
        Indicator = $(if ($seen.ContainsKey(1)) { $seen[1].Indicator } else { '' })
    }
}

# The FIRST line, in file order, where the row reports fewer units than $Baseline --
# whether it is still paging (`show`) or has handed itself back to stock. Both carry
# the display-list population, and both mean the same thing: a unit the shadow list
# still holds failed the row's liveness test.
function Wait-RowDrop {
    param([int]$Baseline, [int]$FromLine, [int]$TimeoutSec = 150)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
        for ($i = $FromLine; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if ($l -match 'HUDROW show n=(\d+) ') {
                if ([int]$Matches[1] -lt $Baseline) {
                    return @{ N = [int]$Matches[1]; Kind = 'show'; Line = $l.Trim(); Index = $i }
                }
            }
            elseif ($l -match 'HUDROW stock restored \(n=(\d+)\)') {
                if ([int]$Matches[1] -lt $Baseline) {
                    return @{ N = [int]$Matches[1]; Kind = 'stock'; Line = $l.Trim(); Index = $i }
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

# The population the row last reported, from whichever kind of line came last.
function Get-RowLastN {
    $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match 'HUDROW show n=(\d+) ') { return [int]$Matches[1] }
        if ($lines[$i] -match 'HUDROW stock restored \(n=(\d+)\)') { return [int]$Matches[1] }
    }
    -1
}

# Block until the row's reported population has held still for $QuietSec. Page walks
# and tag-set comparisons are only meaningful on a settled row: mid-engagement the
# population moves under the walk and the two halves of a comparison describe
# different selections.
function Wait-RowSettled {
    param([int]$QuietSec = 15, [int]$TimeoutSec = 150)
    $last = Get-RowLastN
    $since = Get-Date
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $now = Get-RowLastN
        if ($now -ne $last) { $last = $now; $since = Get-Date }
        elseif (((Get-Date) - $since).TotalSeconds -ge $QuietSec) { return $last }
    }
    $last
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$runStart = Get-Date
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$script:probeFx = $null
$script:combatFx = $null

try {
    # =====================================================================
    # PHASE A -- both slots spawn EXACTLY what the file places
    # =====================================================================
    Step "PHASE A: generate the PLACEMENT PROBE ($UnitCount lurkers + $EnemyCount hydralisks, both the human's)" {
        $script:probeFx = New-Fixture -Name 'probe' -EnemyOwner 'player'
        Assert-That 'the generator succeeded' ($probeFx.Exit -eq 0) "(exit $($probeFx.Exit))"
        Assert-That 'it wrote the map' ([bool]$probeFx.Written)
        Assert-That 'its structural validation passed' ([bool]$probeFx.Ok)
        Assert-That "it placed $EnemyCount enemy-type units" ($probeFx.EnemyN -eq $EnemyCount)
        Assert-That 'the enemy block is owned by the human slot' `
            ($probeFx.EnemySlot -eq 0 -and $probeFx.EnemyOwner -eq 'player')
    }

    Start-Mission

    Step 'PHASE A: the human slot spawns exactly the placed units -- no melee starting units' {
        Invoke-BoxSelect
        $s = Get-ScState 'probe-player-block'
        Assert-That "the box holds all $UnitCount placed units (n=$($s.N))" ($s.N -eq $UnitCount)
        Assert-That "they are all Lurkers and nothing else (types=[$($s.TypesText)])" `
            (@($s.Types.Keys).Count -eq 1 -and @($s.Types.Keys)[0] -eq $LURKER_TYPE)
        Assert-That "every one is live (live=$($s.Live))" ($s.Live -eq $UnitCount)
        Shot 'probe-player-block' | Out-Null
    }

    Step 'PHASE A: the ENEMY BLOCK spawns exactly what the file places, at the coordinates it places them' {
        Assert-That 'the generator reported the enemy block bounds' ($null -ne $probeFx.EnemyBox)
        Assert-That 'and the map dimensions the minimap mapping needs' `
            ($null -ne $probeFx.TilesW -and $null -ne $probeFx.TilesH)
        $cx = [int](($probeFx.EnemyBox[0] + $probeFx.EnemyBox[2]) / 2)
        $cy = [int](($probeFx.EnemyBox[1] + $probeFx.EnemyBox[3]) / 2)
        $pt = Get-ScMinimapPoint -MapTilesW $probeFx.TilesW -MapTilesH $probeFx.TilesH `
            -TileX ([int]($cx / 32)) -TileY ([int]($cy / 32))
        Write-Host "       enemy block centre ($cx,$cy) px = tile ($([int]($cx/32)),$([int]($cy/32)))"
        Write-Host "       minimap click at client ($($pt.X),$($pt.Y))"
        Send-ScClick -Hwnd $hwnd -X $pt.X -Y $pt.Y      # LEFT click: centre the view
        Start-Sleep -Milliseconds 900
        Invoke-BoxSelect
        $s = Get-ScState 'probe-enemy-block'
        Assert-That "exactly $EnemyCount units are there (n=$($s.N))" ($s.N -eq $EnemyCount)
        Assert-That "they are all Hydralisks and nothing else (types=[$($s.TypesText)])" `
            (@($s.Types.Keys).Count -eq 1 -and @($s.Types.Keys)[0] -eq $HYDRALISK_TYPE)
        Assert-That 'and none of the player block came with them (a different type would show)' `
            (-not $s.Types.ContainsKey($LURKER_TYPE))
        Shot 'probe-enemy-block' | Out-Null
    }

    Stop-Mission

    # =====================================================================
    # PHASE B -- combat
    # =====================================================================
    Step "PHASE B: generate the COMBAT map (same block, owned by the computer)" {
        $script:combatFx = New-Fixture -Name 'combat' -EnemyOwner 'computer'
        Assert-That 'the generator succeeded' ($combatFx.Exit -eq 0) "(exit $($combatFx.Exit))"
        Assert-That 'it wrote the map' ([bool]$combatFx.Written)
        Assert-That 'its structural validation passed' ([bool]$combatFx.Ok)
        Assert-That "the computer slot owns the $EnemyCount enemy units" `
            ($combatFx.EnemyN -eq $EnemyCount -and $combatFx.EnemySlot -eq 1 -and
             $combatFx.EnemyOwner -eq 'computer')
        # The phase-A proof only carries over if the two maps put the same units in
        # the same place and differ in WHO OWNS THEM.
        Assert-That 'the enemy block is the same type as the probe measured' `
            ($combatFx.EnemyTypeId -eq $probeFx.EnemyTypeId)
        Assert-That "it occupies the same pixels as the probe's ($($combatFx.EnemyBox -join ',') vs $($probeFx.EnemyBox -join ','))" `
            ((($combatFx.EnemyBox) -join ',') -eq (($probeFx.EnemyBox) -join ','))
        Assert-That "the two blocks are at least 256px apart (gap $($combatFx.GapPx)px)" `
            ($combatFx.GapPx -ge 256)
    }

    Start-Mission

    Step 'PHASE B: the hudrow hook is installed (6 hooks in fanout mode)' {
        $cfg = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'FANOUT config: .*hudrow=1' -TimeoutSec 20)
        Assert-That 'the config line says hudrow=1' ($cfg.Count -gt 0)
        $hooks = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'HOOK: (\d+)/(\d+) installed' -TimeoutSec 20)
        $m = [regex]::Match($hooks[-1], 'HOOK: (\d+)/(\d+) installed')
        Assert-That "all hooks installed ($($m.Groups[1].Value)/$($m.Groups[2].Value))" `
            ($m.Groups[1].Value -eq $m.Groups[2].Value -and [int]$m.Groups[1].Value -eq 6)
    }

    $script:rects = $null
    $script:beforeRow = $null

    Step "PHASE B: the map is IDLE -- all $UnitCount alive well after the mission started, nothing engaged" {
        Invoke-BoxSelect
        $s = Get-ScState 'combat-boxed'
        Assert-That "the box holds all $UnitCount placed units (n=$($s.N))" ($s.N -eq $UnitCount)
        Assert-That "they are all Lurkers (types=[$($s.TypesText)])" `
            (@($s.Types.Keys).Count -eq 1 -and @($s.Types.Keys)[0] -eq $LURKER_TYPE)
        $script:rects = Get-HudRects
        $before = Read-RowPages $rects
        Assert-That "the row is PAGED over all $UnitCount (n=$($before.N), $($before.Pages) pages)" `
            ($before.N -eq $UnitCount -and $before.Pages -eq [Math]::Ceiling($UnitCount / $HUD_SLOTS))
        Assert-That "its pages together name $UnitCount distinct units" ($before.Tags.Count -eq $UnitCount)
        Assert-That 'the enumeration was stable (no unit died while reading the pages)' ([bool]$before.Stable)
        $script:beforeRow = $before

        # Nothing may start on its own: the enemy is 10 tiles away and has to be
        # walked into. Twenty more seconds of nothing happening is the fixture's
        # "still idles indefinitely" property, kept from task 016.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Start-Sleep -Seconds 20
        $drop = Wait-RowDrop -Baseline $UnitCount -FromLine $mark -TimeoutSec 1
        Assert-That 'nothing died while the map was left alone for 20s' ($null -eq $drop) `
            ($null -eq $drop ? '' : "(got: $($drop.Line))")
        $idle = Get-ScState 'combat-idle'
        Assert-That "still all $UnitCount, still all live (n=$($idle.N) live=$($idle.Live))" `
            ($idle.N -eq $UnitCount -and $idle.Live -eq $UnitCount)
        Shot 'idle-boxed' | Out-Null
    }

    $script:samePassProof = $null

    Step "PHASE B: walk the block into the enemy until one of the boxed units DIES" {
        $baseline = $UnitCount
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $t0 = Get-Date
        Send-ScClick -Hwnd $hwnd -X $WALK_X -Y $WALK_Y -Right   # move order, into the enemy
        Start-Sleep -Seconds 2

        $drop = Wait-RowDrop -Baseline $baseline -FromLine $mark -TimeoutSec $FirstDeathTimeoutSec
        $elapsed = [int]((Get-Date) - $t0).TotalSeconds
        # The deadline is doing two jobs: it fails a fixture where nothing engages at
        # all, and it fails one where --unit-hp silently did not reach the engine (at
        # full health these Lurkers need several times this long to fall).
        Assert-That "a HUD-row line reported fewer units than were boxed, within ${FirstDeathTimeoutSec}s of the order (took ${elapsed}s at ${UnitHp}% hit points)" `
            ($null -ne $drop) '(nothing engaged -- no death was observed at all)'
        if ($null -eq $drop) { return }
        Write-Host "       DEATH: $($drop.Line)"

        # THE ORACLE. The row lost a unit; the shadow list did not, and every unit in
        # it still passes sc_fanout's liveness test, which compares CUnit+0xA5 and
        # nothing else. The only term that can separate the two numbers is the one
        # sc_hudrow adds: hitpoints != 0. This is that term firing in a real game.
        $now = Get-ScState 'at-the-death'
        Assert-That "a unit of the boxed selection DIED in combat -- the row's display list is down to $($drop.N) of $baseline" `
            ($drop.N -lt $baseline)
        Assert-That "the shadow list still holds all $baseline captured units (n=$($now.N))" `
            ($now.N -eq $baseline)
        Assert-That "and every one of them still passes the UNIQUENESS test (live=$($now.Live)) -- so what the row dropped, it dropped on HITPOINTS, the case CUnit+0xA5 alone misses" `
            ($now.Live -eq $baseline)
        Write-Host "       $($now.Line)"
        Shot 'at-the-death' | Out-Null

        if ($drop.Kind -eq 'stock') {
            # The dead unit was one of the ENGINE's own visible twelve, so the engine's
            # selection stopped matching our visible tail, the divergence latch fired
            # and the row handed itself back to stock. That is task-017's designed
            # behaviour, and the n it hands back with is already short of the dead unit.
            Write-Host '       (the dead unit was one of the engine''s visible twelve: divergence latch -> stock)'
        }
        else {
            # The dead unit was one of the overflow, so the row is still paging and the
            # SAME selection can be walked page by page right now -- the strongest form
            # of the claim, since the shadow list still holds the dead unit while the
            # row refuses to show it. Opportunistic: which unit the enemy shoots first
            # is not something this fixture controls.
            Write-Host '       (the dead unit was one of the overflow: the row is still paging)'
            try {
                $p = Read-RowPages $rects
                if ($p.Stable -and $p.N -lt $baseline -and $p.N -gt $HUD_SLOTS -and
                    $p.Tags.Count -eq $p.N) {
                    $script:samePassProof = $p
                }
            }
            catch { Write-Host "       (could not walk the pages before the next change: $($_.Exception.Message))" }
        }
    }

    $script:afterRow = $null

    Step 'PHASE B: THE 017 CONSEQUENCE -- the dead units are gone from the row, and the row is otherwise coherent' {
        # Break off the engagement and let the fight actually end before comparing tag
        # sets: a page walk over a selection that is still losing units compares two
        # different lists. Then take a fresh box -- required, not cosmetic, because a
        # death among the engine's visible twelve latches the row to stock and only a
        # new commit (a version bump, sc_hudrow RefreshShadow) clears that latch; a
        # fan-out of a move order does not rebuild the shadow list and so does not.
        # BURROW, not retreat. Walking away does not work: the Hydralisks pursue, the
        # Lurkers keep dying all the way home, and a page walk over a population that
        # is still moving compares two different lists (five disengage attempts in a
        # row failed that way). Burrowing ends the fight where it stands, because a
        # Hydralisk is not a detector and cannot target a burrowed unit at all -- and
        # it moves nobody, so the survivors stay in one boxable clump.
        #
        # It is the same untargeted-ability fan-out test-burrow-fanout.ps1 proves
        # reaches all 36 units from one keypress.
        Write-Host '       breaking off the fight by BURROWING (a Hydralisk is no detector: burrowed units cannot be targeted)'
        Send-ScKey -Hwnd $hwnd -VirtualKey $BURROW_KEY
        Start-Sleep -Seconds 4
        $dug = Get-ScState 'burrowed-out-of-the-fight'
        # More than a full page of them, so the row still has something to page over.
        # Not all of the shadow list: that count is over units passing the UNIQUENESS
        # test, which the ones already killed still do, and a dead Lurker does not
        # burrow. The gap between the two numbers is the deaths, which is the whole
        # point of this test.
        Assert-That "the survivors burrowed and are out of the fight ($($dug.Burrowed) of the $($dug.BurrowedOf) the shadow list still holds)" `
            ($dug.Burrowed -gt $HUD_SLOTS -and $dug.Burrowed -lt $dug.BurrowedOf)
        Wait-RowSettled -QuietSec 6 -TimeoutSec 90 | Out-Null

        for ($attempt = 1; $attempt -le $MaxRounds; $attempt++) {
            Write-Host "       -- regroup attempt $attempt --"
            Invoke-BoxSelect
            $a = Get-ScState "regroup$attempt"
            Start-Sleep -Seconds 5
            Invoke-BoxSelect
            $b = Get-ScState "regroup$attempt-again"
            Write-Host "       two boxes in a row: n=$($a.N) then n=$($b.N)"
            # Two identical boxes five seconds apart: nothing is still dying and
            # nothing is still walking home, so "missing from the row" cannot mean
            # "still on its way back".
            if ($a.N -ne $b.N -or $b.N -le $HUD_SLOTS) { continue }

            # One more box immediately before the page walk. It is the commit that
            # clears any divergence latch left by a death among the engine's visible
            # twelve -- without it the row can be sitting in stock mode and answer
            # nothing at all -- and it starts the walk with as much of the gap to the
            # next death as the fixture can offer.
            Invoke-BoxSelect
            $c = Get-ScState "regroup$attempt-final"
            if ($c.N -ne $b.N) {
                Write-Host "       (the third box disagreed: n=$($c.N) after $($b.N); retrying)"
                continue
            }
            try { $script:afterRow = Read-RowPages $rects } catch {
                Write-Host "       (the row would not answer: $($_.Exception.Message))"
                continue
            }
            if ($script:afterRow.Stable -and $script:afterRow.N -eq $c.N -and
                $script:afterRow.Tags.Count -eq $c.N) { break }
            Write-Host "       (unusable enumeration: n=$($script:afterRow.N) tags=$($script:afterRow.Tags.Count) stable=$($script:afterRow.Stable))"
            $script:afterRow = $null
        }

        Assert-That 'the fight could be broken off and the survivors re-boxed into a paged row' `
            ($null -ne $script:afterRow) "(after $MaxRounds attempts)"
        if ($null -eq $script:afterRow) { return }

        $before = $script:beforeRow
        $after = $script:afterRow
        Write-Host "       before: n=$($before.N) pages=$($before.Pages)  after: n=$($after.N) pages=$($after.Pages)"
        Write-Host "       after indicator: $($after.Indicator)"

        Assert-That "the row shows FEWER units than it did before the fight ($($after.N) < $($before.N))" `
            ($after.N -lt $before.N)
        Assert-That "it is still over the 12-unit cap, so this is a PAGED row (n=$($after.N))" `
            ($after.N -gt $HUD_SLOTS)
        $missing = @($before.Tags | Where-Object { $after.Tags -notcontains $_ })
        $extra = @($after.Tags | Where-Object { $before.Tags -notcontains $_ })
        Assert-That "every unit it shows is one it showed before -- nothing appeared from nowhere (extra: $($extra -join ' '))" `
            ($extra.Count -eq 0)
        # WHAT THIS DOES AND DOES NOT SAY. `$after` is a fresh drag box, so strictly
        # these tags are "in the row before the fight, not in it now" -- a survivor
        # shoved outside the box rectangle would read the same way. Burrowing first
        # makes that unlikely (nobody is moving, and two boxes five seconds apart
        # agreed before the walk), and the population drop is corroborated by the
        # HITPOINTS reading taken at the death itself, which needs no box at all. The
        # count identity that used to sit here -- missing == before.N - after.N --
        # was dropped: with `extra` empty and both tag counts equal to their own n, it
        # follows by set algebra and could not fail while its neighbours passed.
        Assert-That "units the row showed before the fight are gone from it now, by tag: $($missing -join ' ')" `
            ($missing.Count -ge 1)
        Assert-That "its pages together still name every unit it counts ($($after.Tags.Count) distinct vs n=$($after.N))" `
            ($after.Tags.Count -eq $after.N)
        Assert-That "the page count matches the population ($($after.Pages) = ceil($($after.N)/$HUD_SLOTS))" `
            ($after.Pages -eq [Math]::Ceiling($after.N / $HUD_SLOTS))
        Assert-That "the indicator text carries the new population ($($after.Indicator))" `
            ($after.Indicator -match "^$($after.N) units\b" -and $after.Indicator -match "\(1/$($after.Pages)\)")
        $s = Get-ScState 'after-consequence'
        Assert-That "the row and the shadow list agree again on the survivors (row n=$($after.N), shadow n=$($s.N) live=$($s.Live))" `
            ($s.N -eq $after.N -and $s.Live -eq $s.N)
        Shot 'row-after-death' | Out-Null

        # If the death happened to fall on an overflow unit, the same selection was
        # walked page by page WITH the dead unit still in the shadow list -- report it,
        # it is the same claim without the re-box in the middle.
        if ($null -ne $script:samePassProof) {
            $p = $script:samePassProof
            $gone = @($before.Tags | Where-Object { $p.Tags -notcontains $_ })
            Assert-That "BONUS (overflow death): the very same selection, walked page by page with the dead unit still in the shadow list, showed $($p.N) of $($before.N) and left out $($gone -join ' ')" `
                ($gone.Count -eq ($before.N - $p.N) -and $gone.Count -ge 1)
        }
        else {
            Write-Host '       (no same-pass walk this run -- either the first death fell on one of the'
            Write-Host '        engine''s visible twelve, or the next one landed before the walk finished)'
        }
    }

    Step 'PHASE B: losing units does NOT end the mission' {
        # Under Use Map Settings with an empty TRIG nothing can call Victory or Defeat,
        # so the game must still be running a minute after the losses -- and must still
        # take orders. An ended mission answers no markers and boxes no units.
        # Polled rather than one long sleep, so "the mission ended" and "the process
        # went away at some unknown moment" are different, dated observations.
        $held = 0
        $alive = $true
        while ($held -lt $HoldSec -and $alive) {
            Start-Sleep -Seconds 15
            $held += 15
            $p = Get-Process -Id $script:gamePid -ErrorAction SilentlyContinue
            if ($null -eq $p -or $p.HasExited) {
                Write-Host "       the game process went away ${held}s into the hold"
                $alive = $false
                break
            }
            $t = Get-ScState "holding-$held"
            Write-Host "       +${held}s: n=$($t.N) live=$($t.Live)"
            if ($t.N -le 0) { break }
        }
        Assert-That "the game process is still alive ${HoldSec}s after the losses" $alive
        if (-not $alive) { return }
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Invoke-BoxSelect
        $s = Get-ScState 'still-running'
        Assert-That "${HoldSec}s after the deaths the mission still has live units to box (n=$($s.N))" ($s.N -gt 0)
        Assert-That 'they are still the player''s Lurkers' ($s.Types.ContainsKey($LURKER_TYPE))
        Assert-That "and every one of them is live (live=$($s.Live) of n=$($s.N))" ($s.Live -eq $s.N)
        $orderMark = Get-ScLogLineCount -LogPath $LogPath
        # Unburrow: the survivors are dug in, so a move order is not something they can
        # take, but the ability that put them down is. Same untargeted-ability path as
        # test-burrow-fanout, and it has to reach every one of them, not the twelve.
        Send-ScKey -Hwnd $hwnd -VirtualKey $BURROW_KEY
        Start-Sleep -Seconds 4
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $orderLines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $orderMark)
        # An order given after the losses still reaches the engine's command queue
        # through our own hook and still fans out over the whole surviving selection.
        # A mission that had ended would have no selection and no command to fan.
        $fan = @($orderLines | Select-String -Pattern 'FANOUT start: cmd=0x[0-9A-F]{2} .* units=(\d+)')
        Assert-That 'and still take orders -- the order fanned out over the survivors through our hook' `
            ($fan.Count -gt 0) "(no FANOUT line after the order)"
        if ($fan.Count -gt 0) {
            $fm = [regex]::Match($fan[-1].Line, 'units=(\d+)')
            Assert-That "  and it covered the whole surviving selection ($($fm.Groups[1].Value) units)" `
                ([int]$fm.Groups[1].Value -eq $s.N)
        }
        $up = Get-ScState 'unburrowed'
        Assert-That "and every survivor acted on it -- they are back above ground ($($up.Burrowed) of $($up.BurrowedOf) still burrowed)" `
            ($up.Burrowed -eq 0)
        Assert-That 'the selection still ran through our own hooks after the losses' `
            (@($lines | Select-String -Pattern 'SORT candidates=\d+ -> selected=\d+|SHADOW captured: \d+ units').Count -gt 0)
        Shot 'still-running' | Out-Null
    }
}
catch {
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    if (-not $KeepOpen) { Stop-Mission }
    if (-not $KeepOpen -and (Test-Path -LiteralPath $mapDir)) {
        Remove-Item -LiteralPath $mapDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host '[final] the run must balance'
# Pid-scoped, both halves: every pid scinject handed THIS test, and nothing else.
# Another worker's game running right now is not this test's business and must not
# make it fail.
$stillUp = @($script:launchedPids | Where-Object {
    $p = Get-Process -Id $_ -ErrorAction SilentlyContinue
    $null -ne $p -and -not $p.HasExited
})
Assert-That 'no game process this test started is left running' `
    ($KeepOpen -or $stillUp.Count -eq 0) `
    "(launched $($script:launchedPids -join ' '); still up: $($stillUp -join ' '))"
Assert-That 'the generated maps were cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapDir))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host ("test-combat-death: $failures failure(s) in {0:mm\:ss}" -f ((Get-Date) - $runStart))
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
