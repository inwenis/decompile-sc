---
from: 026
to: conductor
sent: 2026-08-09T22:40:36Z
subject: VERDICT: NO. Clean A/B on real cloaking Ghosts - the fan-out took ZERO units off their attack orders, and the count attacking went UP
---

Both arms clean on the FIRST take -- targets 16 -> 16 -> 16 -> 16 across all three windows in each arm. `test-ability-in-combat -Ability cloak`: **0 failures**.

| | plugin (fanout) | stock (observe) |
| --- | --- | --- |
| orders BEFORE the ability | `0x06:3 0x0a:33` | `0x03:24 0x0a:12` |
| orders AFTER | `0x03:1 0x06:1 0x0a:34` | `0x03:24 0x0a:12` |
| changed order across the ability | 2 of 36 | 0 of 36 |
| ...of which had been ATTACKING (0x0a) | **0** | **0** |
| control windows (changed) | 0 / 0 | 0 / 0 |
| units the ability reached | **36** (0 -> 36 carrying 0x6D) | 12 |
| units that paid energy | 36 of 36 | -- |

**The verdict you asked for, plainly: NO.** Nothing we do makes a cloaked Ghost stop attacking. The two units that moved in the plugin arm were both still WALKING into the fight, and one of them was a unit JOINING it (0x06 Move -> 0x0a AttackUnit). The number of units attacking went UP, 33 -> 34.

**Stated sensitivity, so the negative is worth something:**

1. The ability demonstrably fired INSIDE the measured window, at full scale -- 0 -> 36 units carrying secondary order 0x6D, 36 of 36 charged energy, `FANOUT start ... units=36` on the wire. The thing whose side effects we were looking for definitely happened there.
2. The same metric HAS registered the predicted signature: 33 of 36 units going 0x0a -> 0x03 in one window, on the confounded run. That was a target death rather than the ability, but it proves the measurement can see a mass drop-to-idle when one occurs. That is the absence-proved-positive requirement, met by the confound itself.
3. The stock arm is a real control -- no hook line, no CMD line, no FANOUT line, each asserted absent only after being shown present in the plugin arm.

**Limits:** two-second windows, an enemy that cannot act. An effect that takes longer than two seconds, or that needs a real opponent, is outside what this measures.

**And separately, for relaying to the user:** the greyed-Cloak bug does NOT explain their report. That bug was ours and it was in the fixture GENERATOR; their Ghost was in a real game with cloak researched and working. On a correct fixture we measured no plugin effect on a cloaked Ghosts orders. Why theirs appeared to stop is unreproduced, and the plugin contains no AI, targeting or acquisition code that could plausibly cause it.

Focus: `watch-foreground.ps1` across both launches shows one borrow-and-return each (~4s, around the Game Type pick), back to the users Chrome window. Nothing else.

Remaining: the probe re-run (queued -- it is the one suite still owed a green run after I fixed its shadow-vs-engine selection oracle), then run-ci-local on the final head and the PR body. exe byte-identical, no stranded processes, fixture cleaned up.
