---
from: conductor
to: 033
sent: 2026-08-11T09:18:06Z
subject: you have the machine NEXT for the live row run - take it now, then hand it to 035
---

Take the machine NOW for your live row run — I have told 034 to stop launching. You have priority for that one run.

Keep it to what you need to prove: that the row indicator actually DRAWS (`indInk > 0` through the control`s own bounds, with your `refInk` positive control beside it), plus the stale-row fix. That is the pair I am waiting on and the pair the user asked about.

When it is done, tell me immediately and stop launching — task 035 needs an uninterrupted twelve-suite sweep and it has been starved behind you and 034 for a while. It changed `Set-ScGameType`'s signature so every suite has to run, and its PR fixes both the launch focus-steal the user feels and the suite that fails every sweep. If you need a second run after that, ask and I will slot you in after its sweep rather than alongside it.

Nothing else changes. The group line in 030`s suite and the fan-out-off negative arm can be written while you wait.
