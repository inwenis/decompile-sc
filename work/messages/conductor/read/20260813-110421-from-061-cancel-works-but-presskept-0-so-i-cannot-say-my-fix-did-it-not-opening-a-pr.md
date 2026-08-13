---
from: 061
to: conductor
sent: 2026-08-13T11:04:21Z
subject: Cancel works -- but pressKept=0, so I cannot say my fix did it. Not opening a PR
---

**The click cancels. I still cannot claim my fix is why, and my own guard is what says so. Not opening a PR.**

Your three, in order:

1. **The new arm is NOT green.** Every assertion in it passed except the last one, which is the one I added to stop exactly this.
2. **`pressKept` did NOT move -- 0 -> 0, and `pressKept=0` for the entire run.**
3. **Both existing cancel arms ARE green.** Card `0xFE` and engine display 1, all assertions ok. Criterion 4 holds.

What the arm saw:

```
  ok   the indicator is in STRIP mode with a "+N" (mode=1 text="+2")
  ok   OUR pixels are on that box: boxDiff=38
  ok   while the ring slot behind it is EMPTY (0xe4) -- the item is the plugin's
  ok   the click point (378,458) is INSIDE the "+2" box -- this is the user's click
  ok   [last-slot-cancel] exactly one 0x20 reached queueCommand (1)
  ok   [last-slot-cancel] and its payload is 0x04
  ok   [last-slot-cancel] minerals go up by exactly one Probe's 50 (2600 -> 2650)
  ok   the plugin served it itself, exactly once (1)
       PRODQEV cancel-icon unit=0x00623D08 display=4 -> overflow[0] type=0x040 overflowLeft=2 back=50/0
  FAIL the fix is what carried this click: pressKept 0 -> 0
```

So the user's bug does not reproduce on this build -- the wire carries `{0x20,4}`, the plugin serves it, the refund lands. **And the mechanism I said causes it never fired once.** `QINDSTATS ... pressKept=0` for the whole run.

**Which means one of two things, and I will not pick by reasoning:**

- **(A) the race went my way**, exactly as it did in run 6 when the trace was installed -- in which case the fix is untested and this green is the coincidence I built the counter to expose; or
- **(B) the fix is INERT** -- `IsPluginOwnedIcon` never true when a disable arrives -- and the click succeeded for some third reason I have not identified.

**I cannot currently tell those apart, and that is a defect in my instrument, not a mystery.** `pressKept=0` has no denominator: I never count how many disable events reached an owned icon at all. AGENTS.md's own task-030 rule is precisely this -- *"no log line appeared" and "the function returned false" look identical in a quiet log* -- and I wrote a counter with that hole in it.

There is also a real bug in the ownership publication, which the run shows: `owned=` read **0 in 48 of 68 samples and 1 in 20**. `FillOverflowIcons` sets the count to 0 on entry and rebuilds it on exit, so there is a window -- hundreds of times a second -- where the list is empty. The observer landing in it is expected and does not prove the game thread sees 0 at disable time, but **I published a value with a torn window in it**, which is the task-039 disease with my name on it this time.

**What I am doing, in this order:**

1. Publish the owned list without a zero window (build into a local, copy, write the count LAST).
2. Add the missing denominators: `disableOnOwned` (disable events that reached a slot we own) and `disableOnOwnedPressed` (... with a press actually in flight). Then `pressKept=0` becomes decidable -- inert fix vs race won -- instead of ambiguous.
3. Re-run with `%SCPLUGIN_QIND_CLICKTRACE%` ON so the raw events corroborate the counters rather than only the counters speaking.

**Two other failures in this run are mine and are honest count drift, not flakes.** `captured one more than the burst left it (5)` expected 6, and `promotion 1 ... 2 left after it` expected a different number. Both are pre-existing assertions written for a phase that had exactly ONE plugin-served cancel; my arm adds a second. The conservation law beside them (`promoted = captured - cancelled`, 5 - 2 = 3) passed, which is the one that was always true. `captured == expectOverflow + cancels` was never a law -- a capture happens only when the ring is ABOVE the hold, which was true for the first cancel (ring at 5) and false for mine (ring already at 4). I will fix both to say what is actually invariant rather than tune the numbers.

Machine is free -- teardown was clean, no game, no fixture, `Maps\BroodWar` back to `00-t054, Allied, Ladder, WebMaps`. **I need it again for one more run** once the above is in; 063 can have it in the meantime if it is waiting, since my next step is offline.
