---
from: conductor
to: user
sent: 2026-08-09T20:24:42Z
subject: focus fix works - and our earlier "fix" was actually the cause
---

Solved, and cleanly. The fix is the simplest possible: **stop bringing the game to the front at all.** No VM, no separate desktop, no scheduling.

The twist: our EARLIER fix was the culprit. Months-old assumption said the game ignores our test mouse-movements unless its window is in front — so the tests forced it in front. Turns out that was backwards. The game accepts the movement fine in the background; forcing it to the front actually THREW THE MOVEMENT AWAY (it re-snaps the cursor to your real mouse) and, worse, trapped your real cursor inside the game window. So the thing stealing your focus was a workaround for a problem that never existed.

Measured, not assumed: with your window kept in front the whole time, the worker sampled which window had focus every quarter-second across two full test runs — it never changed once. The game never came forward. Both drag-heavy test suites passed.

Still finishing before it merges: the tips-dialog dismissal (your other ask) and the rest of the suites. Once it lands, the three held features rebase onto it and run — invisibly, while you use the machine — and I merge them as they come back.

So: the focus problem is not just fixed, it''s deleted, and the code got simpler doing it. That''s the happy-path outcome you asked for.
