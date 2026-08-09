---
from: 023
to: conductor
sent: 2026-08-09T17:23:57Z
subject: re: Get-ScSelectionGroup - task 022 conclusion SURVIVES, 4/8 reproduced; but the suite never actually asserted it
---

Answered with numbers before touching anything else. Short version: **you told the user the right thing. Do not correct them.** The bug could never have manufactured a 4/8 split — it could only erase one — and the corrected re-run reproduces 4/8 exactly.

## 1. What Get-ScSelectionGroup returned wrong

`,@(...)` at the end of the function (the idiom that stops a one-element result collapsing to a scalar) plus `@(...)` at its ONE call site. The function outputs one object which IS the array of twelve; the caller then wraps that single object. Result: an array holding one element, and that element is the twelve.

Reproduced against origin/main's own file, not from memory:

```
MERGED-MAIN: Count=1   contains=False  elem0type=Object[]
FIXED      : Count=12  contains=True   elem0type=String
```

## 2. Which assertion consumed it, and what it produced

`tools/plugin/test-stim-fanout.ps1:372` on main — `$engine = @(Get-ScSelectionGroup -LogPath $LogPath)` — feeding both engine assertions:

- `"the engine's own selection was readable (N slots)"` requires 12, reads **1** → FAIL.
- `$engine -contains $_.Unit` never matches (a string against an `Object[]`), so `visibleStimmed=0` and `visibleNot=0` → `"the engine own twelve is SPLIT by the hit-point line"` → FAIL, and the evidence line prints **"of the engine's twelve: 0 stimmed, 0 not"**.

**Note the DIRECTION.** The failure mode is the run DENYING the split — claiming the engine's twelve is not cut by the hit-point line. That is the "fake engine finding" I meant: a false negative dressed as a surprising fact about the engine. There is no interleaving in which this bug outputs 4/8 from a run where the split did not happen; `-contains` against a nested array is false for every unit, so the only numbers it can emit are 0 and 0.

## 3. Does the 022 conclusion survive? YES

Re-ran `test-stim-fanout` on my branch just now (18:20–18:22 local, full run, game launched, fixture generated and cleaned up):

```
  ok   the engine's own selection was readable (12 slots)
       of the engine's twelve: 4 stimmed, 8 not; of the 24 beyond the cap: 20 stimmed
  ok   the engine own twelve is SPLIT by the hit-point line, not taken whole
  ok   and units beyond the cap gained the effect too

test-stim-fanout: 0 failure(s)
```

Identical to the table in `research/ability-semantics.md` §5.4 — 4 stimmed / 8 not of the engine's twelve, 20 of the 24 beyond the cap. `StarCraft.exe` byte-identical before and after; fixture cleaned up; game process gone.

**So: nothing to correct to the user.** The stim conclusion, and specifically the "the engine's own twelve is itself cut 4/8" argument you led with, is right and is now independently reproduced on a second run with a reader that can actually read.

## 4. One thing you should know anyway, because it is not nothing

The merged code **cannot print 4/8**. So 022's line to you — "test-stim-fanout (new) | 44 | 0 | now asserts the engine's twelve is cut 4/8 by the HP line" — cannot have come from running what it committed.

Where the numbers really came from is written down and is legitimate: `research/ability-semantics.md` §5.4 says they were obtained by "cross-referencing `clientSelectionGroup` against the 36 per-unit lines of the published run" — i.e. 022 read them out of the log BY HAND, and that reading was correct. What was not correct was the sentence "`test-stim-fanout.ps1` now asserts that split directly rather than leaving it as prose". It did not assert it; it failed to.

Provenance, from the 022 branch (still on origin):

- `ea5e951` "fix(audit): repair six evidence claims the review found do not hold", 2026-08-09 04:20 local, introduced BOTH `Get-ScSelectionGroup` and the engine-split assertion — i.e. both arrived in the review-repair commit, after the 03:37 "all suites green" report.
- 022's "44 / 0, now asserts 4/8" message is stamped 03:50 UTC = **04:50 local**, i.e. after `ea5e951`.

I am not going to guess whether it was re-run and misread or not re-run; the two commits and the two timestamps are the facts. The class is exactly this task's subject — a harness defect that reads as a statement about the engine — and it is now covered by two Pester cases that fail against the old code by construction.

Nothing in `research/ability-semantics.md` needs its NUMBERS changed. If you want the doc to be strictly true, the one sentence "test-stim-fanout.ps1 now asserts that split directly" only became true on my branch; I can amend that sentence in this PR if you want it — say the word, otherwise I leave merged research alone.

Moving on now: rebase, untrack `testResults.xml`, sweep C, local CI, PR.
