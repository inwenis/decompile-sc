#Requires -Version 7
<#
.SYNOPSIS
Task 051. Does a game SAVED with the plugin active LOAD BACK into a correct, playable
state -- and does a save written by the plugin-free game still load under the plugin?
Drives the engine's own Save/Load dialogs in a real game and compares the ENGINE'S OWN
state across the round trip.

.DESCRIPTION
The user asked it directly (2026-08-12): *"btw - does saving and reading games work?
with our mods?"* Nobody had ever tested it in `fanout` mode -- the two save-test logs
that existed (2026-08-08) both ran `-Mode observe`, which writes nothing to game memory,
so they covered the one configuration that could not have broken anything.

## The oracle, and why the same one works in every arm

Both scans this suite reads are READ-ONLY and install no hook, so they exist in
`-Mode observe` exactly as they do in `-Mode fanout` (scplugin.cpp `ScanWorld`,
sc_card.cpp `STATQ`). That is what makes the no-plugin control arm and the fanout arms
comparable at all: it is the SAME oracle on both sides, not two different ones.

  * `STATQ` -- the producing building's own five ring slots at `CUnit+0x98` and the ring
    head. THIS IS THE VERDICT. It is the engine's array, read out of the building's
    memory, not the plugin's bookkeeping (AGENTS.md § "Assert the ENGINE'S OWN RESULT").
  * `WORLD` -- the engine's per-player unit lists: count, types, hp, position.
  * `PRODQSEL` -- the plugin's OWN overflow table and the resource globals. Reported,
    never asserted as the verdict: it exists to localise a failure to the save side or
    the load side, and it does not exist at all in the control arm.

## What the engine writes, from its own instructions

`FUN_004eaaf0` (the function carrying the two `Starcraft\SWAR\lang\CUnitSave.cpp`
asserts, lines 0xA0 and 0xB7) walks all 1700 `CUnit` slots of the static table at
`0x0059CCA8`, stride `0x150`, and for every live unit writes a 4-byte index followed by
a `rep movsd` of `0x54` dwords -- the WHOLE 336-byte CUnit, verbatim. `CUnit+0x98` (the
five-slot ring) and the ring head are inside that copy, so the engine's own five queued
items are serialised by construction. The plugin's over-cap items are NOT in any CUnit:
they live in `g_rec[]` in sc_prodqueue.cpp, keyed by the `CUnit*` address, so nothing in
the file can carry them. This suite exists to find out what that actually does to a
player's game.

## The seam

The state this suite exists to reach is A SAVE TAKEN WHILE THE PLUGIN IS HOLDING ITEMS
ABOVE THE ENGINE'S FIVE. An arm whose overflow was zero at save time cannot detect that
class of bug whatever its verdict says, so every arm prints its own COVERAGE line with
the overflow it actually had at save time (AGENTS.md § task 041).

## The phases

One phase per launch, because the plugin mode is fixed at launch and StarCraft is
single-instance per machine. Snapshots are written to -StateDir as JSON so a later
phase can compare against a state an earlier phase saved.

    control    -Mode observe   arm 1              (also writes the save arm 5 loads)
    fanout     -Mode fanout    arms 2, 3, 5, 6
    crossload  -Mode observe   arm 4              (loads the save arm 3 wrote)

## The user's real saves are never touched

