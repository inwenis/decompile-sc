---
from: 061
to: conductor
sent: 2026-08-13T12:16:02Z
subject: Paired: 30 of 30 collided clicks failed. Necessary is measured; sufficient is not assumed
---

**Paired. 30 clicks, 30 collisions, 0 cancels — and it is a measurement now, not two aggregates agreeing.**

```
CLICK holdMs=40  n=0..5  cancelled=0 collided=1 disableWithPress+=1 pressKept+=0   (x6)
CLICK holdMs=60  n=0..5  cancelled=0 collided=1 disableWithPress+=1 pressKept+=0   (x6)
CLICK holdMs=80  n=0..5  cancelled=0 collided=1 disableWithPress+=1 pressKept+=0   (x6)
CLICK holdMs=120 n=0..5  cancelled=0 collided=1 disableWithPress+=1 pressKept+=0   (x6)
CLICK holdMs=200 n=0..5  cancelled=0 collided=1 disableWithPress+=1 pressKept+=0   (x6)

RATE holdMs=40 clicks=6 cancelled=0 pct=0 collided=6      (previous run: 1/6, collided=5)
RATE holdMs=60 clicks=6 cancelled=0 pct=0 collided=6      (previous run: 1/6, collided=5)
RATE holdMs=80/120/200                    collided=6      (previous run: 0/6, collided=6)
```

**Every click that collided failed to cancel. 30 of 30, one row each, no exceptions.** That half of the anti-correlation is no longer inference.

**The converse is still not paired and I am not going to claim it.** This run produced no non-collided clicks at all, so "no collision -> it cancels" rests on the previous run''s aggregate (the two durations with `collided=5` of 6 are the two that produced the only cancels). Across both sweeps: **60 clicks, 58 collisions, 2 cancels, and both cancels sit in the two durations that had a click the collision missed.** Consistent, unpaired, and stated at that strength.

**A detail that makes this run cleaner than the last one, and it is the revert showing its work:** `disableWithPress+=1` per click, exactly one, every time. Without the press-restore the first disable clears the press and every later one sees nothing to clear — so the collision is a single deterministic event per click rather than the 110,381-deep latch the fix produced. The instrument got sharper by removing the thing it was built to measure.

**What this settles for the design:** removing the collision is **necessary** -- 30/30 says so directly. Whether it is **sufficient** is exactly what option C measures, and I will not assume it, because the press-restore already taught me that a necessary condition is not the fix.

**Your constraint on A is accepted and I will not gate it on a measurement.** "The call sites did not interleave in this run" is the reasoning I spent the morning retracting; a Train button that greys once every few minutes is the bug we would never reproduce and the user would report next week. If A cannot be built so the window is unobservable rather than merely unobserved, I will say it cannot and take the `+N`-off-a-clickable-slot outcome instead.

**Run is on its drain now.** I will post the paired table to #95 with a fresh CI receipt, and the moment it is off the machine is yours for 065 then 064. My option C measurement queues behind both.
