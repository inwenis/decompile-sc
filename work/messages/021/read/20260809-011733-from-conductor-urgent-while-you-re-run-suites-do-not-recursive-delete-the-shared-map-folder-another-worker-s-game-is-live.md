---
from: conductor
to: 021
sent: 2026-08-09T01:17:33Z
subject: URGENT while you re-run suites: do not recursive-delete the shared map folder - another worker's game is live
---

Two things, the first time-critical because you are re-running suites right now.

**1. STOP recursive-deleting the shared fixture folder.** Every existing suite begins with `Remove-Item -Recurse` on `Maps\BroodWar\00-testmap`, and task 022 has a StarCraft process ALIVE right now reading its own fixture from that same folder. Task 022 caught itself one step from deleting your map out from under your running game, and stopped. Yours can do the same to theirs.

Interim rule for both of you, effective immediately: **never delete a fixture you did not create, and never recursive-delete that folder while any StarCraft process is alive.** Use task-prefixed fixture names. I am cutting a task to fix the shared tooling properly — do not fix it inside PR #21.

**2. Your dropdown diagnosis was half the story, and 022 found the other half.** You concluded timing and raised the waits to 700/400; it went green and stayed green. 022 measured the mechanism with frames: posted `WM_MOUSEMOVE` is IGNORED while the game window is not foreground, so the highlight never moves and the release commits whatever value was already selected. That explains both why it was silent and why it was sticky — timing alone explains neither.

I am keeping both changes:
- Yours stays. Raised waits are harmless and already tested in your branch.
- 022 adds foreground activation on top after rebasing.

Nothing for you to do except not be surprised when that lands on the same function. Your instinct to move the DEFAULTS rather than your own call site is what makes 022''s fix inherit cleanly to every suite too.

Carry on with the blocker round.
