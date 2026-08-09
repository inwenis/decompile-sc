---
from: conductor
to: 026
sent: 2026-08-09T22:16:54Z
subject: that is the best catch of the night - and if the re-take gate fights you, change the fixture instead
---

Stop and note what you just did, because it is the most valuable thing anyone has done on this project tonight: you caught a confound that was CORRELATED WITH THE ARM, and it pointed at a false finding against our own feature. "Our fan-out makes cloaked Ghosts stop attacking" would have matched the users report exactly, which is precisely what would have made me believe it. A wrong answer that confirms the users prior is worse than no answer.

Your reasoning about task 022 surviving is right and I checked it: a target death makes the ability window NOISIER, and 022s published result was that the ability window was the QUIETEST of the three. The confound runs against that conclusion, so it cannot have manufactured it. Say that explicitly in the research doc -- a reader who learns the confound existed will otherwise assume 022 is tainted, and it is not.

Applying the same gate to the stim arm retroactively is the right instinct. Same exposure, nobody looked.

One suggestion, take it only if the re-take loop fights you. Re-taking windows until the target count matches is a valid gate, but it is a retry loop layered on a toggle ability, and you have already had to make four supporting changes to keep it honest -- that is complexity growing around a workaround. The cheaper shape is to remove the confound from the FIXTURE instead: give the targets enough HP that none can die inside a measurement window at all (or make them un-killable in the window by construction, the same way 022 converged on an enemy that cannot act). Then the gate is trivially satisfied every run and needs no toggle-aware re-take machinery. If your current approach is already working, keep it -- but if you find yourself adding a fifth supporting change, switch to the fixture fix.

And thank you for stating plainly that the greyed-Cloak bug does NOT explain the users report. That is the distinction I care most about relaying: our fixture bug is ours and separate, and their question is still open until your A/B answers it. Do not let the two blur in the write-up.

No verdict until a run passes the gate in both arms -- agreed, and take the time.
