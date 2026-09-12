#Requires -Version 7
<#
.SYNOPSIS
The EPISODE bodies of the randomized conformance harness: what one generated action
sequence does to the game, and which invariant each assertion belongs to.

.DESCRIPTION
Dot-sourced by test-random-conformance.ps1 into the same scope, so these see the run's
handle, log path and pinned constants. The runner changes when the harness does; this
file changes when a FEATURE does.

Every assertion names its invariant, and every invariant's ground truth is stated where
it is read. The one exception is called out in place: the plugin's overflow count is its
own bookkeeping and appears only to compute headroom and to explain a number.
#>

# ---------------------------------------------------------------------------
# THE CORE EPISODE: press Train N times at a selection of K buildings, then ask the engine
# what happened. This is the user's own sentence, generalised over K.
# ---------------------------------------------------------------------------
function Invoke-QueueEpisode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ep,
        [Parameter(Mandatory)][string[]]$Units,
        [Parameter(Mandatory)][int]$Presses,
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)][int]$SelCount
    )

    # A drain episode needs EMPTY queues first: its claim ("what left the queue appeared in
    # the engine's unit list") is only checkable from a known starting count. The wait is
    # bounded and a timeout SKIPS rather than fails -- a busy queue is not a defect.
    if ($Ep.kind -eq 'queue-drain') {
        if (-not (Wait-QueuesEmpty -Units $Units -TimeoutSec 45)) {
            Write-Skip -Id 'INV-B' -Why 'the selected buildings would not drain to empty inside 45 s'
            return
        }
        $Before = Read-Engine -Tag "ep$($Ep.index)-drained" -Need @('prodq', 'prodfan', 'world')
    }

    $mineralsBefore = $Before.Minerals
    # COMPLETED only: a unit under construction is already linked into the player's list, so a
    # raw count answers "how many exist", and every claim here is about how many were BUILT.
    $scvBefore = Get-OwnedCount -Eng $Before -Type $SCV_TYPE -Completed
    # The same count WITHOUT the completion filter: the baseline for "a unit appeared", which
    # is what an item leaving a queue looks like from the engine's side.
    $scvRawBefore = Get-OwnedCount -Eng $Before -Type $SCV_TYPE
    $refusedFullBefore = $Before.RefusedFull
    $promotedBefore = $Before.Promoted
    $logicalBefore = @{}
    foreach ($u in $Units) { $logicalBefore[$u] = (Get-Logical -Eng $Before -Unit $u).Logical }

    # ---- press ------------------------------------------------------------
    # Through the card's own button, never the hotkey (Get-TrainPoint says why).
    $trainPt = Get-TrainPoint -Tag "ep$($Ep.index)"
    $mark = Get-ScLogMark
    Invoke-TrainPress -Times $Presses -Point $trainPt
    $fresh = @(Get-ScLogSince -Mark $mark)

    # ---- INV-W: the wire --------------------------------------------------
    # GROUND TRUTH: the detour on queueCommand (0x00485BD0). Every command this game sends
    # passes through it, so a press that produced no line here produced no command at all.
    # This is the assertion the unpatched client fails: with a group selected it stops
    # offering the Train button once each ring holds five, and presses six onward never
    # reach the funnel. One press is exactly ONE `CMD id=0x1F`: the fan-out's replayed
    # Select+Train pairs go out through the TRAMPOLINE and do not pass the logger again.
    $cmds = @($fresh | Select-String -Pattern "CMD id=$TRAIN_CMD ")
    $starts = @($fresh | Select-String -Pattern 'FANOUT start: cmd=0x1F')
    # ZERO IS A DIFFERENT CLAIM FROM "SOME". A burst in which NOT ONE press produced a command,
    # while the card showed an enabled Train button when we aimed, is this harness failing to
    # deliver input, not the game refusing it. Named apart from INV-W because under one shared
    # verdict a single lost input path reads as three episodes of "the feature is broken".
    if ($cmds.Count -eq 0 -and $Presses -gt 0 -and $trainPt) {
        Assert-Inv -Id 'INPUT' -What "the $Presses click(s) on the card's Train button reached the game at all (0 commands)" `
            -Ok $false `
            -Detail "(the button was enabled at ($($trainPt.X),$($trainPt.Y)) when this episode aimed; a total silence here is an input-delivery failure in the HARNESS, and the invariants below are not evidence about the game)"
    }
    Assert-Inv -Id 'INV-W' -What "all $Presses presses reached the engine's command funnel ($($cmds.Count))" `
        -Ok ($cmds.Count -eq $Presses) `
        -Detail "(selection of $SelCount; a count that stops at $ENGINE_SLOTS is the client refusing to send)"
    if ($SelCount -gt 1) {
        Assert-Inv -Id 'INV-W' -What "and every one was fanned out across the group ($($starts.Count))" `
            -Ok ($starts.Count -eq $cmds.Count)
    }

    $after = Read-Engine -Tag "ep$($Ep.index)-after" -Need @('prodq', 'prodfan', 'world', 'card')

    # ---- INV-R: each building's own ring ----------------------------------
    # GROUND TRUTH: CUnit+0x98 (head at +0xA4), read out of that building's memory.
    foreach ($u in $Units) {
        $row = @($after.Rows | Where-Object { $_.Unit -eq $u }) | Select-Object -First 1
        if (-not $row) {
            Assert-Inv -Id 'INV-R' -What "building 0x$u is still in the engine's reading" -Ok $false
            continue
        }
        $eng = ($row.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','
        Assert-Inv -Id 'INV-R' -What "0x$u's ring stays inside the engine's $ENGINE_SLOTS slots ($($row.EngineLen))" `
            -Ok ($row.EngineLen -le $ENGINE_SLOTS) -Detail "(engine=[$eng])"
        $occupied = @($row.Engine | Where-Object { $_ -ne $QUEUE_EMPTY })
        $bad = @($occupied | Where-Object { $_ -ne $SCV_TYPE })
        Assert-Inv -Id 'INV-R' -What "0x$u's ring holds only the type that was trained" `
            -Ok ($bad.Count -eq 0) -Detail "(engine=[$eng])"
    }

    # ---- INV-M: the money -------------------------------------------------
    # GROUND TRUTH: the engine's per-player mineral global. This is drain-proof -- a unit
    # completing shortens a queue but never un-spends a mineral -- so it holds whether or
    # not anything finished while the burst was going out.
    $refusals = $after.RefusedFull - $refusedFullBefore
    $expectItems = $Presses * $SelCount
    $paid = $mineralsBefore - $after.Minerals
    if ($refusals -eq 0) {
        Assert-Inv -Id 'INV-M' -What "the engine charged for every one of the $expectItems items: $expectItems x $SCV_COST = $($expectItems * $SCV_COST) ($paid)" `
            -Ok ($paid -eq $expectItems * $SCV_COST) `
            -Detail "(minerals $mineralsBefore -> $($after.Minerals))"
    } else {
        # A refusal is a legitimate engine answer, so it changes the expectation instead of
        # failing -- but it is REPORTED: a silent one turns every later number into a mystery.
        Note "$refusals command(s) were refused for a full ring (full=$($after.RefusedFull - $refusedFullBefore)); the charge is asserted as a bound, not an equality"
        Assert-Inv -Id 'INV-M' -What "the engine charged for no more than the $expectItems items asked for ($paid)" `
            -Ok ($paid -le $expectItems * $SCV_COST -and $paid -ge 0)
    }

    # ---- the logical queue, CROSS-CHECK ------------------------------------
    # The ring half is the engine's; the overflow half is the plugin's own bookkeeping. It is
    # asserted because a wrong number is still a bug, but it is labelled a cross-check and is
    # never the evidence for a claim about the game.
    #
    # Do not guard on `promoted`: a promotion moves an item between the plugin's overflow and
    # the engine's ring and leaves the LOGICAL count alone. What shrinks a queue is a unit
    # STARTING, and a deep queue does that every -UnitBuildTime seconds, burst or no burst --
    # a promotion guard fails by exactly one at random while INV-M stays exact to the mineral.
    $scvAfterBurst = Get-OwnedCount -Eng $after -Type $SCV_TYPE -Completed
    $completed = $scvAfterBurst - $scvBefore
    # Units of the type that APPEARED during the window, in any state of completion -- what
    # "left a queue" means to the engine (the floor bound below says why not `completed`).
    $left = (Get-OwnedCount -Eng $after -Type $SCV_TYPE) - $scvRawBefore
    $promoted = $after.Promoted - $promotedBefore
    $sumBefore = 0; foreach ($u in $Units) { $sumBefore += $logicalBefore[$u] }
    $sumAfter = 0; foreach ($u in $Units) { $sumAfter += (Get-Logical -Eng $after -Unit $u).Logical }
    $queued = $Presses * $SelCount
    if ($refusals -eq 0) {
        # The upper bound is absolute: nothing can add to a queue except the presses this
        # episode sent. The lower bound below is the loose one, and says why.
        Assert-Inv -Id 'INV-R' -What "the selected buildings gained no more than the $queued item(s) queued ($sumBefore -> $sumAfter)" `
            -Ok ($sumAfter -le $sumBefore + $queued) `
            -Detail "(promoted=$promoted; a promotion moves an item between the ring and the plugin and must not change this total)"
        # WHAT LEAVES A QUEUE IS A UNIT APPEARING, of the type, in ANY state of completion.
        # Do not use `completed`: the engine takes an item out of the ring the moment
        # production STARTS, so a one-press burst reads ring 0 with nothing built.
        # Do not use PRODFAN's `buildUnit`: measured `engineLen=0 buildState=0
        # buildUnit=0x00000000` while the WORLD scan held the missing item as an SCV with the
        # COMPLETED bit clear and hp=8466 of 15360. A plausible field is not a reading.
        # The unit list counts the WHOLE PLAYER (measured 10 -> 17 across an episode that
        # queued ONE item; unselected buildings drain throughout), so this is a lower bound:
        # an over-estimate of what left these queues is safe in a floor, fatal in an equality.
        $floor = $sumBefore + $queued - $left
        Assert-Inv -Id 'INV-R' -What "and lost no more than the $left unit(s) that appeared during the burst ($sumAfter >= $floor)" `
            -Ok ($sumAfter -ge $floor) `
            -Detail "(an item leaves a queue exactly when it appears in the engine's unit list, finished or not; $completed of those have finished)"
    }
    if ($left -eq 0 -and $refusals -eq 0) {
        # Nothing left any queue in this window, so the per-building numbers are exactly
        # predictable and are worth asserting one building at a time.
        foreach ($u in $Units) {
            $l = Get-Logical -Eng $after -Unit $u
            $want = $logicalBefore[$u] + $Presses
            Assert-Inv -Id 'INV-R' -What "0x$u holds $want item(s) after $Presses more (ring $($l.Ring) + plugin $($l.Overflow) = $($l.Logical)) [cross-check]" `
                -Ok ($l.Logical -eq $want)
        }
    } else {
        Note "$left unit(s) appeared ($completed of them finished) and $refusals command(s) were refused during the burst; the per-building split is not predictable (the engine's unit list does not say WHICH building made one), so the bounds above are asserted instead"
    }
    # This one holds either way: it is about where the ring is HELD, not how many items are
    # queued -- the whole mechanism is keeping the engine's ring below its cap so the client
    # never greys the button.
    #
    # It is also THE SEAM MEASUREMENT, taken off the engine AFTER the burst and never from the
    # planned press count: a refused press, a ring that never filled and a headroom clamp all
    # read as a reach in the plan and as no reach here -- the difference between what a run
    # intended and what it covered.
    $pastFive = 0
    foreach ($u in $Units) {
        $l = Get-Logical -Eng $after -Unit $u
        if ($l.Logical -gt $ENGINE_SLOTS) {
            $pastFive++
            Assert-Inv -Id 'INV-R' -What "0x$u went PAST the engine's $ENGINE_SLOTS, and its ring is held at $ENGINE_HOLD so the client keeps sending ($($l.Ring))" `
                -Ok ($l.Ring -eq $ENGINE_HOLD)
        }
    }
    # The seam is specifically the MULTI-BUILDING one: with one building selected the two
    # selection arrays agree and a plugin reading the wrong one behaves correctly.
    if ($SelCount -gt 1 -and $pastFive -gt 0) {
        $script:groupOverflowReached++
        Note "SEAM REACHED: $pastFive of $SelCount selected building(s) went past the engine's $ENGINE_SLOTS slots with a multi-building selection (task 038's seam)"
    }

    # ---- the card is still live -------------------------------------------
    # The client half of the design: the button never goes dark, so the next press still
    # reaches the wire. Read out of the dialog, never off a frame.
    if ($after.Card) {
        Assert-Inv -Id 'INV-W' -What 'the Train button is still drawn and enabled after the burst' `
            -Ok ($after.Card.State -eq 'enabled') -Detail "(state $($after.Card.State))"
    } else {
        Assert-Inv -Id 'INV-W' -What 'the Train button is still on the card after the burst' -Ok $false `
            -Detail "(card slots seen: $($after.CardSlots.Count))"
    }

    switch ($Ep.kind) {
        'queue-cancel' { Invoke-CancelByCard -Ep $Ep -After $after }
        'cancel-slot'  { Invoke-CancelBySlot -Ep $Ep -After $after }
        'queue-drain'  { Invoke-Drain -Ep $Ep -Units $Units -Expect ($Presses * $SelCount) -ScvBefore $scvBefore -MineralsAfterBurst $after.Minerals }
    }
}

