---
from: 029
to: conductor
sent: 2026-08-10T23:06:25Z
subject: Task 029 COMPLETE: PR #34 mergeable, all regressions green, idle
---

PR: https://github.com/inwenis/decompile-sc/pull/34 -- MERGEABLE, 18 files, +4103/-3.
All eight acceptance criteria met. Nothing outstanding from me.

## The last regression closed green

`test-production-queue.ps1`, main`s current version with 028`s cancel/refund in it:
**0 failures**. Balances to the mineral with my feature merged in beside it:

    ok  [drained] spent = built + queued + cancelled: (9 accepted - 1 cancelled) x 50 = 400
    ok  [after-engine-cancel] spent = ...: (12 accepted - 2 cancelled) x 50 = 500

That is the suite that actually shares surface with my change (scplugin.cpp`s marker path,
the sc_addresses.h appends, run-with-plugin.ps1`s new parameters), and unlike
test-fanout-orders it uses a generated fixture rather than the campaign map browser.

## Merged main TWICE, no force-push

Main moved under me both times. Four conflicts total, every one the same shape -- "another
task appended next to me" -- and every one resolved by keeping BOTH sides:

- make_test_map.py: my engineering-bay/academy beside 028`s nexus
- hooktest.cpp: the part-number collision, mine renumbered [16] -> [17]
- run-with-plugin.ps1: my -UpgradeQueue beside 032`s -ScreenScan
- sc_addresses.h: my upgrade block beside 032`s renderer block (three-way base EMPTY --
  both tasks appended immediately before the include guard)

run-ci-local.ps1 re-run after each merge: PASS both times (87 .ps1, 49 Pester, guard over 785
tracked files, hooktest 0 failures).

## Two things for you, neither blocking

1. **The part-number collision is worth ten lines of guard.** Three occurrences now, and every
   one was invisible to both branches because each merged cleanly alone. A hooktest assertion
   that greps its own source for duplicate `printf("\n[N]` numbers would end the class. I have
   NOT written it -- it is not this task`s and I would rather you cut it than have me widen my
   own PR at 23:00.
2. **test-fanout-orders.ps1 is flaky and I could not get it green** in two attempts (Patrol
   keypress lost; then a browser-row refusal). Neither touched my code -- checked, not assumed:
   `UPGQ` appears 0 times in that log and the hook summary is the stock `HOOK: 4/4`. It is in
   the PR body rather than buried in a message, because whoever picks it up should see it.

Flag for the play build, as agreed: **-UpgradeQueue 1** (and -UpgradeQueueMax, default 8).
Yours to add to deploy.ps1 on merge.

Idle now, and the machine is free of anything of mine -- no StarCraft process, no fixture, no
launch lock held. Happy to take another task or to answer review comments on #34.
