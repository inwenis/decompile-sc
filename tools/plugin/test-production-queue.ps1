#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that a production building can hold MORE THAN FIVE queued
items AND that CANCELLING one gives back exactly its cost -- both for an item the engine
is holding and for an item the PLUGIN is holding -- with every number read out of the
building's own memory, not off the screen.

Task 025, from the user's words: "enable queuing more then 5 units."
Task 028, from the user's words: "why is there no test that cancels a unit?"

.DESCRIPTION
The engine's queue is `u16 buildQueue[5]` at `CUnit+0x98`, a five-slot ring whose head is
the byte at `+0xA4`, and the 5 is a literal in six functions
(research/production-queue.md 2-3). The plugin does not widen it. It keeps the ring one
item BELOW the engine's five and holds the rest itself, because the CLIENT stops sending
Train commands once the ring holds five -- the first run of this very suite measured that:
five `CMD id=0x1F` at the press cadence and then silence for seven more presses, with the
Train button drawn dark. The engine accepts and pays for every item; the plugin only ever
moves items in and out of the ring, which costs nothing (production-queue.md 4.2, 5.2).

So there are three claims to make in a live game, and this suite makes all three from
memory reads:

  1. MORE THAN FIVE ARE QUEUED. The `PRODQSEL` oracle prints the five slots of
     `CUnit+0x98` verbatim beside what the plugin holds, so `logical=9` is `engineLen=5`
     (read from the building) plus `overflow=4` (read from the plugin). Nothing here comes
     from the status area, which draws at most five icons whatever the truth is.
  2. THEY BUILD, IN ORDER, ONE PER FREED SLOT. Every promotion logs a `PRODQEV promote`
     line naming the type, the slot it went into and how many are left; the run asserts
     one per held item, with the count walking down to zero, and then asserts the
     resulting units exist in the engine's own unit list.
  3. EACH IS PAID FOR ONCE, BY THE ENGINE. Minerals are asserted to an exact figure after
     the burst and asserted UNCHANGED thereafter -- neither holding an item back nor
     handing it over moves money, so a second payment would show up as a drop while the
     queue drains. (The plugin's own `mineralsSpent` counter used to be asserted zero
     beside that; it was deleted in task 055 -- issue #66 -- because nothing incremented
     it. The engine's own balance, above, is the oracle and always was.)

TASK 028 ADDS THE OTHER DIRECTION: CANCELLING, IN A REAL GAME, BOTH WAYS

Nothing had ever clicked cancel in a running game -- task 025 proved the cancel path
offline only, which AGENTS.md's own rule ("a player-input feature is unproven until the
wire has been watched") says is not proof. There are two cases and they take different
code, so this suite drives both, with the CONTROL LOCATED BY READING THE DIALOG THAT
OWNS IT (research/production-queue.md 8):

  4. AN ITEM THE PLUGIN HOLDS. The card's slot-9 Cancel button sends {0x20, 0xFE},
     "cancel the LAST queued item" -- which, while the plugin holds the tail of the
     logical queue, is the plugin's item and not the engine's. The suite reads the card,
     asserts slot 9 really carries that button (action 0x00423490, actionParam 254) and
     is not greyed, clicks the centre computed from the live control rect, and then
     requires: one `CMD id=0x20` with payload 0xFE on the wire, the plugin's own
     `cancel-last` event, the LOGICAL queue one shorter, minerals up by exactly one
     unit's cost, and the plugin's refund counter up by exactly that -- ONCE.
  5. AN ITEM THE ENGINE'S RING HOLDS. That is a different control: the five icons of the
     PRODUCTION QUEUE STRIP in the status pane (statdata dialog, control ids 2..6). A
     click on icon k sends {0x20, k} and the engine's own cancelBuildQueueSlot refunds
     it. The suite reads the strip, clicks the icon for display index 1, and requires the
     engine's ring to be one shorter with minerals up by one unit's cost -- and the
     PLUGIN to have done nothing at all (its `cancelled` counter stays where it was).
  6. THE TOTALS RECONCILE, from memory: spent = built + queued + cancelled, at every
     point where all four are known, so a double refund or a lost item cannot hide
     inside a number that merely looks plausible.

WHY THE FIXTURE IS A NEXUS, AND WHAT THE FIRST RUN CORRECTED ABOUT THAT

The fixture is a Protoss Nexus because slot 9 of its buttonset carries the Cancel button
with nothing ahead of it, while every Terran producer's slot 9 is SHARED with Land and
Lift Off -- and a card control takes the first button whose condition survives, slots
never shifting. Reading the button table alone, that looked like it made the Cancel button
unreachable on a Command Center, which is why this suite trains Probes rather than SCVs.

THE FIRST RUN SHOWED THAT WAS WRONG, which is exactly what reading a dialog instead of
reasoning about a table is for. Lift Off's condition (0x004287D0) requires the "is this
building busy" helper 0x00401500 to return 0, and that helper returns 1 precisely when the
head slot holds a real unit type -- the same thing the Cancel button's own condition tests.
The two are complementary: the control shows Lift Off while the queue is empty and Cancel
the moment anything is queued. The suite now asserts that pair in game on the Command
Center it also places, and the Nexus stays as the fixture because the arms are written for
it and it is proved (research/production-queue.md 8.3).

WHY THE RESULT CANNOT BE FAKED

  * The queue length is read from `CUnit+0x98` on the game's side of the wire. The plugin
    cannot make `engineLen` read 5 without five real entries being there.
  * The positive/negative pair is inside one run and one oracle. Before the clicks,
    `PRODQ ... buildings=0 captured=0` -- the same line that later reads `captured=4`. An
    oracle that could not fail would print the second without the first.
  * THE COUNT OF COMMANDS ON THE WIRE IS THE HEADLINE MEASUREMENT. Vanilla sends five and
    stops; this run presses 12 times and asserts EXACTLY 9 went out, which is the cap
    itself, moved, measured on the engine's own command funnel rather than inferred.
  * The cap is exercised on purpose (`-QueueMax` below `-Clicks`), so "it queues without
    limit" and "it queues what it was configured to" are distinguishable.
  * The map has no hostiles, one unit-less computer slot, and its only trigger sets
    resources once -- so nothing but this test can move a mineral.

THE FIXTURE needs something no earlier one did: STARTING RESOURCES. A CHK has no such
field and Use Map Settings hands out none, so task 025 added `--starting-minerals` /
`--starting-gas` to tools/make_test_map.py -- one `Always -> Set Resources` trigger, and
the generator's own validation proves from the bytes that the trigger carries no
game-ending action.

MEASUREMENT WINDOWS. A cancel is measured across a window in which a queued unit may
also FINISH, and a finished unit shortens the queue by one without moving a single
mineral. That confound is not tolerated and not merely hoped against: every cancel arm
counts the units that exist before and after, and asserts the queue dropped by
`1 + completions` while minerals rose by exactly one unit's cost. So a completion inside
the window changes what the assertion expects instead of quietly passing or failing it.

.EXAMPLE
./tools/plugin/test-production-queue.ps1

.EXAMPLE
./tools/plugin/test-production-queue.ps1 -Clicks 12 -QueueMax 9 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\025\production-queue.log',
    [string]$ShotDir = 'C:\sc-work\logs\025\production-frames',
    [string]$FixtureDir,
    # How many times the Train button is clicked. Deliberately MORE than -QueueMax, so the
    # cap refusal is exercised rather than assumed absent.
    [int]$Clicks = 12,
    # The plugin's total logical queue length, the engine's five included. 9 = 5 engine +
    # 4 plugin, which is both comfortably over the vanilla cap and inside the 18 psi two
    # Nexuses provide -- so the fixture needs no Pylon to be placeable for the run to mean
    # anything.
    [int]$QueueMax = 9,
    # The ENGINE-ring cancel arm's queue: small enough that the plugin holds NOTHING
    # (below SC_PRODQ_ENGINE_HOLD), which is what makes that arm the engine's own path
    # with the plugin passing the command straight through.
    [int]$EngineArmQueue = 3,
    # Which queue icon that arm clicks. 1, not 0: display 0 is the item already BUILDING,
    # whose refund the engine takes down a different branch (0x00468280 rather than
    # refundByType). Both refund the same cost; this arm is about a queued item.
    [int]$EngineArmDisplay = 1,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 1000,
    # THE FIXTURE SPEED-UP (task 031). The map's own UNIx section overrides the Probe's
    # build time for THIS MAP only; vanilla is 20 game seconds, and the Probes building one
    # after another were measured as the single largest term in this suite's wall clock.
    # 0 restores the vanilla fixture exactly -- the flag is not passed at all, and the map
    # the generator writes is byte-for-byte the pre-031 one.
    #
    # WHY IT DOES NOT WEAKEN THE TEST. Every claim this suite makes is about the QUEUE: how
    # many items are in the ring, how many the plugin holds, that each is promoted into a
    # freed slot in order, what a cancel refunds, and that each item is paid for exactly
    # once. Build time is how long the engine takes between one item finishing and the next
    # starting -- the setup this suite waits through, not anything it asserts on.
    #
    # WHAT IT CAN BREAK, and why this number is what it is. TWO windows constrain it, both
    # measured on this suite rather than reasoned about, and a game second is ~0.7 real
    # seconds (measured: tools/plugin/probe-unit-settings.ps1 trains one at build time 1 and
    # it exists 0.7s later).
    #
    #  1. THE BURST. Exactly $QueueMax of the $Clicks clicks may reach the wire, and that
    #     holds only while NO SLOT FREES while they are going out: a Probe completing
    #     mid-burst drops the ring to 4, the plugin promotes into it, the logical queue
    #     falls below the cap and the client sends a TENTH command. Measured on the SCV
    #     version of this suite before task 028 turned it Protoss: at 1 game second ALL
    #     TWELVE clicks reached the wire and the suite reported 21 failures. The burst is
    #     ~2s, so this is the easy constraint.
    #  2. THE PLUGIN-CANCEL ARM, which is the tight one. It asserts the plugin ends up
    #     having captured one MORE item than the burst left it, because the cancel frees
    #     room under the cap and the next rebalance takes one more out of the ring. That is
    #     only true if the ring is still FULL when the cancel lands -- if a Probe has
    #     already completed, the ring is at 4 already and there is nothing extra to take.
    #     The cancel lands about 6s after the first click, so the first completion has to be
    #     later than that. At 8 game seconds (~5.6s) it is not, and the run failed exactly
    #     there: `and it captured one more than the burst left it, because the cancel made
    #     room (4)`.
    #
    # 12 game seconds is ~8.4s, which clears the 6s cancel window with room, and still cuts
    # the drain from ~125s to ~76s. Anything much lower re-opens (2); 0 restores vanilla.
    #
    # Neither margin is left to this comment. The burst step ASSERTS its invariant
    # (`promoted` still 0), and Get-TraineeCount below now counts only COMPLETED units, so
    # the cancel arms' own arithmetic stops mistaking a build that has STARTED for one that
    # has finished -- which is what made the 8-second run fail its first assertion too.
    [int]$ProbeBuildSeconds = 12,
    # Long enough for nine Probes, from the first click to the last unit existing. One
    # Probe is 20 game seconds; a single-player custom game runs at Fastest, so ~9-13 real
    # seconds each, and the measured rate is ~16s per unit including the marker round
    # trip. 300s leaves room, and the drain loop exits as soon as the LOGICAL queue is
    # empty.
    [int]$DrainTimeoutSec = 300,
    # THE RATE ARM for the open defect in research/production-queue.md 8.6, off by default
    # because it is a MEASUREMENT and it perturbs every count after it (task 061).
    #
    # The click that cannot cancel the last queue slot is a RACE, and nothing in this
    # project has ever measured its rate -- four runs across two builds flipped the outcome
    # in both directions, so every "it works" and "it does not" on record, including this
    # suite's own, is a single coin flip. This clicks the same slot N times at each of
    # several BUTTON HOLD DURATIONS and reports the cancel rate for each.
    #
    # Duration is the variable because it is the one that separates the user from the
    # harness. Every automated click this project makes is 60ms; a human pressing a slot
    # they mean to cancel holds it longer, and the longer the hold the more of the engine's
    # disable events land inside it. If the rate falls off a cliff above 60ms, that is the
    # difference between "the user says it never works" and "our runs say it sometimes
    # does" -- and it is a real target for the fix instead of a coin.
    [int]$HoldSweepClicks = 0,
    [string]$HoldSweepMs = '40,60,80,120,200',
    # Task 071: run the SAME suite on the widescreen build. '1' + stage 3 is the
    # input-widened build (mouse clicks reach x=640..799). Every click in this
    # suite is computed from live control rects (Get-ScCardSlotPoint and
    # friends), so it exercises the console at its stock 640 position through the
    # widescreen presentation. Defaults unchanged: the stock run this suite has
    # always been is byte-for-byte the same.
    [ValidateSet('0', '1')][string]$Widescreen = '0',
    [ValidateSet('0', '1', '2', '3')][string]$WidescreenStage = '3',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
$step = 0
# How many items this run has cancelled so far. Every later expectation is written
# against it rather than against a literal, so the two cancel arms cannot drift out of
# step with the counts the drain and the reconciliation expect.
$script:cancels = 0
# ... and how many of those the PLUGIN served (as opposed to the engine). Only the
# plugin's own refund shows up in its stats line.
$script:pluginCancels = 0
# ... and how many of them were made while the engine's ring was still ABOVE the plugin's
# hold, which is the only condition under which a cancel makes the plugin capture one more
# item. Counted from each cancel's own before-reading rather than assumed, because it is
# NOT a property of cancelling -- see the drain step's `captured` assertion (task 061).
$script:capturesFromCancel = 0
# How many Train commands the ENGINE has accepted so far, counted on its own command
# funnel. Every one of them was paid for there, so this is the run's ledger: see
# Assert-Reconciles for why it is counted here and not derived from the unit list.
$script:accepted = 0

# Pinned constants, asserted rather than reported.
$NEXUS_TYPE = 154         # units.dat 154, richchk UnitId 'Protoss Nexus'
$CC_TYPE    = 106         # units.dat 106, richchk UnitId 'Terran Command Center'
$PROBE_TYPE = 64          # units.dat 64,  richchk UnitId 'Protoss Probe'
# CUnit+0xDC bit 0x01. A unit being trained is already in the player's unit list with this
# CLEAR; it is set when the unit is actually there. See Get-TraineeCount below and
# tools/plugin/src/sc_addresses.h for the observation this comes from.
$SC_UNIT_FLAG_COMPLETED = 0x01
$PROBE_COST = 50          # minerals; asserted against the run's own arithmetic below
$TRAIN_CMD  = '0x1F'      # research/data/command-opcodes.tsv
$CANCEL_CMD = '0x20'      # same table: Cancel Train
$ENGINE_SLOTS = 5         # research/production-queue.md 2.3

# The card's Train button, read out of buttonset 154 in the file image
# (work/scratch/028/peek.py): slot 1, condition 0x00428E60, action 0x004234B0, and
# actionParam = the unit type it trains. The suite CLICKS this button at the centre
# computed from the live control rect rather than pressing a guessed hotkey letter.
$TRAIN_ACT   = '004234B0'   # as the card read-back reports it: uppercase hex, no 0x
$TRAIN_SLOT  = 1
# The card's Cancel button: slot 9, condition 0x00428530 ("the head slot holds a real
# type"), action 0x00423490, actionParam 0xFE -- "cancel the LAST queued item", the one
# wire form the plugin can be asked to serve for an item it is holding.
$CANCEL_ACT    = '00423490'
$CANCEL_SLOT   = 9
# The button that SHARES slot 9 with Cancel on every Terran producer: Lift Off (record
# 0x00517FC4, condition 0x004287D0, action 0x00423230). The two conditions are
# complementary -- Lift Off's requires the building NOT to be busy producing, Cancel's
# requires it to have something at the head of its ring -- so the control swaps between
# them, which the Command Center arm reads in both states.
$LIFTOFF_ACT   = '00423230'
$CANCEL_APARAM = 254
# The status pane's queue strip: five controls, ids 2..6, one per display index, and a
# click on display k emits {0x20, k} (research/production-queue.md 8.1).
$STATQ_FIRST_CONTROL = 2
$STATQ_SLOTS         = 5
# The last icon of that strip -- display 4, control id 6. It is the one the plugin fills
# from its own overflow AND the one it anchors the "+N" text to, so it is the only slot
# where a click has to pass through pixels this repo drew (task 061).
$STATQ_LAST_DISPLAY  = $STATQ_SLOTS - 1
# ScQueueIndMode: 1 = SC_QIND_STRIP, the one-building "+N" (sc_queueind.h).
$QIND_MODE_STRIP     = 1

$ENGINE_HOLD = 4          # SC_PRODQ_ENGINE_HOLD -- what the plugin leaves the ring at
# At the cap the plugin stops taking items back, so the ring is left FULL and the client
# refuses the rest on its own. Hence: the logical queue is the engine's five plus what the
# plugin holds, and the presses past the cap never reach the wire at all.
$expectOverflow  = $QueueMax - $ENGINE_SLOTS
$expectNotSent   = $Clicks - $QueueMax
if ($expectOverflow -lt 1) { throw "test: -QueueMax must exceed the engine's $ENGINE_SLOTS slots." }
if ($expectNotSent -lt 1) { throw 'test: -Clicks must exceed -QueueMax, or the cap is never exercised.' }

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t028' -Suite 'production-queue' }
$mapDir = $FixtureDir
$mapName = 'production-queue.scx'
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

# A SKIPPED CHECK IS NOT A PASSED CHECK, and this suite had no way to say so, so an arm
# that could not be measured recorded itself as `Assert-That '...' $true` -- a check that
# cannot fail, padding the ok count with a non-event (task 052 section 6.5, task 055).
# `ci-local`'s own step accounting has said this since task 023; the suites had not caught up.
$script:skipped = @()
function Skip-That {
    param([Parameter(Mandatory)][string]$What, [string]$Detail = '')
    Write-Host "  skip $What $Detail"
    $script:skipped += "$What $Detail"
}

# PER ITEM, on the engine's side. `engineLen=5` is a count and a count can be produced by
# the wrong five things; this names every slot and says which one is wrong.
function Assert-EverySlot {
    param($Selected, [int]$WantType)
    $bad = @()
    for ($i = 0; $i -lt $Selected.Engine.Count; $i++) {
        if ($Selected.Engine[$i] -ne $WantType) { $bad += ("slot{0}=0x{1:x}" -f $i, $Selected.Engine[$i]) }
    }
    Assert-That ("all {0} slots of CUnit+0x98 hold unit type 0x{1:x}" -f $Selected.Engine.Count, $WantType) `
        ($Selected.Engine.Count -eq $ENGINE_SLOTS -and $bad.Count -eq 0) `
        ($bad.Count -gt 0 ? "(wrong: $($bad -join ' '))" : "(only $($Selected.Engine.Count) slots parsed)")
}

function Step {
    param([string]$Name, [scriptblock]$Body, [switch]$SweepPerturbed)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    # A MEASUREMENT RUN ENDS AT THE MEASUREMENT (task 066). The hold sweep clicks the
    # last slot ~30 times and tops the queue back up between clicks, which consumes the
    # preconditions of every drain-and-after step: measured on the first post-fix sweep
    # run, 11 tail assertions failed on counts the sweep had legitimately moved while
    # every fix arm and the table itself were green. Steps that depend on the unperturbed
    # click/cancel ledger are tagged and SKIPPED -- loudly, with their own word, never a
    # silent pass (AGENTS.md task 041) -- and the full-suite verdict on them comes from
    # runs without -HoldSweepClicks, which is every regression run.
    if ($SweepPerturbed -and $HoldSweepClicks -gt 0) {
        Write-Host '       SKIPPED (measurement run): the hold sweep consumed this step''s preconditions.'
        Write-Host '       Its verdict comes from runs without -HoldSweepClicks.'
        return
    }
    & $Body
}

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-World { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScWorldState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }

# The two dialog read-backs, on the same marker channel. Neither clicks anything and
# neither needs a hook: they walk the card (0x0068C148) and the status pane (0x0068C1F0)
# and report what each control holds -- which is the only way this repo is allowed to
# claim anything about a dialog (AGENTS.md, "read a dialog's CONTENT from memory").
function Get-Card { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScCardState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }
function Get-StatusQueue { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScStatusQueue -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }

# Task 033's indicator, read back OUT OF THE LIVE DIALOG on the same marker channel: is
# its control linked into the status pane's child chain, has the engine's own visible bit
# been set on it, and what string does its pszText pointer actually hold.
#
# THE PIXEL FIELDS, and what each can and cannot say (task 039):
#   ink      non-background bytes inside the indicator's own rect. For the GROUP line, whose
#            band belongs to no control, this is a real "was anything drawn". For the STRIP
#            "+N", whose box sits INSIDE a queue icon, it is not: the icon's own pixels are
#            in that box, so it reads > 0 whether or not our text landed. It passed for a
#            whole task while the icon underneath was drawing the wrong art.
#   refInk   the same count over a control the ENGINE fills, so `ink=0` cannot be confused
#            with a blind probe. refId says which control it used -- the first queue icon
#            normally, the first wireframe button when the strip is hidden by a group. It is
#            -1 when NEITHER is visible, which is a real state (a single building with an
#            empty queue has no queue icons up and no wireframe row), and it stays -1 rather
#            than falling back to a hidden control: ink over something nobody can see answers
#            neither question this number is for.
#   surfInk  the same count over the WHOLE dialog surface. This is the blindness check that
#            has an answer in every state, drained pane included -- the pane's own art covers
#            that surface, so a live one is never 0.
#   boxDiff  bytes inside the indicator's own box that differ from a copy of that same box
#            taken by the game thread while the indicator was HIDDEN. THIS is the oracle for
#            "did our line land", and `ink` is not: measured in this task's first live run,
#            ink read 448 of 448 bytes inside the box and refInk 1330 of 1330 over a queue
#            icon, before anything of ours had been drawn. -1 means there is no baseline for
#            this rect yet (it moved, or the indicator has not been hidden in this dialog),
#            which is an honest "no answer" and never a 0.
#   slotDiff bytes that differ between queue slot 0 and slot 4 on the dialog's own surface,
#            below the rows their labels occupy. Same rect size, same border graphic, same
#            queued type, so this is the honest screen-level check on the fifth icon: a
#            wrong GRP shows up as hundreds, our "+N" on top as tens, our text painted
#            under the icon as zero.
#   fontH    the height of the small font, from the font's own header -- the number the
#            engine's string draw refuses a box shorter than.
# Each icon entry is `icon:mode:state:art:label`, where art is I (the icon GRP an occupied
# slot must draw from), B (the empty-slot placeholder art) or ?.
$script:qindSeq = 0
function ConvertFrom-QIndLine {
    param($Hit)
    # PARSED BY NAME, NOT BY POSITION. This line gained two fields in one task (boxDiff, then
    # surfInk) and a positional parse shifts EVERY group after the insertion point without
    # failing: `bldgs` then reads out of `queued`, and an assertion passes or fails on a number
    # nobody wrote. Named groups cannot shift, and an added field costs one line here.
    $m = [regex]::Match($Hit.Line,
                'QIND \[[^\]]+\] mode=(?<mode>\d+) linked=(?<linked>\d+) visible=(?<visible>\d+) ' +
                'text="(?<text>[^"]*)" ' +
                'bounds=\((?<left>-?\d+),(?<top>-?\d+),(?<right>-?\d+),(?<bottom>-?\d+)\) ' +
                'ink=(?<ink>-?\d+) refInk=(?<refInk>-?\d+) refId=(?<refId>-?\d+) ' +
                'surfInk=(?<surfInk>-?\d+) slotDiff=(?<slotDiff>-?\d+) boxDiff=(?<boxDiff>-?\d+) ' +
                'fontH=(?<fontH>\d+) ' +
                'icons=\[(?<icons>[^\]]*)\] ' +
                'sel=(?<sel>\d+) engineLen=(?<engineLen>\d+) overflow=(?<overflow>\d+) ' +
                'upg=(?<upg>\d+) bldgs=(?<bldgs>\d+) queued=(?<queued>\d+)')
    # Parsed SEPARATELY, and deliberately not folded into the big pattern above: these two
    # were added after it and a field a caller does not read must never be able to make the
    # whole line unparseable. `owned` is how many icons the plugin is holding an item behind
    # right now; `pressKept` is the running count of presses carried across the engine's own
    # disable event on one of them (task 061). -1 means the field was not on the line, which
    # is a different fact from 0 and has to stay different -- an arm that requires the count
    # to MOVE would otherwise read a missing field as "the fix did nothing".
    $extra = [regex]::Match($Hit.Line,
        'owned=(?<owned>-?\d+) disableOnOwned=(?<disOwned>\d+) disableWithPress=(?<disPressed>\d+) pressKept=(?<pressKept>\d+)')
    # Task 066's fields, separate for the same reason: `phantom` counts ring slots made
    # visible to queueLayout by the bracket (the fix's own activity), `ringStable` says the
    # observer's ring reads settled against the bracket's seqlock.
    $extra66 = [regex]::Match($Hit.Line,
        'phantom=(?<phantom>\d+) phantomDirty=(?<phantomDirty>\d+) ringGen=(?<ringGen>\d+) ringStable=(?<ringStable>\d+)')
    if (-not $m.Success) { throw "test: unparseable QIND line: $($Hit.Line)" }
    return [pscustomobject]@{
        Mode = [int]$m.Groups['mode'].Value; Linked = $m.Groups['linked'].Value -eq '1'
        Visible = $m.Groups['visible'].Value -eq '1'; Text = $m.Groups['text'].Value
        Left = [int]$m.Groups['left'].Value; Top = [int]$m.Groups['top'].Value
        Right = [int]$m.Groups['right'].Value; Bottom = [int]$m.Groups['bottom'].Value
        Ink = [int]$m.Groups['ink'].Value; RefInk = [int]$m.Groups['refInk'].Value
        RefId = [int]$m.Groups['refId'].Value; SurfInk = [int]$m.Groups['surfInk'].Value
        SlotDiff = [int]$m.Groups['slotDiff'].Value; BoxDiff = [int]$m.Groups['boxDiff'].Value
        FontH = [int]$m.Groups['fontH'].Value
        Icons = @($m.Groups['icons'].Value -split ',' | Where-Object { $_ } | ForEach-Object {
            $p = $_ -split ':'
            [pscustomobject]@{ Icon = [Convert]::ToInt32(($p[0] -replace '^0x'), 16)
                               Mode = [int]$p[1]; State = $p[2]
                               Art = $p[3]; Label = ($p[4] -eq '1') } })
        Sel = [int]$m.Groups['sel'].Value; EngineLen = [int]$m.Groups['engineLen'].Value
        Overflow = [int]$m.Groups['overflow'].Value; Upg = [int]$m.Groups['upg'].Value
        Buildings = [int]$m.Groups['bldgs'].Value; Queued = [int]$m.Groups['queued'].Value
        Owned = ($extra.Success ? [int]$extra.Groups['owned'].Value : -1)
        DisableOnOwned = ($extra.Success ? [int]$extra.Groups['disOwned'].Value : -1)
        DisableWithPress = ($extra.Success ? [int]$extra.Groups['disPressed'].Value : -1)
        PressKept = ($extra.Success ? [int]$extra.Groups['pressKept'].Value : -1)
        Phantom = ($extra66.Success ? [int]$extra66.Groups['phantom'].Value : -1)
        PhantomDirty = ($extra66.Success ? [int]$extra66.Groups['phantomDirty'].Value : -1)
        RingGen = ($extra66.Success ? [int]$extra66.Groups['ringGen'].Value : -1)
        RingStable = ($extra66.Success ? [int]$extra66.Groups['ringStable'].Value : -1)
        Line = $Hit.Line
    }
}

# Reads the indicator line the observer already wrote for SOMEBODY ELSE'S marker, taking
# the newest one past $FromLine. This exists so an assertion can be added to this suite
# without adding a marker round trip: two of the arms below are TIMING-SENSITIVE (the
# plugin-cancel arm asserts the ring is still full when the cancel lands, which is only
# true before the first Probe completes), and a spare second between the burst and the
# cancel is enough to break them. The freshness gate is $FromLine plus the state
# assertions the caller makes on the numbers in the line.
function Get-QIndAfter {
    param([int]$FromLine, [int]$TimeoutSec = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $hit = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                 Select-Object -Skip $FromLine | Select-String -Pattern 'QIND \[') |
               Select-Object -Last 1
        if ($hit) { return ConvertFrom-QIndLine $hit }
        Start-Sleep -Milliseconds 250
    }
    throw "test: no QIND line after line $FromLine within ${TimeoutSec}s (log: $LogPath)."
}

