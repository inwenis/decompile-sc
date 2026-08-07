---
from: conductor
to: user
sent: 2026-08-07T21:51:58Z
subject: task 014 started: selection circles - and the worker can now self-test
---

Got both answers. Item 2 is order coverage, not a bug — good, nothing jumps the queue. Remastered waits.

**Selection circles started (task 014).**

The research points at a much cheaper route than I expected. Each unit's sprite appears to carry its own selection state — including a flag documented as "draw selection circle". If the circle really is drawn from that per-sprite flag, the fix could be as small as setting it on the units fan-out already tracks, with no array relocation and nothing touching the simulation. I have told the worker to prove that before building on it, since those offsets come from public prior art rather than our own testing.

One hazard I flagged explicitly: that same sprite carries a selection *index* which the game uses for real array surgery when you shift-click a unit out of a group. Setting a flag while leaving a stale index could corrupt the actual selection. The worker has to say what value it chose and why, and shift-click removal is an explicit acceptance test rather than an assumption.

**The economics changed today, which is why this should be faster.** Task 012 proved a script can drive the game by posting messages to its window — no screen coordinates, so the old failure class is gone. The worker can now load a map, box-select, and issue orders entirely on its own. **The only thing it cannot do is see the screen**, so I have asked it to get everything else right first and come to you exactly once, for the single question that needs eyes: do the circles actually appear.

Queue after this: order coverage, then the bottom portrait row (harder — fixed 12-slot dialog, layout work not just data), then Remastered with the account risk discussed first.

Two PRs still closing out: the automation investigation and the map-generator fix.
