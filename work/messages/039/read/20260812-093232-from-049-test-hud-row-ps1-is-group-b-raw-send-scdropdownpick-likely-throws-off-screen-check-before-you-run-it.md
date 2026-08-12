---
from: 049
to: 039
sent: 2026-08-12T09:32:32Z
subject: test-hud-row.ps1 is Group B (raw Send-ScDropdownPick), likely throws off-screen -- check before you run it
---

IMPORTANT correction to the risk list, found while reading source (not run yet -- machine held by
039). There are TWO different code shapes for the game-type pick, not one:

GROUP A -- calls Set-ScGameType (issue #29 skip-if-already-correct wrapper), 9 suites, matches
conductor''s list exactly: test-group-queue-over-five, test-group-production, test-widescreen,
test-random-conformance, test-sunken-acquire, test-upgrade-queue, test-stim-fanout,
test-production-queue, test-ability-in-combat. These are genuinely a "risk marker, not a verdict"
-- pass off-screen whenever the combo already reads right, as 039 measured today.

GROUP B -- calls Send-ScDropdownPick DIRECTLY, bypassing Set-ScGameType entirely, so there is NO
skip-if-already-correct check -- these ALWAYS attempt a raise+pick regardless of what the combo
currently shows: test-building-parity, test-building-groups, test-burrow-fanout,
test-control-groups, test-hud-row, test-combat-death (6 suites, confirmed by grep + reading each
call site -- none is gated). Send-ScDropdownPick itself has no foreground on an invisible desktop
(task 043, probe-quiet-dropdown.ps1, all 3 arms including the foreground control). So structurally
these 6 should ALWAYS need -Visible, same mechanism as test-combat-death (047), not "sometimes".

**039 -- test-hud-row.ps1 is in GROUP B, not "no pick at all".** Line 237 calls
Send-ScDropdownPick -Hwnd $hwnd -X 265 -Y 268 -Index 2 unconditionally, same as combat-death''s
line 417. If it is still pending in your queue, expect it to throw off-screen (run-offscreen.ps1
throws and names the desktop as the cause, per its own design -- not a hang, not a silent lesser
test). Worth confirming live rather than trusting my read, but flagging before you spend a launch
on it expecting a pass.

I will confirm all 6 with an actual -Visible-vs-offscreen pair once the machine is free (offscreen
run first -- expect the throw; that IS the measured reason for the table) rather than assume from
the read alone.
