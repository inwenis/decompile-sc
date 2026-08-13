---
from: 061
to: conductor
sent: 2026-08-13T08:59:03Z
subject: REPRODUCED -- half 1: NO cancel command on the wire at all
---

**Reproduced in a real game, and the wire has split it: HALF 1 — the click never becomes a cancel. NOTHING reaches `queueCommand`.**

Run: `run-offscreen.ps1 -Suite test-production-queue.ps1`, plugin build `9e5db71` (unmodified plugin source; only the test script carries my new arm). Log `C:\sc-work\logs\061\production-queue.log`, transcript `C:\sc-work\logs\061\prefix-run3.txt`.

The new arm proves it reached the exact state the user describes BEFORE it clicks -- all of these passed:

```
QIND [qi-last-slot-before-2] mode=1 linked=1 visible=1 text="+2"
  bounds=(231,65,259,81) ink=448 refInk=1330 surfInk=24828 slotDiff=76 boxDiff=38 fontH=11
  icons=[0x040:3:lit:I:1 x5] engineLen=4 overflow=3
STATQ disp=4 enabled idx=6 rect=(221,53,259,88) uicon=0x040 umode=3 qtype=0x0E4
  ok   OUR pixels are on that box: boxDiff=38 bytes differ from the same rect without them
  ok   display 4 is an icon the player can click (enabled)
  ok   the ring slot behind it is EMPTY (0xe4) -- the item is the plugin's
  ok   the click point (378,458) is INSIDE the "+2" box -- this is the user's click
```

Then the click, and the wire:

```
  FAIL [last-slot-cancel] exactly one 0x20 reached queueCommand (0) ()
  FAIL [last-slot-cancel] and its payload is 0x04 ()
  FAIL [last-slot-cancel] minerals go up by exactly one Probe's 50 (2600 -> 2600)
  FAIL the plugin served it itself, exactly once (0)
```

**Zero `CMD id=0x20`. Not a wrong cancel -- no cancel at all.** For contrast, the same run's existing engine-cancel arm (display 1, below cap, no `+N` anywhere) put its command on the wire normally, so clicking a queue icon works in general.

So it is your (1): the click never became a cancel. What I do NOT yet know is which of two sub-causes, and they have different fixes:

1. **our `+N` control has the pixels** -- it is spliced at the TAIL of the statdata child list (task 039 moved it there to fix the drawing), and the tail is what the hit test would return LAST;
2. **the icon itself refuses the click** -- the plugin lights it (clears DISABLED) but the engine's input path may want something else the plugin never wrote.

Static reading of the engine says (1) should NOT happen -- the hit test `0x00418340` walks children HEAD to TAIL and returns the FIRST one that accepts a `{type=0xE, dwUser=4}` probe, and the LSTATIC handler `0x00419190` returns 0 for `dwUser=4` (byte table `0x004191C4[4]=1` -> `0x004191B3` = `xor eax,eax; ret`). That is a READ, not a measurement, and the measurement disagrees with what I would predict from it, so I am not trusting it.

**The next run splits those two and needs no plugin change**: the icon's rect is `(221,53,259,88)` and our box is `(231,65,259,81)`, so there are points inside the icon and OUTSIDE our text. One run clicks both. Outside-the-box cancels and inside-the-box does not -> (1), our pixels. Neither cancels -> (2), the icon.

Machine still in use by me. One more run, ~8 minutes.

Also from this run, unrelated and worth knowing: step 12's pre-existing `plugin-cancel` logical-queue assertion failed on its own timing (`8 -> 7 ... (expected 6)`) with my arm not yet reached. Not caused by this task; I will say whether it is a flake or real once I have a second data point.
