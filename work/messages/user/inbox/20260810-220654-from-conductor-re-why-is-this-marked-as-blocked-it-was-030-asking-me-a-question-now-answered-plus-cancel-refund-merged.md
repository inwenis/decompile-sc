---
from: conductor
to: user
sent: 2026-08-10T22:06:54Z
subject: re: 'why is this marked as blocked' - it was 030 asking me a question, now answered. Plus: cancel/refund MERGED
---

# "Why is this marked as blocked?" (you sent this to task 030)

Because in this system a worker`s unanswered QUESTION is what makes a task read as blocked -- there is no status field anyone writes, it is derived. Task 030 had asked me whether it should take the game machine itself or wait for task 028 to report a measurement first, and until I answered, the board showed it blocked.

It was blocked for about a minute, and it was blocked correctly: 030 was right to ask rather than duplicate a run on a machine four other workers were sharing. I answered (take the launch yourself; I cancelled the overlapping request I had given 028), and it cleared.

So "blocked" there means "waiting on me", not "stuck" or "broken". If you ever see it and I have not cleared it within a few minutes, that is worth poking me about.

# Meanwhile: your cancel question is ANSWERED and MERGED

PR #31 is in. Cancelling a queued unit is now proved in a real game, both cases, and the finding is more interesting than expected: **there are TWO cancel controls, not one.**

1. Clicking a unit`s icon in the production strip cancels THAT item -- the game refunds it, exactly as always.
2. The Cancel button on the command card cancels the LAST queued item -- and that is the only way to reach an item held past the game`s own five, because the strip only ever draws five icons.

Both were located by reading the game`s own dialogs from memory, both clicked in a running game, both refunds checked against the actual mineral count. Plugin-held item: 9 queued -> 8, minerals 2550 -> 2600, refunded once. Game-held item: ring 3 -> 2, minerals 2450 -> 2500, and the plugin`s counter never moved -- the game did it.

**A limit you should know:** the production strip cannot address the overflow. It draws five icons for a nine-item queue. To cancel deep items you press the Cancel button repeatedly, last-in-first-out.

028 also reported two things it got WRONG and the runs caught -- it had predicted from the button tables that a Terran producer could never show a Cancel button, and the live read proved otherwise; and its first reconciliation double-counted the unit already being built. Both written up rather than quietly fixed.

# Also measured tonight: why the tests are slow

68% of a production test run is literally waiting for nine SCVs to build, 20 seconds each. Your idea works -- roughly 2.5-3x on the suites that BUILD something. But nine of eleven suites build nothing, and for those the cost is ~52 seconds of fixed overhead per run (launch, menu walk, map load) that nobody chose. I have asked for that to be priced too, since it is paid eleven times per sweep.
