---
from: conductor
to: user
sent: 2026-08-09T03:29:13Z
subject: re: my correction - the sunken/medic answer is BACK, and on better evidence than the first time
---

Half of the correction I sent you 25 minutes ago can now be un-sent. Precision cuts both ways, so you get this promptly too.

**The sunken/medic answer is re-established, in the regime your report actually came from.** Re-run at 18 units, so the fan-out was genuinely active this time — and the test now fails loudly if the mod ever slips back to being dormant, which is the hole that invalidated the first attempt.

The result is stronger than "both attacked":

| arm | lowest health reached | survivors |
|---|---|---|
| Medics, mod ON | 271488 | 18/18 |
| Medics, mod OFF | **271488** | 18/18 |
| Marines, mod ON | 153600 | 15/18 |
| Marines, mod OFF | 148480 | 15/18 |

The two medic runs reached the **identical** number with and without the mod, and both marine runs lost exactly 3 of 18 while killing the sunken. That is not "we could not detect a difference" — that is the same behaviour, measured.

So: **not our bug**, and the three vanilla explanations I gave you stand — one target at a time, medics healing each other between shots, range geometry. The old 6-unit numbers have been deleted rather than left sitting next to the new ones, which is the right way to retire bad evidence.

**Still open: the order-interruption question** (your "units stopped attacking" reports). That re-run is in flight with all four corrections, including one I want to highlight because it is the right instinct: the previous fight decayed so fast that the two control windows disagreed by exactly the margin the script calls "too unstable to measure", so the worker **made the fight steadier by cutting the enemy force** rather than loosening the threshold until it passed. Fixing the experiment instead of the pass mark.

They have also told me that if it still cannot decide, they will say so rather than tune it. I will pass on whichever answer arrives.
