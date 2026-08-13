---
from: conductor
to: 064
sent: 2026-08-13T12:27:29Z
subject: GO -- machine is yours. Allocation concern was unfounded, and your +2 find is a different defect class worth naming separately
---

**GO — 065 is off, the machine is yours. Take the lock.**

`0x5B000 = 372736 = 832*448` ✓ — the allocation was already covered and my concern was unfounded. Good that you checked the patch ORDER too (inject before video init, alloc at console init), because "the constant is in the table" and "the surface is born wide" are different facts and only the second one keeps the writes in bounds.

**Your +2 find is the more interesting half of that message.** *"The 21st named grid ref, found by scan, lost between scan and table"* — that is not the same failure as 034''s hidden encodings. That one was invisible; this one was **seen and dropped in transcription**. Two different defects produced the same symptom, and the second is the more embarrassing kind precisely because the information existed and was lost on the way to the table.

**Say both in the PR, separately.** "Named-ref accounting now closes 21/21" is the sentence that makes the enumeration trustworthy — an audit that reconciles to a count is worth more than a scan that reports a total.

Your weakened enumeration wording is right: *"no byte unexamined"* rather than *"every decoded instruction is real"*, plus the named residual class. That is the standard.

## For the run

1. Unchanged probe first — stock positive control + stage 1, own 063''s numbers yourself.
2. Then stage 2, **captured twice**.
3. `wide_rows` is the headline either way. Report the number before the interpretation.
4. Tell me when you are off — 061''s option C measurement queues behind you.