Everything happens in -GameDir (`C:\sc-work\1161-base`), which has its own
`save\asdf\`. `C:\sc-deploy\starcraft-modded\game\save\` and `…\characters\` are hashed
by the task around this suite and are never opened by it.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-save-load.ps1 -SuiteArgs @{ Phase = 'control' }

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/test-save-load.ps1 -SuiteArgs @{ Phase = 'fanout' }
#>
[CmdletBinding()]
param(
    [ValidateSet('control', 'fanout', 'crossload')][string]$Phase = 'control',
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath,
    [string]$ShotDir = 'C:\sc-work\logs\051-frames',
    # Where the cross-phase snapshots live. Not the repo: these are run data.
    [string]$StateDir = 'C:\sc-work\logs\051',
    [string]$FixtureDir,
    # The plugin's logical cap for the fanout arms. 8 = 4 in the engine's ring
    # (SC_PRODQ_ENGINE_HOLD) + 4 held by the plugin, comfortably inside the 18 psi two
    # Nexuses provide, so no Pylon has to be placed for the run to mean anything.
    [int]$QueueMax = 8,
    # The ordinary-queue arm: below the hold, so the plugin holds NOTHING and the ring
    # carries the lot. That is the arm that says "fanout with nothing above the cap".
    [int]$OrdinaryQueue = 4,
    # Vanilla Probe build time is 20 game seconds, and this run measures across a window
    # in which a COMPLETION would change the ring for reasons that have nothing to do with
    # save/load. 90s was NOT enough and the run said so rather than averaging it away: the
    # over-cap arm went INCONCLUSIVE with `completed units (player 0) 2 -> 3`, because the
    # window from the queueing clicks to the post-load read is ~75 s of real time (8
    # clicks, snapshot, save + confirm, witness, load, re-select, snapshot) and the head
    # item had already been building for part of its 90 before the save was taken. 240
    # leaves the whole window inside one item's build, and the run still asserts it
    # instead of assuming it.
    [int]$ProbeBuildSeconds = 240,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 1000,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptDir -Parent) -Parent
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

if (-not $LogPath) { $LogPath = "C:\sc-work\logs\051\save-load-$Phase.log" }

# --- fixture ------------------------------------------------------------------
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t051' }
$mapDir = $FixtureDir
$mapName = 'save-load.scx'                    # named for the SUITE (hard rule, task 021/022)
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

# --- constants ----------------------------------------------------------------
$NEXUS_TYPE = 154         # units.dat 154, 'Protoss Nexus'
$PROBE_TYPE = 64          # units.dat 64,  'Protoss Probe'
$TRAIN_ACT  = '004234B0'  # the card's Train action, as the CARD read-back reports it
$TRAIN_SLOT = 1
$TRAIN_CMD  = '0x1F'
$ENGINE_SLOTS = 5         # research/production-queue.md 2.3
$ENGINE_HOLD  = 4         # SC_PRODQ_ENGINE_HOLD
$QUEUE_EMPTY  = 0xE4      # SC_BUILD_QUEUE_EMPTY
$SC_UNIT_FLAG_COMPLETED = 0x01
$VK_F10 = 0x79

$saveRoot = Join-Path $GameDir 'save'
$stashDir = Join-Path $StateDir 'stash'

$failures = 0
$step = 0
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

# =============================================================================
# READS
# =============================================================================

function Get-World { param([string]$Tag) Get-ScWorldState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath }
function Get-Statq { param([string]$Tag) Get-ScStatusQueue -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath }
function Get-Card  { param([string]$Tag) Get-ScCardState   -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath }

# The plugin's OWN table, for THE MARKER THIS READ WROTE -- matched on the tag, not
# "the newest PRODQSEL line in the log", so it cannot silently report a different
# instant's state than the STATQ read it is printed beside.
#
# $null when this arm has no production queue at all (the control and crossload phases),
# which is a normal answer here and never a failure -- what it must not do is read as
# "the plugin holds nothing", which is why every caller prints it as -1 rather than 0.
function Get-Prodq {
    param([string]$Tag)
    $esc = [regex]::Escape($Tag)
    $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
               Select-String -Pattern "PRODQ(SEL)? \[$esc-\d+\]")
    if ($lines.Count -eq 0) { return $null }
    $sel = @($lines | Select-String -Pattern 'PRODQSEL' | Select-Object -Last 1)
    if ($sel.Count -eq 0) { return $null }
    $m = [regex]::Match($sel[0].Line,
        'PRODQSEL \[[^\]]+\] unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) logical=(\d+) minerals=(\d+) gas=(\d+)')
    if (-not $m.Success) { return $null }
    # The summary line of the same dump: how many buildings the plugin is TRACKING. After
    # a load that is the number that says whether stale records survived (arm 6).
    $sum = @($lines | Select-String -Pattern 'buildings=(\d+) max=' | Select-Object -Last 1)
    $buildings = -1
    $promoted = -1
    if ($sum.Count -gt 0) {
        $buildings = [int][regex]::Match($sum[0].Line, 'buildings=(\d+)').Groups[1].Value
        # promoted counts, for the whole run, the times the plugin moved an item into a
        # ring slot that FREED -- i.e. the times an item finished building. It is the
        # plugin's own counter and it is used here only as corroboration for the window
        # check, whose primary evidence is the engine's own completed-unit count.
        $pm = [regex]::Match($sum[0].Line, 'promoted=(\d+)')
        if ($pm.Success) { $promoted = [int]$pm.Groups[1].Value }
    }
    [pscustomobject]@{
        Unit = $m.Groups[1].Value; Type = [Convert]::ToInt32($m.Groups[2].Value, 16)
        Player = [int]$m.Groups[3].Value; Head = [int]$m.Groups[4].Value
        EngineLen = [int]$m.Groups[5].Value
        Overflow = [int]$m.Groups[7].Value; Logical = [int]$m.Groups[8].Value
        Minerals = [int]$m.Groups[9].Value; Gas = [int]$m.Groups[10].Value
        Buildings = $buildings
        Promoted = $promoted
        Line = $sel[0].Line.Trim()
    }
}

# ONE snapshot of everything this suite compares. Taken with the building selected.
function Get-Snapshot {
    param([string]$Tag)
    $statq = Get-Statq $Tag
    $world = Get-World $Tag
    $prodq = Get-Prodq $Tag
    $engine = @($statq.Engine)
    $occupied = @($engine | Where-Object { $_ -ne $QUEUE_EMPTY -and $_ -ne 0 })
    $units = @($world.Units | ForEach-Object {
        [pscustomobject]@{
            Player = $_.Player; Type = $_.Type; Hp = $_.Hp; X = $_.X; Y = $_.Y
            Complete = (($_.Flags -band $SC_UNIT_FLAG_COMPLETED) -ne 0)
        }
    })
    [pscustomobject]@{
        Tag = $Tag
        Head = $statq.Head
        Engine = $engine
        EngineLen = $occupied.Count
        PortraitType = $statq.PortraitType
        PortraitOwner = $statq.PortraitOwner
        StatqOk = $statq.Ok
        Units = $units
        Counts = @($world.Counts.Keys | Sort-Object | ForEach-Object {
            [pscustomobject]@{ Player = $_; Units = $world.Counts[$_].Units
                               Recount = $world.Counts[$_].Recount; Complete = $world.Counts[$_].Complete } })
        Overflow = $(if ($prodq) { $prodq.Overflow } else { -1 })
        Logical  = $(if ($prodq) { $prodq.Logical } else { -1 })
        Minerals = $(if ($prodq) { $prodq.Minerals } else { -1 })
        Gas      = $(if ($prodq) { $prodq.Gas } else { -1 })
        # How many buildings the plugin's own table is tracking. -1 = this arm has no
        # production queue, which is NOT the same as zero (AGENTS.md, absence rule).
        Buildings = $(if ($prodq) { $prodq.Buildings } else { -1 })
        Promoted  = $(if ($prodq) { $prodq.Promoted } else { -1 })
        # THE WINDOW EVIDENCE, and it is the ENGINE's: how many of player 0's units carry
        # the completed flag. A queued item that merely STARTS building is already in the
        # unit list with that flag CLEAR, so this number moves only when something
        # actually finishes -- which is the event that would invalidate the comparison.
        CompletedP0 = @($units | Where-Object { $_.Player -eq 0 -and $_.Complete }).Count
        ProdqLine = $(if ($prodq) { $prodq.Line } else { '(no PRODQSEL line -- this arm has no production queue)' })
        StatqLine = ($statq.Lines | Select-Object -First 1)
    }
}

function Show-Snapshot {
    param([string]$What, $S)
    $eng = ($S.Engine | ForEach-Object { '0x{0:X3}' -f $_ }) -join ','
    Write-Host ("       {0}: head={1} engineLen={2} engine=[{3}] overflow={4} minerals={5} units(p0)={6}" -f `
        $What, $S.Head, $S.EngineLen, $eng, $S.Overflow, $S.Minerals,
        (@($S.Units | Where-Object Player -eq 0).Count))
}

function Save-Snapshot {
    param([string]$Name, $S)
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    $p = Join-Path $StateDir "snap-$Name.json"
    $S | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $p
    Write-Host "       snapshot -> $p"
}

function Read-Snapshot {
    param([string]$Name)
    $p = Join-Path $StateDir "snap-$Name.json"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
}

# =============================================================================
# THE COMPARISON -- section 4.1 of the report, one function
# =============================================================================

