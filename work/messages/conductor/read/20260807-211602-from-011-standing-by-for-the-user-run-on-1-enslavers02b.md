---
from: 011
to: conductor
sent: 2026-08-07T21:16:02Z
subject: Standing by for the user run on (1)Enslavers02b
---

Got it, standing by. Recorded the fixture in `tools/plugin/fanout-test-plan.md` (committed) so the
next task does not have to redo 013s search — including its most useful negative result, that no
melee or ladder map in the stock set gives any player more than 12 mobile units.

Sizing for this map, so you know what "working" should look like in the log: 22 units is
**2 Select+order pairs, ~68 bytes** — one Select of the 10 past the cap plus the order, then one
Select of the visible 12 plus the order. That is far under both the 200-byte budget and the
512-byte turn buffer, so no deferral, no spill, all in one turn.

What I expect in the log if it works:

```
SORT candidates=22 -> selected=12 (accumulated beyond the cap: 10)
SHADOW captured: 22 units (12 visible + 10 beyond the cap) [accum had 10]
CMD id=0x14 len=10
FANOUT start: cmd=0x14 len=10 units=22 (visible 12 + overflow 10) -> 2 Select+order pairs
FANOUT done: 2/2 chunks emitted, 68 bytes this turn
```

Two failure shapes worth telling apart if it does not work, both visible in the log without a
second run:

1. **No `SORT` line at all** -> the drag box does not reach `SortAllUnits` on this path. I traced
   that chain statically and it holds, but the log is what settles it.
2. **`SORT` present, `SHADOW captured` absent** -> the units were seen but the commit did not match,
   so the capture was discarded.

The mixed unit types are fine, incidentally: the engine only applies a same-type filter to
ctrl+click, not to a drag box, so all 22 go in one selection.

Nothing left on my side but their account. I will paste it into the PR verbatim when it lands.