# ---------------------------------------------------------------------------
# CANCEL, by the command card's Cancel button ({0x20,0xFE}, "the last queued item").
# The plugin owns the tail of a logical queue while it holds anything, so this is the one
# path on which the PLUGIN moves a resource -- and the refund is read back out of the
# engine's globals, not out of the plugin's counter.
# ---------------------------------------------------------------------------
# A unit the building FINISHES inside a cancel's window also leaves its queue. Its current
# build (CUnit+0xEC, PRODFAN buildUnit=) then names a different unit on the two sides of
# the window; cancelling the last item, or one the plugin holds, never changes it.
function Get-FinishedBetween {
    param($L0, $L1)
    [int]($L0.BuildUnit -and $L1.BuildUnit -and $L0.BuildUnit -ne '00000000' -and
          $L1.BuildUnit -ne '00000000' -and $L0.BuildUnit -ne $L1.BuildUnit)
}

function Invoke-CancelByCard {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Ep, [Parameter(Mandatory)]$After)

    # Cancel is single-gated in the engine and in the plugin alike, so it acts on one
    # building. Select the first member of whatever the engine says is selected.
    $w = Read-Engine -Tag "ep$($Ep.index)-cancel-aim" -Need @('world', 'prodfan')
    $unit = if ($After.Rows.Count -gt 0) { $After.Rows[0].Unit } else { $null }
    if (-not $unit) { Write-Skip -Id 'INV-M' -Why 'no building to cancel at'; return }
    $target = @($w.Units | Where-Object { $_.Unit -eq $unit }) | Select-Object -First 1
    if (-not $target) { Write-Skip -Id 'INV-M' -Why "building 0x$unit is not in the world scan"; return }
    if (-not (Select-ByClick -Target $target -World $w)) { Write-Skip -Id 'INV-M' -Why 'could not click the building'; return }

    for ($c = 1; $c -le [int]$Ep.cancels; $c++) {
        $before = Read-Engine -Tag "ep$($Ep.index)-cancel$c-before" -Need @('prodq', 'prodfan', 'card')
        if ($before.Buildings -ne 1) { Write-Skip -Id 'INV-M' -Why "expected one building selected, got $($before.Buildings)"; return }
        $l0 = Get-Logical -Eng $before -Unit $unit
        if ($l0.Logical -lt 1) { Write-Skip -Id 'INV-M' -Why "0x$unit has nothing left to cancel"; return }
        if (-not $before.Cancel) { Write-Skip -Id 'INV-M' -Why "the card offers no Cancel button (action 0x$CANCEL_ACTION)"; return }
        $m0 = $before.Minerals
        $cancelled0 = $before.Cancelled

        $card = Get-ScCardState -LogPath $LogPath -Tag "ep$($Ep.index)-cancelpt-$c" -MarkerPath $markerPath
        $pt = Get-ScCardSlotPoint -Card $card -Slot $before.Cancel.Slot
        Send-ScClick -Hwnd $script:hwnd -X $pt.X -Y $pt.Y
        Start-Sleep -Milliseconds 1200

        $post = Read-Engine -Tag "ep$($Ep.index)-cancel$c-after" -Need @('prodq', 'prodfan')
        $l1 = Get-Logical -Eng $post -Unit $unit
        $back = $post.Minerals - $m0
        # GROUND TRUTH: the engine's mineral global. Exactly one item's cost, exactly once.
        Assert-Inv -Id 'INV-M' -What "cancelling one queued item refunded exactly $SCV_COST minerals ($back)" `
            -Ok ($back -eq $SCV_COST) -Detail "(minerals $m0 -> $($post.Minerals))"
        $fin = Get-FinishedBetween $l0 $l1
        Assert-Inv -Id 'INV-R' -What "and 0x$unit's queue is one shorter$(if ($fin) { ', plus the unit it finished meanwhile' }) ($($l0.Logical) -> $($l1.Logical)) [cross-check]" `
            -Ok ($l1.Logical -eq $l0.Logical - 1 - $fin)
        if ($l0.Overflow -gt 0) {
            Assert-Inv -Id 'INV-P' -What "the plugin cancelled one of its OWN held items ($($post.Cancelled - $cancelled0)) [self-check]" `
                -Ok (($post.Cancelled - $cancelled0) -eq 1)
        }
    }
}

# ---------------------------------------------------------------------------
# CANCEL, by a queue ICON in the status strip ({0x20,k}). A different control sending a
# different payload -- and possibly an icon the PLUGIN drew over an empty engine slot, which
# the plugin then has to serve itself or the engine would refund by the sentinel type 0xE4
# and read both cost tables out of bounds.
# ---------------------------------------------------------------------------
function Invoke-CancelBySlot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Ep, [Parameter(Mandatory)]$After)

    $w = Read-Engine -Tag "ep$($Ep.index)-slot-aim" -Need @('world', 'prodfan')
    $unit = if ($After.Rows.Count -gt 0) { $After.Rows[0].Unit } else { $null }
    if (-not $unit) { Write-Skip -Id 'INV-M' -Why 'no building to cancel at'; return }
    $target = @($w.Units | Where-Object { $_.Unit -eq $unit }) | Select-Object -First 1
    if (-not $target) { Write-Skip -Id 'INV-M' -Why "building 0x$unit is not in the world scan"; return }
    if (-not (Select-ByClick -Target $target -World $w)) { Write-Skip -Id 'INV-M' -Why 'could not click the building'; return }

    $before = Read-Engine -Tag "ep$($Ep.index)-slot-before" -Need @('prodq', 'prodfan')
    $l0 = Get-Logical -Eng $before -Unit $unit
    if ($l0.Logical -lt 1) { Write-Skip -Id 'INV-M' -Why "0x$unit has nothing queued to cancel"; return }
    $m0 = $before.Minerals

    $status = Get-ScStatusQueue -LogPath $LogPath -Tag "ep$($Ep.index)-strip" -MarkerPath $markerPath
    if (-not $status.Ok) { Write-Skip -Id 'INV-M' -Why 'the status pane has no queue strip in this state'; return }
    $display = [int]$Ep.display
    $slot = @($status.Slots | Where-Object { $_.Display -eq $display }) | Select-Object -First 1
    if (-not $slot) { Write-Skip -Id 'INV-M' -Why "the strip has no display index $display"; return }
    if ($slot.Disabled -or -not $slot.Visible) {
        # An EMPTY queue slot's icon is disabled by the engine's own layout (0x00418640),
        # and both input paths refuse it. Not clicking it is the correct behaviour, so this
        # is a skip with the reason named, not a failure.
        Write-Skip -Id 'INV-M' -Why "strip icon $display is $($slot.State) -- the engine's layout refuses clicks on it"
        return
    }
    # The engine takes ONE number from each: the walk position and the payload. Assert they
    # are the same control before clicking it (drive-game.ps1, Get-ScStatusSlotPoint).
    Assert-Inv -Id 'INV-R' -What "strip icon $display is control id $($display + 2), so the click's payload names the slot it draws" `
        -Ok ($slot.Index -eq $display + 2) -Detail "(idx=$($slot.Index))"

    $pt = Get-ScStatusSlotPoint -Status $status -Display $display
    Send-ScClick -Hwnd $script:hwnd -X $pt.X -Y $pt.Y
    Start-Sleep -Milliseconds 1200

    $post = Read-Engine -Tag "ep$($Ep.index)-slot-after" -Need @('prodq', 'prodfan')
    $l1 = Get-Logical -Eng $post -Unit $unit
    $back = $post.Minerals - $m0
    Assert-Inv -Id 'INV-M' -What "clicking queue icon $display refunded exactly $SCV_COST minerals ($back)" `
        -Ok ($back -eq $SCV_COST) -Detail "(minerals $m0 -> $($post.Minerals))"
    # Icon 0 is the unit in production: cancelling it changes the current build by itself.
    $fin = if ($display -eq 0) { 0 } else { Get-FinishedBetween $l0 $l1 }
    Assert-Inv -Id 'INV-R' -What "and 0x$unit's queue is one shorter$(if ($fin) { ', plus the unit it finished meanwhile' }) ($($l0.Logical) -> $($l1.Logical)) [cross-check]" `
        -Ok ($l1.Logical -eq $l0.Logical - 1 - $fin)
}

# ---------------------------------------------------------------------------
# DRAIN -- "and it built 12".
# GROUND TRUTH: the engine's own per-player unit lists. Every item that left the queue has
# to appear there as a unit, exactly once, and no more. This is the only assertion whose
# cost is a BUILD TIME rather than a click, which is why the plan emits it rarely and small.
# ---------------------------------------------------------------------------
function Invoke-Drain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ep,
        [Parameter(Mandatory)][string[]]$Units,
        [Parameter(Mandatory)][int]$Expect,
        [Parameter(Mandatory)][int]$ScvBefore,
        [Parameter(Mandatory)][int]$MineralsAfterBurst
    )
    $budget = [math]::Max(30, ($Expect * $BuildTimeSec) + 25)
    Note "waiting up to ${budget}s for $Expect unit(s) to be built"
    # -AlsoWaitProduction, because "the queue is empty" is TRUE while the last item is still
    # being built -- the engine takes it out of the ring when production starts. Counting
    # completed units at that instant reads one short; a fixed sleep instead is timing that
    # passes until the machine is busy.
    if (-not (Wait-QueuesEmpty -Units $Units -TimeoutSec $budget -AlsoWaitProduction)) {
        Write-Skip -Id 'INV-B' -Why "the queues had not emptied (and finished producing) inside ${budget}s"
        return
    }
    Start-Sleep -Seconds 2
    $post = Read-Engine -Tag "ep$($Ep.index)-built" -Need @('world', 'prodfan')
    Assert-Inv -Id 'INV-B' -What 'the world scan of player 0 was not taken mid-edit' `
        -Ok ($post.Counts[0].Units -eq $post.Counts[0].Recount -and $post.Counts[0].Complete -eq 1)
    # COMPLETED only, and here it is load-bearing: this is the "and it built 12" half of the
    # user's sentence. A unit that has merely STARTED is in the list too, so a raw count would
    # let a queue that is still working report the number it was asked for.
    $scvAfter = Get-OwnedCount -Eng $post -Type $SCV_TYPE -Completed
    Assert-Inv -Id 'INV-B' -What "the engine's own unit list gained exactly $Expect COMPLETED unit(s) ($($scvAfter - $ScvBefore))" `
        -Ok (($scvAfter - $ScvBefore) -eq $Expect) -Detail "(SCVs $ScvBefore -> $scvAfter)"
    # A unit COMPLETING must not move a mineral: everything was paid for when it was
    # queued. This is the other half of "paid exactly once".
    Assert-Inv -Id 'INV-M' -What "nothing was charged or refunded while the queue drained ($($post.Minerals - $MineralsAfterBurst))" `
        -Ok ($post.Minerals -eq $MineralsAfterBurst) `
        -Detail "(minerals $MineralsAfterBurst -> $($post.Minerals))"
}

