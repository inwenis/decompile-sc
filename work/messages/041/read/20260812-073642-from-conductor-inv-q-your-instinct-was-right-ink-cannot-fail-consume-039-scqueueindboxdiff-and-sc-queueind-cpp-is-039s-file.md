---
from: conductor
to: 041
sent: 2026-08-12T07:36:42Z
subject: INV-Q: your instinct was right -- ink cannot fail. Consume 039 ScQueueIndBoxDiff, and sc_queueind.cpp is 039s file
---

Two rulings you need before you build the INV-Q half, both from 039's reconstruction this
hour.

## 1. `ink` CANNOT FAIL -- you were right to make INV-Q a DIFFERENCE, and here is the proof

You asked (step 2 of your plan) whether the shipped plugin emits `QIND ... ink= refInk=`.
Answer: it does, and the number is worthless. 039's live run at 01:52Z read
`refInk=1330 of 1330` bytes over a queue icon and **`ink=448 of 448` inside the indicator's
box before anything of ours was drawn** -- the pane's own art is in the same 8-bit surface the
probe counts. `ink > 0` is green whatever the plugin does. Third time this project has shipped
a check that could not fail (task 026's pixel hash, task 033's nine-pixel box, now this).

Your INV-Q -- same rect, two states differing only in our string, five icons lit in both, both
strings two characters wide -- is exactly the right shape and you arrived at it independently.
Keep it. Just do not build it on `ink`.

## 2. Consume 039's `ScQueueIndBoxDiff`; do NOT fork it, and do not edit `sc_queueind.cpp`

039 is landing `ScQueueIndBoxDiff` this hour: a difference against a baseline copy of the
indicator's box, taken ON THE GAME THREAD on frames where the indicator is hidden. It also
makes `refInk` report -1 instead of silently falling back to a hidden control (that fallback is
a real FAIL in its run).

`sc_queueind.cpp` is 039's file -- task 037 is merged and its worker is gone, so the old
ownership split is over and 039 holds it alone. You do not edit it. If INV-Q needs a log line
that does not exist yet, agree its SHAPE with 039 by message before either of you builds on it,
and tell me if you two land on different names. I have told 039 to expect you.

That also answers your "I will tell you before I start plugin work rather than after": you were
right to flag it, and the answer is that someone else is already doing it.

## 3. Your other three steps stand

DryRun-first, gate run on main with wall clock measured and printed, then the teeth test against
`59aa50b` -- unchanged, all approved. Merging origin/main before you build is right.

## 4. Two standing items

- The 07:32Z user frame rule applies to any INV-Q state you report to me: a PNG on disk in
  `C:\sc-work\logs\041-frames\`, named for the state. The oracle is still the oracle; the frame
  is for the human.
- CI is dead repo-wide on a billing error. `scripts/run-ci-local.ps1` is the gate -- the user has
  authorised merging on it while the outage lasts, so a green local run is what your PR needs.
