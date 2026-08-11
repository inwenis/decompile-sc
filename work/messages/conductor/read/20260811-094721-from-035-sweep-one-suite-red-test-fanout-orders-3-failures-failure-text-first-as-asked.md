---
from: 035
to: conductor
sent: 2026-08-11T09:47:21Z
subject: SWEEP: one suite RED - test-fanout-orders, 3 failures. Failure text first, as asked
---

Undiagnosed, exactly as you asked. Raw:

    [5] Attack and Patrol are Targeted Order (0x15), and it fans out
      ok   Attack: the re-box still captures more than twelve (24)
      ok   Attack emits Targeted Order 0x15
           Attack -> order byte 0x08
      ok   Attack was fanned out
      ok   Attack: more than twelve units were commanded (24)
      ok   Patrol: the re-box still captures more than twelve (24)
      FAIL Patrol emits Targeted Order 0x15
      FAIL Patrol was fanned out
      FAIL Attack and Patrol are different orders inside the same command id (attack=0x08 patrol=0x)

    test-fanout-orders: 3 failure(s)

    [6] the run never fanned out anything outside the policy set
           ids fanned out this run: 0x15 0x1A 0x2B
      ok   every fanned-out id is in the policy set
           ids seen but NOT fanned out: 0x09 0x0A 0x0B 0x37 0x54

Reading it plainly: Attack worked (0x15 emitted, fanned out, 24 units commanded). Patrol produced NO command at all - patrol=0x is an empty order byte, not a wrong one - so the input did not reach the engine. The re-box before it captured 24 units fine, so the selection was there.

Sweep state, all on the rebased tree:

    test-stim-fanout        0 failures   1.9 min
    test-sunken-acquire     0 failures   7.5 min
    test-upgrade-queue      0 failures   4.9 min
    test-production-queue   0 failures   2.8 min
    test-group-production   0 failures   2.9 min   (my sweep parser missed its verdict line - it prints "test-group-production (feature): 0 failure(s)" - the suite itself is green)
    test-selection-circles  0 failures   1.3 min
    test-fanout-orders      3 FAILURES   1.4 min   <-- this one
    ...burrow-fanout, hud-row, control-groups, building-groups, combat-death still to run

test-fanout-orders is NOT a Set-ScGameType caller, so of my five changes only the marker write (#37) and the launch foreground restore (#30) touch it at all - neither of which plausibly swallows one keypress while the one before it lands. But that is reasoning, not evidence, so I am about to run it on origin/main as a control, same machine, same conditions. I will not touch the code until I know whether it is red there too.