function Get-QInd {
    param([string]$Tag, [int]$TimeoutSec = 20)
    # A line whose own ringStable says 0 carries ring numbers that may be mid-phantom-
    # window (task 066); run 2's last-slot arm consumed engineLen=5 from exactly such a
    # line and failed its precondition on a value the plugin had flagged as suspect. So a
    # ringStable=0 answer is re-asked (fresh marker, fresh read), up to three times; only
    # then is the unstable line returned, and the caller's assertion fails with the line
    # visible -- never silently on a flagged number.
    for ($ask = 0; $ask -lt 3; $ask++) {
        $script:qindSeq++
        $label = "qi-$Tag-$script:qindSeq"
        Set-ScMarker -MarkerPath $markerPath -Label $label
        $esc = [regex]::Escape($label)
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        $qi = $null
        while ((Get-Date) -lt $deadline) {
            $hit = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                     Select-String -Pattern "QIND \[$esc\]") | Select-Object -Last 1
            if ($hit) { $qi = ConvertFrom-QIndLine $hit; break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $qi) { throw "test: no QIND answer for marker '$label' within ${TimeoutSec}s (log: $LogPath)." }
        if ($qi.RingStable -ne 0) { return $qi }
        Write-Host "       (QIND '$label' reported ringStable=0 -- re-asking rather than trusting a flagged read)"
    }
    return $qi
}

