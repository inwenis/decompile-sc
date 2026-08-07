---
from: 008
to: conductor
sent: 2026-08-07T07:40:49Z
subject: VERDICT: static map HOLDS at runtime - 1/2/4 confirmed, plus two live behavioural findings
---

**The statically-derived addresses hold in a live process. Yes.**

The log is clean and unambiguous — no need for the user to repeat anything. Full log is
`C:\sc-work\logs\run-wmode-early.log`, 53 lines. Their three actions are the only three state
transitions in it.

## 1. Did `clientSelectionCount` go 1 -> 2 -> box?

Yes, exactly, and nothing else moved in between.

```
[2026-08-07 08:35:48.210] SEL count=0 nonNullGroup=0 iter=0 player=1/1/1 ok=0x3F     <- in game, nothing selected
[2026-08-07 08:35:58.438] SEL count=1 nonNullGroup=1 iter=0 player=1/1/1 ok=0x3F     <- click one worker
[2026-08-07 08:36:07.647] SEL count=2 nonNullGroup=2 iter=0 player=1/1/1 ok=0x3F     <- shift-click second
[2026-08-07 08:36:15.071] SEL count=4 nonNullGroup=4 iter=0 player=1/1/1 ok=0x3F     <- drag-box
```

`count=4` is the right answer, not an approximate one: a melee start is 4 workers plus one main
building, and a drag box containing both selects only the units. Getting exactly 4 rather than 5
is itself a small confirmation that the byte means what we think.

## 2. Does `nonNullGroup` agree with `clientSelectionCount`?

**On every single sample**, including the zero ones: 0/0, 0/0, 0/0, 1/1, 2/2, 2/2, 4/4. The
count byte and the array never disagreed about reality. (`nonNullGroup` is counted independently
by walking all 12 slots, so this is a real cross-check, not the same number printed twice.)

## 3. Are the populated slots contiguous from index 0?

Yes, in all three cases:

```
count=1   clientSelectionGroup   [0]=0x00623678
count=2   clientSelectionGroup   [0]=0x00623678 [1]=0x00623288
count=4   clientSelectionGroup   [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
```

No gaps, no stale pointers past the count, nothing above index 3.

**Bonus corroboration nobody asked for.** The four pointers are separated by *exactly* `0x150`
(336 bytes) each — measured straight from the logged values, no outside assumption:

```
00623678 - 00623528 = 0x150
00623528 - 006233D8 = 0x150
006233D8 - 00623288 = 0x150
```

336 is the community-documented `CUnit` size. And if the community unit-array base `0x0059CCA8`
is assumed, the four land on **exact integer indices 1638, 1639, 1640, 1641** — consecutive, zero
remainder on all four. The stride is our own measurement; the base is unverified prior art and I
will flag it as such in the doc. But four exact hits is not a coincidence.

## 4. Do the client-side and simulation-side arrays differ? YES — two ways

This is the most interesting thing in the log, and the recon's prediction was right.

**(a) They update at different times.** At `08:36:07.647` the client array already had two units
while `playersSelections[1]` still had one. It caught up 268 ms later:

```
[08:36:07.647]  clientSelectionGroup   [0]=0x00623678 [1]=0x00623288
[08:36:07.647]  playersSelections[1]   [0]=0x00623678                  <- one behind
[08:36:07.915]  playersSelections[1]   [0]=0x00623678 [1]=0x00623288   <- caught up
```

**The client array leads; the per-player array follows.** That is the command-latency/turn model
showing up in memory, and it matters directly for rung 2: whichever array rung 2 keeps in step
with, it must not assume the two are coherent within a frame.

**(b) They order the same units differently.** At `count=4`:

```
clientSelectionGroup   [0]=0x00623678 [1]=0x00623528 [2]=0x006233D8 [3]=0x00623288
playersSelections[1]   [0]=0x00623678 [1]=0x00623288 [2]=0x00623528 [3]=0x006233D8
```

Same four units, different order. The client array is in strict descending pointer order (i.e.
rebuilt from scratch, ordered by unit-array position). `playersSelections[1]` keeps the two
already-selected units first, in their original selection order, and appends the new ones — an
append-if-absent update, consistent with the 12-bounded de-duplication scan
`binary-selection-map.md` §6 describes.

`activePlayerSelection` (`0x006284B8`), by contrast, matched `clientSelectionGroup` **exactly**,
element for element and order for order, on every sample — including the lagging one. So
`activePlayerSelection` moves with the client copy, not with `playersSelections`, despite the two
being physically adjacent in memory.

`clientSelectionGroup2` (`0x0059724C`) also tracked `clientSelectionGroup` exactly throughout.

## 5. What did `selectionIterator` do?

**Nothing — it read `0` on every sample**, before, during and after all three transitions.

Stated honestly: that does not prove it is unused. We sample at 200-250 ms, so a value that is
set and cleared inside one function call is invisible to us. All we can say is that it is 0
whenever nobody is mid-operation.

## Extra: the three player-id globals are genuinely distinct

`binary-selection-map.md` §7 note 7 warns that conflating them causes bugs. The log shows them
**actually disagreeing**, transiently, during the transition into the game:

```
[08:35:46.659] player=8/8/8 -> 8/0/8    <- 0x00512688 updates first
[08:35:48.210] player=1/1/1             <- all three settle
```

(`8` is the no-active-player value at the menu.) In steady state in-game all three read `1`. The
warning is correct and now has live evidence behind it. Note the active player is **1, not 0** —
worth knowing before anyone indexes `playersSelections[0]` by habit.

## Verdict

| | |
|---|---|
| `clientSelectionGroup` `0x00597208` | **holds** |
| `clientSelectionCount` `0x0059723D` | **holds**, and is a `u8` as §7.2 resolved |
| `activePlayerSelection` `0x006284B8` | **holds** |
| `playersSelections` `0x006284E8` `[8][12]` | **holds**, row stride 48 bytes confirmed at player 1 |
| `clientSelectionGroup2` `0x0059724C` | **holds** |
| `selectionIterator` `0x006284B6` | readable, always 0 at our sampling rate — unconfirmed either way |
| player ids `0x0051267C` / `0x00512688` / `0x00512678` | **hold**, and are distinct as warned |
| module base | `0x00400000`, reloc delta `+0` — usable verbatim |

**Nothing disagreed.** No address was wrong, no shape was wrong, no width was wrong. The two
differences found (§4a timing, §4b ordering) are between two arrays the map already says are
different things — they are new behavioural facts, not errors in the map.

Writing up `research/runtime-selection-observations.md` now, then PR.
