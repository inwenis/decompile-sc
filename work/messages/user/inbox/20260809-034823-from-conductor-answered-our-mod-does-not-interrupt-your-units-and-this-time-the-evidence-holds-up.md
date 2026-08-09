---
from: conductor
to: user
sent: 2026-08-09T03:48:23Z
subject: ANSWERED: our mod does not interrupt your units - and this time the evidence holds up
---

Third time on this question, and this one is solid. Here is why you can believe it where you could not believe the first two.

**The answer: our mod does not interrupt units that are already doing something.**

```
mod ON   control before: 4 units changed order, 4 stopped attacking
mod ON   control after : 7 units changed order, 6 stopped attacking
mod ON   ABILITY window: 1 unit  changed order, 0 stopped attacking
mod OFF  all windows   : 0, 0, 0
population 36 -> 36 in both arms, nothing died
```

**The moment the mod does its work is the QUIETEST part of the fight.** One order change, against four and seven in ordinary two-second stretches either side of it. Not one unit stopped attacking during it, while four and six did on their own in the control windows.

**The detail that makes it evidence rather than silence:** in that same measurement, **36 units were stimmed under the mod against 12 without it.** The feature provably fired at three times the game''s own cap inside the very run that found nothing disturbed. A quiet result from a run where nothing happened proves nothing; this is the opposite.

**Why the first two attempts failed, briefly, because it is the interesting part:**

1. Attempt 1 used Hydralisks as the enemy — they shoot back, units died throughout, and the comparison measured mortality rather than interruption.
2. Attempt 2 used Lurkers, picked because an unburrowed Lurker has no weapon. But the computer gets to burrow them, and a burrowed Lurker is area damage into a ball of Marines: 36 units became 2. That run produced a terrifying-looking number which the test correctly threw away.
3. Attempt 3 used computer-owned buildings — no weapon, no movement, nothing they can choose to do. The only thing that can move a Marine off its order is the thing being tested. Nothing died in either arm.

The general rule the worker wrote down from it: anything measuring behaviour during a fight needs the fight to be boring in every respect except the one under test.

**So all three of your questions now have answers**: stim applies to every unit and each pays its own health; the sunken/medic thing is vanilla; and our commands do not interrupt your units. **Your cloaked ghost specifically stays open** — we still cannot make the game issue Cloak from a script, and that is recorded as unknown rather than guessed at.
