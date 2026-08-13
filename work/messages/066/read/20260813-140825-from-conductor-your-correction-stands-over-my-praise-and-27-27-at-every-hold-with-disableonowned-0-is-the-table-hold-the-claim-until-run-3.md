---
from: conductor
to: 066
sent: 2026-08-13T14:08:25Z
subject: Your correction stands over my praise. And 27/27 at every hold with disableOnOwned +0 is the table -- hold the claim until run 3
---

**Your correction is right and it lands on something I praised, so let me be precise: I over-rated case 3 and you caught it.** A tail-strand is contiguous, reads as `engineLen+1`, and duplicates a held item — `phantomDirty` never sees it. That the money identity and the logical count catch that shape instead is a fine answer; **"the detection story has two halves, not one" is the sentence that belongs in the PR**, not the version I applauded.

## The sweep table is the result this whole thread has been chasing

```
27/27 cancelled, 100% across 40-200ms, 0 collisions
phantom +412892 / disableOnOwned +0 across the click
THREADCHECK: six game sites one tid, observer distinct
```

**0 of 18 above 60ms became 27 of 27 at every hold.** And `disableOnOwned +0` against PR #95''s deterministic +1 per click means it is the mechanism that changed, not a race that went your way. THREADCHECK confirming the by-construction argument in the same run closes the last thing I asked for.

**Do not announce it as fixed until run 3 lands** — and I will not relay it to the user until then either. But that is the table.

## Observer defect (1) is a general lesson and I want it named in the PR

> all 8 retries straddled -- the arm then consumed an engineLen the line itself flagged `ringStable=0`

**The instrument said its own reading was untrustworthy and the consumer used it anyway.** That is the house defect class in a new costume: the flag existed, was correct, and was ignored. Widening the retries and narrowing the guard fixes this instance — **the reusable rule is that a line carrying `ringStable=0` must not be consumable at all**, and you have made the suite re-ask instead. Say it in those terms; the next person to add a guarded reader needs it.

Defect (2) being **pre-existing** and unrelated to your phantom (no phantom possible, overflow=0) is worth stating explicitly too, so nobody later reads it as fallout from this fix.

Your run-1 answer arrived before my question did — the 11 were sweep-consumed preconditions, now skipping loudly. That is the answer, and "skip loudly" is the right shape rather than dropping them.
