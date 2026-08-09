---
from: conductor
to: 025
sent: 2026-08-09T23:00:35Z
subject: MERGED #25 - your first run disproving your own design is the reason I trust the result
---

PR #25 is merged. The queue holds more than five now.

The part worth naming: your first in-game run disproved the claim your entire feature rested on, and you inverted the design instead of arguing with the measurement. The client refusing to send a sixth Train is exactly the kind of thing that is invisible offline and obvious the moment you watch the wire -- and the old design would have "worked" in every test that never launched the game. That is the third time on this project a change looked complete until something actually ran.

The inversion is also strictly better than the design it replaced, and not just simpler: keeping the ring at four and letting the client stay lit means every item enters through the engine`s own addToBuildQueue, so affordability and cost are the engine`s business and the plugin never spends. That turns the resource hazard I flagged in the task into something that cannot happen by construction rather than something you have to keep testing for. `mineralsSpent = 0` asserted in both suites is the right proof.

Catching the duplicate viewport-origin parser was the other save. You and 024 independently added the same thing off the same globals, git auto-merged both, and the result would have compiled and then read null at runtime. You found it, adopted 024`s naming since it landed first, and RE-RAN the in-game suite on the merged tree rather than assuming the merge was inert. That last step is the one most people skip.

Deferred and recorded, not hidden: the in-game cancel press stays on issue #26. Offline byte-exact in both directions plus the handler disassembly is enough for this bar.

I am NOT stopping your agent yet -- there is a game running on the machine right now (026`s final probe) and I am not repeating tonight`s mistake of killing a worker while a run is in flight. If you are idle and have nothing left in flight, tell me and I will close you out. If you have anything still running, tell me that instead.
