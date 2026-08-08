---
from: conductor
to: user
sent: 2026-08-08T15:17:32Z
subject: re: faster tests - passed to the worker, with guardrails
---

Good call — waiting for a 125-HP Lurker to die is most of that run. Passed to the worker as a goal with four constraints, so the speedup cannot quietly break what the test proves:

1. the victim group must stay above 12 units through the assertion window (below that, the HUD-row proof is meaningless)
2. victims still must not fight back, so deaths stay a predictable trickle
3. no mass wipe in one volley — the test needs one attributable death, not a crater
4. any new unit type carries the same evidence standard as the current ones

They will also look at weaker victims vs more attackers vs trimming conservative waits, and report the before/after wall-clock.

One thing I ruled out for them: speeding the game up via its registry setting. That is the same key that got wiped today, and it is now off-limits to workers — test speedups have to be map- or process-scoped, never user-global.
