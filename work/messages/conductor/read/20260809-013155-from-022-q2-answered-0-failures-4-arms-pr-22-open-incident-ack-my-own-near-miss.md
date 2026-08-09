---
from: 022
to: conductor
sent: 2026-08-09T01:31:55Z
subject: Q2 answered (0 failures, 4 arms); PR #22 open; incident ack + my own near-miss
---

**Q2 is answered and it is not ours.** `tools/plugin/test-sunken-acquire.ps1`, 0 failure(s),
four arms over one fixture:

| arm | attacked? | evidence |
|---|---|---|
| Medics, fanout | yes | hp 92160 -> 88768; Sunken order 0x12 -> 0x13 |
| Medics, observe (stock) | yes | hp 92160 -> 88368; same transition |
| Marines, fanout | yes | all six killed; Sunken taken to 23876/76800 |
| Marines, observe | yes | same |

Plugin and stock agree on every measure. The stock arm is ASSERTED stock (no `FANOUT start`,
no hook line in its own log) and both arms carry the same read-only WORLD oracle, so the
comparison is like-for-like - which is the thing you flagged as the validity risk, and it holds.

Three vanilla facts explain what the user saw, all read out of the per-unit data rather than
recited:
1. a Sunken shoots ONE target at a time - exactly one Medic was taking damage at any moment
   while the other five stood in range untouched;
2. Medics heal each other - the healer is visible in the same scan on order 0xB0 with its
   energy down at 8412 - so the damage is repaired between shots and the bar you are watching
   may never look low. Endpoint-only sampling shows the group back at almost full health;
3. the range is 7 tiles against a large sprite; the block was fired on at 197px.

**PR #22 is open:** https://github.com/inwenis/decompile-sc/pull/22

**Incident ack.** Your read is right and it cost me exactly one run: my Q3 run at 02:27 came up
with `units=0` for every player - the map was gone, not mis-loaded. I have voided it. Nothing of
mine is built on a run in that window; Q1 (01:20) and the Q2 matrix (02:05-02:20) are both
outside it and both had their unit types and counts asserted in-process at the start.

**My own near-miss, for symmetry:** earlier I edited `tools/README-test-map.md` in the MAIN
checkout by mistake (a python heredoc that inherited the wrong working directory). I noticed it
in `git status`, saved the diff, reverted the main checkout to clean, and re-applied it in my
worktree. No tracked content in the main checkout is modified by me now.

I have implemented your new rule fully: task-prefixed fixtures, only my own named files deleted
on every path including `finally`, and a refusal to start if any `.scx` I did not create is
present. I also added the half that rule does not cover: a re-check IMMEDIATELY BEFORE the
launch, because the folder can be cleared between generating my fixture and clicking the browser
row - which is precisely what happened to me. It throws with the cause named instead of playing
whatever is there.

Still to do: Q3 re-run (running now), then the five existing suites. Noted that CI is down; the
local suites are the evidence and I will report them individually.
