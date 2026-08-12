---
from: conductor
to: 051
sent: 2026-08-12T22:07:32Z
subject: Your newest crossload arm reports 0 failures at the seam -- does the leak still reproduce? I have told the user it is real and need it confirmed or killed
---

**I need you to confirm or kill the leak finding explicitly, because I have already told the user it is real.** That was on the strength of your arm-5/6 message, and I stand behind relaying it -- but I have just read your two newest runs and I cannot tell from the transcripts whether the finding still reproduces.

What I see:

    20260812-225452 [fanout]   : 1 failure(s) across 4 arm(s)
                                 arm3-fanout-overcap: overflow held at save time = 3  (reaches the seam)
                                 both witnesses pass -- loads really happened
    20260812-230441 [crossload]: 0 failure(s) across 1 arm(s)
                                 overflow held at save time = 3  (reaches the seam)
                                 load: (no PRODQSEL line -- this arm has no production queue)

That last arm is the shape that produced the finding -- crossload, seam reached -- and it now comes back clean, with the assertion you said you were adding (`overflow must be 0 in a game this process never queued in`) presumably in place.

Three readings and I do not want to pick one for you:

1. **The leak is real and this arm does not test it** -- e.g. this crossload runs in a process that never queued over cap itself, so there is nothing stale to carry, and the 0 failures are correct and uninteresting. The original finding needed the SAME process to queue 8 in game A and then load game B.
2. **The leak is real and this arm should have caught it but the new assertion is not wired to the arm that reaches the seam.** A pass that cannot fail, again, and this time in the check written specifically to catch it.
3. **The leak does not reproduce** and the original observation had another explanation.

Tell me which, in one paragraph, and point at the line that settles it. If it is (1), name what the leak arm actually requires so the fix task inherits a reproduction that works. If it is (2), fix the wiring before you report anything. If it is (3), say so plainly and I will correct the user tonight -- I would far rather retract than let them plan around a bug that is not there.

Do not soften it either way. "It reproduces under exactly these conditions and not these" is the useful answer; so is "I was wrong". What is not useful is a report where the headline says leak and the run table says 0 failures, because that is what a reader will notice first and it will cost you the credibility the rest of this work has earned.

For what it is worth I think (1) is most likely, given `no PRODQSEL line -- this arm has no production queue` on the load side. But you have the arms and I do not.
