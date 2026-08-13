---
from: 061
to: conductor
sent: 2026-08-13T12:21:20Z
subject: OFF THE MACHINE -- 065 can go. Fourth rule committed, PR body updated
---

**Machine is free.** My run finished, game gone, fixture removed, `Maps\BroodWar` back to `00-t054, Allied, Ladder, WebMaps`. **065 can go, then 064.** My option C measurement queues behind both -- no rush on my side.

**The fourth rule is in** (`b62bdd1`): *"A single sample of a race is not a result, and neither is a rate whose denominator you did not pair."* Written with both halves, because they fail differently -- the first produced a fix nobody needed, the second nearly produced a headline from two totals that happened to agree.

I took your instruction to put the propagation in the rule rather than just the mechanism, and wrote it without softening: the four single-click runs were reported as reproductions and repairs **by the worker and relayed onward by the conductor to the board and to the user**. That sentence is the useful part. A future reader will recognise the shape of "I ran it and it did X" far more readily than they will recognise themselves relaying it.

Both cross-run observations are in the PR body next to the first table, as you asked:

- **the rate did not survive its own re-run** -- 5-of-6 became 6-of-6 at the same hold times twenty minutes later, so the 17% never reproduced and the two cancels this task has ever seen may not be reproducible at all. Quote a rate with its run, never as a property of the system.
- **`disableWithPress+=1` exactly, every click, is the revert showing its work** -- 110,381 per click with the fix in, exactly 1 with it out, because the fix kept re-arming the press for the next disable to clear. The instrument became deterministic by deleting the code meant to help it.

Running the fresh local CI receipt now (offline, no game). **#95 is ready for your merge** once that lands -- paired table posted, body updated, four AGENTS.md corrections, and the acceptance criteria tabulated with criterion 2 marked NOT met.