function Wait-QueuesEmpty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Units,
        [int]$TimeoutSec = 45,
        # Also wait for what each building is CURRENTLY BUILDING to finish. An item in
        # production has left the ring already, so an empty queue is not an idle building.
        [switch]$AlsoWaitProduction
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $e = Read-Engine -Tag 'drainwait' -Need @('prodq', 'prodfan')
        $left = 0
        foreach ($u in $Units) { $left += [math]::Max(0, (Get-Logical -Eng $e -Unit $u).Logical) }
        $busy = 0
        if ($AlsoWaitProduction) {
            $busy = @($e.Rows | Where-Object { $Units -contains $_.Unit -and $_.BuildUnit -and $_.BuildUnit -ne '00000000' }).Count
        }
        if ($left -le 0 -and $busy -eq 0) { return $true }
        Start-Sleep -Seconds 2
    }
    $false
}

# ---------------------------------------------------------------------------
# INV-Q -- the queue indicator, as a DIFFERENCE against a baseline, NOT built on `ink`.
#
# Do not assert on `ink` (set bytes inside the indicator's bounds) in either direction: the
# pane's own art supplies it, measured `ink=448 of 448` BEFORE anything of ours was drawn
# and `refInk=1330 of 1330` over the reference icon. A presence test passes with the box
# invisible, and at saturation our glyph changes WHICH bytes are set, never HOW MANY, so a
# difference test on ink calls a working indicator broken on every run. A positive control
# only proves that something drew. `ink` and `refInk` are PRINTED and asserted on nowhere.
#
# The oracle is `boxDiff`: bytes inside the live bounds that differ from a copy of the same
# rect taken on the game thread on a frame where the indicator was HIDDEN. Its zero means
# "our pixels are identical to the pane with no indicator on it" -- the bug being hunted.
# Two states differing only in our string (a short "+1", a longer "+10") must carry
# different strings, fit each in the box, and read boxDiff > 0 in both. NOT proved: that
# the text is legible, placed or sized right -- a human's judgement, which is why both
# states are captured as frames named for the state.
# ---------------------------------------------------------------------------
function Invoke-IndicatorEpisode {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Ep, [Parameter(Mandatory)][string]$Unit, [Parameter(Mandatory)]$Before)

    if (-not (Wait-QueuesEmpty -Units @($Unit) -TimeoutSec 45)) {
        Write-Skip -Id 'INV-Q' -Why 'the building would not drain to empty, so the two states are not comparable'
        return
    }
    # FROM THE PLAN, not recomputed here: the plan is the thing a seed reproduces, and a
    # constant that lives in the runner instead would make two runs of one seed able to
    # differ. Older plans without these fields fall back to the same numbers the plan uses.
    $lowTotal = if ($Ep.PSObject.Properties['qLow']) { [int]$Ep.qLow } else { $ENGINE_SLOTS + 1 }
    $highTotal = if ($Ep.PSObject.Properties['qHigh']) { [int]$Ep.qHigh } else { $ENGINE_SLOTS + 10 }
    if ($highTotal -ge $QueueMax) {
        Write-Skip -Id 'INV-Q' -Why "the two states need a logical queue of $highTotal, above -QueueMax $QueueMax"
        return
    }

    Invoke-TrainPress -Times $lowTotal
    $low = Read-Engine -Tag "ep$($Ep.index)-qind-low" -Need @('prodq', 'prodfan', 'qind')
    # The frame is for the HUMAN, named for the string it is a picture OF (Get-TextTag), never
    # for its order in the run. It is not the oracle and nothing below asserts on it
    # (AGENTS.md: read a dialog's content from memory, never hash its pixels).
    Shot "queueind-short-string-$(Get-TextTag -Text $(if ($low.Qind) { $low.Qind.Text } else { '' }))-ep$($Ep.index)" | Out-Null

    # THE SECOND STATE IS DEFINED BY THE READING, NOT BY THE PRESS COUNT. An SCV completes
    # every -UnitBuildTime seconds throughout the burst, so "press to 15" measures a logical
    # 14 and draws "+9" -- the same LENGTH as "+1", which the width assertion below rests on.
    # Press until the string has actually grown.
    $high = $null
    $pressed = $lowTotal
    $step = [math]::Max(1, $highTotal - $lowTotal)
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Invoke-TrainPress -Times $step
        $pressed += $step
        $high = Read-Engine -Tag "ep$($Ep.index)-qind-high$attempt" -Need @('prodq', 'prodfan', 'qind')
        if ($high.Qind -and $low.Qind -and $high.Qind.Text.Length -gt $low.Qind.Text.Length) { break }
        # THE CAP IS A FACT ABOUT THE QUEUE, NOT ABOUT HOW MANY TIMES WE PRESSED. Do not guard
        # on `pressed`: the plan's target IS the cap, so `pressed >= QueueMax-1` is true on the
        # first pass and the top-up never runs, skipping on a "+9" one press short. The queue
        # is shorter than the presses by however many units completed; only the engine knows.
        $curLogical = (Get-Logical -Eng $high -Unit $Unit).Logical
        if ($curLogical -ge $QueueMax) {
            Note "the building is at the plugin's cap of $QueueMax with `"$($high.Qind.Text)`" showing; no room to lengthen the string"
            break
        }
        # Top up by what the queue has drained since, rather than by the original step: the
        # count we are chasing is the plugin's "+N", and completions eat it while we press.
        $step = 2
        Note "the string has not grown yet (`"$(if ($high.Qind) { $high.Qind.Text })`"); pressing $step more"
    }
    Shot "queueind-long-string-$(Get-TextTag -Text $(if ($high -and $high.Qind) { $high.Qind.Text } else { '' }))-ep$($Ep.index)" | Out-Null

    if (-not $low.Qind -or -not $high -or -not $high.Qind) {
        Write-Skip -Id 'INV-Q' -Why 'the plugin reported no indicator state (is -QueueIndicator 1 on?)'
        return
    }
    # ink/refInk are printed, never asserted (saturated; see the banner above). refInk is ink
    # over the first VISIBLE of the queue icon and the wireframe button and is legitimately -1
    # when neither is up, so it is not a blindness control either.
    $lowW = $low.Qind.Bounds[2] - $low.Qind.Bounds[0]
    $highW = $high.Qind.Bounds[2] - $high.Qind.Bounds[0]
    Note "low:  text=`"$($low.Qind.Text)`" bounds=($($low.Qind.Bounds -join ',')) width=$lowW boxDiff=$($low.Qind.BoxDiff) [diagnostic only: ink=$($low.Qind.Ink) refInk=$($low.Qind.RefInk) surfInk=$($low.Qind.SurfInk)]"
    Note "high: text=`"$($high.Qind.Text)`" bounds=($($high.Qind.Bounds -join ',')) width=$highW boxDiff=$($high.Qind.BoxDiff) [diagnostic only: ink=$($high.Qind.Ink) refInk=$($high.Qind.RefInk) surfInk=$($high.Qind.SurfInk)]"

    Assert-Inv -Id 'INV-Q' -What 'the indicator is linked into the status dialog in both states' `
        -Ok ($low.Qind.Linked -and $high.Qind.Linked)

    # WHAT IT SAYS -- the content oracle, read out of the live control's own pszText.
    Assert-Inv -Id 'INV-Q' -What "the two states really do carry different strings (`"$($low.Qind.Text)`" vs `"$($high.Qind.Text)`")" `
        -Ok ($low.Qind.Text -ne $high.Qind.Text)
    # AND THAT THE BOX CAN HOLD IT. Do not assert that a longer string made the box WIDER:
    # `"+1"` and `"+10"` both measure 28 px, because in STRIP mode PlaceOn CLAMPS the box to
    # its anchor icon (`b[2] = min(left + want, a[2])`) so our pixels sit inside a control the
    # engine repaints -- which is what paints them over when the indicator goes away. What
    # must hold is the other direction: a box narrower than its string is drawn TRUNCATED.
    # Same invariant hooktest asserts offline, checked here against the live control.
    foreach ($state in @(
        [pscustomobject]@{ Name = 'short'; Q = $low.Qind },
        [pscustomobject]@{ Name = 'long';  Q = $high.Qind }
    )) {
        $w = $state.Q.Bounds[2] - $state.Q.Bounds[0]
        $need = $state.Q.Text.Length * $QIND_CHAR_W
        Assert-Inv -Id 'INV-Q' -What "the $($state.Name) state's box is wide enough for `"$($state.Q.Text)`" ($w px, needs $need)" `
            -Ok ($w -ge $need) `
            -Detail "(SC_QIND_CHAR_W = $QIND_CHAR_W px per character; a box narrower than its string is drawn truncated)"
    }

    # THAT IT LANDED -- the pixel oracle, and it refuses to run rather than guess. $null means
    # this plugin build has no boxDiff field; -1 means it has one but no baseline was captured
    # for this rect. Both are "the probe did not run", which is NOT the same claim as "the
    # probe ran and saw nothing" -- and only the second is a bug.
    if ($null -eq $low.Qind.BoxDiff -or $null -eq $high.Qind.BoxDiff) {
        Write-Skip -Id 'INV-Q' -Why 'this plugin build reports no boxDiff on its QIND line (task 039 is landing ScQueueIndBoxDiff) -- the surface half of INV-Q did not run, and ink= is NOT a substitute for it (039 measured it saturated at 448 of 448)'
        return
    }
    if ($low.Qind.BoxDiff -lt 0 -or $high.Qind.BoxDiff -lt 0) {
        Write-Skip -Id 'INV-Q' -Why "boxDiff has no baseline for this rect yet (low=$($low.Qind.BoxDiff) high=$($high.Qind.BoxDiff)); a run with no baseline cannot tell 'nothing was drawn' from 'nothing was measured'"
        return
    }
    # THE BLINDNESS CONTROL: surfInk is ink over the WHOLE dialog surface, the one number that
    # is positive in every state a player can be in. A zero there means the probe cannot see
    # this surface at all, and its verdict on our box means nothing whichever way it comes out
    # (AGENTS.md: prove the pattern positive before trusting it).
    if ($null -ne $low.Qind.SurfInk -and $null -ne $high.Qind.SurfInk) {
        Assert-Inv -Id 'INV-Q' -What "the surface probe can see this dialog at all in both states (surfInk $($low.Qind.SurfInk) / $($high.Qind.SurfInk))" `
            -Ok ($low.Qind.SurfInk -gt 0 -and $high.Qind.SurfInk -gt 0)
    }
    Assert-Inv -Id 'INV-Q' -What "our string changed the indicator's box against the no-indicator baseline in both states (boxDiff $($low.Qind.BoxDiff) / $($high.Qind.BoxDiff))" `
        -Ok ($low.Qind.BoxDiff -gt 0 -and $high.Qind.BoxDiff -gt 0) `
        -Detail '(0 means our pixels are identical to the pane with no indicator on it)'
}

