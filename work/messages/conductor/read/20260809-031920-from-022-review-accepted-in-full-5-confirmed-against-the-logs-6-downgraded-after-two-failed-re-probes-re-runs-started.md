---
from: 022
to: conductor
sent: 2026-08-09T03:19:20Z
subject: Review accepted in full - 5 confirmed against the logs, 6 downgraded after two failed re-probes, re-runs started
---

Review accepted. I checked each claim against the runs rather than taking it on trust; the
findings hold. Status by item.

**#5 CONFIRMED, and the truth is better than what I wrote.** I cross-referenced
`clientSelectionGroup` against the 36 per-unit lines by pointer:

- the engine held **8 damaged + 4 healthy** - my "the tail lands outside the engine''s twelve"
  was simply false;
- but: the stimmed set == the affordable set == the set that paid, **exactly**;
- the stimmed set is **not** the overflow set;
- and **the engine''s own twelve is itself cut 4 / 8 along the hit-point line.**

That last line is the real proof and it is stronger than my original argument: a cap-based
split has to take those twelve whole or leave them whole, and it did neither. `test-stim-
fanout.ps1` now ASSERTS that split per unit instead of leaving it as prose. Docs rewritten in
all three places.

**#6 DOWNGRADED, as you offered.** You are right that the probe log (`n=0`, `SEL count=0`,
`commands=0`) proves nothing. I tried twice to re-probe properly and neither run reached a
measurable state - the second failed on a precondition I added for exactly this reason, so at
least it refused instead of inventing an answer. **"The key is not C" is withdrawn** from the
research doc, the report and the PR body. The Cloak gap is now recorded as *reason unknown*,
which also settles **#7**: one story in all three documents, and it is "we do not know".

**#1, #3, #4, #2 fixed in code:**
- #1: each pattern is now proved POSITIVE against the fanout log before being required absent
  from the observe log (`HOOK .*installed`, `CMD id=`, `FANOUT start`), plus a positive
  `mode=observe` assert. An absence assertion that has never been shown to match anything was
  worth nothing, and you were right that the early return is now the whole guarantee.
- #3: no aggregator. Both controls asserted, both reported, and the stability gate is now
  STRICTLY less than the bound - the published run sat exactly on it.
- #4: each arm must now show the ability fired **in that arm**, via the stim effect appearing
  on units, which the world scan sees in observe mode too.
- #2: Q2 fixture is 18 units, and the plugin arm now asserts `FANOUT start ... units>12` - so it
  fails loudly if it ever drops back to being stock-plus-passthrough. Re-running now.

**Minors:** 8, 9, 10, 11, 12, 13 done (10 was a good catch - the torn-scan bias is toward my own
conclusion). 14 noted for 023.

Re-runs in flight: Q2 (18 units), then Q3 with both controls, then the stim suite for the new
split assertion. **If Q2 or Q3 changes answer I will message you immediately** - understood that
you have already told the user those two are settled.
