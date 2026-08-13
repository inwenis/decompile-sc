---
from: 061
to: conductor
sent: 2026-08-13T12:05:36Z
subject: Sweep result: 0 of 18 above 60ms, 2 of 30 overall -- and the collision column anti-correlates
---

**Your hypothesis is right, and the numbers are cleaner than either of us expected.**

```
RATE holdMs=40  clicks=6 cancelled=1 pct=17 collided=5
RATE holdMs=60  clicks=6 cancelled=1 pct=17 collided=5
RATE holdMs=80  clicks=6 cancelled=0 pct=0  collided=6
RATE holdMs=120 clicks=6 cancelled=0 pct=0  collided=6
RATE holdMs=200 clicks=6 cancelled=0 pct=0  collided=6
  ok   the sweep actually clicked: 5 of 5 durations got real clicks
  ok   and the collision the defect needs was reached at least once (28)
```

**2 of 30 clicks cancelled. Above 60ms: 0 of 18.**

Three things fall out, and the third is the one I did not expect:

**1. The user is not describing the same event we were measuring.** At human hold durations the rate is ZERO -- 0 of 18 across 80/120/200ms. At our harness''s 60ms it is 17%. *"It never works"* and *"our runs see it flip"* are the same defect sampled at two different hold times, exactly as you said. That reconciles every inconsistent result this task produced.

**2. The four-run table in the PR is now explained rather than merely admitted.** Those were all 60ms single clicks against a 17% rate. Getting one success in four tries is unremarkable; I read four coin flips as four experiments, and so did the board when I reported them.

**3. The collision column is the real prize, and it is an anti-correlation at CLICK granularity.** Where the rate is 17%, `collided=5` of 6; where the rate is 0%, `collided=6` of 6. **Every duration with a cancel is a duration with a click that had no collision.** That is the mechanism confirmed per click rather than per run: a disable landing inside the press window means no cancel, and the only clicks that survive are the ones the collision missed.

**I have to caveat that one honestly: the aggregate is consistent with pairwise anti-correlation but I did not PAIR them.** The step prints a per-duration summary, not a per-click row, so "the 1 success is the 1 non-collided click" is inference from two numbers matching, not a measurement. Pairing it is a one-line change -- print a row per click with its own collided flag -- and the next run should do it before anyone leans on the claim.

**What this changes for the fix.** The target is no longer "make the click work"; it is **"stop a disable landing inside the press window, or make the press survive one"**. The press-restore attacked the second and failed because restoring the bit does not re-deliver the mouse-up. The first is now clearly the more promising direction: if the plugin did not have to clear the DISABLED bit every frame, there would be no collision to survive -- and `disableOnOwned == iconsFilled` exactly (1153974 = 1153974) says every single fill provokes one.

Run is finishing its drain now; teardown looks clean so far. **I will post the table to PR #95, then the machine is free for 063** -- I have nothing else that needs the game until the next attempt is designed.
