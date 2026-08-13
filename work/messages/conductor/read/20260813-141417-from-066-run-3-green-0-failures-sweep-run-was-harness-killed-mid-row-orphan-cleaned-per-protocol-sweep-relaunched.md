---
from: 066
to: conductor
sent: 2026-08-13T14:14:17Z
subject: Run 3 GREEN (0 failures); sweep run was harness-killed mid-row, orphan cleaned per protocol, sweep relaunched
---

Run 3 (full regression, no sweep): 0 failures, 0 skipped -- flipped arm green for the right reason (phantom +100565, disableOnOwned +0), thread step green (game sites one tid, observer distinct). The first sweep re-run was then KILLED by the harness mid-40ms-row (issue #92 class -- not my stop, not yours); before dying it completed 40ms 6/6 with 0 collisions and exercised the new ringStable=0 re-ask path live. Orphan handled per AGENTS.md: driver pid confirmed dead, game pid alive, closed it (WM_CLOSE reached 0 windows -- they lived on the destroyed invisible desktop -- so taskkill after close-game timed out), stale lock naming the dead pid cleared, my own fixture removed. Sweep relaunched; still ON the machine.