# How many of the trained type player 0 owns right now. The cancel arms need it because a
# queued unit can FINISH inside the measurement window, which shortens the queue by one
# without moving a mineral -- so the expected drop is `1 + completions`, and completions
# is counted rather than assumed to be zero.
function Get-TraineeCount {
    <#
    COMPLETED Probes only, and the flag test is the whole point (task 031).

    A unit still being TRAINED is already linked into the player's unit list, so counting
    the list answers "how many exist", not "how many have been BUILT". Observed in this
    suite's own log, the same type before and after:

        in progress   type=0x007 hp=13484 flags=0x00130000
        finished      type=0x007 hp=15360 flags=0x00130001

    -- hit points ramping up towards the type's maximum with bit 0x01 clear, then set once
    it is there (SC_UNIT_FLAG_COMPLETED, tools/plugin/src/sc_addresses.h).

    This function's answer feeds `$completed`, which the cancel arms subtract from the
    expected queue length -- so counting a STARTED build as a finished one makes the arm
    expect one item fewer than the engine has and fail an assertion about cancelling.
    Task 031 hit exactly that when it shortened the Probe's build time: the first run
    reported `the LOGICAL queue drops by one: 8 -> 7 ... (expected 6)`. The same mis-count
    can happen on the vanilla fixture whenever a build happens to finish inside a cancel
    window -- it is simply rarer there, which is the worst kind of rare.
    #>
    param([string]$Tag)
    $w = Get-World $Tag
    @($w.Units | Where-Object {
        $_.Type -eq $PROBE_TYPE -and $_.Player -eq 0 -and
        ($_.Flags -band $SC_UNIT_FLAG_COMPLETED)
    }).Count
}

# One cancel, measured end to end. `Do` is the click; everything either side of it is the
# evidence. Returns the before/after readings so a caller can assert the case-specific
# parts (which counter moved) on top of the two that are common to both cases: the
# LOGICAL queue lost exactly one item, and the player got exactly one unit's cost back.
function Invoke-CancelAndMeasure {
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][scriptblock]$Do,
        # The payload byte this click must put on the wire: 0xFE for "the last queued
        # item", or a display index for one queue icon. Mandatory, because THE WIRE IS
        # ASSERTED BEFORE ANY REFUND CLAIM IS MADE -- AGENTS.md's rule from task 025, whose
        # first design was inert and whose offline proof said otherwise. If the command
        # never went out, nothing below it means anything and the run says so first.
        [Parameter(Mandatory)][int]$ExpectPayload,
        [int]$SettleSec = 3
    )
    $unitsBefore = Get-TraineeCount "$Tag-units-before"
    $before = Get-ProdQueue "$Tag-before"
    $mark = Get-ScLogLineCount -LogPath $LogPath
    & $Do
    Start-Sleep -Seconds $SettleSec
    $after = Get-ProdQueue "$Tag-after"
    $unitsAfter = Get-TraineeCount "$Tag-units-after"
    $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

    $completed = $unitsAfter - $unitsBefore
    $r = [pscustomobject]@{
        Before = $before; After = $after
        Completed = $completed
        UnitsBefore = $unitsBefore; UnitsAfter = $unitsAfter
        Cmds = @($lines | Select-String -Pattern "CMD id=$CANCEL_CMD ")
        Lines = $lines
    }

    # THE WIRE FIRST, before anything below it is claimed. One Cancel Train command, and
    # its payload is the byte that decides WHICH of the two cases this is: 0xFE means "the
    # last queued item" (the plugin's, while it holds any), a small number names a slot in
    # the engine's own ring.
    Assert-That "[$Tag] exactly one $CANCEL_CMD reached queueCommand ($($r.Cmds.Count))" `
        ($r.Cmds.Count -eq 1) "($(($r.Cmds | ForEach-Object { $_.Line.Trim() }) -join ' | '))"
    Assert-That ("[$Tag] and its payload is 0x{0:X2}" -f $ExpectPayload) `
        (@($r.Cmds | Select-String -Pattern ('bytes=\[20 {0:X2} 00\]' -f $ExpectPayload)).Count -eq 1) `
        "($(($r.Cmds | ForEach-Object { $_.Line.Trim() }) -join ' | '))"

    # THE TWO ASSERTIONS BOTH CASES OWE, from the building's memory and the player's
    # resource global -- never from the screen.
    $wantLogical = $before.Selected.Logical - 1 - $completed
    Assert-That ("[$Tag] the LOGICAL queue drops by one: $($before.Selected.Logical) -> $($after.Selected.Logical)" +
                 ($completed -gt 0 ? " (and $completed finished building in the window)" : '')) `
        ($after.Selected.Logical -eq $wantLogical) "(expected $wantLogical)"
    Assert-That "[$Tag] minerals go up by exactly one Probe's $PROBE_COST ($($before.Selected.Minerals) -> $($after.Selected.Minerals))" `
        ($after.Selected.Minerals -eq $before.Selected.Minerals + $PROBE_COST) `
        "(expected $($before.Selected.Minerals + $PROBE_COST))"
    return $r
}

