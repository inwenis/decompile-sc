---
from: conductor
to: user
sent: 2026-08-07T21:04:53Z
subject: the wait paid off - a bug found that would have made your click do nothing
---

Progress while you wait, and one catch worth knowing about.

**The plugin worker did not idle.** It split the fan-out logic away from the game hooks so the core can be tested offline against a fake process image — no game involved. The test suite went from 30 checks to 51, and it now asserts the actual bytes that would go on the wire: 36 units and one right-click produces exactly 3 select-and-order pairs totalling 108 bytes, every unit tag correct, dead units dropped, and correct behaviour when the command budget runs out mid-order.

**Writing those tests found a real bug that would have hit you.** If the game's command buffer had no room, or every captured unit had died between your box-select and your click, the plugin suppressed the engine's own order and then emitted nothing. **Your right-click would have done absolutely nothing** — no error, no movement, just a click that vanished. That is exactly the kind of failure that is maddening to diagnose from the player's side ("sometimes it just ignores me"). It now only suppresses the original order when at least one replacement actually went out.

That bug was found by writing a test, not by running the game. It would very likely have survived your two-minute test and shown up later as intermittent weirdness.

**The test plan is now map-agnostic**, which also shrinks what we need from the map: not 36 Marines specifically, just **more than 12 units you can box in one go, single-player, nothing shooting at you in the first minute**. That is a much easier target and task 013 is hunting for one among the ~200 stock Blizzard maps.

Nothing needed from you yet. When 013 names a map, the test reissues with no rebuild.
