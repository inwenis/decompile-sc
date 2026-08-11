---
from: conductor
to: user
sent: 2026-08-11T00:21:11Z
subject: OVERNIGHT DONE: everything we talked about is merged and deployed. 8 PRs, 5 tasks, queue empty
---

# Good morning — the queue is drained

Everything we discussed is merged and on your desktop shortcut. **No open PRs, no open tasks, nothing waiting on you.**

## New in your game (double-click the shortcut)

| what | how to use it |
| --- | --- |
| **Queue upgrades** | At an Academy/Engineering Bay/Forge, click a second upgrade while one is running. They run in order. Stacking LEVELS works too — Weapons 1, then 2, then 3. |
| **Train at every selected building** | Box several Barracks, click Train once → every one of them queues a unit. |
| **Queue more than 5 units** | 16 per building. |
| **Select same-type buildings as a group** | Drag a box over them. |

Plus everything from before: >12 unit selection, orders and abilities fanning out to all of them, selection circles, HUD row paging.

**Two limits worth knowing before you meet them:**

1. **Multi-building training shows ONE queue.** Select 4 Barracks, click Train, and you see one queue while 4x50 minerals leave. All four really are building — you can see it on each building — but the status strip only ever draws the primary one. Fixing that properly means splicing a second UI dialog; much bigger than the feature itself.
2. **The production strip only draws 5 icons** even when 9 are queued. To cancel deep items, press the Cancel button repeatedly (it removes the last one each time).

## Your cancel question — answered and proved

Cancelling is now tested in a real game, both cases. There turned out to be TWO cancel controls: the queue icon in the status strip cancels that item (the game refunds it), and the card`s Cancel button removes the LAST queued item — which is the only way to reach anything past the game`s own five. Both clicked in a live game, both refunds checked against actual minerals.

## Wider screen — the answer is NO, with reasons

Mapped the renderer properly. It is not "hard", it is structurally blocked:

- **There is no viewport setting.** 640x400 is hardcoded in ~30 separate places.
- **The buffer cannot grow** — another live variable sits immediately after it in memory.
- **"Stock HUD" is the expensive half** — the console art is fixed-width, so a wider screen leaves a strip of nothing unless someone draws new art, which we will not ship.
- **WMode just upscales**, which is the option you already rejected.

No partial version was shipped on purpose: every intermediate step gives the same small image in the corner of a bigger black rectangle — worse than what you have. The map is written down if you ever want to revisit it.

## Tests are faster

Your idea was right and now measured: 68% of a production test run was waiting for units to build. Map-level build times are now settable, and that suite went 215s -> 160s. A tool now exists that tells you where any suite`s time went.

## What the night actually produced, beyond features

Nine defects, every one found by RUNNING something rather than reasoning about it. The two worth your time:

1. **A worker nearly reported a false bug against our own mod** — 33 of 36 cloaked Ghosts appearing to stop attacking, which matched your report exactly. It was a target dying mid-measurement, and it was MORE likely in the modded arm precisely because the feature works. Caught before publication.
2. **A test was mis-counting about one run in three** — it counted units still being built as finished. That reads as a flake, and a flake is the worst kind of bug because people re-run instead of investigating. It was in code merged the same evening. It surfaced only because making tests faster turned a rare race into a near-certain one.

Also: a merge nearly dropped the upgrade queue from YOUR build silently — "keep both sides" produced something that parses and is wrong, twice in three merges.

## Filed for later, nothing blocking

- **#30** focus stealing: solved the mystery. The game takes focus when its window is CREATED, not from anything the test harness does. Fix is known.
- **#35** test part numbers collide across branches (3 times now)
- **#37** a rare file race that fails a run for unrelated reasons
- **#39** one test suite fails reproducibly — its own retry logic, not a real failure
- **#29** a cleaner way to set the game type that would remove the last window flicker

## One thing only you can do

GitHub Actions is still billing-blocked. Everything ran on local checks instead, with a receipt per merge, so nothing was skipped — but the cloud CI badge will stay red until that is sorted.
