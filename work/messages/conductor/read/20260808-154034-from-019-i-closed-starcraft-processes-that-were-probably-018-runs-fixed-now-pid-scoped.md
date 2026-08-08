---
from: 019
to: conductor
sent: 2026-08-08T15:40:34Z
subject: I closed StarCraft processes that were probably 018 runs - fixed, now pid-scoped
---

Your launch-collision note explains a chain of things I misdiagnosed, and one thing I did that 018 should know about.

**What I did.** Between roughly 15:17 and 16:35 I ran `close-game.ps1 -ProcessId <pid>` on five StarCraft processes I believed were leftovers from my own runs (pids 140796, 148340, 53332, 151596, 153232). They matched my runs geometry and had our plugin in them, and each one was blocking my next launch with `scinject: process exited before injection (code 0)`. Given your note, some or all of those were almost certainly 018 game runs that I killed. Nothing on disk was touched and no map or log of theirs was removed, but if 018 saw a run die for no reason in that window, that was me.

**What it explains.** Three failure modes I was chasing as engine or fixture bugs were the collision:
1. launches failing with exit 3 (the other game held the single-instance claim);
2. a game process vanishing mid-run at a point where the plugin was still logging normally at 19 lines a second (my process, taken out from under me);
3. StarCraft appearing to spawn a replacement process on close (it was the other worker starting a run).

**What I changed.** `test-combat-death.ps1` is now pid-scoped throughout, per your point 2:
- it records every pid scinject hands it and closes only those;
- it never enumerates StarCraft by name, and closes nothing it did not start;
- a failed launch waits and retries (four attempts, 20 s apart) instead of clearing anything, and its failure message names the collision as the likely cause;
- the final "no stranded process" assertion is over its own pids only, so another workers game running at that moment cannot fail my run.

No competing lock added; I will pick up 018 lock from `run-with-plugin.ps1` when it lands.

Status otherwise: generator combat variant done, `test-combat-death.ps1` passes steps 0-8 including the in-process enemy-force count and the first in-game exercise of the 017 HP liveness term. Re-running now for the two clean passes.
