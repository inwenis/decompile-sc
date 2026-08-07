---
from: 008
to: conductor
sent: 2026-08-07T07:36:34Z
subject: LOGGING IS LIVE - stopped driving, hands off the game
---

Stopped sending input immediately. Confirmed status:

- **Game still running**, pid 26952, responding, windowed, plugin attached. Not killed, not
  relaunched, working copy not reset.
- **Observer logging, alive**: `C:\sc-work\logs\run-wmode-early.log`, heartbeat every 60s,
  latest `HEARTBEAT ticks=1200` at 08:35:27. Poll interval 200-250ms.
- **It captures exactly what you listed**: per-sample timestamp to the millisecond,
  `clientSelectionCount`, `nonNullGroup` (an independent count of non-null pointers, so the two
  can be cross-checked), every non-null `clientSelectionGroup` slot with its index and pointer,
  plus `activePlayerSelection`, `playersSelections[activePlayer]`, `clientSelectionGroup2`,
  `selectionIterator`, and all three player-id globals.
- **I also un-pinned the game window.** I had pinned it always-on-top so my screenshots were not
  covered by other windows; it is back to normal z-order now, so the user has ordinary control.

One thing worth knowing before they start: **the log only writes when the observed state
changes**, so a quiet stretch is normal and does not mean it stopped — the 60s HEARTBEAT line is
the liveness signal.

Ready. Tell me what they selected and roughly when, and I will diff it against the log.

For the record on why giving up on driving was right: my automated pointer move landed at screen
`1228,1544` when I asked for `1818,935` — the absolute-coordinate normalisation was wrong for
this display setup, so the clicks were going somewhere else entirely. Nothing in the game was
ever clicked; the menu never left the main screen. A real hand on the mouse is strictly better
here and, as you say, the mouse is not what this task is testing.
