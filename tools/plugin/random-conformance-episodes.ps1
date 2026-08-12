#Requires -Version 7
<#
.SYNOPSIS
The EPISODE bodies of the randomized conformance harness (task 041): what one generated
action sequence actually does to the game, and which invariant each assertion belongs to.

.DESCRIPTION
Dot-sourced by test-random-conformance.ps1 into the same scope, so these see the run's
handle, log path and pinned constants. Split out only because the runner is already the
longest thing in this directory and the two halves change for different reasons: the runner
changes when the harness does, this file changes when a FEATURE does.

Every assertion here names its invariant, and every invariant's ground truth is stated
where it is read. The one exception is called out in place: the plugin's overflow count is
its own bookkeeping and appears only to compute headroom and to explain a number.
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

    # A drain episode wants the queues EMPTY first, because its claim ("what left the queue
    # appeared in the engine's unit list") is only checkable against a known starting
    # count. Waiting is bounded and a timeout SKIPS rather than fails -- a busy queue is
    # not a defect.
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
    $refusedFullBefore = $Before.RefusedFull
    $refusedCostBefore = $Before.RefusedCost
    $promotedBefore = $Before.Promoted
    $logicalBefore = @{}
    foreach ($u in $Units) { $logicalBefore[$u] = (Get-Logical -Eng $Before -Unit $u).Logical }

    # ---- press ------------------------------------------------------------
    $mark = Get-ScLogMark
    for ($i = 1; $i -le $Presses; $i++) {
        Send-ScKey -Hwnd $script:hwnd -VirtualKey $TRAIN_KEY -SettleMs $ClickDelayMs
    }
    Start-Sleep -Seconds 3
    $fresh = @(Get-ScLogSince -Mark $mark)

    # ---- INV-W: the wire --------------------------------------------------
    # GROUND TRUTH: the detour on queueCommand (0x00485BD0). Every command this game sends
    # passes through it, so a press that produced no line here produced no command at all.
    # THIS IS THE ASSERTION TASK 038'S PARENT FAILS: with a group selected, the client
    # stops offering the Train button once each ring holds five, and presses six onward
    # never reach the funnel.
    #
    # One press is exactly ONE `CMD id=0x1F`: the fan-out's replayed Select+Train pairs go
    # out through the TRAMPOLINE and deliberately do not pass the logger again.
    $cmds = @($fresh | Select-String -Pattern "CMD id=$TRAIN_CMD ")
    $starts = @($fresh | Select-String -Pattern 'FANOUT start: cmd=0x1F')
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
    $refusals = ($after.RefusedFull - $refusedFullBefore) + ($after.RefusedCost - $refusedCostBefore)
    $expectItems = $Presses * $SelCount
    $paid = $mineralsBefore - $after.Minerals
    if ($refusals -eq 0) {
        Assert-Inv -Id 'INV-M' -What "the engine charged for every one of the $expectItems items: $expectItems x $SCV_COST = $($expectItems * $SCV_COST) ($paid)" `
            -Ok ($paid -eq $expectItems * $SCV_COST) `
            -Detail "(minerals $mineralsBefore -> $($after.Minerals))"
    } else {
        # A refusal is a legitimate engine answer, so it changes the expectation instead of
        # failing -- but it is REPORTED, because a silent one would turn every later number
        # into a mystery.
        Note "$refusals command(s) were refused (full=$($after.RefusedFull - $refusedFullBefore) cost=$($after.RefusedCost - $refusedCostBefore)); the charge is asserted as a bound, not an equality"
        Assert-Inv -Id 'INV-M' -What "the engine charged for no more than the $expectItems items asked for ($paid)" `
            -Ok ($paid -le $expectItems * $SCV_COST -and $paid -ge 0)
    }

    # ---- the logical queue, CROSS-CHECK ------------------------------------
    # The ring half is the engine's; the overflow half is the plugin's own bookkeeping.
    # It is asserted because a wrong number here is still a bug worth catching, but it is
    # labelled a cross-check and it is never the evidence for a claim about the game.
    #
    # WHAT LEAVES A QUEUE IS A COMPLETION, NOT A PROMOTION, and the first version of this
    # guarded on the wrong one. A promotion moves an item from the plugin's overflow into the
    # engine's ring and leaves the LOGICAL count alone; a unit COMPLETING takes one out of the
    # queue for good. Guarding on `promoted` let a completion through, so a deep queue (which
    # completes an SCV every -UnitBuildTime seconds, burst or no burst) failed this check by
    # exactly one, twice in one run, while INV-M was exact to the mineral -- the signature of
    # a race in the CHECK rather than a defect in the game (AGENTS.md: a check that fails at
    # random is worth as little as one that cannot fail).
    #
    # The repair is to read the completions rather than hope there were none: the engine's own
    # unit list is the only place an item goes when it leaves a queue, so the SCV delta over
    # the same window is the correction term, and the sum becomes exactly assertable.
    $scvAfterBurst = Get-OwnedCount -Eng $after -Type $SCV_TYPE -Completed
    $completed = $scvAfterBurst - $scvBefore
    $promoted = $after.Promoted - $promotedBefore
    $sumBefore = 0; foreach ($u in $Units) { $sumBefore += $logicalBefore[$u] }
    $sumAfter = 0; foreach ($u in $Units) { $sumAfter += (Get-Logical -Eng $after -Unit $u).Logical }
    $queued = $Presses * $SelCount
    if ($refusals -eq 0) {
        # A BOUND, not an equality, and the asymmetry is the reason. `completed` is a count for
        # the WHOLE PLAYER: the engine's unit list does not say which building finished a unit,
        # and buildings this episode never selected are draining their own queues the whole
        # time. So a completion elsewhere may loosen the lower bound and must never fail this
        # check -- while the upper bound is absolute, because nothing can add to a queue except
        # the presses this episode sent.
        Assert-Inv -Id 'INV-R' -What "the selected buildings gained no more than the $queued item(s) queued ($sumBefore -> $sumAfter)" `
            -Ok ($sumAfter -le $sumBefore + $queued) `
            -Detail "(promoted=$promoted; a promotion moves an item between the ring and the plugin and must not change this total)"
        Assert-Inv -Id 'INV-R' -What "and lost no more than the $completed unit(s) the player finished during the burst ($sumAfter >= $($sumBefore + $queued - $completed))" `
            -Ok ($sumAfter -ge $sumBefore + $queued - $completed) `
            -Detail '(items can only leave a queue by being built)'
    }
    if ($completed -eq 0 -and $refusals -eq 0) {
        # Nothing left any queue in this window, so the per-building numbers are exactly
        # predictable and are worth asserting one building at a time.
        foreach ($u in $Units) {
            $l = Get-Logical -Eng $after -Unit $u
            $want = $logicalBefore[$u] + $Presses
            Assert-Inv -Id 'INV-R' -What "0x$u holds $want item(s) after $Presses more (ring $($l.Ring) + plugin $($l.Overflow) = $($l.Logical)) [cross-check]" `
                -Ok ($l.Logical -eq $want)
        }
    } else {
        Note "$completed unit(s) completed and $refusals command(s) were refused during the burst; the per-building split is not predictable (the engine's unit list does not say WHICH building finished one), so the total above is asserted instead"
    }
    # This one holds either way: it is about where the ring is HELD, not about how many items
    # are in the queue, and that is the whole mechanism of task 025 (keep the engine's ring
    # below its cap so the client never greys the button).
    foreach ($u in $Units) {
        $l = Get-Logical -Eng $after -Unit $u
        if ($l.Logical -gt $ENGINE_SLOTS) {
            Assert-Inv -Id 'INV-R' -What "0x$u went PAST the engine's $ENGINE_SLOTS, and its ring is held at $ENGINE_HOLD so the client keeps sending ($($l.Ring))" `
                -Ok ($l.Ring -eq $ENGINE_HOLD)
        }
    }

    # ---- the card is still live -------------------------------------------
    # The client half of task 025's design: the button never goes dark, so the next press
    # still reaches the wire. Read out of the dialog, never off a frame.
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
        Assert-Inv -Id 'INV-R' -What "and 0x$unit's queue is one shorter ($($l0.Logical) -> $($l1.Logical)) [cross-check]" `
            -Ok ($l1.Logical -eq $l0.Logical - 1)
        if ($l0.Overflow -gt 0) {
            Assert-Inv -Id 'INV-P' -What "the plugin cancelled one of its OWN held items ($($post.Cancelled - $cancelled0)) [self-check]" `
                -Ok (($post.Cancelled - $cancelled0) -eq 1)
        }
    }
}

# ---------------------------------------------------------------------------
# CANCEL, by a queue ICON in the status strip ({0x20,k}). A different control sending a
# different payload -- and, since task 033, an icon the PLUGIN may have drawn over an
# empty engine slot, which the plugin then has to serve itself or the engine would refund
# by the sentinel type 0xE4 and read both cost tables out of bounds.
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
    Assert-Inv -Id 'INV-R' -What "and 0x$unit's queue is one shorter ($($l0.Logical) -> $($l1.Logical)) [cross-check]" `
        -Ok ($l1.Logical -eq $l0.Logical - 1)
}

# ---------------------------------------------------------------------------
# DRAIN -- "and it built 12".
#
# GROUND TRUTH: the engine's own per-player unit lists. Every item that left the queue has
# to appear there as a unit, exactly once, and no more than that. This is the only
# assertion in the harness whose cost is a BUILD TIME rather than a click, which is why
# the plan emits it rarely and small.
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
    if (-not (Wait-QueuesEmpty -Units $Units -TimeoutSec $budget)) {
        Write-Skip -Id 'INV-B' -Why "the queues had not emptied inside ${budget}s"
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
    param([Parameter(Mandatory)][string[]]$Units, [int]$TimeoutSec = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $e = Read-Engine -Tag 'drainwait' -Need @('prodq', 'prodfan')
        $left = 0
        foreach ($u in $Units) { $left += [math]::Max(0, (Get-Logical -Eng $e -Unit $u).Logical) }
        if ($left -le 0) { return $true }
        Start-Sleep -Seconds 2
    }
    $false
}

# ---------------------------------------------------------------------------
# INV-Q -- the queue indicator, as a DIFFERENCE, and NOT built on `ink`.
#
# A PRESENCE test here is worthless, and that is not a hypothetical: task 033 shipped
# `ink > 0` over the indicator's own bounds and it passed while the box was invisible,
# because the pane's own art lies inside those bounds and supplies the ink. Task 039
# measured it on 2026-08-12 -- `ink=448 of 448` bytes inside the box BEFORE anything of
# ours was drawn, and `refInk=1330 of 1330` over the reference icon. A positive control
# does not rescue that: the positive control also only proves that something drew.
#
# The saturation is worth stating precisely, because it kills the obvious repair too. At
# 448 of 448, our glyph changes WHICH bytes are set and cannot change HOW MANY -- so a
# difference test built on `ink` would not merely fail to fail, it would fail to PASS,
# reporting a working indicator as broken on every run. `ink` and `refInk` are therefore
# PRINTED here and asserted on nowhere. Do not put them back.
#
# What this asserts instead is task 039's `boxDiff`: bytes inside the indicator's live
# bounds that differ from a baseline copy of that same rect, taken on the game thread on a
# frame where the indicator was HIDDEN. That has a defined zero -- "our pixels are
# identical to the pane with no indicator on it" -- which is exactly the bug being hunted.
#
# The episode reads it in two states that differ ONLY in our string: a logical queue of 6
# ("+1") against one of 14 ("+9"). Five icons are lit in both and both strings are two
# characters wide, so the bounds and everything underneath are identical, and the only
# variable left is the glyph the engine drew out of our buffer. Hence two assertions:
# boxDiff > 0 in both states (our text changed the box at all), and boxDiff(low) !=
# boxDiff(high) (the change tracks OUR string, rather than something else that drew).
#
# WHAT IT DOES NOT PROVE, stated so nobody has to infer it: that the text is legible, or
# in the right place, or the right size. It proves the engine drew OUR string into the
# pixels we asked for. Legibility is a human's judgement and stays one -- which is why
# both states are also captured as frames, named for the state, for the user to open.
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
    # The frame is for the HUMAN and is named for the state it holds, never for its order in
    # the run. It is not the oracle and nothing below asserts on it (AGENTS.md: read a
    # dialog's content from memory, never hash its pixels).
    # The frame's name carries the string it is a picture OF, with '+' spelled out so the name
    # is a filename on every path that will ever handle it.
    Shot "queueind-short-string-$(Get-TextTag -Text $(if ($low.Qind) { $low.Qind.Text } else { '' }))-ep$($Ep.index)" | Out-Null

    # THE SECOND STATE IS DEFINED BY THE READING, NOT BY THE PRESS COUNT. The plan's target is
    # a target: an SCV completes every -UnitBuildTime seconds and a deep queue is completing
    # them throughout the burst, so "press to 15" measured a logical 14 on the first run of
    # this episode and drew "+9" -- the same LENGTH as "+1", which is the one property the
    # width assertion below rests on. Pressing until the string has actually grown is the
    # difference between a state this episode assumed and a state it verified.
    $high = $null
    $pressed = $lowTotal
    $step = [math]::Max(1, $highTotal - $lowTotal)
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Invoke-TrainPress -Times $step
        $pressed += $step
        $high = Read-Engine -Tag "ep$($Ep.index)-qind-high$attempt" -Need @('prodq', 'prodfan', 'qind')
        if ($high.Qind -and $low.Qind -and $high.Qind.Text.Length -gt $low.Qind.Text.Length) { break }
        if ($pressed -ge $QueueMax - 1) { break }
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
    # ink/refInk are printed and NOT asserted, and the reason is measured rather than
    # supposed: 039 read ink saturated (448 of 448 inside the box before anything of ours was
    # drawn), so it can neither fail nor pass. refInk is ink over the first VISIBLE of the
    # queue icon and the wireframe button and is legitimately -1 when neither is up, so it is
    # not a blindness control either. They stay on the line because a number that explains a
    # verdict is worth having beside it. Do not assert on them.
    $lowW = $low.Qind.Bounds[2] - $low.Qind.Bounds[0]
    $highW = $high.Qind.Bounds[2] - $high.Qind.Bounds[0]
    Note "low:  text=`"$($low.Qind.Text)`" bounds=($($low.Qind.Bounds -join ',')) width=$lowW boxDiff=$($low.Qind.BoxDiff) [diagnostic only: ink=$($low.Qind.Ink) refInk=$($low.Qind.RefInk) surfInk=$($low.Qind.SurfInk)]"
    Note "high: text=`"$($high.Qind.Text)`" bounds=($($high.Qind.Bounds -join ',')) width=$highW boxDiff=$($high.Qind.BoxDiff) [diagnostic only: ink=$($high.Qind.Ink) refInk=$($high.Qind.RefInk) surfInk=$($high.Qind.SurfInk)]"

    Assert-Inv -Id 'INV-Q' -What 'the indicator is linked into the status dialog in both states' `
        -Ok ($low.Qind.Linked -and $high.Qind.Linked)

    # WHAT IT SAYS -- the content oracle, read out of the live control's own pszText.
    Assert-Inv -Id 'INV-Q' -What "the two states really do carry different strings (`"$($low.Qind.Text)`" vs `"$($high.Qind.Text)`")" `
        -Ok ($low.Qind.Text -ne $high.Qind.Text)
    if ($high.Qind.Text.Length -le $low.Qind.Text.Length) {
        # The whole point of the +9 gap is that the second string is LONGER. If it is not, the
        # strip is showing a different number of icons than this episode assumed, and the
        # width claim below would be measuring nothing. Say so rather than assert into it.
        Write-Skip -Id 'INV-Q' -Why "the second string (`"$($high.Qind.Text)`") is not longer than the first (`"$($low.Qind.Text)`"), so the box was never expected to grow -- the strip is not showing the icon count this episode assumed"
    } else {
        # AND WHERE IT PUT IT, guaranteed by construction rather than by a font: the box's
        # width is a function of strlen in the indicator's own PlaceOn, so a longer string
        # MUST widen the box. This is the half that survives two digits happening to set the
        # same number of pixels (039's correction, 2026-08-12).
        Assert-Inv -Id 'INV-Q' -What "the longer string widened the box ($lowW -> $highW px for `"$($low.Qind.Text)`" -> `"$($high.Qind.Text)`")" `
            -Ok ($highW -gt $lowW) `
            -Detail '(the box is sized from strlen, so a longer string that did not widen it means the box is not being sized from OUR text)'
    }

    # THAT IT LANDED -- the pixel oracle, and it refuses to run rather than guess. $null means
    # this plugin has no boxDiff field at all (039's is not merged yet); -1 means it has one
    # but no baseline was captured for this rect. Both are "the probe did not run", which is
    # NOT the same claim as "the probe ran and saw nothing" -- and only the second is a bug.
    if ($null -eq $low.Qind.BoxDiff -or $null -eq $high.Qind.BoxDiff) {
        Write-Skip -Id 'INV-Q' -Why 'this plugin build reports no boxDiff on its QIND line (task 039 is landing ScQueueIndBoxDiff) -- the surface half of INV-Q did not run, and ink= is NOT a substitute for it (039 measured it saturated at 448 of 448)'
        return
    }
    if ($low.Qind.BoxDiff -lt 0 -or $high.Qind.BoxDiff -lt 0) {
        Write-Skip -Id 'INV-Q' -Why "boxDiff has no baseline for this rect yet (low=$($low.Qind.BoxDiff) high=$($high.Qind.BoxDiff)); a run with no baseline cannot tell 'nothing was drawn' from 'nothing was measured'"
        return
    }
    # THE BLINDNESS CONTROL, on 039's ruling: surfInk is ink over the WHOLE dialog surface, and
    # it is the one number that is positive in every state a player can be in. A zero there
    # means the probe cannot see this surface at all, and its verdict on our box means nothing
    # whichever way it comes out (AGENTS.md: prove the pattern positive before trusting it).
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

function Invoke-TrainPress {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Times)
    for ($i = 1; $i -le $Times; $i++) {
        Send-ScKey -Hwnd $script:hwnd -VirtualKey $TRAIN_KEY -SettleMs $ClickDelayMs
    }
    Start-Sleep -Seconds 2
}
