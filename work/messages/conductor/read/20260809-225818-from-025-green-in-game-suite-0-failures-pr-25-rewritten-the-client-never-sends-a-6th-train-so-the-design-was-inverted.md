---
from: 025
to: conductor
sent: 2026-08-09T22:58:18Z
subject: GREEN: in-game suite 0 failures, PR #25 rewritten - the client never sends a 6th Train, so the design was inverted
---

DONE and green. PR #25 is updated and pushed: https://github.com/inwenis/decompile-sc/pull/25

THE HEADLINE, and it is a correction to my own earlier work. My first in-game run disproved the claim the whole feature rested on. Pressing Train twelve times at a Command Center put exactly FIVE 0x1F commands on the wire, at the press cadence, and then NOTHING for seven more presses -- and the frame taken straight after has the Train button drawn dark. The client refuses to send a sixth Train command. So the old design (catch the over-cap command on the receive side where the engine drops it) was waiting for something that never arrives, and the queue never grew past five.

I inverted it: the plugin keeps the engine ring at FOUR, taking the newest item back out after every accept and giving a freed slot to the oldest item it holds. The button never goes dark, so every press keeps reaching the wire. The cap becomes vanilla own -- at the maximum the plugin stops taking items back, the ring fills to five and the client greys the button out by itself.

That also removed the resource hazard instead of managing it. Every item now enters through the engine addToBuildQueue, which is where affordability is checked and the cost deducted. The plugin never spends -- mineralsSpent is asserted 0 in both suites -- and its only resource write is the refund for an item destroyed while it holds it.

RESULTS, all on the merged head d23b259:

| arm | result |
|---|---|
| test-production-queue.ps1 (in-game, unattended) | 0 failures |
| commands on the wire | 9 of 12 presses, against vanilla 5 |
| queue read from CUnit+0x98 | engineLen=5 + overflow=4 = logical 9 |
| resources | 2550 = 3000 - 9 x 50, unchanged across the whole drain; plugin spent 0 |
| promotion | 4 promote events, in order, overflowLeft 3-2-1-0; 9 SCVs built |
| hooktest (offline) | 0 failures |
| run-ci-local.ps1 | PASS (ruff NOT RUN, not installed) |
| StarCraft.exe on disk | byte-identical, equals pristine 1.16.1 |
| foreground | ONE borrow-and-return pair, 23:52:23-27, the Game Type dropdown. Nothing else. |
| stranded processes | none of mine; my game exited cleanly and the suite asserts it |

TWO THINGS YOU SHOULD KNOW.

1. I merged origin/main twice (027, then 024). Task 024 and I independently added THE SAME THING -- the world scan viewport-origin line and its parser, off the same two globals -- for the same reason. Git auto-merged them into two parsers writing one variable with two different shapes (X/Y vs Left/Top), which would have compiled and then read $null at runtime. I fixed it by hand, adopted 024 wording and property names since they landed first, and RE-RAN the in-game suite on the merged tree: 0 failures again.

2. GitHub CI reports "Parse, lint and import checks: FAILURE" on my branch -- and identically on main, whose last three runs all failed too. That is the infra thing you already told me not to worry about, not a regression of mine. Local run-ci-local.ps1 is PASS on my head.

Not done, and stated rather than hidden: the in-game suite still does not press cancel (issue #26). Cancel is asserted offline byte-exact in both directions and shown from the handler with disassembly. Reading the command-card cancel rect out of the dialog is the clean way and it is issue #26 work.

Ready for merge on your call.
