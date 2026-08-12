---
from: conductor
to: user
sent: 2026-08-12T21:38:22Z
subject: Task 050 merged -- no test needs your screen any more, and I sent one fix back before it landed
---

**Merged: https://github.com/inwenis/decompile-sc/pull/61. No suite is tied to your screen any more, including the one I asked you for three minutes of this morning.**

All six converted suites ran off-screen with 0 failures and the skip line present, `test-hud-row` among them. That request is now genuinely retired rather than optimistically retired, which is the distinction I got wrong earlier tonight.

## What I checked before merging, since I reviewed it rather than trusting it

050 also "fixed in passing" a broken assertion in `test-hud-row.ps1` — a hardcoded count of installed hooks that had gone stale. It bumped the number from 6 to 7 and cited an earlier task as precedent. I read that earlier task, and the precedent said the opposite: task 047 had **deleted** the number and replaced it with a by-name comparison, for a stated reason sitting right there in the file — *"a count mismatch names no hook"*.

The bumped number was worse than it looks. `HOOK: 7/7 installed` only asserts that a total matched a total. Remove `statDataUpdate` — the one hook that suite exists to test — add any other hook, and the count is still 7 and the suite goes green with the feature under test not hooked at all. That is a check that cannot fail in the way that matters.

I sent it back. What came back was better than what I asked for: the two helper functions lifted into `drive-game.ps1` so both suites share them, the flags read from the run's own config line, and the count kept but **derived** from the named set as an independent corroboration rather than a second literal. The failure text now reads:

    FAIL the installed hooks are exactly this arm's set ([...]) (missing: [statDataUpdate] extra: [])

It names the hook.

## The finding underneath all of this

`Custom Type` in your Blizzard registry key is one machine-wide value shared between your play and our tests, in both directions. That is now written into AGENTS.md as its own section, next to hard rule 5, including the part that is about you: a test run that picks Use Map Settings leaves your next custom game defaulting to it. The engine's own menu does the writing, never our code — but you should not have to discover that by noticing.

`tools/plugin/prime-game-type.ps1` is yours to run whenever it drifts. Launch, one pick, verify, quit, under a minute.

## Board

| # | task | state |
| --- | --- | --- |
| 039 | fifth slot / group line | merged, deployed, you have it |
| 050 | six screen-stealing suites | **merged and closed** |
| 051 | does save/load survive the mods | running, has the machine exclusively |
| 048 | the same overlap bug, latent, in the 12-icon row | just dispatched, holding launches |
| 049 | off-screen verdict table | mostly absorbed by 050; one leftover regression check |

Two more issues filed tonight, both from things that actually happened rather than things I imagined: [#59](https://github.com/inwenis/decompile-sc/issues/59) (the agent heartbeat reads a worker as dead exactly when it is busiest, which has already cost you an orphaned game once) and [#60](https://github.com/inwenis/decompile-sc/issues/60) (the launch lock guards one launch, not a chain, so a polite waiter breaks the run it is waiting for — found by worker 051 watching it happen, not by hitting it).

Still open for you when you feel like it: whether the fifth slot actually looks right in a real game now.
