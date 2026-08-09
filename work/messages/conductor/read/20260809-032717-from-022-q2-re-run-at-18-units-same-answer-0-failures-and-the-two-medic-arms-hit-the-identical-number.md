---
from: 022
to: conductor
sent: 2026-08-09T03:27:17Z
subject: Q2 re-run at 18 units: SAME ANSWER, 0 failures - and the two medic arms hit the identical number
---

**Q2 re-run in the regime the question is actually about. Answer unchanged, and it is now
worth more than it was.**

`test-sunken-acquire.ps1`, 18 units, `0 failure(s)`. The plugin arm asserts
`FANOUT start ... units=18`, so it fails loudly if it ever slips back to being stock plus
pass-through hooks.

| arm | lowest hit points | survivors | Sunken order | attacked? |
|---|---|---|---|---|
| Medics, fanout | 276480 -> **271488** | 18/18 | 0x12 -> 0x13 | yes |
| Medics, observe | 276480 -> **271488** | 18/18 | 0x12 -> 0x13 | yes |
| Marines, fanout | 184320 -> 153600 | 15/18 | Sunken destroyed | yes |
| Marines, observe | 184320 -> 148480 | 15/18 | Sunken destroyed | yes |

**The two Medic arms reach the identical lowest hit-point total - 271488 - with and without
the plugin.** Not "both attacked"; the same number. And both Marine arms lost exactly 3 of 18
while destroying the Sunken. Nothing to report to you under the stop-and-message rule: the
plugin arm does not differ from stock.

So Q2''s answer survives the correction that mattered most, and now rests on a run where the
fan-out demonstrably fired. Research doc and report updated with the 18-unit table; the old
6-unit numbers are gone rather than left sitting next to the new ones.

Q3''s re-run is in flight with all four of its corrections: both controls asserted and reported,
the stability gate strictly below its bound, each arm required to show the ability actually
fired in that arm, and every scan the metric uses checked for tearing. I also cut the enemy
from 16 to 10 - the old fixture decayed fast enough that the two control windows disagreed by
exactly the amount the script calls too unstable to mean anything, and steadying the fight is
the fixture''s job rather than the assertion''s.

If it comes back saying the fight still cannot decide it, I will say that rather than tune the
threshold until it passes.
