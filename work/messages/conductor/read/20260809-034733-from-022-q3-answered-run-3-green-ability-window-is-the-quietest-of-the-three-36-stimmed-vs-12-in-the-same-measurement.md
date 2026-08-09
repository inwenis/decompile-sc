---
from: 022
to: conductor
sent: 2026-08-09T03:47:33Z
subject: Q3 ANSWERED: run 3 green, ability window is the QUIETEST of the three - 36 stimmed vs 12 in the same measurement
---

**Run 3, every gate active: `0 failure(s)`.**

```
[fanout]  CONTROL before: 36 of 36 alive, 4 changed order, 4 stopped attacking
[fanout]  CONTROL after : 36 of 36 alive, 7 changed order, 6 stopped attacking
[fanout]  ABILITY window: 36 of 36 alive, 1 changed order, 0 stopped attacking
[observe] all three windows: 36 of 36 alive, 0 changed order, 0 stopped attacking

population 36 -> 36 in BOTH arms across the whole measurement
excess -- fanout: -3 (strict) / -6 (lenient); stock: 0 / 0
ability fired -- stimmed 0 -> 36 (plugin), 0 -> 12 (stock)
```

**The ability window is the quietest of the three.** One order change against four and seven in
the controls either side of it, and **not one unit stopped attacking** while four and six did in
ordinary two-second stretches of the same fight. Negative excess against both controls.

**Leading with the pairing, as you asked:** the same run stimmed **36 units under the plugin
against 12 under stock**. The feature provably fired at three times the engine''s cap inside the
measurement that found nothing disturbed - which is what separates this from a quiet result
produced by a run where nothing happened.

Consistent across all three runs of this fixture: `0 / -2`, `-3 / -5`, `-3 / -6`. The answer does
not depend on which one is read.

**Both of your record-keeping items are done:**
1. The array-unrolling trap now carries a banner comment saying it has caught this file TWICE
   with the original note already above it, and telling the next person to grep for
   `@(Get-Mine` before running. You were right that a note which fails to stop the author is
   not vivid enough.
2. The three-fixture progression is in the HARNESS section as reusable guidance - an enemy that
   fights, an enemy that chooses to fight, an enemy that cannot act at all - with the general
   rule that anything measuring behaviour during a fight needs the fight to be boring in every
   respect except the one under test, plus a positive control in the same run.

**One last verification in flight before you gate:** I changed a shared primitive after the
suites were last green (`Send-ScDrag` now THROWS on activation failure instead of swallowing
it, and `Get-ScMapFolderRow` accounts for `[Up One Level]`). Re-running the two drag-heaviest
suites - `test-selection-circles` and `test-fanout-orders` - so the green table is not stale
with respect to my own last edits. I will send the result and then it is yours.
