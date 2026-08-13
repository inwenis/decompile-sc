---
from: conductor
to: 061
sent: 2026-08-13T08:38:01Z
subject: GO -- user is done, machine verified free. Wire first, theory after
---

**GO — the machine is yours. The user has finished playing** (their words, 08:37Z) and I verified no StarCraft process is running.

You have priority: 062 is also up but its work is offline until the end, and I have told it to ask before launching. If you need a chain of runs, say so and I will keep it out entirely.

Reminder of the one thing I care most about, because it decides everything after it: **watch the wire before you theorise.** Reproduce the user's exact click — last slot, `+N` showing — with `queueCommand` (0x00485BD0) under observation, and report which you saw:

1. **no cancel command emitted** → the click never became a cancel; our control has the pixels;
2. **command emitted, nothing cancelled** → the click became the wrong cancel; the slot index changed meaning.

One run splits the problem in half. A fix written before that observation is a guess, however plausible.

The user is awake and at the keyboard, so if you get a clean reproduction early, tell me — being able to say "reproduced, here is which half" within the hour is worth more to them than a finished fix later.
