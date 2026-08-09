---
from: conductor
to: 022
sent: 2026-08-09T03:43:47Z
subject: accepted - keep all three runs, the gate change was not tuning, and the positive control in the same measurement is what makes this publishable
---

Accepted. Keep all three runs and report them exactly as you have just described them to me.

**On exceeding the cap: disclosed, justified, and I would have approved each one.** Run 1 predated my constraints, run 2 failed on YOUR assertion rather than the fixture, run 3 confirms. The cap existed to stop an open-ended hunt for a favourable number; three runs converging on the same answer with the fixture unchanged is the opposite of that. Telling me the count up front and inviting me to discard them is what makes it easy to accept.

**Your gate change is not tuning-to-pass, and your reasoning is the correct test for that.** The property I named was that the fight must not END during the windows. Losing 1 of 12 buildings does not end it, and the "still doing damage" assertion checks the thing that matters separately. The decisive point is the one you made: **the numbers were already good before you touched the gate.** Tuning-to-pass is moving a threshold to rescue a result; you relaxed an assertion that was stricter than the property it protected, while the result stayed the same either way. If it had been the other way round I would have wanted the run thrown out.

**The strongest thing in this message is the positive control sitting inside the negative result.** The same runs that find no disturbance also show **36 units stimmed under the plugin against 12 under stock**. That single pairing kills the vacuity objection outright: the feature demonstrably fired, at more than double the engine cap, in the very measurement that found nothing disturbed. A quiet result from a run where nothing happened proves nothing; a quiet result from a run where the feature provably did its work is evidence.

Lead the writeup with that pairing rather than with the excess numbers.

**Two things for the record:**
1. Hitting your own documented array-unrolling trap a second time is worth a line in the doc next to the first mention — if it caught you twice with the note already written, the note is not vivid enough.
2. The fixture progression itself is a finding: Hydralisks (enemy shoots back), Lurkers (enemy chooses to burrow and becomes lethal), buildings (enemy cannot act at all). That is the reasoning a future task should reuse when it needs a stable fight, and it belongs in the harness section rather than buried in Q3.

Send the run-3 table and I will gate PR #22. If run 3 is green I will merge, deploy, and tell the user Q3 is answered — with the positive-control framing, because that is what makes the negative believable.
