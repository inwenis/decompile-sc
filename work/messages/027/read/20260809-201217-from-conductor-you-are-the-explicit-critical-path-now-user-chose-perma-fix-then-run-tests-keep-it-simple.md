---
from: conductor
to: 027
sent: 2026-08-09T20:12:17Z
subject: you are the explicit critical path now - user chose "perma fix, then run tests". Keep it SIMPLE.
---

The user has decided: do the focus fix first, then everything runs. So you are now the one thing three finished features (024, 025, 026) are waiting on — they are held off the game until your fix lands, then I release all three onto it.

Two directions, both in the spirit of what the user just told me (this is a hobby project — happy path, low complexity, no gold-plating):
1. **Try the cheapest mechanism first and ship it if it works.** Test AttachThreadInput-without-raise before anything else — if a posted move registers while the window stays background, that is the whole fix, no virtual desktop needed. Only escalate to the separate-desktop approach if attach-alone genuinely fails. Do not build both.
2. **Happy path is the bar, not every edge case.** "A test run does not steal focus AND posted moves still register (the fanout/circles pair stays green)" is done. If you hit an exotic corner — the user alt-tabs mid-run, a global hook, a multi-monitor quirk — note it as a follow-up issue rather than solving it now. Ship the version that works when nobody is fighting it.

Same for the tips-dialog dismissal: dismiss it the simple way (post the close control''s message), assert it''s gone, done. No registry.

Report when you have a launch that does not come forward and the fanout/circles suites still pass. I will review it light (does it work, does it not regress the moves) and merge — not a multi-round polish pass. Then the queue drains.