function Compare-RoundTrip {
    param(
        [string]$Arm,
        $Before, $After,
        # The over-cap items the plugin was holding when the save was taken. Printed as
        # the arm's COVERAGE line, because an arm with 0 of them cannot see the class of
        # bug this suite exists to find.
        [int]$OverflowAtSave
    )
    Write-Host ''
    Write-Host "  --- $Arm ---"
    Show-Snapshot 'at save ' $Before
    Show-Snapshot 'at load ' $After

    # THE MEASUREMENT WINDOW COMES FIRST, because it decides whether the verdict below can
    # be read at all. Two windows exist -- between the S1 read and the file being written,
    # and between the load finishing and the S2 read -- and a queued item COMPLETING in
    # either one changes the ring for a reason that has nothing to do with save/load.
    #
    # It is not inferred from "the queue is still N deep": an item can finish while another
    # is promoted behind it and leave the depth looking untouched. The evidence is the
    # ENGINE'S OWN completed-unit count, with the plugin's promotion counter beside it as
    # corroboration where it exists.
    $windowClean = ($Before.CompletedP0 -eq $After.CompletedP0)
    $promoNote = if ($Before.Promoted -ge 0 -and $After.Promoted -ge 0) {
        ", plugin promotions $($Before.Promoted) -> $($After.Promoted)"
    } else { ', plugin promotions not reported in this arm' }
    Write-Host ("  WINDOW    completed units (player 0) {0} -> {1}{2}" -f `
        $Before.CompletedP0, $After.CompletedP0, $promoNote)
    if (-not $windowClean) {
        Write-Host "  INCONCLUSIVE  $Arm`: a unit COMPLETED inside the measurement window."
        Write-Host "            The comparison below is about two different world states and its"
        Write-Host "            verdict must not be read as a save/load result. Re-run this arm with"
        Write-Host "            a longer -ProbeBuildSeconds. NOT a pass and NOT a save/load failure."
        $script:inconclusive++
    }
    Assert-That "$Arm W: nothing completed inside the measurement window" $windowClean `
        "(completed p0 $($Before.CompletedP0) -> $($After.CompletedP0) -- see INCONCLUSIVE above)"

    # A1/A2/A3 -- THE VERDICT. The engine's own ring, out of the building's memory.
    $engBefore = ($Before.Engine | ForEach-Object { '0x{0:X3}' -f $_ }) -join ','
    $engAfter  = ($After.Engine  | ForEach-Object { '0x{0:X3}' -f $_ }) -join ','
    Assert-That "$Arm A2: the five ring slots at CUnit+0x98 survive the round trip" `
        ($engBefore -eq $engAfter) "(save=[$engBefore] load=[$engAfter])"
    Assert-That "$Arm A1: the ring head survives ($($Before.Head) -> $($After.Head))" `
        ($Before.Head -eq $After.Head)
    Assert-That "$Arm A3: the occupied-slot count survives ($($Before.EngineLen) -> $($After.EngineLen))" `
        ($Before.EngineLen -eq $After.EngineLen)
    # A4 -- task 039: a reading taken while the pane holds a different unit is a reading
    # about the wrong building.
    Assert-That "$Arm A4: the status pane still holds the same building type/owner" `
        ($Before.PortraitType -eq $After.PortraitType -and $Before.PortraitOwner -eq $After.PortraitOwner) `
        "(save=0x$('{0:X}' -f $Before.PortraitType)/$($Before.PortraitOwner) load=0x$('{0:X}' -f $After.PortraitType)/$($After.PortraitOwner))"

    # B1/B2 -- the world.
    $b0 = @($Before.Units | Where-Object Player -eq 0)
    $a0 = @($After.Units  | Where-Object Player -eq 0)
    Assert-That "$Arm B1: player 0 owns the same number of units ($($b0.Count) -> $($a0.Count))" `
        ($b0.Count -eq $a0.Count)
    $bt = (@($b0 | ForEach-Object { $_.Type }) | Sort-Object) -join ','
    $at = (@($a0 | ForEach-Object { $_.Type }) | Sort-Object) -join ','
    Assert-That "$Arm B2: the multiset of unit types is unchanged" ($bt -eq $at) `
        "(save=[$bt] load=[$at])"
    # B3 -- COMPLETED units only, exactly. A unit still being trained has its hp ramping,
    # so its hp legitimately differs between two reads taken seconds apart; it is counted
    # (B1/B2) and reported, never asserted equal.
    $bc = @($b0 | Where-Object Complete | ForEach-Object { "$($_.Type):$($_.Hp)@$($_.X),$($_.Y)" } | Sort-Object)
    $ac = @($a0 | Where-Object Complete | ForEach-Object { "$($_.Type):$($_.Hp)@$($_.X),$($_.Y)" } | Sort-Object)
    Assert-That "$Arm B3: every COMPLETED unit has the same hp and position ($($bc.Count) unit(s))" `
        (($bc -join '|') -eq ($ac -join '|')) `
        "(save=[$($bc -join ' ')] load=[$($ac -join ' ')])"

    # C/D -- the plugin's own books and the money. REPORTED. Never the verdict.
    Write-Host ("       plugin (not the verdict): overflow {0} -> {1}, logical {2} -> {3}, minerals {4} -> {5}, tracked buildings {6} -> {7}" -f `
        $Before.Overflow, $After.Overflow, $Before.Logical, $After.Logical, $Before.Minerals, $After.Minerals,
        $Before.Buildings, $After.Buildings)
    Write-Host "       save: $($Before.ProdqLine)"
    Write-Host "       load: $($After.ProdqLine)"

    # COVERAGE -- what this arm was able to see at all.
    if ($OverflowAtSave -gt 0) {
        Write-Host "  COVERAGE  overflow held at save time = $OverflowAtSave -- this arm DOES reach the over-cap seam."
    }
    else {
        Write-Host "  COVERAGE  overflow held at save time = 0 -- this arm CANNOT detect the over-cap class,"
        Write-Host "            whatever its verdict says. Only an arm with overflow > 0 can."
    }
}

# =============================================================================
# DRIVING THE ENGINE'S OWN SAVE / LOAD DIALOGS
# =============================================================================
#
# Nothing here clicks a fixed point or a row by number. Every click is computed from the
# control's OWN bounds in the engine's dialog list (the plugin's DIALOGS line), and every
# failure prints the full inventory of what WAS on screen. The primitives themselves live
# in drive-game.ps1 (Show-ScDialogInventory / Find-ScDialogControl / Invoke-ScDialogControl
# / Open-ScGameMenu / Send-ScText) so this suite and probe-save-load-dialogs.ps1 drive the
# same dialogs through exactly one implementation.

function Get-SaveFiles {
    if (-not (Test-Path -LiteralPath $saveRoot)) { return @() }
    @(Get-ChildItem -LiteralPath $saveRoot -Recurse -File -Filter '*.snx' -ErrorAction SilentlyContinue)
}

# Save the running game, and prove it by the FILE THE ENGINE WROTE -- not by the dialog
# going away. Returns the FileInfo of the new save.
function Save-ScGame {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$Name)
    # The evidence that a save happened is THE FILE, and on the overwrite path -- which
    # every re-run of this suite takes -- no NEW file appears: an existing one is
    # rewritten. So the record kept here is name -> last-write time, and "saved" means the
    # file called $Name either did not exist before or has a newer timestamp than it did.
    # Counting files would report a successful overwrite as a failure.
    $beforeStamp = @{}
    foreach ($f in (Get-SaveFiles)) { $beforeStamp[$f.FullName] = $f.LastWriteTimeUtc }
    $before = @($beforeStamp.Keys)
    $savedFile = {
        $hit = @(Get-SaveFiles | Where-Object { $_.BaseName -ieq $Name }) | Select-Object -First 1
        if (-not $hit) { return $null }
        if (-not $beforeStamp.ContainsKey($hit.FullName)) { return $hit }
        if ($hit.LastWriteTimeUtc -gt $beforeStamp[$hit.FullName]) { return $hit }
        return $null
    }
    Open-ScGameMenu -Hwnd $Hwnd -LogPath $LogPath | Out-Null
    Invoke-ScDialogControl -Hwnd $Hwnd -LogPath $LogPath -Pattern 'Save' -What 'Save Game' | Out-Null
    Start-Sleep -Seconds 1
    Show-ScDialogInventory -LogPath $LogPath -What 'save dialog'

    # Type the name. The dialog opens with its edit box focused and the engine reads
    # typed text through WM_CHAR (drive-game.ps1 Send-ScKey -Char). Backspaces first, in
    # case the box opens pre-filled with a previous name -- typing into a filled box
    # would otherwise produce a name this run cannot predict. NOTHING is concluded from
    # having typed it: the file the engine writes is the evidence (task 033).
    Send-ScText -Hwnd $Hwnd -Text $Name -ClearCount 24
    Start-Sleep -Milliseconds 500
    Show-ScDialogInventory -LogPath $LogPath -What 'save dialog, name typed'

    # THE BOX IS READ BACK, EVERY TIME, AND ITS CONTENT IS THE ENGINE'S. This dialog opens
    # PRE-FILLED with the previous save's name, so a run that types without clearing --
    # or whose clear fell short -- silently saves over the file an earlier phase wrote,
    # and the load that follows reads a file that is not the one this arm means. That
    # would produce a confident, wrong verdict rather than an error, so it throws.
    #
    # Compared against the control's RAW text (not the letter-stripped form the matcher
    # uses), so a name with digits in it would still be checked exactly.
    $box = @(Get-ScDialogs -LogPath $LogPath |
             Where-Object { $_.Name -match 'SaveGame' } |
             ForEach-Object { $_.Controls } | Where-Object { $_.Type -eq 8 }) | Select-Object -First 1
    if (-not $box) {
        Show-ScDialogInventory -LogPath $LogPath -What 'no type-8 edit control on the save dialog'
        throw 'test: the save dialog has no name box in the engine walk -- refusing to save blind.'
    }
    if ($box.Text -cne $Name) {
        throw ("test: the save dialog's name box reads '$($box.Text)', not '$Name'. Saving now " +
               'would write a file this arm cannot identify, and could overwrite another arm''s save.')
    }
    Write-Host "       the name box reads '$($box.Text)' -- exactly what this arm meant to save"

    # 'Save$', not '^Save$': the engine keeps the hotkey inside the string, so the button
    # reads 's.S.ave' and its LETTERS are 'sSave' (measured, task 051's dialog probe).
    # Anchoring at the END separates the button from the dialog TITLE, 'SaveGame'.
    Invoke-ScDialogControl -Hwnd $Hwnd -LogPath $LogPath -Pattern '(OK$|Save$)' `
        -What 'the save dialog Save button' | Out-Null
    Start-Sleep -Seconds 3

    # THE SAVE IS A STATE MACHINE, NOT ONE CLICK, and both of its facts were measured
    # rather than assumed (task 051):
    #
    #   * A POSTED CLICK ON THIS ENGINE'S DEFAULT DIALOG BUTTON DOES NOT FIRE IT. The
    #     save dialog's own 's.S.ave' (type=1) was clicked at the centre computed from
    #     its own bounds and the dialog just sat there with the name intact; Return wrote
    #     the file. So every step here is click-then-Return, never click alone.
    #   * SAVING OVER AN EXISTING NAME OPENS A SECOND DIALOG: `OkCancel`, reading
    #     "Replace the contents of game .slctl.?" with its own default `o.O.K`. It appears
    #     only on the overwrite path -- which is the path a player takes constantly and
    #     the path every re-run of this suite takes.
    #
    # So: loop over the states the engine can be in, name the branch taken each time
    # (AGENTS.md § task 030 -- print WHICH branch, not that a branch happened), and stop
    # the moment the FILE exists, which is the only evidence that counts.
    $how = 'the Save button'
    for ($round = 1; $round -le 5; $round++) {
        if (& $savedFile) { break }
        $replace = @(Find-ScDialogControl -LogPath $LogPath -Pattern 'OK$' |
                     Where-Object { $_.Dialog.Name -match 'OkCancel' })
        if ($replace.Count -gt 0) {
            Write-Host "       round ${round}: the engine is asking to REPLACE an existing save; confirming"
            Send-ScClick -Hwnd $Hwnd -X $replace[0].X -Y $replace[0].Y
            Start-Sleep -Milliseconds 700
            if (@(Find-ScDialogControl -LogPath $LogPath -Pattern 'OK$' |
                  Where-Object { $_.Dialog.Name -match 'OkCancel' }).Count -gt 0) {
                Send-ScKey -Hwnd $Hwnd -VirtualKey 0x0D
            }
            $how = 'Return + the replace confirmation'
            Start-Sleep -Seconds 3
            continue
        }
        if (@(Find-ScDialogControl -LogPath $LogPath -Pattern 'Save$').Count -gt 0) {
            Write-Host "       round ${round}: the save dialog is still up; pressing Return, which the default button answers to"
            Send-ScKey -Hwnd $Hwnd -VirtualKey 0x0D
            $how = 'the Return key (THE BUTTON CLICK DID NOT SAVE)'
            Start-Sleep -Seconds 3
            continue
        }
        Start-Sleep -Seconds 2
    }

    $after = @(Get-SaveFiles)
    # `@(& $savedFile)` around a block that can `return $null` yields an array of ONE
    # $null, whose .Count is 1 -- so an empty-count test passes it straight through to a
    # property access on nothing. Filter the nulls out at the source instead.
    $new = @(& $savedFile | Where-Object { $null -ne $_ })
    if ($new.Count -eq 0) {
        Show-ScDialogInventory -LogPath $LogPath -What 'after the save attempt'
        # Where else could it have gone? A save written somewhere this suite does not look
        # would otherwise read exactly like a save that was never written.
        $loose = @(Get-ChildItem -LiteralPath $GameDir -Recurse -File -Filter '*.snx' -ErrorAction SilentlyContinue |
                   Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-3) })
        Write-Host ("       .snx files anywhere under $GameDir modified in the last 3 minutes: {0}" -f `
            $(if ($loose.Count) { ($loose | ForEach-Object { $_.FullName }) -join ', ' } else { 'none' }))
        throw ("test: the engine wrote no new .snx under $saveRoot, by button OR by Return. Files there: " +
               (($after | ForEach-Object { $_.Name }) -join ', '))
    }
    Write-Host "       the save was taken by $how"
    Write-Host ("       the engine wrote {0} ({1} bytes)" -f $new[0].FullName, $new[0].Length)
    $new[0]
}

# Load a save. The target is made unambiguous BY THE FILESYSTEM -- every other .snx is
# moved out of the save folder first -- so this never clicks a list row by number
# (the map-browser hard rule, task 023, in its other costume).
# A run that died between the stash and the restore leaves other people's saves sitting
# in the stash directory. Put anything found there back BEFORE this run stashes again --
# otherwise the second run's restore would overwrite the first run's rescue with its own
# empty idea of what was moved.
function Restore-StashedSaves {
    if (-not (Test-Path -LiteralPath $stashDir)) { return }
    $left = @(Get-ChildItem -LiteralPath $stashDir -File -Filter '*.snx' -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) { return }
    $charDir = Join-Path $saveRoot 'asdf'
    New-Item -ItemType Directory -Path $charDir -Force | Out-Null
    foreach ($f in $left) {
        $dest = Join-Path $charDir $f.Name
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $f.FullName -Force }
        else { Move-Item -LiteralPath $f.FullName -Destination $dest -Force }
    }
    Write-Host "       recovered $($left.Count) save(s) left in the stash by an earlier run"
}

function Load-ScGame {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][System.IO.FileInfo]$File)
    New-Item -ItemType Directory -Path $stashDir -Force | Out-Null
    $moved = @()
    foreach ($f in (Get-SaveFiles)) {
        if ($f.FullName -ne $File.FullName) {
            $dest = Join-Path $stashDir $f.Name
            Move-Item -LiteralPath $f.FullName -Destination $dest -Force
            $moved += [pscustomobject]@{ From = $f.FullName; To = $dest }
        }
    }
    Write-Host ("       {0} other save(s) stashed; '{1}' is the only one the dialog can list" -f $moved.Count, $File.Name)
    try {
        Open-ScGameMenu -Hwnd $Hwnd -LogPath $LogPath | Out-Null
        Invoke-ScDialogControl -Hwnd $Hwnd -LogPath $LogPath -Pattern 'Load' -What 'Load Game' | Out-Null
        Start-Sleep -Seconds 1
        Show-ScDialogInventory -LogPath $LogPath -What 'load dialog'
        # The list holds exactly one entry. If the engine puts its name in a control, say
        # so -- that is the read that proves the row is the file we mean.
        $named = @(Find-ScDialogControl -LogPath $LogPath -Pattern ([regex]::Escape(($File.BaseName -replace '[^A-Za-z]', ''))))
        if ($named.Count -gt 0) {
            Write-Host "       the dialog lists '$($named[0].Control.Text)' -- clicking that entry"
            Send-ScClick -Hwnd $Hwnd -X $named[0].X -Y $named[0].Y
            Start-Sleep -Milliseconds 600
        }
        else {
            Write-Host '       the list rows carry no text in the engine dialog walk; relying on the single-entry folder'
        }
        Invoke-ScDialogControl -Hwnd $Hwnd -LogPath $LogPath -Pattern '(OK$|Load$)' `
            -What 'the load dialog Load button' | Out-Null
        Start-Sleep -Seconds 4
        # Same two-ways-in as the save, and for the same measured reason: a posted click on
        # this engine's DEFAULT dialog button does not fire it (task 051 -- the save
        # dialog's own 's.S.ave' was clicked at its centre and wrote nothing, while Return
        # wrote the file). If the dialog is still up, press the key the default button
        # answers to, and say which branch got us out.
        if (@(Find-ScDialogControl -LogPath $LogPath -Pattern 'Load$').Count -gt 0) {
            Write-Host '       the load dialog is still up after the click; pressing Return'
            Send-ScKey -Hwnd $Hwnd -VirtualKey 0x0D
        }
        Start-Sleep -Seconds 12
        Dismiss-ScTipsDialog -Hwnd $Hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
    }
    finally {
        foreach ($m in $moved) { Move-Item -LiteralPath $m.To -Destination $m.From -Force }
        if ($moved.Count) { Write-Host "       $($moved.Count) stashed save(s) put back" }
    }
}

