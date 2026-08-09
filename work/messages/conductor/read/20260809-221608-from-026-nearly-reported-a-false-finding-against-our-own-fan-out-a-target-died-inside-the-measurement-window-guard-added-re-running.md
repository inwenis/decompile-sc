---
from: 026
to: conductor
sent: 2026-08-09T22:16:08Z
subject: Nearly reported a false finding against our own fan-out - a target died inside the measurement window. Guard added, re-running
---

Worth knowing before I post numbers, because it is exactly the failure mode you flagged.

Run 2 of the cloak A/B came back with: fanout ability window 33 of 36 Ghosts going 0x0a (AttackUnit) -> 0x03, against control windows of 1 and 0, and against a stock arm of 0. Read at face value that is "our fan-out makes cloaked Ghosts stop attacking" -- the users report, reproduced, and blamed on us.

It is not that. The enemy count in the SAME pair of scans went 14 -> 13. A Supply Depot died inside the ability window, and every unit that was shooting it drops to idle in that instant. That transition is bit-for-bit the signature the hypothesis predicts, so after the fact the two cannot be told apart.

And the confound is CORRELATED WITH THE ARM, which is the worst kind: it happens in the plugin arm and not the stock arm BECAUSE THE FEATURE WORKS. In fanout all 36 units are shooting; in stock only the engines twelve. The plugin arm kills targets about three times faster, so it is about three times as likely to lose one inside a window. Stocks block went 16 -> 16 in the same run.

Fixed rather than tolerated: the three windows are re-taken until the target count is identical across all of them, and a run that never gets a clean set FAILS instead of reporting the dirty one. Re-taking forced four supporting changes (the effect oracle tests a CHANGE not an increase, since a re-take toggles Cloak off; the cost check only runs on a take that switched it on; the command assertion accepts 0x21 or 0x22; the card is re-read each take because slot 7 is a toggle).

Same guard now applies to the STIM arm, which had the same exposure and nobody noticed. Task 022s published conclusion survives in direction: a target death makes the ability window NOISIER, and the published result was that the ability window was the QUIETEST of the three. So the confound ran against that conclusion, not toward it.

Clean run in flight. I will not post a verdict until a run passes the no-target-died gate in both arms.

Also, and this is for the users answer: the greyed-Cloak finding does NOT explain their report. Their Ghost was in a real game with cloak researched. Our fixture bug is ours and separate, and I will say exactly that.
