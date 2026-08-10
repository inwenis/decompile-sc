---
from: 029
to: conductor
sent: 2026-08-10T22:49:36Z
subject: PR #34 open: upgrade queue, in-game 0 failures - plus one flaky suite I could not get green
---

PR: https://github.com/inwenis/decompile-sc/pull/34 (Status.pr updated)

## Where it stands

- Feature complete, in-game suite **0 failures**, `run-ci-local.ps1` **PASS** post-merge
  (hooktest 0 failures, 49 Pester, game-content guard over 779 files).
- Merged origin/main in (was 9 behind, no force-push). Two conflicts, both "another task
  appended next to me", both resolved keeping BOTH sides.
- **One thing you should know about the merge**: 028 took hooktest part `[16]` on main while
  I was in flight, and mine was also `[16]`. Renumbered mine to `[17]`. That is the THIRD
  time this repo has had that collision, and each time it was invisible to both sides
  because each branch merged cleanly on its own. Might be worth a cheap guard -- a test that
  greps its own source for duplicate part numbers would cost ten lines.

## The in-game result, briefly

Academy fixture. Card offered five items across both opcodes; the suite pressed three.

    press 1 -> CMD 0x32 [32 10]  U-238 starts, engine paid (3000 -> 2850)
    press 2 -> CMD 0x30 [30 00]  Stim QUEUED   -- and not one mineral moved
    press 3 -> CMD 0x30 [30 18]  Restoration QUEUED -- and not one mineral moved
    queue read from memory: [T:0,T:24]        a MIXED queue
    at the cap: shown=1, 0 buttons, 3 presses -> 0 commands on the wire
    drained in order; techs=[0,24] levels=[16:1] -- all three FINISHED
    3000 -> 2650 = 150+100+100, one payment per item, each at the moment it STARTED
    UPGQSTATS ... mineralsSpent=0 gasSpent=0

## The one thing I could NOT get green, stated rather than dropped

`test-fanout-orders.ps1` failed twice and I never got a clean run out of it:

1. Three failures, all Patrol -- the Patrol keypress never reached the wire at all (only two
   `CMD id=0x15` in the whole run, one of them Attack), so there was nothing to fan out.
2. Re-run: the map-browser row check refused to launch (`clicking row 4 ... did not select a
   map`). That is the hard rule working -- it declined to play the wrong map.

Neither reached my code, and I checked rather than assumed: in that run`s log `UPGQ` appears
**0 times** and the hook summary is `HOOK: 4/4 installed, mode=fanout`, the stock set. None of
my eight detours was installed, because -UpgradeQueue defaults to 0 and that suite does not
pass it. Both look like pre-existing input/browser flakiness in that suite. I have not chased
them -- not mine, and I did not want to burn the shared machine on it -- but somebody should,
and it is in the PR body rather than buried here.

`test-production-queue.ps1` (main`s current version, 028`s changes included) is running now as
the in-game regression instead: it shares far more surface with my change and it uses a
generated fixture rather than the campaign browser. I will comment the result on the PR.

## Ready for you

Everything in the acceptance criteria is done except that last regression line, which is
in flight. No question outstanding -- this is a status, not a block.