# =============================================================================
# IN-GAME HELPERS
# =============================================================================

# Select the fixture's first Nexus by a point DERIVED FROM MEMORY (client = map -
# viewport, the arithmetic the engine's own click handler at 0x0046FB40 does).
function Select-Nexus {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [string]$Tag, [int]$Which = 0)
    $w = Get-World "aim-$Tag"
    $all = @(@($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $NEXUS_TYPE }) | Sort-Object X, Y)
    if ($all.Count -le $Which) {
        throw "test: the world scan found $($all.Count) player-0 Nexus(es); need index $Which ($Tag)."
    }
    $nx = $all[$Which]
    if (-not $w.Screen) { throw 'test: the world scan reports no viewport origin.' }
    $cx = $nx.X - $w.Screen.Left
    $cy = $nx.Y - $w.Screen.Top
    if ($cx -lt 0 -or $cx -ge 640 -or $cy -lt 0 -or $cy -ge 340) {
        throw "test: the Nexus is not inside the play area at client ($cx,$cy) -- refusing to click."
    }
    Send-ScClick -Hwnd $Hwnd -X $cx -Y $cy
    Start-Sleep -Seconds 2
    $st = Get-Statq "sel-$Tag"
    if (-not $st.Ok) { throw "test: no status pane after selecting the Nexus ($Tag)." }
    Write-Host ("       Nexus selected: portrait type=0x{0:X} owner={1} head={2}" -f `
        $st.PortraitType, $st.PortraitOwner, $st.Head)
    $st
}

# Click Train N times. THE CARD IS RE-READ BEFORE EVERY CLICK (task 039): a slot's
# meaning changes under you, and a loop that reads once and clicks N times is how a
# Command Center ends up in the air.
function Add-ToQueue {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][int]$Count, [string]$Tag)
    $sent = 0
    for ($i = 1; $i -le $Count; $i++) {
        $card = Get-Card "train-$Tag-$i"
        $slot = Get-ScCardSlot -Card $card -Slot $TRAIN_SLOT
        if (-not $slot -or -not $slot.HasButton -or $slot.Action -ne $TRAIN_ACT) {
            Write-Host ("       press {0}: slot {1} is no longer the Train action (act={2}) -- stopping" -f `
                $i, $TRAIN_SLOT, $slot.Action)
            break
        }
        if ($slot.Disabled -or -not $slot.Visible) {
            Write-Host "       press ${i}: the Train button is $($slot.State) -- the client refuses more; stopping"
            break
        }
        if ($slot.ActParam -ne $PROBE_TYPE) {
            throw "test: the Train button trains type $($slot.ActParam), not the Probe ($PROBE_TYPE)."
        }
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $pt = Get-ScCardSlotPoint -Card $card -Slot $TRAIN_SLOT
        Send-ScClick -Hwnd $Hwnd -X $pt.X -Y $pt.Y -SettleMs 400
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        if (@($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ").Count -gt 0) { $sent++ }
    }
    Write-Host "       $sent Train command(s) reached the engine's own funnel"
    $sent
}