# THE RECONCILIATION: spent = built + queued + cancelled.
#
# `built + queued + cancelled` is the same number as ACCEPTED -- every item the engine
# took a Train command for either exists, is still waiting, or was cancelled; there is no
# fourth place for one to be. So the identity is asserted in that form, and it has to be,
# because BUILT CANNOT BE COUNTED FROM THE UNIT LIST WHILE THE QUEUE IS RUNNING:
#
#   the engine creates the unit when production STARTS, not when it finishes
#   (research/production-queue.md 4.3 -- FUN_00468200, stashed at CUnit+0xEC), so the item
#   being built is in the world AND in the ring at the same time, and adding the two
#   double-counts it by exactly one.
#
# That is measured, not theorised: the first run of this arm read 1 unit and a 9-item
# logical queue for 9 accepted items, and the sum came out one too high.
#
# So: `accepted` comes from the engine's own command funnel (the CMD id=0x1F lines this
# run counted), `cancelled` from the cancels this run made, and the money from the
# player's resource global. Every item is paid once at accept and refunded once at cancel,
# so the balance must be exactly `(accepted - cancelled) x cost` -- a double refund reads
# too high here and a swallowed item too low.
#
# The other half of the identity -- that no item was LOST -- is asserted where it can be
# said without ambiguity: at the end of the drain, when the logical queue is zero and
# nothing is in progress, the units that exist must be exactly `accepted - cancelled`.
function Assert-Reconciles {
    param([Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)]$Q,
          [Parameter(Mandatory)][int]$Accepted, [Parameter(Mandatory)][int]$Cancelled)
    $net    = $StartingMinerals - $Q.Selected.Minerals
    $expect = ($Accepted - $Cancelled) * $PROBE_COST
    Assert-That ("[$Tag] spent = built + queued + cancelled: ($Accepted accepted - $Cancelled cancelled)" +
                 " x $PROBE_COST = $expect") `
        ($net -eq $expect) "(the player is actually $net down)"
}

# The production-queue oracle. Same marker handshake as Get-ScWorldState, but it waits for
# the `PRODQ [label] buildings=` SUMMARY line -- which the plugin writes LAST for a marker,
# and writes unconditionally, so waiting for it means the whole answer has landed AND an
# empty answer is still an answer. (Absence has to be positively reported; see AGENTS.md.)
$script:prodqSeq = 0
function Get-ProdQueue {
    param([string]$Tag, [int]$TimeoutSec = 20)
  # A LINE THE PLUGIN FLAGGED IS NOT CONSUMABLE (task 066, and it took two consumers to
  # learn it once): PRODQSEL/PRODQ carry ringStable=0 when the observer's ring read never
  # settled against the phantom bracket's seqlock -- an OS preemption inside the guarded
  # section can straddle every retry, so the flag can appear even with a tight guard. The
  # first sweep re-run consumed `engineLen=5 ringStable=0` here and failed two assertions
  # on a phantom the plugin had already disclaimed. Same rule as Get-QInd: re-ask, up to
  # three times; only then return the flagged answer so the assertion fails with the flag
  # in view.
  for ($ask = 0; $ask -lt 3; $ask++) {
    $script:prodqSeq++
    $label = "pq-$Tag-$script:prodqSeq"
    Set-ScMarker -MarkerPath $markerPath -Label $label
    $esc = [regex]::Escape($label)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                   Select-String -Pattern "PRODQ(SEL)? \[$esc\]")
        $summary = @($lines | Select-String -Pattern 'buildings=')
        if ($summary.Count -gt 0) {
            if ($ask -lt 2 -and
                @($lines | Where-Object { $_.Line -match ' ringStable=0' }).Count -gt 0) {
                Write-Host "       (PRODQ '$label' carries ringStable=0 -- re-asking rather than trusting a flagged read)"
                break
            }
            $out = [pscustomobject]@{
                Label = $label; Selected = $null
                Buildings = 0; Max = 0; Captured = 0; Promoted = 0
                Cancelled = 0; Refunded = 0; RefusedFull = 0
                Tracked = @(); Lines = @($lines | ForEach-Object { $_.Line })
            }
            foreach ($l in $lines) {
                $m = [regex]::Match($l.Line,
                    'PRODQSEL \[[^\]]+\] unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) logical=(\d+) minerals=(\d+) gas=(\d+)')
                if ($m.Success) {
                    $out.Selected = [pscustomobject]@{
                        Unit = $m.Groups[1].Value
                        Type = [Convert]::ToInt32($m.Groups[2].Value, 16)
                        Player = [int]$m.Groups[3].Value
                        Head = [int]$m.Groups[4].Value
                        EngineLen = [int]$m.Groups[5].Value
                        Engine = @($m.Groups[6].Value -split ',' | ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                        Overflow = [int]$m.Groups[7].Value
                        Logical = [int]$m.Groups[8].Value
                        Minerals = [int]$m.Groups[9].Value
                        Gas = [int]$m.Groups[10].Value
                    }
                    continue
                }
                $t = [regex]::Match($l.Line,
                    'PRODQ \[[^\]]+\] unit=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(\d+) engine=\[([^\]]*)\] overflow=(\d+) overflowTypes=\[([^\]]*)\] logical=(\d+) minerals=(\d+) gas=(\d+)')
                if ($t.Success) {
                    $out.Tracked += [pscustomobject]@{
                        Unit = $t.Groups[1].Value
                        EngineLen = [int]$t.Groups[4].Value
                        Overflow = [int]$t.Groups[6].Value
                        OverflowTypes = @($t.Groups[7].Value -split ',' |
                                          Where-Object { $_ -match '^0x' } |
                                          ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                        Logical = [int]$t.Groups[8].Value
                        Minerals = [int]$t.Groups[9].Value
                    }
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'buildings=(\d+) max=(\d+) captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+)')
                if ($s.Success) {
                    $out.Buildings = [int]$s.Groups[1].Value
                    $out.Max = [int]$s.Groups[2].Value
                    $out.Captured = [int]$s.Groups[3].Value
                    $out.Promoted = [int]$s.Groups[4].Value
                    $out.Cancelled = [int]$s.Groups[5].Value
                    $out.Refunded = [int]$s.Groups[6].Value
                    $out.RefusedFull = [int]$s.Groups[7].Value
                } elseif ($l.Line -match 'buildings=') {
                    Assert-That 'the PRODQ summary line parsed' $false "($($l.Line))"
                }
            }
            return $out
        }
        Start-Sleep -Milliseconds 250
    }
    if ((Get-Date) -ge $deadline) {
        throw "test: no PRODQ answer for marker '$label' within ${TimeoutSec}s (log: $LogPath). Was the game launched with -ProdQueue 1?"
    }
  }
  throw "test: Get-ProdQueue fell out of its re-ask loop -- unreachable"
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
$launchLock = $null
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

try {
    Step "generate the fixture: two Nexuses + one Command Center, $StartingMinerals minerals" {
        Wait-ScFixtureFolderFree -Run $fixtures
        # TWO Nexuses, because two supply 18 psi between them and a queue of $QueueMax
        # Probes needs 9 -- so no Pylon has to land on buildable ground for the run to
        # mean anything. Only ONE of them is ever selected; the second is supply.
        #
        # And ONE Command Center, owned by the PLAYER too (-EnemyOwner player is the
        # generator's "same block, human-owned" mode). It is not scenery: the claim that
        # a Terran producer's card cannot show the Cancel button is a claim about a
        # dialog, and this repo proves those by reading the dialog rather than by
        # reasoning about a button table. So the run trains at it and reads its card.
        # -UnitBuildTime is opt-in: at 0 the argument is not passed at all and the map is
        # byte-for-byte the one this suite generated before task 031.
        $genArgs = @{
            UnitCount = 2; UnitType = 'nexus'; Player = 0; ClearPlayerUnits = $true
            Race = 'protoss'; GridSpacing = 160
            EnemyCount = 1; EnemyType = 'command-center'; EnemyOwner = 'player'
            EnemyOffsetX = 288; EnemyOffsetY = 0; MinEnemyGap = 150
            StartingMinerals = $StartingMinerals; StartingGas = $StartingGas
            OutputPath = $mapPath
        }
        if ($ProbeBuildSeconds -gt 0) { $genArgs.UnitBuildTime = @("probe=$ProbeBuildSeconds") }
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        # ONE trigger, and the generator has already proved from the bytes that its only
        # action is Set Resources -- so the fixture still cannot end the game by itself.
        Assert-That 'the map carries exactly the one resource trigger (2400 bytes)' `
            (@($gen | Select-String -Pattern 'TRIG holds 2400 byte').Count -gt 0)
        Assert-That 'the map differs from its template only where this tool meant it to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC').Count -gt 0)
        # POSITIVE, and only worth anything because the negative case is reachable: at
        # -ProbeBuildSeconds 0 no UNIx is written and the else branch asserts it is ABSENT
        # from the section diff (AGENTS.md: prove an absence positive somewhere first).
        if ($ProbeBuildSeconds -gt 0) {
            Assert-That "the fixture overrides the Probe's build time to ${ProbeBuildSeconds}s in UNIx" `
                (@($gen | Select-String -Pattern "probe \(64\) usesDefault=0 .*\*build-time=$ProbeBuildSeconds ").Count -gt 0)
            Assert-That 'and UNIx is one of the sections that differ from the template' `
                (@($gen | Select-String -Pattern 'ONLY in: OWNR SIDE UNIT TRIG FORC UNIx').Count -gt 0)
        }
        else {
            Assert-That 'the vanilla fixture touches no UNIx at all' `
                (@($gen | Select-String -Pattern 'ONLY in: OWNR SIDE UNIT TRIG FORC$').Count -gt 0)
        }
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '028-production-cancel-refund'
    # hooktest mode: the ONE queueCommand hook, so `CMD id=` lines exist, and none of the
    # selection machinery. The production queue is a per-building feature and has nothing
    # to do with selection fan-out -- running in `fanout` would put four unrelated hooks
    # in the picture for no gain.
    #
    # -CardScan 1 adds the two READ-ONLY dialog walks (command card + status-pane queue
    # strip). They install no hook and write nothing, which is why they can be on in a run
    # that is also asserting the plugin's own writes.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 -CardScan 1 `
        -ProdQueue 1 -ProdQueueMax $QueueMax -QueueIndicator 1 `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -Widescreen $Widescreen -WidescreenStage $WidescreenStage `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'the plugin armed the production queue at all' {
        $cfg = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODQ config: enabled max=')
        Assert-That "the feature reports itself enabled at max=$QueueMax" `
            (@($cfg | Select-String -Pattern "max=$QueueMax ").Count -gt 0) `
            "(lines: $($cfg.Count))"
        # The absence check below is only worth anything because this positive one exists:
        # 'HOOK <name>: installed at' is the plugin's real wording (AGENTS.md, 2026-08-09).
        $hooks = @(Get-Content -LiteralPath $LogPath |
                   Select-String -Pattern 'HOOK (cmdrecvTrain|cmdrecvCancelTrain|productionTick): installed at')
        Assert-That 'all three production detours are spliced' ($hooks.Count -eq 3) `
            "(got $($hooks.Count): $(($hooks | ForEach-Object { $_.Line }) -join ' | '))"
        Assert-That 'and none of them rolled back' `
            (@(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODQ: only \d+ of 3').Count -eq 0)
    }

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2      # Use Map Settings, verified
        Shot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN
        # OK button, then asserted gone (task 027) -- never a fixed point, never the registry.
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step 'the map spawned the two Nexuses and the Command Center, and nothing else' {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $nexuses = @($mine | Where-Object { $_.Type -eq $NEXUS_TYPE })
        $ccs = @($mine | Where-Object { $_.Type -eq $CC_TYPE })
        Assert-That "player 0 owns exactly two Nexuses ($($nexuses.Count))" ($nexuses.Count -eq 2)
        Assert-That "and exactly one Command Center ($($ccs.Count))" ($ccs.Count -eq 1)
        Assert-That "and owns nothing else ($($mine.Count) unit(s) total)" ($mine.Count -eq 3) `
            "(types seen: $((($mine | ForEach-Object { '0x{0:x}' -f $_.Type }) | Sort-Object -Unique) -join ' '))"
        Assert-That 'the world scan of player 0 was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1) `
            "(units=$($w.Counts[0].Units) recount=$($w.Counts[0].Recount) complete=$($w.Counts[0].Complete))"
        # The FIRST Nexus is the one every later step selects; the other is supply.
        $script:nexusUnit = if ($nexuses.Count -gt 0) { $nexuses[0].Unit } else { $null }
    }

    Step 'select a Nexus -- exactly one building, nothing else' {
        # NOT a drag box. The first run of this suite boxed the whole play area and the
        # engine handed back a neutral MINERAL FIELD (`type=0x0B2 player=11`) that shares
        # the box with the building -- so a box is not a way to name a specific building
        # when the only thing you own is one.
        #
        # The click point is DERIVED FROM MEMORY instead, never measured off a frame
        # (AGENTS.md, task 026): the world scan reports the building's own map-pixel
        # position and the viewport's top-left, and `client = map - viewport` is exactly
        # the arithmetic the engine's own click handler at 0x0046FB40 does when it builds
        # the rectangle it hit-tests. So this clicks the building the scan found, and if
        # the sums ever put it off the play area the step says so instead of clicking
        # somewhere arbitrary.
        $w = Get-World 'aim'
        $cc = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $NEXUS_TYPE -and
                                          ($null -eq $script:nexusUnit -or $_.Unit -eq $script:nexusUnit) })[0]
        Assert-That 'the scan reports the viewport origin' ($null -ne $w.Screen)
        Assert-That 'and the Nexus has a sprite position' `
            ($null -ne $cc -and $cc.X -gt 0 -and $cc.Y -gt 0)
        $cx = $cc.X - $w.Screen.Left
        $cy = $cc.Y - $w.Screen.Top
        Write-Host "       Nexus at map ($($cc.X),$($cc.Y)), viewport ($($w.Screen.Left),$($w.Screen.Top)) -> client ($cx,$cy)"
        # 340 is the world-area bound every suite in this repo drags inside; below it is
        # the console, which would eat the click.
        Assert-That "the building is on screen, inside the play area ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2
        $q = Get-ProdQueue 'selected'
        Assert-That 'exactly one building is selected' ($null -ne $q.Selected) `
            "($(($q.Lines | Select-Object -First 2) -join ' | '))"
        if ($q.Selected) {
            Assert-That "and it is the Nexus (type 0x$('{0:x}' -f $q.Selected.Type))" `
                ($q.Selected.Type -eq $NEXUS_TYPE)
            # The mineral field the box used to grab was player 11. Naming the owner keeps
            # that failure mode from ever reading as a pass again.
            Assert-That "owned by the human player 0 ($($q.Selected.Player))" `
                ($q.Selected.Player -eq 0)
            Assert-That "and it is the same building the world scan found ($($q.Selected.Unit))" `
                ($null -eq $script:nexusUnit -or $q.Selected.Unit -eq $script:nexusUnit)
            $script:nexusUnit = $q.Selected.Unit
            Assert-That 'it starts with an empty queue, read from CUnit+0x98' `
                ($q.Selected.EngineLen -eq 0) "(engine=$($q.Selected.Engine -join ','))"
            Assert-That "it starts with the $StartingMinerals minerals the trigger granted" `
                ($q.Selected.Minerals -eq $StartingMinerals) "(got $($q.Selected.Minerals))"
        }
        # THE NEGATIVE HALF of the pair. The same oracle, the same line, before anything
        # has happened -- so the positive reading later cannot be an oracle that always
        # says yes.
        Assert-That 'the plugin is holding nothing yet' `
            ($q.Buildings -eq 0 -and $q.Captured -eq 0 -and $q.Promoted -eq 0)
        Shot 'selected'
    }

    Step 'READ the command card: which control trains, and which one cancels' {
        # THE CONTROL IS LOCATED BY READING THE DIALOG THAT OWNS IT. No hotkey letter is
        # guessed and no coordinate is measured off a frame: the card read-back names the
        # Button record behind each slot -- its action and its actionParam -- and
        # Get-ScCardSlotPoint computes the click point from the live control rect, which
        # is the sum the engine itself forms at 0x00458850.
        $card = Get-Card 'card-idle'
        Assert-That 'the card read-back answered' ($card.Ok)
        Assert-That "the card resolves to the Nexus buttonset ($($card.CardId))" `
            ($card.CardId -eq $NEXUS_TYPE) "(portrait set $($card.PortraitSet))"

        $train = Get-ScCardSlot -Card $card -Slot $TRAIN_SLOT
        Assert-That "slot $TRAIN_SLOT carries a Button record" ($null -ne $train -and $train.HasButton)
        if ($train -and $train.HasButton) {
            Assert-That "slot $TRAIN_SLOT is the Train action 0x$TRAIN_ACT (0x$($train.Action))" `
                ($train.Action -eq $TRAIN_ACT)
            Assert-That "and its actionParam is the Probe, type $PROBE_TYPE ($($train.ActParam))" `
                ($train.ActParam -eq $PROBE_TYPE)
            Assert-That 'and it is not greyed -- the run can actually press it' `
                ($train.Visible -and -not $train.Disabled) "(state $($train.State))"
        }
        $script:trainPoint = Get-ScCardSlotPoint -Card $card -Slot $TRAIN_SLOT
        Write-Host "       Train button -> client ($($script:trainPoint.X),$($script:trainPoint.Y))"

        # THE NEGATIVE HALF, before anything is queued: the Cancel button's condition is
        # "the head slot holds a real unit type" (0x00428530), so with an empty queue it
        # must NOT be on the card. Reading it here is what makes the positive reading
        # after the burst mean something.
        $cancelIdle = Get-ScCardSlot -Card $card -Slot $CANCEL_SLOT
        $idleIsCancel = $cancelIdle -and $cancelIdle.HasButton -and $cancelIdle.Action -eq $CANCEL_ACT
        Assert-That 'with an empty queue there is no Cancel button on the card' `
            (-not $idleIsCancel) `
            "(slot $CANCEL_SLOT holds act=$($cancelIdle.Action) aparam=$($cancelIdle.ActParam))"
    }

    Step "click Train x$Clicks in one burst" {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        # One burst, no marker in the middle: a Probe takes ~9s to build and the burst
        # takes ~3s, so no slot can free while it is running -- which is what makes the
        # counter arithmetic below exact rather than approximate.
        for ($i = 1; $i -le $Clicks; $i++) {
            Send-ScClick -Hwnd $hwnd -X $script:trainPoint.X -Y $script:trainPoint.Y -SettleMs 120
        }
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ")
        # THE HEADLINE MEASUREMENT, on the engine's own command funnel. Vanilla puts FIVE
        # Train commands on the wire and then goes quiet, because the client greys the
        # button out once the ring holds five -- this suite measured exactly that before
        # the plugin kept the ring below it. With the plugin, the client keeps offering
        # the button until the logical queue reaches the configured maximum, so the number
        # of commands that actually went out IS the cap.
        Assert-That "$QueueMax of the $Clicks presses reached the wire, not $ENGINE_SLOTS ($($cmds.Count))" `
            ($cmds.Count -eq $QueueMax)
        Assert-That "and the $expectNotSent presses past the cap were refused by the client itself" `
            ($cmds.Count -eq $Clicks - $expectNotSent)
        $script:cmdsSent = $cmds.Count

        # THE ASSUMPTION THE COUNT ABOVE RESTS ON, checked rather than commented. If a slot
        # freed while the clicks were going out, the plugin would have promoted an item into
        # it, the logical queue would have fallen below the cap, and the client would have
        # sent a TENTH command -- so both assertions above would fail with nothing to say
        # about why. A faster fixture is exactly what causes that (task 031,
        # -ProbeBuildSeconds), so the cause is named here instead of being guessed at.
        #
        # `promoted` IS THE INVARIANT, not "how many Probes exist". An earlier version of
        # this guard counted units and failed a run whose fixture was fine, because a unit
        # still being TRAINED is already linked into the player's unit list -- that run's log
        # has `hp=13484 flags=0x00130000` beside the finished ones' `hp=15360
        # flags=0x00130001`, i.e. HP ramping up with the completed bit (0x01) still clear.
        # A slot frees when a unit FINISHES, and the plugin's promotion counter is the
        # engine-side record of exactly that.
        $burst = Get-ProdQueue 'burst-end'
        Assert-That "no queue slot freed while the burst was going out (promoted=$($burst.Promoted)) -- the wire count depends on it" `
            ($burst.Promoted -eq 0) `
            "(-ProbeBuildSeconds $ProbeBuildSeconds is too short for a $Clicks-click burst)"

        # THE LEDGER. Every command that reached the funnel was accepted and paid for
        # there (refusedFull is asserted zero below), so this is what the money has to
        # reconcile against for the rest of the run.
        $script:accepted += $cmds.Count
        Shot 'queued'
    }

    Step "the building holds $QueueMax items -- $ENGINE_SLOTS in its own memory, $expectOverflow in the plugin" {
        $q = Get-ProdQueue 'queued'
        Assert-That 'the oracle still sees one selected building' ($null -ne $q.Selected)
        if ($q.Selected) {
            $s = $q.Selected
            Write-Host "       $($q.Lines | Where-Object { $_ -match 'PRODQSEL' } | Select-Object -First 1)"
            # READ FROM THE BUILDING'S OWN MEMORY. Five occupied slots at CUnit+0x98.
            Assert-That "the engine's five slots are all occupied ($($s.EngineLen))" `
                ($s.EngineLen -eq $ENGINE_SLOTS) "(engine=$(($s.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))"
            Assert-EverySlot -Selected $s -WantType $PROBE_TYPE
            Assert-That "the plugin holds the other $expectOverflow ($($s.Overflow))" `
                ($s.Overflow -eq $expectOverflow)
            Assert-That "so the logical queue is $QueueMax, which is MORE THAN $ENGINE_SLOTS ($($s.Logical))" `
                ($s.Logical -eq $QueueMax -and $s.Logical -gt $ENGINE_SLOTS)
            # PAID EXACTLY ONCE, each. $QueueMax accepted items, $expectRefused refused
            # ones that must have cost nothing at all.
            $expectMinerals = $StartingMinerals - $QueueMax * $PROBE_COST
            Assert-That "minerals are down by exactly $QueueMax x $PROBE_COST and no more ($($s.Minerals))" `
                ($s.Minerals -eq $expectMinerals) "(expected $expectMinerals)"
        }
        Assert-That "the plugin is holding exactly $expectOverflow item(s) ($($q.Captured))" `
            ($q.Captured -eq $expectOverflow)
        # NOTHING was refused by the plugin: at the cap it simply stops taking items back,
        # the ring is left full, and vanilla's own UI declines the rest. A refusal here
        # would mean an over-cap command reached the handler, which the client should
        # never have sent.
        Assert-That "and refused nothing itself ($($q.RefusedFull))" ($q.RefusedFull -eq 0)
        # "nothing was refused for cost" was asserted here from refusedCost, a counter no
        # code path could move (issue #66). The fixture's resource state is asserted for
        # real by the exact-minerals check above, which is what a starved fixture breaks.
        # The engine's cap, stated as a subtraction over this run's own counters: 9
        # commands went out and 4 of them are with the plugin, so the engine is holding 5
        # -- its five slots, full, which is what stopped the tenth press.
        $engineHas = $cmdsSent - $q.Captured
        Assert-That "the engine itself is holding $ENGINE_SLOTS of the $cmdsSent sent ($engineHas)" `
            ($engineHas -eq $ENGINE_SLOTS)
        Assert-That 'one building is tracked' ($q.Buildings -eq 1)
        if ($q.Tracked.Count -eq 1) {
            Assert-That "its overflow is all Probes ($(($q.Tracked[0].OverflowTypes | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))" `
                (@($q.Tracked[0].OverflowTypes | Where-Object { $_ -ne $PROBE_TYPE }).Count -eq 0)
        }
        $script:mineralsAfterBurst = if ($q.Selected) { $q.Selected.Minerals } else { -1 }
        Assert-Reconciles 'queued' $q -Accepted $script:accepted -Cancelled $script:cancels
    }

    # ---------------------------------------------------------------------------
    # TASK 028: what the player can actually SEE and CLICK, with nine queued
    # ---------------------------------------------------------------------------
    Step 'READ the status pane: five icons for a nine-item queue' {
        # The line mark the indicator step below reads from, so it costs no extra marker
        # round trip -- see Get-QIndAfter for why a spare second here is expensive.
        $script:stripMark = Get-ScLogLineCount -LogPath $LogPath
        $st = Get-StatusQueue 'strip-full'
        Assert-That 'the status-strip read-back answered' ($st.Ok)
        Assert-That "the strip is showing this Nexus ($($st.Portrait))" `
            ($st.PortraitType -eq $NEXUS_TYPE -and $st.PortraitOwner -eq 0)
        Assert-That "it holds exactly $STATQ_SLOTS icon controls ($($st.Slots.Count))" `
            ($st.Slots.Count -eq $STATQ_SLOTS)
        # The engine takes the display index from the WALK ORDER and the click payload
        # from `index - 2`. Two numbers, assumed equal by the engine and never checked by
        # it, so this run checks them.
        $misordered = @($st.Slots | Where-Object { $_.Index -ne ($_.Display + $STATQ_FIRST_CONTROL) })
        Assert-That 'every icon carries control index = display + 2, as the engine assumes' `
            ($misordered.Count -eq 0) `
            "(bad: $(($misordered | ForEach-Object { "disp$($_.Display)=idx$($_.Index)" }) -join ' '))"
        # THE FINDING, and it is a read, not an inference: the strip draws the RING and
        # nothing else. Five icons, all clickable, all Probes -- while the building's
        # logical queue is nine. The four the plugin holds are not on the screen at all.
        Assert-That "all $ENGINE_SLOTS icons are clickable -- the ring is full ($($st.Clickable))" `
            ($st.Clickable -eq $ENGINE_SLOTS)
        $wrong = @($st.Slots | Where-Object { $_.UType -ne $PROBE_TYPE -or $_.QueueType -ne $PROBE_TYPE })
        Assert-That 'and every icon draws the Probe its own ring slot holds' `
            ($wrong.Count -eq 0) `
            "(bad: $(($wrong | ForEach-Object { "disp$($_.Display) uicon=0x$('{0:x}' -f $_.UIcon) qtype=0x$('{0:x}' -f $_.QueueType)" }) -join ' '))"
        Write-Host "       the player sees $($st.Clickable) icons for a queue of $QueueMax -- the $expectOverflow the plugin holds are NOT drawn"
        $script:stripWithOverflow = $st
    }

    Step 'THE INDICATOR says what the strip cannot show (task 033)' {
        # The user asked for this in as many words: "when more then 5 units a queued - is
        # the info showing that? (some +x number somewhere in tug?)". At the CAP the plugin
        # has stopped taking items back, so the ring is full at five and the four it holds
        # are the ones no icon can draw -- which is exactly what the "+N" is for.
        # The observer writes the QIND line on EVERY marker, so the strip read above has
        # already produced one; taking that line costs nothing, where a marker of our own
        # would delay the timing-sensitive cancel arm below.
        $qi = Get-QIndAfter $script:stripMark
        Write-Host "       $($qi.Line)"
        Assert-That 'the indicator control is spliced into the status dialog' ($qi.Linked)
        Assert-That "and the ENGINE's own visible bit is set on it" ($qi.Visible)
        # Read through the control's pszText pointer, not echoed from the module's buffer:
        # that distinction is what let sc_hudrow's indicator pass its own test for weeks
        # while drawing nothing (AGENTS.md: assert the engine's own result).
        Assert-That "its text says +$expectOverflow -- the items the strip cannot draw (`"$($qi.Text)`")" `
            ($qi.Text -eq "+$expectOverflow")
        Assert-That "and the numbers behind it are the building's own ($($qi.EngineLen) + $($qi.Overflow))" `
            ($qi.EngineLen -eq $ENGINE_SLOTS -and $qi.Overflow -eq $expectOverflow)
        # THE DRAW ITSELF. A control can be linked, visible and hold the right string and
        # still put no pixel on the screen -- the engine's text routine refuses to draw at
        # all when the box is shorter than the font. refInk is the positive control: if the
        # probe cannot see the surface, BOTH numbers are 0 and the ink assertion means
        # nothing, so it is asserted first.
        Assert-That "the ink probe can see the dialog's surface (refInk=$($qi.RefInk) over control $($qi.RefId))" `
            ($qi.RefInk -gt 0)
        Assert-That "the box is taller than the font, or the engine would refuse it outright ($($qi.Bottom - $qi.Top) >= $($qi.FontH))" `
            (($qi.Bottom - $qi.Top) -ge $qi.FontH)
        # ... and THAT is as far as ink can take this case. The "+N" box sits inside queue
        # icon 6, so the icon's own pixels are inside it: ink > 0 is true here whether or not
        # one pixel of ours was drawn, and it stayed true through the whole of task 039's
        # defect, when the icon under it was drawing the wrong art entirely. What CAN fail is
        # the difference between slot 0 and slot 4: same rect size, same border graphic, same
        # queued Probe, so with the ring full and the strip settled the only bytes that differ
        # are the ones this plugin put there.
        # `ink` is reported for continuity and is NOT an oracle here: this pane's own art
        # lives in the same surface, so every rect in it reads saturated (this run: 1330 of
        # 1330 bytes over a queue icon). What can fail is boxDiff -- the same box compared
        # against a copy of itself taken while the indicator was hidden.
        # AND WHAT boxDiff CLAIMS HERE, exactly. This box sits inside queue icon 6, which is
        # the icon this module also FILLS, and the baseline predates that fill -- so in STRIP
        # mode the number is "bytes inside the box this plugin is responsible for", the icon
        # and the text together, not "the text drew". The text-specific oracle in this mode is
        # slotDiff below, where both slots hold the same art and the string is all that is
        # left to differ. In GROUP mode the band belongs to no control and boxDiff IS the text.
        Assert-That "the box holds bytes this plugin put there: boxDiff=$($qi.BoxDiff) (ink=$($qi.Ink), saturated by the pane art)" `
            ($qi.BoxDiff -gt 0)
        Assert-That ("the fifth icon draws the SAME picture as the first: slotDiff=$($qi.SlotDiff) bytes, " +
                     'i.e. our "+N" and nothing else') `
            ($qi.SlotDiff -gt 0 -and $qi.SlotDiff -lt 200) `
            '(hundreds of differing bytes means the two slots are not the same art at all)'
        Assert-That 'every lit icon draws from the ICON grp, not the empty-slot placeholder art' `
            (@($qi.Icons | Where-Object { $_.State -eq 'lit' -and $_.Art -ne 'I' }).Count -eq 0) `
            "(art letters: $(($qi.Icons | ForEach-Object { $_.Art }) -join ''))"
        $script:qindDrawn = $qi
    }

    Step 'READ the card again: NOW the Cancel button is there' {
        # The positive half of the pair taken before the burst. Same walk, same slot,
        # different answer -- which is what makes "no Cancel button when the queue is
        # empty" a measurement rather than a missing line.
        $card = Get-Card 'card-queued'
        Assert-That 'the card read-back answered' ($card.Ok)
        $cancel = Get-ScCardSlot -Card $card -Slot $CANCEL_SLOT
        Assert-That "slot $CANCEL_SLOT carries a Button record" ($null -ne $cancel -and $cancel.HasButton)
        if ($cancel -and $cancel.HasButton) {
            Assert-That "slot $CANCEL_SLOT is the Cancel action 0x$CANCEL_ACT (0x$($cancel.Action))" `
                ($cancel.Action -eq $CANCEL_ACT)
            # 0xFE is the whole reason this button is the plugin's: it means "cancel the
            # LAST queued item", which is the item the plugin is holding.
            Assert-That "and its actionParam is 0x00FE, cancel-the-last ($($cancel.ActParam))" `
                ($cancel.ActParam -eq $CANCEL_APARAM)
            Assert-That 'and it is not greyed -- the click can reach the action' `
                ($cancel.Visible -and -not $cancel.Disabled) "(state $($cancel.State))"
        }
        $script:cancelPoint = Get-ScCardSlotPoint -Card $card -Slot $CANCEL_SLOT
        Write-Host "       Cancel button -> client ($($script:cancelPoint.X),$($script:cancelPoint.Y))"
    }

    Step 'CANCEL AN ITEM THE PLUGIN IS HOLDING -- the refund path with real money on it' {
        # The payload the card's Cancel button carries: "the LAST queued item", which is
        # the plugin's while it holds any. Asserted on the wire inside the helper, before
        # a single refund number is looked at.
        $r = Invoke-CancelAndMeasure -Tag 'plugin-cancel' -ExpectPayload $CANCEL_APARAM -Do {
            Send-ScClick -Hwnd $hwnd -X $script:cancelPoint.X -Y $script:cancelPoint.Y
        }
        # THE PLUGIN CONSUMED IT. Its own event line, once, naming the type and the money.
        $ev = @($r.Lines | Select-String -Pattern 'PRODQEV cancel-last ')
        Assert-That "the plugin cancelled it itself, exactly once ($($ev.Count))" ($ev.Count -eq 1)
        if ($ev.Count -eq 1) {
            Write-Host "       $($ev[0].Line.Trim())"
            Assert-That "and gave back one Probe's $PROBE_COST minerals and no gas" `
                ($ev[0].Line -match "type=0x0*$('{0:X}' -f $PROBE_TYPE) " -and
                 $ev[0].Line -match "back=$PROBE_COST/0")
        }
        Assert-That "the plugin's cancelled counter is 1 ($($r.After.Cancelled))" `
            ($r.After.Cancelled -eq 1)
        # NOT the other counter: `refunded` counts items given back because their BUILDING
        # went away. Nothing died here, so a bump in it would mean the run measured
        # something else entirely.
        Assert-That "and its building-gone refund counter is still 0 ($($r.After.Refunded))" `
            ($r.After.Refunded -eq 0)
        # The engine's own ring was NOT the thing that shrank: it still holds five (or
        # four, if the plugin has already rebalanced into it), and the item that went is
        # the one the plugin was holding.
        Assert-That "the overflow the plugin holds is what absorbed the cancel ($($r.Before.Selected.Overflow) -> $($r.After.Selected.Overflow), ring $($r.Before.Selected.EngineLen) -> $($r.After.Selected.EngineLen))" `
            ($r.After.Selected.EngineLen + $r.After.Selected.Overflow -eq $QueueMax - 1 - $r.Completed)
        $script:cancels++
        $script:pluginCancels++
        # Whether THIS cancel makes the plugin take one more item out of the ring is a
        # property of the ring at the moment it was made, not of cancelling -- see the
        # drain step. Recorded from this arm's own before-reading.
        if ($r.Before.Selected.EngineLen -gt $ENGINE_HOLD) { $script:capturesFromCancel++ }
        $script:mineralsAfterBurst = $r.After.Selected.Minerals
        Assert-Reconciles 'after-plugin-cancel' $r.After -Accepted $script:accepted -Cancelled $script:cancels
        Shot 'plugin-cancelled'
    }

    Step 'THE FIFTH ICON: below the cap the plugin draws the slot the engine leaves empty' {
        # The user's second report: "when i queue more then 5 units the 5'th slot is emtpy".
        # It is task 025's SC_PRODQ_ENGINE_HOLD = 4 showing through -- the ring is kept one
        # below its cap so the client keeps sending Train commands. The cancel above put the
        # logical queue back under the maximum, so the plugin is holding the ring at four
        # again, which is precisely the state where display 4 has nothing behind it.
        #
        # Both halves are read from the ENGINE's own dialog: the strip walk says which icons
        # are drawn and clickable, and the indicator line says what the plugin put there.
        $qi = Get-QInd 'fifth-icon'
        Write-Host "       $($qi.Line)"
        if ($qi.EngineLen -ge $ENGINE_SLOTS) {
            Write-Host "       SKIPPED: the ring is still full ($($qi.EngineLen)) -- nothing was left empty to fill"
        }
        else {
            Assert-That "the engine's ring is at the hold, so display $($qi.EngineLen) is its first empty slot ($($qi.EngineLen))" `
                ($qi.EngineLen -eq $ENGINE_HOLD)
            Assert-That "and the plugin still holds items to draw there ($($qi.Overflow))" `
                ($qi.Overflow -gt 0)
            # THE HEADLINE: five icons drawn and lit for a queue whose ring holds four.
            # Before task 033 this read four, and the fifth came back GREYED with 0xE4
            # behind it (research/production-queue.md 8.4 recorded exactly that).
            #
            # Asserted from the indicator's OWN snapshot, which the GAME THREAD takes at the
            # end of the frame that filled the icons -- not from the observer's asynchronous
            # walk. The engine's layout re-greys these slots microseconds before the plugin
            # re-fills them, inside the same driver call and before anything is drawn, so an
            # async reader can sample a state the player never sees. It did, and it made this
            # assertion pass one run and fail the next.
            $lit = @($qi.Icons | Where-Object { $_.State -eq 'lit' })
            Assert-That "all $STATQ_SLOTS icons are lit, not $ENGINE_HOLD ($($lit.Count)): [$(($qi.Icons | ForEach-Object { "0x$('{0:x}' -f $_.Icon):$($_.State)" }) -join ' ')]" `
                ($lit.Count -eq $STATQ_SLOTS)
            $fifth = $qi.Icons[$ENGINE_SLOTS - 1]
            if ($fifth) {
                Assert-That "the fifth icon draws a Probe (icon=0x$('{0:x}' -f $fifth.Icon))" `
                    ($fifth.Icon -eq $PROBE_TYPE)
                Assert-That "with the OCCUPIED mode the engine writes for a real item ($($fifth.Mode))" `
                    ($fifth.Mode -eq 3)
                Assert-That 'and it is NOT greyed' ($fifth.State -eq 'lit')
                # THE FIELD THIS SUITE USED TO MISS, and the one task 039 exists for. An
                # icon INDEX is meaningless without the GRP it indexes, and the plugin was
                # inheriting the GRP the engine leaves on a slot it drew EMPTY -- the command
                # button borders -- so this slot was blitting frame #unitType out of the
                # wrong art. Every assertion above passed while that was true. `art` is read
                # back from the live statUser record and compared against the engine's own
                # two globals, so B here is precisely the defect the user reported.
                Assert-That "and it draws from the ICON grp, not the empty-slot art (art=$($fifth.Art))" `
                    ($fifth.Art -eq 'I') `
                    '(B = <race>cmdbtns.grp, the placeholder art -- the frame index then means nothing)'
                Assert-That 'and carries a slot label, like the four the engine filled' `
                    ($fifth.Label)
                # The screen itself: slot 4 and slot 0 hold the same Probe, are the same
                # size and take the same border graphic, so what differs between them below
                # their labels is our "+N" and nothing else. With the wrong GRP the two are
                # not the same picture at all and this runs to hundreds.
                Assert-That "the two slots are the same picture: slotDiff=$($qi.SlotDiff) bytes" `
                    ($qi.SlotDiff -ge 0 -and $qi.SlotDiff -lt 200)
            }
            # ... and the engine's own ring slot behind it is still EMPTY. That is the point
            # of the whole exercise: the item is real and paid for, but it lives in the
            # plugin, which is why a click on that icon is the plugin's to serve and never
            # reaches cancelBuildQueueSlot. This one IS the async walk -- the ring is the
            # BUILDING's memory, which nothing in this frame path writes, so it cannot race.
            $st = Get-StatusQueue 'strip-fifth'
            Assert-That 'the status-strip read-back answered' ($st.Ok)
            $ring = @($st.Slots | Where-Object { $_.Display -eq ($ENGINE_SLOTS - 1) })[0]
            if ($ring) {
                Assert-That "while the RING slot behind it is still empty (0x$('{0:x}' -f $ring.QueueType))" `
                    ($ring.QueueType -eq 0xE4)
            }
        }
    }

    # ---------------------------------------------------------------------------
    # TASK 061. The user, playing the deployed build 2c239e6: "i can cancel a queue
    # unit by clicking it, but it doesn't work if i click the last slock when it has
    # our extra +x text".
    #
    # Every arm above this one cancels a slot our own drawing is NOT on: the card's
    # Cancel button (0xFE) and, later, a middle icon on a below-cap queue. The LAST
    # icon is the only one where a click has to pass through pixels this repo put on
    # the screen -- it is both the slot the plugin fills from its own overflow and the
    # control the "+N" indicator anchors to -- and that is the slot the user cannot
    # cancel. It had never been clicked by anything.
    #
    # THE SEAM THIS ARM EXISTS TO REACH, named and measured rather than assumed
    # (AGENTS.md, task 041 -- a generated or state-dependent case that never reaches
    # its seam is a passing check standing guard over a bug):
    #
    #   1. the strip's last icon is LIT and its RING SLOT IS EMPTY, so the item behind
    #      it is the plugin's and the click is the plugin's to serve;
    #   2. the indicator is in STRIP mode with a "+N" on that icon;
    #   3. OUR PIXELS ARE ACTUALLY ON IT -- boxDiff, never ink: the icon's own art is
    #      inside that box, so ink reads saturated before anything of ours is drawn
    #      (measured in task 039: 448 of 448 bytes);
    #   4. and the point this arm clicks is INSIDE that box, so it is the user's click
    #      and not some corner of the slot their report is not about.
    #
    # All four are assertions. A run that does not reach that state FAILS here rather
    # than skipping, because below it this arm cannot detect the bug at all.
    Step 'THE LAST SLOT, WITH "+N" DRAWN ON IT: clicking it must cancel like any other' {
        $qi = Get-QInd 'last-slot-before'
        Write-Host "       $($qi.Line)"
        Assert-That "the indicator is in STRIP mode with a `"+N`" (mode=$($qi.Mode) text=`"$($qi.Text)`")" `
            ($qi.Mode -eq $QIND_MODE_STRIP -and $qi.Text -match '^\+\d+$')
        Assert-That "and the engine has our control linked and visible (linked=$($qi.Linked) visible=$($qi.Visible))" `
            ($qi.Linked -and $qi.Visible)
        # THE ORACLE FOR "OUR TEXT IS ON THAT SLOT", and the reason it is not `ink`:
        # boxDiff counts the bytes inside the box that differ from a copy of the SAME
        # rect taken while the indicator was hidden. 0 means nothing of ours is on the
        # screen; -1 means the probe has no baseline and therefore never answered.
        Assert-That "and OUR pixels are on that box: boxDiff=$($qi.BoxDiff) bytes differ from the same rect without them" `
            ($qi.BoxDiff -gt 0) `
            '(0 = nothing of ours is drawn there; -1 = no baseline, so the probe never answered)'
        Assert-That "the ring is at the hold, so display $STATQ_LAST_DISPLAY is not the engine's ($($qi.EngineLen))" `
            ($qi.EngineLen -eq $ENGINE_HOLD)
        Assert-That "and the plugin is holding the item behind it ($($qi.Overflow))" ($qi.Overflow -gt 0)

        $st = Get-StatusQueue 'strip-before-last-cancel'
        Assert-That 'the status-strip read-back answered' ($st.Ok)
        $last = @($st.Slots | Where-Object { $_.Display -eq $STATQ_LAST_DISPLAY })[0]
        Assert-That "display $STATQ_LAST_DISPLAY is an icon the player can click ($($last.State))" `
            ($null -ne $last -and $last.Visible -and -not $last.Disabled)
        if ($last) {
            Assert-That "and its control id is $($STATQ_LAST_DISPLAY + $STATQ_FIRST_CONTROL), the id whose click sends payload $STATQ_LAST_DISPLAY" `
                ($last.Index -eq $STATQ_LAST_DISPLAY + $STATQ_FIRST_CONTROL)
            Assert-That "while the ring slot behind it is EMPTY (0x$('{0:x}' -f $last.QueueType)) -- the item is the plugin's" `
                ($last.QueueType -eq 0xE4)
        }

        $script:lastSlotPoint = Get-ScStatusSlotPoint -Status $st -Display $STATQ_LAST_DISPLAY
        # A control's rect and the indicator's bounds are read in the SAME (dialog-
        # relative) space -- PlaceOn derives the box from the anchor control's own
        # bounds -- so the click point converts back by subtracting the root origin and
        # can be compared directly. Without this the arm could pass by clicking a part
        # of the slot the "+N" is not on, which is not the case being reported.
        $dx = $script:lastSlotPoint.X - $st.RootRect[0]
        $dy = $script:lastSlotPoint.Y - $st.RootRect[1]
        Assert-That ("the click point ($($script:lastSlotPoint.X),$($script:lastSlotPoint.Y)) is INSIDE the `"$($qi.Text)`" box " +
                     "($($qi.Left),$($qi.Top),$($qi.Right),$($qi.Bottom)) -- this is the user's click") `
            ($dx -ge $qi.Left -and $dx -le $qi.Right -and $dy -ge $qi.Top -and $dy -le $qi.Bottom) `
            "(dialog-relative ($dx,$dy))"
        Shot 'last-slot-before-cancel'

        # THIS ARM TURNED GREEN WITH TASK 066, and green here is not "the race was won":
        # the race is REMOVED. The phantom bracket around queueLayout makes the engine lay
        # the owned slot out as OCCUPIED (enableControl, its own fields), so the disable
        # event that used to clear the player's PRESSED bit mid-click -- exactly once per
        # click, deterministically, PR #95's paired rows -- never fires at all. What makes
        # a single click assertable where 061's task file forbade it is that determinism:
        # pre-fix EVERY collided click failed (30 of 30) and every click collided exactly
        # once; post-fix the collision cannot occur, and the counters below prove WHICH
        # world this click ran in rather than trusting the outcome. The RATE arm
        # (-HoldSweepClicks) is still the acceptance measurement across hold durations.
        #
        # THE WIRE FIRST, and it is the whole diagnosis in one reading (AGENTS.md, task
        # 025): if no Cancel Train command leaves queueCommand, the click never became a
        # cancel at all. If one leaves and nothing is refunded, it became the WRONG cancel.
        # The helper asserts the command and its payload before it looks at a single
        # mineral.
        $r = Invoke-CancelAndMeasure -Tag 'last-slot-cancel' -ExpectPayload $STATQ_LAST_DISPLAY -Do {
            Send-ScClick -Hwnd $hwnd -X $script:lastSlotPoint.X -Y $script:lastSlotPoint.Y
        }
        # THE PLUGIN SERVED IT. The ring slot behind that icon is empty, so the engine's
        # own cancelBuildQueueSlot must never see this command -- it would refund by the
        # empty-slot sentinel 0xE4 (sc_prodqueue.cpp).
        $ev = @($r.Lines | Select-String -Pattern 'PRODQEV cancel-icon ')
        Assert-That "the plugin served it itself, exactly once ($($ev.Count))" ($ev.Count -eq 1)
        if ($ev.Count -eq 1) {
            Write-Host "       $($ev[0].Line.Trim())"
            Assert-That "naming display $STATQ_LAST_DISPLAY, one of its OWN overflow items, refunded at $PROBE_COST" `
                ($ev[0].Line -match "display=$STATQ_LAST_DISPLAY " -and
                 $ev[0].Line -match '-> overflow\[\d+\]' -and
                 $ev[0].Line -match "back=$PROBE_COST/0")
            Assert-That 'and it is not the "names an empty ring slot -- swallowed" branch' `
                ($ev[0].Line -notmatch 'swallowed')
        }
        $script:cancels++
        $script:pluginCancels++
        if ($r.Before.Selected.EngineLen -gt $ENGINE_HOLD) { $script:capturesFromCancel++ }
        Assert-That "the plugin's cancelled counter is now $script:pluginCancels ($($r.After.Cancelled))" `
            ($r.After.Cancelled -eq $script:pluginCancels)
        Assert-That "and its building-gone refund counter is still 0 ($($r.After.Refunded))" `
            ($r.After.Refunded -eq 0)
        Assert-That ("the OVERFLOW is what absorbed it ($($r.Before.Selected.Overflow) -> $($r.After.Selected.Overflow), " +
                     "ring $($r.Before.Selected.EngineLen) -> $($r.After.Selected.EngineLen))") `
            ($r.After.Selected.EngineLen + $r.After.Selected.Overflow -eq
             $r.Before.Selected.Logical - 1 - $r.Completed)
        # The later "minerals are UNCHANGED across the whole drain" assertion is written
        # against this, so it has to move with every cancel that spends or refunds.
        $script:mineralsAfterBurst = $r.After.Selected.Minerals
        # AND IT PASSED FOR THE RIGHT REASON (task 066). A green wire assertion alone
        # cannot separate "the fix removed the collision" from "the click won the race the
        # collision creates" -- 061 measured that race flipping in both directions. So the
        # arm requires the fix's own signature, both halves:
        #
        #   * `phantom` MOVED across the click: the bracket was actively making the slot
        #     occupied for queueLayout while the strip was up. A green with phantom +0
        #     means the fix never ran and this arm is guarding nothing.
        #   * `disableOnOwned` DID NOT MOVE: pre-fix, every fill provoked exactly one
        #     disable (1153974 = 1153974) and every click collided exactly once,
        #     deterministically (PR #95). +0 here is therefore a POSITIVE reading -- the
        #     fight is gone -- and any movement is the fight back, red, whatever the wire
        #     said.
        $qiAfter = Get-QInd 'last-slot-after'
        Write-Host "       $($qiAfter.Line)"
        $dOwned   = $qiAfter.DisableOnOwned - $qi.DisableOnOwned
        $dPress   = $qiAfter.DisableWithPress - $qi.DisableWithPress
        $dPhantom = $qiAfter.Phantom - $qi.Phantom
        Write-Host ("       across the click: phantom +$dPhantom, disableOnOwned +$dOwned, disableWithPress +$dPress " +
                    "(owned $($qi.Owned) -> $($qiAfter.Owned), phantomDirty $($qiAfter.PhantomDirty))")
        Assert-That 'the plugin reported the fix counters at all' `
            ($qi.Phantom -ge 0 -and $qi.DisableOnOwned -ge 0) `
            '(-1 = the field was not on the QIND line, which is a different fact from 0 and must not pass as one)'
        Assert-That "the phantom bracket was ACTIVE across this click (phantom +$dPhantom)" `
            ($dPhantom -gt 0) `
            '(+0 = the fix never ran during the click window, so this green would be the race won, not the fix working)'
        Assert-That "and the engine never disabled a slot we own (disableOnOwned +$dOwned)" `
            ($dOwned -eq 0) `
            '(pre-fix this moved EXACTLY once per click, deterministically -- any movement is the fight back)'
        Assert-That "and no phantom write ever found a non-empty slot (phantomDirty=$($qiAfter.PhantomDirty))" `
            ($qiAfter.PhantomDirty -eq 0) `
            '(non-zero = the rebalance invariant broke somewhere -- the bracket refused rather than overwrote, but the refusal must be investigated)'
        Assert-Reconciles 'after-last-slot-cancel' $r.After -Accepted $script:accepted -Cancelled $script:cancels
        Shot 'last-slot-cancelled'
    }

    Step 'ONE GAME THREAD: the claim the phantom bracket rests on, measured in this run' {
        # The bracket's safety argument is "every engine reader of the ring runs on the
        # game thread" (research/production-queue.md 8.8). Each hooked site logs its
        # thread id once (THREADCHECK), and a CHANGED suffix if it ever moves -- so the
        # claim is a reading here, not an assumption. By this point in the run all six
        # game-side sites have fired (the cancel arm above was the last), and the
        # observer -- the thread the seqlock exists FOR -- must be a DIFFERENT id.
        $tc = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'THREADCHECK (\S+) tid=(\d+)')
        foreach ($l in $tc) { Write-Host "       $($l.Line.Trim())" }
        $sites = @{}
        foreach ($l in $tc) {
            $m = [regex]::Match($l.Line, 'THREADCHECK (\S+) tid=(\d+)')
            if ($m.Success) { $sites[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
        }
        $gameSites = @('qind-driver', 'qind-layout', 'qind-interact',
                       'prodq-train', 'prodq-tick', 'prodq-cancel')
        $present = @($gameSites | Where-Object { $sites.ContainsKey($_) })
        Assert-That "all six game-side sites reported a thread id ($($present.Count))" `
            ($present.Count -eq $gameSites.Count)
        $gameTids = @($present | ForEach-Object { $sites[$_] } | Select-Object -Unique)
        Assert-That "and they are ONE thread ($($gameTids -join ','))" ($gameTids.Count -eq 1)
        Assert-That 'the observer reported its own id' ($sites.ContainsKey('prodq-observer'))
        if ($sites.ContainsKey('prodq-observer') -and $gameTids.Count -eq 1) {
            Assert-That "and it is a DIFFERENT thread ($($sites['prodq-observer']) vs $($gameTids[0])) -- the one the seqlock exists for" `
                ($sites['prodq-observer'] -ne $gameTids[0])
        }
        Assert-That 'no site ever changed thread mid-run' `
            (@(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'THREADCHECK .* CHANGED').Count -eq 0) `
            '(a CHANGED line is the single-thread claim breaking underneath the fix)'
    }

    if ($HoldSweepClicks -gt 0) {
      Step "RATE ARM: how often does the last slot cancel, by how long the button is held" {
        Write-Host '       *** MEASUREMENT RUN. Every step after this one has its counts perturbed by'
        Write-Host '       *** these extra clicks and its verdict does NOT apply. Read the table, not the tail.'
        $durations = @($HoldSweepMs -split ',' | ForEach-Object { [int]$_.Trim() } | Where-Object { $_ -gt 0 })
        $rows = @()
        foreach ($hold in $durations) {
            $ok = 0; $tried = 0; $collided = 0
            for ($i = 0; $i -lt $HoldSweepClicks; $i++) {
                # TOP THE QUEUE BACK UP FIRST. Every cancel that lands removes the item
                # behind the slot, and a click at a slot with nothing behind it measures
                # nothing -- the plugin swallows it and no command goes out for a reason
                # that has nothing to do with the race.
                $q = Get-ProdQueue "sweep-$hold-$i-pre"
                $guard = 0
                while ($q.Selected -and $q.Selected.Overflow -lt 2 -and $guard -lt 6) {
                    Send-ScClick -Hwnd $hwnd -X $script:trainPoint.X -Y $script:trainPoint.Y -SettleMs 150
                    $script:accepted++
                    $q = Get-ProdQueue "sweep-$hold-$i-top"
                    $guard++
                }
                if (-not $q.Selected -or $q.Selected.Overflow -lt 1) {
                    Write-Host "       hold $($hold)ms click $($i): SKIPPED, could not get an item behind the slot (overflow $($q.Selected.Overflow))"
                    continue
                }
                $st = Get-StatusQueue "sweep-$hold-$i"
                $slot = @($st.Slots | Where-Object { $_.Display -eq $STATQ_LAST_DISPLAY })[0]
                if (-not $slot -or $slot.QueueType -ne 0xE4) {
                    Write-Host "       hold $($hold)ms click $($i): SKIPPED, the ring holds that slot (qtype=0x$('{0:x}' -f $slot.QueueType))"
                    continue
                }
                $p  = Get-ScStatusSlotPoint -Status $st -Display $STATQ_LAST_DISPLAY
                $qb = Get-QInd "sweep-$hold-$i-b"
                $mark = Get-ScLogLineCount -LogPath $LogPath
                Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -HoldMs $hold -SettleMs 400
                Start-Sleep -Milliseconds 900
                $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
                # Get-QInd, NOT Get-QIndAfter. The `-After` form takes a line some OTHER
                # marker caused the observer to write, and nothing in this loop asks for
                # one -- so it waited 20s for a line that was never going to appear and
                # threw the whole step away. Asking for our own marker costs a round trip
                # per click and always has an answer.
                $qa = Get-QInd "sweep-$hold-$i-a"
                $tried++
                # PAIRED PER CLICK, not summed per duration. The first version of this
                # printed only the two totals, and "the one click that cancelled is the one
                # click with no collision" was then inference from two aggregates agreeing
                # -- the same shape as the single-sample conclusions this task spent a
                # morning retracting. One row per click makes the anti-correlation a
                # measurement instead: the CLICK line carries its own verdict and its own
                # collision count, so a reader can pair them without trusting a summary.
                $didCancel = @($lines | Select-String -Pattern "CMD id=$CANCEL_CMD ").Count -gt 0
                $dCollide  = $qa.DisableWithPress - $qb.DisableWithPress
                if ($didCancel) { $ok++; $script:cancels++; $script:pluginCancels++ }
                if ($dCollide -gt 0) { $collided++ }
                Write-Host ("       CLICK holdMs={0} n={1} cancelled={2} collided={3} disableWithPress+={4} pressKept+={5}" -f
                            $hold, $i, ($didCancel ? 1 : 0), (($dCollide -gt 0) ? 1 : 0), $dCollide,
                            ($qa.PressKept - $qb.PressKept))
            }
            $rate = if ($tried -gt 0) { [math]::Round(100.0 * $ok / $tried) } else { -1 }
            $rows += [pscustomobject]@{ HoldMs = $hold; Clicks = $tried; Cancelled = $ok; Pct = $rate; Collided = $collided }
            Write-Host ("       hold {0,4}ms : {1}/{2} cancelled ({3}%), collision seen in {4}" -f $hold, $ok, $tried, $rate, $collided)
        }
        Write-Host '       --- RATE TABLE (the number a future run compares against) ---'
        foreach ($r in $rows) {
            Write-Host ("       RATE holdMs={0} clicks={1} cancelled={2} pct={3} collided={4}" -f
                        $r.HoldMs, $r.Clicks, $r.Cancelled, $r.Pct, $r.Collided)
        }
        # THE RATE IS ASSERTED NOW, and here is why that stopped being the made-up
        # threshold 061 refused to invent (task 066):
        #
        #   * The baseline exists. PR #95 measured the pre-fix rate: 0 of 18 above a 60ms
        #     hold, 30 of 30 collided clicks failed, and every click collided exactly
        #     once. The user lives at long holds; that is where the defect was absolute.
        #   * The fix claims DETERMINISM, not luck: with the phantom bracket in place no
        #     disable event exists to lose a race against, so every click that reaches the
        #     slot must cancel, at every hold. 100% is the mechanism's own prediction, and
        #     asserting less would be tolerating the race this fix claims to have removed.
        #     A miss here is a real finding -- report it, never widen the threshold.
        #
        # The collided column is the same claim from the other side: pre-fix it read one
        # per click, deterministically; the bracket leaves nothing to collide with.
        $measured = @($rows | Where-Object { $_.Clicks -gt 0 })
        Assert-That "the sweep actually clicked: $($measured.Count) of $($durations.Count) durations got real clicks" `
            ($measured.Count -eq $durations.Count) `
            '(a duration with 0 clicks measured nothing -- its row is not a rate)'
        Write-Host '       PR #95 pre-fix baseline for this table: 0 of 18 cancelled above a 60ms hold; every click collided exactly once.'
        foreach ($r in $measured) {
            Assert-That "hold $($r.HoldMs)ms: every click cancelled ($($r.Cancelled)/$($r.Clicks))" `
                ($r.Cancelled -eq $r.Clicks) `
                '(the fix is deterministic or it is not the fix -- a miss is a finding, not noise)'
        }
        Assert-That "and no click collided with a disable across the whole sweep ($(($rows | Measure-Object Collided -Sum).Sum))" `
            ((($rows | Measure-Object Collided -Sum).Sum) -eq 0) `
            '(pre-fix: exactly one collision per click; any here means the bracket is not holding)'
      }
    }

    Step "watch it drain: every over-cap item is promoted into a freed slot, in order" -SweepPerturbed {
        $deadline = (Get-Date).AddSeconds($DrainTimeoutSec)
        $seen = @()
        while ((Get-Date) -lt $deadline) {
            $q = Get-ProdQueue 'drain'
            if ($q.Selected) {
                $seen += "logical=$($q.Selected.Logical) engineLen=$($q.Selected.EngineLen) overflow=$($q.Selected.Overflow)"
                # WHILE the plugin is still holding something, the ring must never fall
                # below the hold. A slot that sat empty for a whole marker would mean the
                # plugin skipped a promotion, which is the defect this asserts against.
                # It may be at five rather than four -- that is the state the cap leaves
                # it in -- so the bound is `at least`, not `exactly`.
                if ($q.Selected.Overflow -gt 0) {
                    Assert-That "while $($q.Selected.Overflow) are held, the ring stays at $ENGINE_HOLD or more ($($q.Selected.EngineLen))" `
                        ($q.Selected.EngineLen -ge $ENGINE_HOLD)
                }
            }
            # WAIT FOR THE WHOLE LOGICAL QUEUE, not just for the plugin's part of it. The
            # plugin empties four items before the end -- it hands its last one over while
            # four are still building -- so exiting on "the plugin is done" would walk
            # straight into the next step with half the units not yet made.
            if ($q.Buildings -eq 0 -and $q.Selected -and $q.Selected.Logical -eq 0) { break }
            # 2s, not 5. This is a DETECTION loop, not a measurement window: every pass
            # takes a fresh PRODQ reading and re-asserts the ring invariant, so polling
            # more often strictly adds evidence and only costs a marker round trip. At the
            # old 5s the drain's tail was mostly waiting for the next look, which matters
            # once the builds themselves are seconds rather than tens of seconds
            # (task 031, -ProbeBuildSeconds).
            Start-Sleep -Seconds 2
        }
        Write-Host "       $($seen -join ' -> ')"

        $q = Get-ProdQueue 'drained'
        # THE CONSERVATION LAW FOR THE PLUGIN'S OWN LIST, which is what "no item was lost"
        # means on its side: everything it ever took back it either handed over or
        # cancelled. `captured` is NOT `-QueueMax - 5` any more once a cancel has
        # happened -- the cancel frees room under the cap, so the next rebalance takes one
        # more item back out of the ring and the plugin ends up holding the same four
        # again. Measured: captured 5, promoted 4, cancelled 1. Writing the expectation as
        # a literal would have hidden that; writing it as the law makes it visible.
        $expectPromoted = $q.Captured - $q.Cancelled
        Assert-That "everything the plugin captured was promoted or cancelled: $($q.Captured) - $($q.Cancelled) = $($q.Promoted)" `
            ($q.Promoted -eq $expectPromoted)
        # A CANCEL DOES NOT ALWAYS MAKE ROOM, and writing that it does was a coincidence of
        # having exactly one cancel in this phase (task 061). This used to read
        # `captured == expectOverflow + cancels`, which held for the plugin-cancel arm and
        # failed the moment a second plugin-served cancel was added: measured, captured 5
        # with 2 cancels where that formula wanted 6.
        #
        # The reason is the RING, not the cancel. The plugin takes an item back only when
        # the ring is ABOVE its hold; the first cancel happened while the ring was full at
        # five, so the next rebalance pulled one out and `captured` went up. The second
        # happened with the ring already at four, so there was nothing to pull. So the
        # expectation is counted from the state each cancel was actually made in --
        # `$script:capturesFromCancel`, incremented by the arms themselves -- rather than
        # from how many cancels there were.
        Assert-That ("and it captured one more for each cancel made while the ring was still above the hold: " +
                     "$expectOverflow + $script:capturesFromCancel = $($q.Captured)") `
            ($q.Captured -eq $expectOverflow + $script:capturesFromCancel)
        Assert-That 'the plugin is holding nothing any more' ($q.Buildings -eq 0)
        Assert-That 'and nothing was refunded for a lost building -- no item vanished' ($q.Refunded -eq 0)
        Assert-That "the cancel counter is still exactly $script:cancels -- nothing cancelled itself" `
            ($q.Cancelled -eq $script:cancels)

        # PER ITEM. One promote line each, naming the type and the slot it went into. A
        # single line saying "3 promoted" would not distinguish three promotions from one
        # promotion counted three times.
        $ev = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODQEV promote ')
        Assert-That "exactly $expectPromoted promote events ($($ev.Count))" ($ev.Count -eq $expectPromoted)
        for ($i = 0; $i -lt $ev.Count; $i++) {
            $m = [regex]::Match($ev[$i].Line, 'type=0x([0-9A-Fa-f]+) -> slot=(\d+) overflowLeft=(\d+)')
            $okType = $m.Success -and [Convert]::ToInt32($m.Groups[1].Value, 16) -eq $PROBE_TYPE
            $okSlot = $m.Success -and [int]$m.Groups[2].Value -ge 0 -and [int]$m.Groups[2].Value -lt $ENGINE_SLOTS
            Assert-That ("promotion {0}: a Probe into a real slot" -f ($i + 1)) `
                ($okType -and $okSlot) "($($ev[$i].Line.Trim()))"
        }

        # THE COUNT ITSELF, asserted across EVERY event that moves it rather than against a
        # per-promotion literal. The old form expected promotion i to leave
        # `expectPromoted - 1 - i` behind, which silently assumed promotions are the only
        # thing that changes the plugin's list. They are not: a CANCEL removes an item and a
        # HOLD adds one, and with two cancels in this phase the sequence stopped matching --
        # a real ordering the run does not guarantee, encoded as arithmetic (task 061).
        #
        # So walk all four event kinds in the order the plugin logged them and require each
        # to move its own reported count by exactly one, in the right direction. That is
        # strictly stronger than the old check -- it covers the cancels and the captures too
        # -- and it cannot be broken by adding an arm.
        $moves = @(Get-Content -LiteralPath $LogPath |
                   Select-String -Pattern 'PRODQEV (promote|hold|cancel-last|cancel-icon) ')
        $running = $null
        $bad = @()
        foreach ($line in $moves) {
            $kind = [regex]::Match($line.Line, 'PRODQEV (\w[\w-]*) ').Groups[1].Value
            $n = if ($kind -eq 'hold') {
                     [regex]::Match($line.Line, ' overflow=(\d+)').Groups[1].Value
                 } else {
                     [regex]::Match($line.Line, ' overflowLeft=(\d+)').Groups[1].Value
                 }
            if ($n -eq '') { $bad += "unparsed: $($line.Line.Trim())"; continue }
            $n = [int]$n
            $want = if ($null -eq $running) { $n } elseif ($kind -eq 'hold') { $running + 1 } else { $running - 1 }
            if ($n -ne $want) { $bad += "$kind left $n, expected $want ($($line.Line.Trim()))" }
            $running = $n
        }
        Assert-That "every one of the $($moves.Count) events that moves the plugin's list moved it by exactly one" `
            ($moves.Count -gt 0 -and $bad.Count -eq 0) `
            ($bad.Count -gt 0 ? "(first: $($bad[0]))" : '(no PRODQEV move events found at all -- the walk was blind)')
        Assert-That "and the last one left it empty ($running)" ($running -eq 0)
    }

    Step 'every surviving item became a unit, and not one was paid for twice' -SweepPerturbed {
        $expectBuilt = $QueueMax - $script:cancels
        $w = Get-World 'built'
        $probes = @($w.Units | Where-Object { $_.Type -eq $PROBE_TYPE -and $_.Player -eq 0 })
        Assert-That "player 0 owns $expectBuilt Probes -- every queued item that was not cancelled became a unit ($($probes.Count))" `
            ($probes.Count -eq $expectBuilt)
        Assert-That 'both Nexuses are still there' `
            (@($w.Units | Where-Object { $_.Type -eq $NEXUS_TYPE -and $_.Player -eq 0 }).Count -eq 2)
        Assert-That 'the world scan was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)

        $q = Get-ProdQueue 'final'
        Assert-That 'the queue is empty in the building own memory too' `
            ($null -ne $q.Selected -and $q.Selected.EngineLen -eq 0 -and $q.Selected.Logical -eq 0) `
            "($(($q.Lines | Where-Object { $_ -match 'PRODQSEL' } | Select-Object -First 1)))"
        # THE PAY-ONCE ASSERTION. Promotion moves no money, so the balance must be exactly
        # what it was after the cancel -- three promotions later. A second payment would
        # show as a drop of 3 x 50 here and nowhere else.
        if ($q.Selected) {
            Assert-That "minerals are UNCHANGED across the whole drain ($($q.Selected.Minerals))" `
                ($q.Selected.Minerals -eq $script:mineralsAfterBurst) `
                "(was $script:mineralsAfterBurst after the cancel)"
        }
        Assert-That "and still exactly $StartingMinerals - ($QueueMax - $script:cancels) x $PROBE_COST" `
            ($null -ne $q.Selected -and
             $q.Selected.Minerals -eq ($StartingMinerals - ($QueueMax - $script:cancels) * $PROBE_COST))
        Assert-Reconciles 'drained' $q -Accepted $script:accepted -Cancelled $script:cancels
        Shot 'built'
    }

    # ---------------------------------------------------------------------------
    # TASK 028: the OTHER cancel -- an item inside the ENGINE's own ring, cancelled
    # through the control vanilla actually gives the player for it
    # ---------------------------------------------------------------------------
    Step 'AND IT GOES AWAY: an empty queue puts the indicator back out of sight' -SweepPerturbed {
        # The other half of criterion 3, and the half a "does it appear" test cannot give
        # you: with the logical queue drained there is nothing the strip cannot show, so the
        # engine's visible bit must be OFF our control again and the module must say it is
        # showing nothing. The control stays LINKED on purpose -- it is ours, hiding it is
        # one flag write, and re-splicing it every time a queue empties would be churn.
        $qi = Get-QInd 'drained'
        Write-Host "       $($qi.Line)"
        Assert-That "the building's logical queue really is empty ($($qi.EngineLen) + $($qi.Overflow))" `
            ($qi.EngineLen + $qi.Overflow -eq 0)
        Assert-That 'the indicator reports itself showing nothing (mode 0)' ($qi.Mode -eq 0)
        Assert-That "and the engine's visible bit is CLEAR on the control" (-not $qi.Visible)
        # 'HIDDEN' HAS TO BE A READING RATHER THAN A BLIND SPOT, and the number that says so
        # here is surfInk, not refInk. This is precisely the state in which refInk has no
        # answer: the queue is empty, so the strip's icons are down, and one building is
        # selected, so the wireframe row is down too -- neither candidate is visible and
        # refInk is -1 ON PURPOSE. The old assertion demanded a number the pane cannot
        # produce, and the fix for that is NOT to let refInk fall back to a control nobody
        # can see. surfInk counts the whole surface, which the pane's own art always covers.
        Assert-That "the probe can still read the surface, so 'hidden' is a reading and not a blind spot (surfInk=$($qi.SurfInk))" `
            ($qi.SurfInk -gt 0)
    }

    Step "queue $EngineArmQueue more, so the plugin holds NOTHING and the ring is the whole queue" -SweepPerturbed {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        for ($i = 1; $i -le $EngineArmQueue; $i++) {
            Send-ScClick -Hwnd $hwnd -X $script:trainPoint.X -Y $script:trainPoint.Y -SettleMs 120
        }
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $sent = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ").Count
        Assert-That "$EngineArmQueue Train commands went out ($sent)" ($sent -eq $EngineArmQueue)
        $script:accepted += $sent

        $q = Get-ProdQueue 'engine-arm-queued'
        Assert-That "the ring holds all $EngineArmQueue of them ($($q.Selected.EngineLen))" `
            ($q.Selected.EngineLen -eq $EngineArmQueue)
        # THE PRECONDITION that makes this arm the ENGINE's case: below the hold, the
        # plugin takes nothing back, so there is no overflow for it to serve a cancel from
        # and the command must pass straight through to the engine's own handler.
        Assert-That 'and the plugin is holding nothing at all' `
            ($q.Selected.Overflow -eq 0 -and $q.Buildings -eq 0)
        $script:cancelledBeforeEngineArm = $q.Cancelled
    }

    Step 'READ the status pane again: only the queued icons can be clicked' -SweepPerturbed {
        $st = Get-StatusQueue 'strip-partial'
        Assert-That 'the status-strip read-back answered' ($st.Ok)
        Assert-That "it still holds $STATQ_SLOTS icon controls ($($st.Slots.Count))" `
            ($st.Slots.Count -eq $STATQ_SLOTS)
        # THE OTHER DIRECTION of the earlier reading, on the same walk: with three queued
        # instead of five, exactly three icons are clickable and the other two are GREYED
        # by the layout's own 0x00418640 call. An oracle that always said "clickable"
        # passed the first reading and fails here.
        Assert-That "exactly $EngineArmQueue icons are clickable ($($st.Clickable))" `
            ($st.Clickable -eq $EngineArmQueue)
        $empties = @($st.Slots | Where-Object { $_.Display -ge $EngineArmQueue })
        Assert-That "and the other $($empties.Count) are GREYED, with empty ring slots behind them" `
            (@($empties | Where-Object { -not $_.Disabled -or $_.QueueType -ne 0xE4 }).Count -eq 0) `
            "($(($empties | ForEach-Object { "disp$($_.Display)=$($_.State)/0x$('{0:x}' -f $_.QueueType)" }) -join ' '))"

        $target = @($st.Slots | Where-Object Display -eq $EngineArmDisplay)[0]
        Assert-That "display $EngineArmDisplay is an enabled icon drawing a Probe" `
            ($null -ne $target -and -not $target.Disabled -and $target.UType -eq $PROBE_TYPE -and
             $target.QueueType -eq $PROBE_TYPE) `
            "(state $($target.State) uicon=0x$('{0:x}' -f $target.UIcon) qtype=0x$('{0:x}' -f $target.QueueType))"
        Assert-That "and its control id is $($EngineArmDisplay + $STATQ_FIRST_CONTROL), the id whose click sends payload $EngineArmDisplay" `
            ($target.Index -eq $EngineArmDisplay + $STATQ_FIRST_CONTROL)
        $script:iconPoint = Get-ScStatusSlotPoint -Status $st -Display $EngineArmDisplay
        Write-Host "       queue icon $EngineArmDisplay -> client ($($script:iconPoint.X),$($script:iconPoint.Y))"
    }

    Step "CANCEL AN ITEM IN THE ENGINE'S RING -- the vanilla control, the engine's refund" -SweepPerturbed {
        # The payload here is the DISPLAY INDEX of the icon clicked, not 0xFE -- that one
        # byte is the whole difference between the two cases, and the helper asserts it on
        # the wire before any refund number is read.
        $r = Invoke-CancelAndMeasure -Tag 'engine-cancel' -ExpectPayload $EngineArmDisplay -Do {
            Send-ScClick -Hwnd $hwnd -X $script:iconPoint.X -Y $script:iconPoint.Y
        }
        # THE ENGINE DID IT, NOT THE PLUGIN. The ring itself is one shorter, read from
        # CUnit+0x98, and the plugin's cancel counter has not moved -- so this refund came
        # out of the engine's cancelBuildQueueSlot and the plugin passed the command
        # through, which is the behaviour the two-case design claims.
        Assert-That "the engine's own ring is one shorter ($($r.Before.Selected.EngineLen) -> $($r.After.Selected.EngineLen))" `
            ($r.After.Selected.EngineLen -eq $r.Before.Selected.EngineLen - 1 - $r.Completed)
        Assert-That "the plugin's cancel counter did NOT move ($($r.After.Cancelled))" `
            ($r.After.Cancelled -eq $script:cancelledBeforeEngineArm)
        Assert-That 'and the plugin never consumed a cancel this arm' `
            (@($r.Lines | Select-String -Pattern 'PRODQEV cancel-last ').Count -eq 0)
        Assert-That 'the plugin is still holding nothing' `
            ($r.After.Selected.Overflow -eq 0 -and $r.After.Buildings -eq 0)
        # PER ITEM on the engine's side: every slot still occupied holds a Probe, and the
        # compaction the engine does on cancel left no hole behind the head.
        $left = @($r.After.Selected.Engine | Where-Object { $_ -ne 0xE4 })
        Assert-That "the $($left.Count) slot(s) still occupied all hold Probes" `
            (@($left | Where-Object { $_ -ne $PROBE_TYPE }).Count -eq 0) `
            "($(($r.After.Selected.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))"
        $script:cancels++
        Assert-Reconciles 'after-engine-cancel' $r.After -Accepted $script:accepted -Cancelled $script:cancels
        Shot 'engine-cancelled'
    }

    Step 'and the strip agrees afterwards: one fewer icon can be clicked' -SweepPerturbed {
        # RE-READ ON MISMATCH, bounded. There is a real one-frame window here that is not
        # a defect: productionTick clears a ring slot the instant a unit completes, and
        # the icon's flags are re-greyed by the NEXT queueLayout pass -- so an async walk
        # landing between the two reads flags one layout behind the ring (run 2 measured
        # exactly that: clickable 2 vs engineLen 1, with the plugin holding nothing, one
        # completion inside the sample). The player never sees that state (the pane is
        # rendered after the layout). Two consecutive agreeing reads is the assertion;
        # three disagreements in a row is a real desynchronisation and fails with both
        # numbers printed.
        $st = $null; $q = $null
        for ($try = 0; $try -lt 3; $try++) {
            $st = Get-StatusQueue 'strip-after-cancel'
            $q = Get-ProdQueue 'after-engine-cancel'
            if ($st.Clickable -eq $q.Selected.EngineLen) { break }
            Write-Host ("       (clickable $($st.Clickable) vs engineLen $($q.Selected.EngineLen) -- " +
                        're-reading: a completion between the tick and the next layout leaves the flags one pass behind)')
        }
        Assert-That "the clickable icons now match the ring exactly ($($st.Clickable) vs engineLen $($q.Selected.EngineLen))" `
            ($st.Clickable -eq $q.Selected.EngineLen)
    }

    # ---------------------------------------------------------------------------
    # TASK 028: the same read on a TERRAN producer, whose slot 9 is SHARED between
    # Lift Off and Cancel. Which one is drawn is a claim about a dialog, so it is
    # READ -- and the first (static) reading of the button table got it wrong.
    # ---------------------------------------------------------------------------
    Step 'a Command Center: slot 9 holds Lift Off when idle and Cancel when training' {
        $w = Get-World 'cc-aim'
        $cc = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $CC_TYPE })[0]
        $cx = if ($cc) { $cc.X - $w.Screen.Left } else { -1 }
        $cy = if ($cc) { $cc.Y - $w.Screen.Top } else { -1 }
        $onScreen = ($null -ne $cc -and $cx -ge 0 -and $cx -lt 630 -and $cy -ge 0 -and $cy -lt 340)
        Write-Host "       Command Center at client ($cx,$cy) -- on screen: $onScreen"
        if (-not $onScreen) {
            # A definite outcome either way: this arm never silently disappears. The
            # static half stands on its own (buttonset 106 is in the binary), and the
            # acceptance criteria do not rest on it.
            Skip-That 'the Command Center is off the opening viewport, so this arm is not measured' `
                "(client $cx,$cy -- the claim about Terran cards stays static-only for this run)"
            return
        }
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2
        $q = Get-ProdQueue 'cc-selected'
        Assert-That "the Command Center is the selected building (type 0x$('{0:x}' -f $q.Selected.Type))" `
            ($null -ne $q.Selected -and $q.Selected.Type -eq $CC_TYPE)

        $card = Get-Card 'cc-card-idle'
        $train = Get-ScCardSlot -Card $card -Slot $TRAIN_SLOT
        Assert-That "its card resolves to buttonset $CC_TYPE ($($card.CardId))" ($card.CardId -eq $CC_TYPE)
        Assert-That "slot $TRAIN_SLOT is Train SCV (act 0x$($train.Action), aparam $($train.ActParam))" `
            ($train.HasButton -and $train.Action -eq $TRAIN_ACT -and $train.ActParam -eq 7)
        # THE FIRST HALF OF THE PAIR, while the queue is empty: slot 9 belongs to LIFT OFF
        # (button 0x00517FC4, cond 0x004287D0, act 0x00423230), which sorts ahead of the
        # Cancel button in this buttonset and therefore hides it.
        $idle9 = Get-ScCardSlot -Card $card -Slot $CANCEL_SLOT
        Write-Host ("       idle: slot 9 state={0} act=0x{1} aparam={2} icon=0x{3:x}" -f
                    $idle9.State, $idle9.Action, $idle9.ActParam, $idle9.Icon)
        Assert-That 'with an empty queue slot 9 is Lift Off, not Cancel' `
            ($idle9.HasButton -and $idle9.Action -eq $LIFTOFF_ACT)
        $p = Get-ScCardSlotPoint -Card $card -Slot $TRAIN_SLOT
        Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y
        Start-Sleep -Seconds 2

        $q = Get-ProdQueue 'cc-queued'
        Assert-That "the Command Center now has something queued ($($q.Selected.EngineLen))" `
            ($q.Selected.EngineLen -ge 1)
        # THE SECOND HALF OF THE PAIR, and the point of the arm: the two conditions are
        # complementary. Lift Off's (0x004287D0) requires the "is this building busy"
        # helper 0x00401500 to return 0, and that helper returns 1 exactly when the head
        # slot holds a real type -- which is exactly when the Cancel button's own
        # condition (0x00428530) is true. So the same control swaps from one to the other
        # the moment anything is queued, and the Cancel button IS reachable on a Terran
        # producer, at precisely the times it would be useful.
        $card = Get-Card 'cc-card-queued'
        $slot9 = Get-ScCardSlot -Card $card -Slot $CANCEL_SLOT
        Write-Host ("       training: slot 9 state={0} act=0x{1} aparam={2} icon=0x{3:x}" -f
                    $slot9.State, $slot9.Action, $slot9.ActParam, $slot9.Icon)
        Assert-That 'with something queued the SAME control now holds the Cancel button' `
            ($slot9.HasButton -and $slot9.Action -eq $CANCEL_ACT -and $slot9.ActParam -eq $CANCEL_APARAM)
        Assert-That 'and it is the same control record, so this is one slot changing hands' `
            ($slot9.Control -eq $idle9.Control) "($($slot9.Control) vs $($idle9.Control))"
        Assert-That 'and it is enabled -- a Terran player really can press it' `
            ($slot9.Visible -and -not $slot9.Disabled) "(state $($slot9.State))"
        # And the strip is still the control that CAN address its queue, on this card too.
        $st = Get-StatusQueue 'cc-strip'
        Assert-That "its queue strip has $($q.Selected.EngineLen) clickable icon(s) ($($st.Clickable))" `
            ($st.Clickable -eq $q.Selected.EngineLen)
    }

    Step 'the engine was never asked to do anything outside the production path' {
        $log = @(Get-Content -LiteralPath $LogPath)
        # Nothing here fans anything out -- the suite runs in hooktest mode, which installs
        # no selection hooks at all. Proved positively first: the mode line says hooktest,
        # so "no FANOUT lines" is a real absence and not a missing feature.
        # The COUNT is not pinned: task 033's indicator installs a second detour in this
        # mode when -QueueIndicator is on. What has to hold is the mode (so "no FANOUT
        # lines" below is a real absence) and that every hook the run wanted went in.
        $hookLine = @($log | Select-String -Pattern 'HOOK: (\d+)/(\d+) installed, mode=hooktest')
        Assert-That 'the run really was in hooktest mode' ($hookLine.Count -gt 0)
        if ($hookLine.Count -gt 0) {
            $hm = [regex]::Match($hookLine[-1].Line, 'HOOK: (\d+)/(\d+) installed')
            Assert-That "and every hook it wanted went in ($($hm.Groups[1].Value)/$($hm.Groups[2].Value))" `
                ($hm.Groups[1].Value -eq $hm.Groups[2].Value)
        }
        Assert-That 'and nothing was fanned out' `
            (@($log | Select-String -Pattern 'FANOUT start:').Count -eq 0)
        Assert-That 'no hook rolled back at any point' `
            (@($log | Select-String -Pattern 'ROLLING BACK').Count -eq 0)
        $stats = @($log | Select-String -Pattern 'PRODQSTATS ')
        if ($stats.Count -gt 0) { Write-Host "       $($stats[-1].Line.Trim())" }
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
        catch {
            Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"
            $failures++
        }
        Start-Sleep -Seconds 2
    }
    elseif (-not $KeepOpen) {
        Write-Host '  FAIL no pid was ever parsed, so nothing could be closed'
        $failures++
    }
    if (-not $KeepOpen) { Remove-ScOwnFixture -Run $fixtures }
    Remove-ScOwnFixtureDir -Dir $mapDir
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock; $launchLock = $null }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

# THE DETACH-TIME REFUND. The plugin gives back anything it is still holding before it
# un-splices, so a run can never end with the player short. By this point it is holding
# nothing, so the honest assertion is that spend and refund agree with the queue.
$statLine = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern 'PRODQSTATS ')
if ($statLine.Count -gt 0) {
    $m = [regex]::Match($statLine[-1].Line,
        'captured=(\d+) promoted=(\d+) cancelled=(\d+) refunded=(\d+)(?:\s+\w+=\S+)*\s+refusedFull=(\d+) mineralsRefunded=(\d+)')
    if ($m.Success) {
        $cancelled = [int]$m.Groups[3].Value
        $refunded  = [int]$m.Groups[4].Value
        $back = [int]$m.Groups[6].Value
        # "the plugin spent NOTHING of its own" was asserted here from mineralsSpent.
        # Deleted with the counter (issue #66, task 055). The pay-once claim is carried by
        # the engine's own balance -- asserted exactly at the burst and asserted UNCHANGED
        # across the drain -- which is where a plugin that also paid would show up.
        # THE REFUND, ONCE. The plugin served exactly the cancels that were its own, and
        # gave back exactly one unit's cost for each. This is the counter that would read
        # 2 x 50 on a double refund and 0 on a swallowed item, and neither would show up
        # in the player's balance as anything but a number that still looked plausible.
        Assert-That "the plugin served exactly $script:pluginCancels cancel(s) of its own ($cancelled)" `
            ($cancelled -eq $script:pluginCancels)
        Assert-That "and refunded exactly $script:pluginCancels x $PROBE_COST minerals for them ($back)" `
            ($back -eq $script:pluginCancels * $PROBE_COST)
        # The engine's own cancel is NOT in these numbers, and that is the point: it never
        # reached the plugin's refund path at all.
        Assert-That 'nothing was refunded for a building that went away' ($refunded -eq 0)
    }
    else { Assert-That 'the detach stats line is parseable' $false "($($statLine[-1].Line))" }
}
else { Assert-That 'the plugin wrote its detach stats line' $false }

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
if ($script:skipped.Count -gt 0) {
    Write-Host "SKIPPED ($($script:skipped.Count)) -- a skipped check is NOT a passed check:"
    $script:skipped | ForEach-Object { Write-Host "  $_" }
}
Write-Host "test-production-queue: $failures failure(s), $($script:skipped.Count) skipped"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
