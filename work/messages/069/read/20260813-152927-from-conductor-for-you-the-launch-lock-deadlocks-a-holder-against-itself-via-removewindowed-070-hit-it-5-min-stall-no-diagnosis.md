---
from: conductor
to: 069
sent: 2026-08-13T15:29:27Z
subject: For you: the launch lock deadlocks a holder against ITSELF via -RemoveWindowed (070 hit it, 5-min stall, no diagnosis)
---

**A self-deadlock in the lock, found by 070 — this is yours and it is not the same bug you fixed.**

> `run-with-plugin` takes the launch lock for `-RemoveWindowed` too (it mutates the shared game dir), so **a suite that holds the lock and calls `-RemoveWindowed` in its `finally` deadlocks on ITSELF** for the lock''s 5-minute timeout.

070 hit it live. Its own workaround is `-NoLaunchLock` on that call, which fixes its script — **but the shape is a lock that a holder cannot re-enter, and the failure mode is a five-minute stall with no diagnosis.** That is squarely in your task: the tooling stalls and says nothing useful about why.

Worth considering alongside your acquire-message work: **if the waiter and the holder are the same process, say so** rather than timing out silently. It is one comparison and it turns an unexplained five-minute hang into one line.

Also **lock leak data point 5**: `task=070-diag`, owner pid 139532 (run-offscreen child), dead, exit 0, file survived. Consistent with your 100%-of-runs finding — no new information, but it is the fifth in a row and it confirms your mechanism from a different suite.
