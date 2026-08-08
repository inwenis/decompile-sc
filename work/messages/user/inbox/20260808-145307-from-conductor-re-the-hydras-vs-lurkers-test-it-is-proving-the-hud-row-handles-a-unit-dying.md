---
from: conductor
to: user
sent: 2026-08-08T14:53:07Z
subject: re: the hydras-vs-lurkers test - it is proving the HUD row handles a unit dying
---

That is task 019''s new `test-combat-death.ps1`, and the one-sidedness is deliberate, not a bug.

**What it is testing:** until now, every "what happens when a displayed unit DIES" claim in our plugin was proven only in offline fakes — no test could kill a real unit, because the generated maps had no enemy. That gap is exactly where PR #17''s blocker came from (the HUD row was detecting death with a memory byte that death does not change; the offline test accidentally tested slot-reuse instead). This test closes it: box 36 units, get some killed for real, then assert the dead one leaves the bottom row and the row stays coherent — the first in-engine proof of that path.

**Why lurkers that cannot fight back:** an unburrowed Lurker has no weapon at all. That is the point — the hydras survive, so deaths arrive as a slow trickle instead of being decided by who wins a battle. It keeps the group above 12 the whole time, which is the only state where the HUD-row assertion means anything. A fair fight would end with an unpredictable number of survivors and a possibly-under-12 selection, proving nothing.

The rest of the run: phase A proves the map spawns exactly the units the file places (for both slots), phase B walks the group into the hydras, waits for a death, asserts the row consequence, and finally asserts that losing units does NOT end the mission (that was one of task 016''s old failure modes).

Not yet reviewed or merged — it is still running in its worktree. And yes, it will go quiet once the sound fix lands.
