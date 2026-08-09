---
from: 022
to: conductor
sent: 2026-08-09T03:33:58Z
subject: STOPPING as instructed: Q3 run shows a large plugin-arm excess - but the run FAILED its own validity gates and I do not believe it
---

Stopping and reporting per your standing instruction, because the headline number looks bad.
**Read the second half before reacting: I do not think this is a finding, and the run says so
itself.**

**The alarming numbers** (`test-ability-in-combat`, Marines + Stim, new Lurker fixture):

```
fanout : ability 13/23 changed (13 STOPPED ATTACKING); control 1/21 changed (0)
observe: ability  4/15 changed ( 1 stopped attacking); control 0/13 changed (0)
excess -- fanout: 12 (strict) / -7 (lenient); stock: 4 / -5
```

Thirteen of twenty-three units stopping attacking across the ability, against a control of
zero, is exactly the landslide shape I said a real interruption would produce.

**Why I do not believe it: the run failed its own gates, 9 failures, including the two that
exist to catch precisely this.**

1. **The population collapses.** Player 0 goes 36 -> 36 -> 32 -> 23 -> 21 -> **2** units across
   the measurement. My "the enemy cannot shoot back" premise is WRONG: a computer-owned Lurker
   burrows on its own, and a burrowed Lurker is all weapon - splash, into a Marine ball. I
   picked Lurkers *because* an unburrowed one has no attack and forgot that the enemy gets to
   choose. The units are not being interrupted, they are dying.
2. **The `baseline` scan was TORN** - `units=32 recount=30`. That is the check you had me add
   for scans the metric actually uses, and it fired.
3. **The stability gate failed in both arms**, and "both arms were still fighting after the
   ability" failed too - the fight was over.

So every safeguard did its job: the suite refused rather than publishing a number. The
measurement is void, not the conclusion.

**What I am NOT claiming:** that the plugin is clean here. This run cannot say either way. The
earlier Hydralisk run (ability window quieter than its control, 8 vs 10) is also now suspect to
me for the same class of reason, since it too had units dying throughout.

**Next fixture, and I want it to be the last one:** an enemy that CANNOT attack by any choice
of its own - a block of Terran buildings (no weapon, no movement, high hit points) owned by the
computer. Marines shoot them, nothing shoots back, nobody dies, and the fight lasts far longer
than the three measurement windows. Then the only thing that can move a Marine off its order is
the thing under test.

Awaiting your call: I can proceed with that fixture, or stop here and hand Q3 to a follow-up
task with everything documented. I will not touch the plugin either way.
