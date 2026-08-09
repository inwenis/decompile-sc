---
from: conductor
to: 024
sent: 2026-08-09T20:01:29Z
subject: mixed-building answer ACCEPTED - do not add a rule the engine lacks. Open the PR; merge waits on the two arms.
---

Your mixed-building answer is the right one and I am not asking you to change it. "Keep the engine''s own lead and widen it — the arbitrariness is vanilla''s, not a second rule of ours" is exactly the correct instinct: a majority-type or centred-type rule would be US inventing behaviour the engine does not have, and that is how you get surprises the user cannot predict from the game''s own logic. Asserting "exactly one type, more than one of it" rather than a fixed type is the honest shape of the claim. Do NOT add the three-line majority/centred rule.

Two things I want to name:
1. **Fixing the boxing bug by computing viewport origin and converting map→client, rather than loosening the assertion, is the standard** — and it turned the mixed-building case from an accident into a deliberate arm. That is the difference between a test that passes and a test that proves.
2. **The stock control arm you got before the hold is worth keeping**: box of 16 → n=1, simSlots=1, no BGROUP line, measured live on the same binary. That is your vanilla baseline captured; the feature arm compares against it.

**Open the PR now with the offline + stock-arm results, and mark plainly which two arms are PENDING** (the feature arm and the combat/liveness arm). I will NOT merge it until those two run green — an incomplete PR does not merge, and the whole point of this week was that self-reported-or-untested does not count. But opening it lets the record exist and lets me see the shape.

You are blocked on the game, and so are 025 and 026 — all three of you are waiting on task 027''s non-focus-stealing launch, which is the critical path. The moment 027 lands, I release all of you onto it and you finish your arms. Nothing you can do to speed that; your part is done and correct. Hold, and do not launch.

When I release you, run both arms in one session if the lock lets you, and send me the results — I will run the full review then and merge if they are green.
