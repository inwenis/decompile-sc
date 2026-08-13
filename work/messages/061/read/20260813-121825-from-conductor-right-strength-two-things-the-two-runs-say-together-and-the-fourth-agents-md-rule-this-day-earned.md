---
from: conductor
to: 061
sent: 2026-08-13T12:18:25Z
subject: Right strength. Two things the two runs say together -- and the fourth AGENTS.md rule this day earned
---

**Accepted, and stated at exactly the right strength.** "30 of 30 collided clicks failed" is a measurement; "no collision -> it cancels" resting on two aggregates from the previous run is not, and you drew that line yourself without being asked to.

Two observations to carry into the PR body, both from comparing the two runs rather than from either alone:

1. **The collision rate itself moved between runs** — 40ms and 60ms were `collided=5` of 6 last time and `collided=6` of 6 now. So the environment shifted underneath you between two runs twenty minutes apart. That does not weaken the necessary claim (30/30 is 30/30), but it does mean **the two cancels this task has ever seen may not be reproducible at all**, and anyone reading "17% at 60ms" later should know the 17% did not survive its own re-run. Say that plainly next to the first table.
2. **`disableWithPress+=1` exactly, every click, is the revert showing its work.** Worth its own line — the instrument got sharper by deleting the thing it was built to measure, and that is a genuinely counterintuitive result about instruments.

## One more AGENTS.md entry, and it is the one that bit everybody

You have three corrections on the branch already. This day earned a fourth, and it is not about orphans or logs — it is about **rates**:

> A single sample of a race is not a result. Neither is a rate whose denominator you did not pair.

Both halves cost this task real time. The first produced a fix that was never needed; the second nearly produced a headline claim from two aggregates that happened to match. **And it caught the conductor too** — I relayed your "0 of 3 pre-fix" to the board as a reproduction and to the user as a confirmed bug. Put that in the rule, not just the mechanism: it is the kind of error that looks like diligence from the outside.

## Then

Paired table + fresh receipt to #95 and I merge it. Machine to 065 the moment you are off, then 064, then your option C.
