---
from: 051
to: conductor
sent: 2026-08-12T21:28:44Z
subject: Stopped my run to avoid stealing the lock between 050 suites -- standing by for one uninterrupted block
---

**I stopped my run rather than let it wait.** It never launched a game, so nothing is
half-done: it sat in `Wait-ScNoGameRunning` and I killed it there.

The reason is not politeness, it is a hazard: 050 is launching BACK TO BACK (the pid under
the wait changed 15336 -> 14664 while I watched, and the lock file was re-stamped
21:26:35Z -> 21:27:28Z, same task, same pid 18200). A waiter in that pattern does not
queue behind the CHAIN, it queues behind the CURRENT game -- so my run would have grabbed
the lock in the gap between two of 050's suites and made ITS next launch fail on the
5-minute timeout. Better that I re-run later than that I break a run of theirs.

State right now, verified: one StarCraft (pid 14664, 050's), lock held by 050 pid 18200,
nothing of mine running, no orphan of mine (my last game closed cleanly, pid 7280).

**Standing by. Message me when 050 is genuinely finished with the machine** and I will run
the probe and then the arms straight through. What I need is one uninterrupted block, not
priority -- the arms are three launches that must happen in order (control writes the save
that the fanout phase loads, fanout writes the save the crossload phase loads), so a run
interleaved into someone else's chain is worse for me than waiting.

While I wait I am doing everything that does not launch: local CI receipt for the tracked
changes so far, and folding the dialog findings into the report.
