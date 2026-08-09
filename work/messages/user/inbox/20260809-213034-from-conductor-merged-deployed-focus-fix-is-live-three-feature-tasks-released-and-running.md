---
from: conductor
to: user
sent: 2026-08-09T21:30:34Z
subject: MERGED + DEPLOYED: focus fix is live. Three feature tasks released and running
---

# Focus fix is merged, deployed, and the queue is moving

## What just landed on your desktop

PR #28 merged and deployed to `C:\sc-deploy\starcraft-modded` -- the "StarCraft Modded" shortcut is refreshed. Your saves, replays and settings were excluded from the copy and verified untouched afterwards, as always.

**Tests no longer steal your focus.** Measured, not asserted: six of the nine suites made ZERO foreground changes across their whole run. The other three borrow the foreground once each, for about four seconds, during a dropdown in the menu -- because Windows only grants mouse capture to the foreground window, and that dropdown is a press-and-hold. Before this, the game grabbed the foreground on the first click of every run and kept your mouse clipped inside its window for the entire run.

Final sweep: all nine suites 0 failures. Offline CI green (83 scripts parsed, 34 unit tests, hook engine 0 failures).

One honest note: `test-ability-in-combat` needed a second run. Its first attempt tripped its own sanity guard -- the two control measurements disagreed too much for the comparison to mean anything, so it refused to report a result rather than report a shaky one. Second run was clean. Not an input failure; the game type set on the first try and every real assertion passed.

## Housekeeping you should know about

All three feature workers had gone silent -- their session transcripts were gone from disk, so they could not be woken. I killed and fresh-spawned them into the same worktrees. **No work was lost**: everything they had done is committed on their branches and written up in their PRs, and I briefed each new session to read its own PR first rather than redo anything.

## Now running

| task | feature | PR | doing now |
| --- | --- | --- | --- |
| 024 | box-select same-type buildings | #24 | 2 in-game runs |
| 025 | queue more than 5 units | #25 | 1 in-game run |
| 026 | cloaked-ghost answer | #27 | 2 in-game runs |

They share one launch lock, so they will queue behind each other rather than fight over the game. As each finishes I merge it and deploy, so features land on your shortcut one at a time.

## After those

Queuing upgrades, then the wider screen.

Also filed issue #29: read the game-type setting straight from memory instead of clicking it, which would remove even that four-second flicker. Not urgent, not blocking.
