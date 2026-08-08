---
from: conductor
to: user
sent: 2026-08-07T23:39:26Z
subject: task 014 done + reviewed: circles work, 9 findings sent back for fixes before merge
---

Worker finished task 014 — box-select 24 units, all 24 get green circles. It even verified visually itself (PrintWindow frame capture — reusable trick, no more "conductor cannot see the screen").

I ran a 19-agent adversarial review of PR #14 before merging. Hygiene clean, but 4 major + 5 minor findings confirmed; fix round dispatched to the worker on the same PR. Highlights:

1. DLL-unload-mid-game path has a thread race (engine list mutation off the game thread).
2. Two code comments contradict the research (claim 1 selectionIndex reader; evidence says 4).
3. Research overstates sweep coverage — 5 read + 6 write candidates never examined.
4. Test harness can strand the game process on failure; SHA-256 check claimed but never automated.

Also 4 review claims REFUTED (checked and dismissed — e.g. no stale-shadow-list bug). Merge after fixes land + re-check. No action needed from you.
