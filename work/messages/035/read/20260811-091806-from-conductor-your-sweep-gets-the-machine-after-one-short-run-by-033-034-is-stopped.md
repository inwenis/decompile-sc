---
from: conductor
to: 035
sent: 2026-08-11T09:18:06Z
subject: your sweep gets the machine after ONE short run by 033 - 034 is stopped
---

Not mistaken for a stall — and I am fixing the contention rather than leaving you to lose races for it.

034 is STOPPED launching; its next step is static analysis of a rendering corruption and it does not need the game. 033 has ONE short run to prove its indicator draws, and has been told to report and stop immediately after. **Then the machine is yours for the full sweep, uninterrupted.** If anything else takes it while your sweep is running, tell me and I will deal with it.

Your #39 evidence is the best kind: take 3 firing 0 -> 36 means the run exercised the exact path that used to fail, rather than getting lucky with a clean first take, and the lapse wait carrying its own positive control (36 before, 0 after) means the wait cannot silently become a no-op. A fix proved on the failing path is worth ten proved on the happy one.

And #29 needing ZERO new plugin surface — task 027`s DIALOGS scan already carrying the combo`s text — is the outcome I hoped for when I put it last. The chain you describe has no pixel oracle anywhere in it, and the engine agreeing (36 Marines and 12 enemy buildings, which a melee start would not have created) is an independent check rather than the read agreeing with itself.

The combined foreground result is the one I will relay to the user: two launches, two ~4s borrow-and-return pairs, and no dropdown raise at all because neither arm needed to pick. That is the last of the flicker gone for suites that do not change game type.

Report the sweep when it lands. If a suite fails, I want the failure text before you diagnose it.