# =============================================================================
# THE RUN
# =============================================================================

$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Write-Host "[0] phase=$Phase  StarCraft.exe SHA-256 before: $hashBefore"
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
$launchLock = $null
$episodes = 0          # arms that ran to a verdict -- see the INCOMPLETE rule at the end
$inconclusive = 0      # arms whose measurement window was dirty -- neither pass nor fail
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0}-{1:d2}-{2}.png" -f $Phase, $script:shotN, $tag)) -FullWindow | Out-Null
}

try {
    Restore-StashedSaves

    Step "generate the fixture: two Nexuses, Probe build time ${ProbeBuildSeconds}s" {
        Wait-ScFixtureFolderFree -Run $fixtures
        # Two Nexuses: 18 psi between them, so a queue of $QueueMax Probes needs no Pylon
        # on buildable ground for the run to mean anything. Only the first is ever
        # selected. The long Probe build time is what keeps a COMPLETION out of both
        # measurement windows -- asserted, not assumed, at the end of each arm.
        $genArgs = @{
            UnitCount = 2; UnitType = 'nexus'; Player = 0; ClearPlayerUnits = $true
            Race = 'protoss'; GridSpacing = 160
            StartingMinerals = $StartingMinerals; StartingGas = $StartingGas
            UnitBuildTime = @("probe=$ProbeBuildSeconds")
            OutputPath = $mapPath
        }
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That "the fixture overrides the Probe's build time to ${ProbeBuildSeconds}s in UNIx" `
            (@($gen | Select-String -Pattern "probe \(64\) usesDefault=0 .*\*build-time=$ProbeBuildSeconds ").Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId "051-save-load-$Phase"

    Step "launch: $(if ($Phase -eq 'fanout') { 'fanout, the flags deploy.ps1 bakes into the user shortcut' } else { 'observe -- NO hooks, nothing written to game memory' })" {
        $common = @{
            InjectWindowedHelper = 'WMode'; NoLaunchLock = $true
            GameDir = $GameDir; LogPath = $LogPath
            WorldScan = '1'; CardScan = '1'; LogCommands = '1'
        }
        if ($Phase -eq 'fanout') {
            & (Join-Path $scriptDir 'run-with-plugin.ps1') @common `
                -Mode fanout -Circles 1 -HudRow 1 -ProdQueue 1 -ProdQueueMax $QueueMax `
                -ProdFan 1 -UpgradeQueue 1 -QueueIndicator 1 6>&1 | ForEach-Object {
                    Write-Host $_
                    if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
                }
        }
        else {
            & (Join-Path $scriptDir 'run-with-plugin.ps1') @common -Mode observe 6>&1 | ForEach-Object {
                Write-Host $_
                if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
            }
        }
        if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
        $script:hwnd = Get-ScGameWindow -ProcessId $gamePid
    }

    Step 'the arm is the arm it says it is -- hooks present, or positively absent' {
        # AGENTS.md § "Absence assertions must first be proved positive": the pattern
        # asserted absent in the observe arms is the plugin's REAL wording, and the fanout
        # arm asserts the same pattern PRESENT in the same run of the same suite.
        $hooks = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'HOOK [A-Za-z]+: installed at')
        if ($Phase -eq 'fanout') {
            Assert-That "fanout: the plugin's detours are spliced ($($hooks.Count) HOOK line(s))" ($hooks.Count -gt 0)
            $cfg = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODQ config: enabled max=')
            Assert-That "and the production queue is enabled at max=$QueueMax" `
                (@($cfg | Select-String -Pattern "max=$QueueMax ").Count -gt 0) "(lines: $($cfg.Count))"
        }
        else {
            Assert-That 'observe: NOT ONE hook is installed -- this is the plugin-free control' `
                ($hooks.Count -eq 0) "(got $($hooks.Count): $(($hooks | ForEach-Object { $_.Line }) -join ' | '))"
            Assert-That 'and the plugin says so itself' `
                (@(Get-Content -LiteralPath $LogPath |
                   Select-String -Pattern 'mode\s+: observe').Count -gt 0)
        }
    }

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2      # Use Map Settings, verified
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    # -------------------------------------------------------------------------
    # One round trip, parameterised. Used by every arm that saves in this phase.
    # -------------------------------------------------------------------------
    function Invoke-RoundTrip {
        param([string]$Arm, [int]$Queue, [string]$SaveName)
        Select-Nexus -Hwnd $hwnd -Tag $Arm | Out-Null
        $sent = Add-ToQueue -Hwnd $hwnd -Count $Queue -Tag $Arm
        # The wire count is REPORTED, not asserted, and here is why: `CMD id=` lines are
        # written by the command-funnel hook, which exists in fanout/hooktest and NOT in
        # observe. The control arm therefore reports 0 commands however well the clicks
        # worked -- an assertion on it fails the arm for the arm's own configuration
        # (measured: the control run's first pass said "0 Train commands" while the
        # engine's ring read [0x040,0x040,0x040,0x040,0x0E4]).
        #
        # What IS asserted is the ENGINE'S OWN RING, which exists in every arm.
        Write-Host "       Train commands seen on the funnel: $sent (absent by design in -Mode observe)"
        $q = Get-Statq "$Arm-queued"
        $qLen = @($q.Engine | Where-Object { $_ -ne $QUEUE_EMPTY -and $_ -ne 0 }).Count
        # min(Queue, 5), in EVERY arm. An earlier version expected the ring to sit at
        # SC_PRODQ_ENGINE_HOLD (4) whenever the plugin was holding anything, and the run
        # said 5 -- the plugin was right and the expectation was wrong. HoldRoom() measures
        # room against the engine's FIVE, not against the hold: once the plugin stops taking
        # items back the ring fills to five and STAYS there, and leaving it full IS the cap
        # (sc_prodqueue.cpp, "Leaving the ring full IS the cap"). Measured: 8 clicks ->
        # engine=[0x040 x5], overflow=3, logical=8, minerals 3000-8*50=2600.
        $wantRing = [math]::Min($Queue, $ENGINE_SLOTS)
        Assert-That "$Arm`: the engine's ring holds $wantRing item(s) after $Queue click(s) ($qLen)" `
            ($qLen -eq $wantRing) `
            "(engine=[$(($q.Engine | ForEach-Object { '0x{0:X3}' -f $_ }) -join ',')])"
        $before = Get-Snapshot "$Arm-save"
        Show-Snapshot 'before save' $before
        Shot "$Arm-before-save"
        $file = Save-ScGame -Hwnd $hwnd -Name $SaveName

        # ---------------------------------------------------------------------
        # THE LOAD WITNESS. Without it this whole suite is un-failable.
        #
        # Every assertion below compares the world at the save with the world after the
        # load and passes when they MATCH -- and a load that never happened produces
        # exactly that match, because the game simply carried on with the state it
        # already had. Task 051's first control run passed all nine of them without any
        # evidence a load occurred at all, on the same run that proved a posted click on
        # this engine's default dialog button does nothing.
        #
        # So: change the world AFTER the save, in a way the saved file cannot contain,
        # and require the load to undo it. One Train click at the SECOND Nexus -- a
        # building this suite never measures and which the save recorded with an EMPTY
        # ring. The mutation is asserted POSITIVE first (its ring really did go to 1),
        # because a witness that never landed would make the after-check pass for the
        # wrong reason (AGENTS.md § "Absence assertions must first be proved positive").
        # ---------------------------------------------------------------------
        Select-Nexus -Hwnd $hwnd -Tag "$Arm-witness" -Which 1 | Out-Null
        $wq = Add-ToQueue -Hwnd $hwnd -Count 1 -Tag "$Arm-witness"
        $wBefore = Get-Statq "$Arm-witness-set"
        $wLenBefore = @($wBefore.Engine | Where-Object { $_ -ne $QUEUE_EMPTY -and $_ -ne 0 }).Count
        Assert-That "$Arm witness: the second Nexus now holds 1 queued item the save does NOT contain" `
            ($wLenBefore -eq 1) "(engine=[$(($wBefore.Engine | ForEach-Object { '0x{0:X3}' -f $_ }) -join ',')], clicks accepted=$wq)"

        Load-ScGame -Hwnd $hwnd -File $file
        Shot "$Arm-after-load"

        Select-Nexus -Hwnd $hwnd -Tag "$Arm-witness-after" -Which 1 | Out-Null
        $wAfter = Get-Statq "$Arm-witness-check"
        $wLenAfter = @($wAfter.Engine | Where-Object { $_ -ne $QUEUE_EMPTY -and $_ -ne 0 }).Count
        $loadHappened = ($wLenBefore -eq 1 -and $wLenAfter -eq 0)
        Assert-That "$Arm witness: THE LOAD REALLY REPLACED THE WORLD (witness ring $wLenBefore -> $wLenAfter)" `
            $loadHappened `
            "(engine=[$(($wAfter.Engine | ForEach-Object { '0x{0:X3}' -f $_ }) -join ',')]) -- if this is 1, no load occurred and every verdict below is vacuous"
        if (-not $loadHappened) {
            Write-Host "  INCONCLUSIVE  $Arm`: the witness says no load took place. The comparison below"
            Write-Host '            compares a running game with itself and means NOTHING either way.'
            $script:inconclusive++
        }

        Select-Nexus -Hwnd $hwnd -Tag "$Arm-after" | Out-Null
        $after = Get-Snapshot "$Arm-load"
        Compare-RoundTrip -Arm $Arm -Before $before -After $after -OverflowAtSave ([math]::Max($before.Overflow, 0))
        Save-Snapshot $Arm $before
        Save-Snapshot "$Arm-after" $after
        $script:episodes++
        [pscustomobject]@{ Before = $before; After = $after; File = $file }
    }

    if ($Phase -eq 'control') {
        Step "ARM 1 (positive control): no plugin, $OrdinaryQueue queued, save -> load" {
            $r = Invoke-RoundTrip -Arm 'arm1-control' -Queue $OrdinaryQueue -SaveName 'slctl'
            # This save is what arm 5 loads under fanout, in a later phase.
            Copy-Item -LiteralPath $r.File.FullName -Destination (Join-Path $StateDir 'arm5-source.snx') -Force
            Write-Host "       kept a copy for arm 5: $(Join-Path $StateDir 'arm5-source.snx')"
        }
    }
    elseif ($Phase -eq 'fanout') {
        Step "ARM 2: fanout, ordinary queue ($OrdinaryQueue, nothing above the cap), save -> load" {
            Invoke-RoundTrip -Arm 'arm2-fanout-ordinary' -Queue $OrdinaryQueue -SaveName 'slfour' | Out-Null
        }
        Step "ARM 3 (the seam): fanout, $QueueMax queued -- $ENGINE_HOLD in the ring, $($QueueMax - $ENGINE_HOLD) held by the plugin" {
            $r = Invoke-RoundTrip -Arm 'arm3-fanout-overcap' -Queue $QueueMax -SaveName 'slcap'
            Copy-Item -LiteralPath $r.File.FullName -Destination (Join-Path $StateDir 'arm4-source.snx') -Force
            Write-Host "       kept a copy for arm 4: $(Join-Path $StateDir 'arm4-source.snx')"
        }
        Step 'ARM 5 + ARM 6: load the save the NO-PLUGIN arm wrote, under fanout' {
            $src = Join-Path $StateDir 'arm5-source.snx'
            if (-not (Test-Path -LiteralPath $src)) {
                Write-Host '  SKIP arm 5/6: no control save on disk -- run -Phase control first.'
                Write-Host '       NOT RUN is not a pass.'
            }
            else {
                $dest = Join-Path $saveRoot 'asdf\slctl.snx'
                New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
                Copy-Item -LiteralPath $src -Destination $dest -Force
                Load-ScGame -Hwnd $hwnd -File (Get-Item -LiteralPath $dest)
                Select-Nexus -Hwnd $hwnd -Tag 'arm5' | Out-Null
                $after = Get-Snapshot 'arm5-load'
                $before = Read-Snapshot 'arm1-control'
                if (-not $before) {
                    Write-Host '  SKIP arm 5: the control phase left no snapshot to compare against.'
                }
                else {
                    Compare-RoundTrip -Arm 'arm5-vanilla-save-fanout-load' -Before $before -After $after `
                        -OverflowAtSave 0
                    $script:episodes++
                }
                # ARM 6 -- the phantom-promotion check, and it is only meaningful HERE:
                # this game was loaded into a process whose plugin still holds g_rec[]
                # records from arms 2 and 3, keyed by addresses in the STATIC unit table
                # the load has just refilled. If a stale record still matches, the plugin
                # promotes items into a building that never queued them.
                Assert-That ("arm6: the loaded vanilla game's ring holds ONLY what the vanilla save had " +
                             "($($after.EngineLen) occupied)") `
                    ($null -ne $before -and $after.EngineLen -le $before.EngineLen) `
                    "(save=[$(($before.Engine | ForEach-Object { '0x{0:X3}' -f $_ }) -join ',')] load=[$(($after.Engine | ForEach-Object { '0x{0:X3}' -f $_ }) -join ',')])"
                # THE HALF THE RING CANNOT SHOW, and the one that matters. The ring being
                # right proves only that the ENGINE restored its own array. The plugin's
                # table is not in the save file and is not reset by a load, so it can walk
                # into the loaded game still holding items queued in a DIFFERENT one --
                # bound to a CUnit address the static unit table has just refilled. Those
                # items were paid for in the other game, and the moment a ring slot frees
                # here the plugin promotes one into a building that never queued it.
                #
                # Measured on the first run of this arm: `overflow=3 logical=7` against
                # unit=0x00623E58 in a game whose own save contained a queue of four and no
                # overflow at all.
                Assert-That ("arm6: the plugin holds NOTHING for a game it never queued in " +
                             "(overflow=$($after.Overflow), tracked buildings=$($after.Buildings))") `
                    ($after.Overflow -eq 0) `
                    '-- items held from an earlier game survive the load and will be promoted into this one'
                Write-Host "       plugin books after the cross-load: $($after.ProdqLine)"
                $script:episodes++
            }
        }
    }
    else {
        Step 'ARM 4: load the save the FANOUT arm wrote, with no plugin' {
            $src = Join-Path $StateDir 'arm4-source.snx'
            if (-not (Test-Path -LiteralPath $src)) {
                Write-Host '  SKIP arm 4: no fanout save on disk -- run -Phase fanout first.'
                Write-Host '       NOT RUN is not a pass.'
            }
            else {
                $dest = Join-Path $saveRoot 'asdf\slcap.snx'
                New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
                Copy-Item -LiteralPath $src -Destination $dest -Force
                Load-ScGame -Hwnd $hwnd -File (Get-Item -LiteralPath $dest)
                Select-Nexus -Hwnd $hwnd -Tag 'arm4' | Out-Null
                $after = Get-Snapshot 'arm4-load'
                $before = Read-Snapshot 'arm3-fanout-overcap'
                if (-not $before) {
                    Write-Host '  SKIP arm 4: the fanout phase left no snapshot to compare against.'
                }
                else {
                    Compare-RoundTrip -Arm 'arm4-fanout-save-vanilla-load' -Before $before -After $after `
                        -OverflowAtSave ([math]::Max($before.Overflow, 0))
                    $script:episodes++
                }
            }
        }
    }
}
catch {
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"; $failures++ }
        Start-Sleep -Seconds 2
    }
    # The fixture is left in place for the phases that follow; only the LAST phase
    # removes it. Deleting it earlier would leave the saves pointing at a map that is
    # no longer there.
    if ($Phase -eq 'crossload') {
        try { Remove-ScOwnFixture -Run $fixtures; Remove-ScOwnFixtureDir -Dir $mapDir }
        catch { Write-Host "       (fixture cleanup: $($_.Exception.Message))" }
    }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)

# AGENTS.md § task 041: a verdict that does not depend on reaching the end of the work is
# not a verdict. If no arm ran to a comparison, this run says INCOMPLETE -- its own word,
# never PASS -- however few assertions happened to fail.
Write-Host ''
if ($episodes -eq 0) {
    Write-Host "test-save-load [$Phase]: INCOMPLETE -- 0 arms reached a verdict, $failures failure(s)."
    Write-Host "frames (diagnostic, NOT committable): $ShotDir"
    exit 1
}
if ($inconclusive -gt 0) {
    Write-Host "test-save-load [$Phase]: $inconclusive arm(s) INCONCLUSIVE -- a unit completed inside"
    Write-Host '            their measurement window. Those arms say nothing about save/load either way.'
}
Write-Host "test-save-load [$Phase]: $failures failure(s) across $episodes arm(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