# A frame's name has to say WHICH state it holds, and the state here IS the string the
# indicator was showing -- so the string goes in the name, with the characters a path cannot
# carry spelled out rather than dropped ("+1" -> "plus1", an empty string -> "empty").
function Get-TextTag {
    [CmdletBinding()]
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 'empty' }
    $t = $Text -replace '\+', 'plus' -replace '\s+', '-' -replace '[^A-Za-z0-9\-]', ''
    if ([string]::IsNullOrEmpty($t)) { 'empty' } else { $t }
}

# TRAIN IS DRIVEN BY CLICKING THE CARD'S OWN BUTTON, NOT BY THE HOTKEY. Do not drive it by
# posted keys: measured, they stop being processed mid-episode and stay dead for the rest of
# the game -- `trainSeen` froze at 11 while three further episodes pressed 22 more times,
# minerals never moved and the detour was never entered, so the CLIENT sent nothing. Posted
# CLICKS kept landing the whole time and the card read `slot=1 enabled act=0x004234B0`
# throughout. Every later episode then fails INV-W and INV-M with "0 presses reached the
# funnel", which reads exactly like the feature being broken. So the press goes through the
# control a player would click, located from the card's own rects (Get-ScCardSlotPoint).
function Get-TrainPoint {
    [CmdletBinding()]
    param([string]$Tag = 'train')
    $card = Get-ScCardState -LogPath $LogPath -Tag "rc-$Tag-card" -MarkerPath $markerPath
    if (-not $card.Ok) { return $null }
    # Located by its ACTION, never by slot number: which slot the Train button sits in is the
    # engine's business and it moves with the unit. Get-ScCardState upper-cases the action, so
    # the comparison does too rather than hoping about case.
    $slot = @($card.Slots | Where-Object {
        $_.HasButton -and $_.Action -eq $TRAIN_ACTION.ToUpperInvariant() -and -not $_.Disabled -and $_.Visible
    }) | Select-Object -First 1
    if (-not $slot) { return $null }
    Get-ScCardSlotPoint -Card $card -Slot $slot.Index
}

function Invoke-TrainPress {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Times, $Point)
    if (-not $Point) { $Point = Get-TrainPoint -Tag 'press' }
    if (-not $Point) {
        Note 'the card has no Train button to click; falling back to the hotkey for this burst'
        for ($i = 1; $i -le $Times; $i++) {
            Send-ScKey -Hwnd $script:hwnd -VirtualKey $TRAIN_KEY -SettleMs $ClickDelayMs
        }
    } else {
        for ($i = 1; $i -le $Times; $i++) {
            Send-ScClick -Hwnd $script:hwnd -X $Point.X -Y $Point.Y
            Start-Sleep -Milliseconds $ClickDelayMs
        }
    }
    Start-Sleep -Seconds 2
}
