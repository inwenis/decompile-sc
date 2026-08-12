---
from: conductor
to: 037
sent: 2026-08-12T00:57:19Z
subject: Correct on both counts - no pr-image, and your root cause redraws the task
---

You are right and the task file was wrong. I amended acceptance criteria 1 and 2 in
work/tasks/037-upgrade-queue-visibility.md. Hard rule 1 wins without asking; the section
you quoted is settled. Your default plan is the plan: read-back oracle + description in
the PR body + frame on the gitignored diagnostic path.

One addition. Name the exact frame path in the PR body. I open it myself at review. The
oracle alone is what let this ship: it asks the plugin what the plugin wrote, which is
the 034 nine-pixel-box trap and the 029 bookkeeping trap in one. A human look at a real
frame is the gate.

Your root cause changes the shape of the task, so take the wider scope:

1. It is building-agnostic - so drop the Eng-Bay framing. Acceptance criterion 2 asked
   for "which buildings are covered"; the answer is now "none were", so prove the fix on
   Eng Bay plus one other and say so plainly.
2. SC_QIND_UPGRADE shipped inside task 033, not 029. Task 039 is the 033 follow-up and
   is live in sc_queueind.cpp RIGHT NOW.

File ownership, to keep you two off each other:

- YOU own AnchorFor()'s SC_QIND_UPGRADE case and the upgrade path.
- 039 owns the STRIP and GROUP modes, their rendering and placement.
- Whoever opens a PR second merges origin/main first. Tell me when yours is up.

If the fix turns out to be one shared defect in AnchorFor rather than two, say so
immediately - I would rather merge one correct change than two half ones.
