---
from: conductor
to: user
sent: 2026-08-10T20:40:26Z
subject: re: why is there no cancel test - honest answer, and it is now being built (task 028)
---

# Why there is no cancel test

Straight answer: **because we could not click the cancel button, and I chose to ship without it rather than guess where it was.**

The longer version, because the reasoning matters:

1. Cancel IS proved -- but only offline. Task 025 proved the refund is byte-exact in both directions and showed it from the disassembled handler. What was never done is a real game, a real click, and reading the minerals back afterwards.
2. To click a control we have to know where it is. This project has a hard rule against guessing pixel coordinates, written after hardcoded coordinates cost six runs in one day, and after a pixel-hash "finding" turned out to be invented and burned two sessions. So the control has to be READ out of the game`s dialog structures in memory.
3. At the time 025 finished, we could not read that dialog. So I filed it as issue #26 and merged without it, because your standing preference is happy path first, polish later.

**What changed:** task 026 built exactly that capability the same night -- reading command controls and their positions out of the running game. So the blocker is gone, and the answer to "why is there no test" is now just "there is not one YET".

## Now being built -- task 028

I have cut it and it is running. The interesting part is not the part you would expect:

- Cancelling an item in the GAME`s own queue is low risk -- the engine handles the refund, as it always has.
- Cancelling an item OUR plugin is holding is the real one. Because we keep the game`s queue at 4 and hold the rest ourselves, the plugin has its own refund path -- and that path is the ONLY place the plugin ever writes to your resources. It has never been exercised in a running game. That is precisely where a double-refund or a lost unit would live.

So the task covers both, asserts the totals reconcile (spent = built + queued + cancelled) from memory rather than from the UI, and -- per the rule your own queue feature produced -- confirms a cancel click actually reaches the engine before believing anything about refunds.

One thing I told it NOT to assume: that cancel lives on the command card. In vanilla you cancel by clicking the unit`s icon in the production strip, which is a different dialog. If it needs the same memory-read treatment the command card got, that IS the work.

Board is otherwise empty -- 024, 025, 026, 027 all merged and deployed. After 028: queuing upgrades, then the wider screen.
