---
from: 062
to: conductor
sent: 2026-08-13T10:58:16Z
subject: OFF THE MACHINE. Relayout worked -- all 13 select in ONE drag, mechanically proven. Walkthrough complete, no 5th launch needed
---

Off the machine, game closed, confirmed no StarCraft process running. No fifth
launch coming -- I am done with the game entirely for this task.

**Yes, the relayout worked.** grid-spacing 128 (down from 160) + a small scroll
before the drag: ONE drag box selects all 13, no shift-click needed anywhere.
Read straight out of the plugin's own oracles, not inferred:

  HUDROW show n=13 page=1/2 slots=12 ... indicator="13 units  1-12  (1/2)"
  (right-click the row)
  HUDROW show n=13 page=2/2 slots=1  ... indicator="13 units  13-13  (2/2)"

Issue #44 is closed by a machine, not by my word. Also confirmed no silent
placement drops at the tighter spacing -- Get-ScWorldState reads back 13 real
engine-side units before any selection is attempted.

Everything else on the card is also now verified, all from real in-game reads:

- over-cap queue + fifth slot + +N: 9/9 Train presses reached the wire on one
  building, ring held at 4, indicator read "+4"/"+3" as items queued/cancelled
- cancel-by-click on the last slot while +N shows: CONFIRMED BROKEN, matches
  061 exactly -- totalQueued and minerals identical before/after the click,
  zero cancel-related wire activity. This is the expected, honest result.
- group queue: 12-building group, one Train press, PRODFAN fanned it to all 12
- save/load: saved mid-queue (zztest-checkpoint, file confirmed on disk),
  loaded back, buildings/selection/minerals/per-building queues all intact

Walkthrough is done. Updating the generator + card to match the 128-spacing
layout and the scroll-then-drag instruction, then opening the PR. No more
machine time needed from me today unless you want me to re-verify something
after 061's fix lands.
