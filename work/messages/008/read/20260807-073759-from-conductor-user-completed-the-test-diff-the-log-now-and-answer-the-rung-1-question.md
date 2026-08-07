---
from: conductor
to: 008
sent: 2026-08-07T07:37:59Z
subject: USER COMPLETED THE TEST - diff the log now and answer the rung-1 question
---

The user has DONE the test. Their report, verbatim:

  "i did exactly this
   Once in game:
   click ONE worker (we expect count = 1)
   shift-click a second (we expect count = 2)
   drag a box around all your starting units (we expect count = 4-ish, whatever you see)"

Sent at 07:36:57Z, so the three selections happened in the minutes around then. They did not give exact per-action timestamps — work from the log's own state transitions.

Diff it now and report precisely:

1. Did `clientSelectionCount` actually go 1 -> 2 -> (box group)? Quote the log lines with timestamps.
2. Does `nonNullGroup` agree with `clientSelectionCount` on every sample? A disagreement between those two is itself a finding — it would mean the count and the array disagree about reality.
3. Do the populated `clientSelectionGroup` slots match the count, and are they contiguous from index 0?
4. Does `activePlayerSelection` / `playersSelections[activePlayer]` track the same units as the client-side array, or do they differ? The recon predicted the client copy and the simulation-side array are distinct; this is the first chance to see it live.
5. What did `selectionIterator` do across those transitions?

Then answer the question this whole rung exists for, in one line: **do the statically-derived addresses from `binary-selection-map.md` hold in a live process — yes or no?**

If ANYTHING disagrees, say so plainly and do not round it off. A mismatch found now, read-only, is exactly the cheap outcome we wanted; a mismatch smoothed over here becomes a corrupted game later.

If the user's actions did not produce clean transitions in the log — if the box-select is ambiguous or you cannot tell the actions apart — say that too. They are at the keyboard right now and can repeat any single step on request. Do not guess to fill a gap; ask, and I will relay.

Once you have the answer, write up `research/runtime-selection-observations.md` and finish the task. You are close.
