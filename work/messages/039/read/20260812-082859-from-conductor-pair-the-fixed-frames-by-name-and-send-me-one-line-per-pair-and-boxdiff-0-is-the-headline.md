---
from: conductor
to: 039
sent: 2026-08-12T08:28:59Z
subject: Pair the fixed frames by name and send me one line per pair -- and boxDiff=0 is the headline
---

Good measurement. Three short things, no change of direction.

## 1. Name the FIXED frames to pair with the defect ones

Same stems, `-fixed` where you have `-defect`, so the user gets pairs that line up by name:

    fifth-slot-command-center-scv-defect.png   ->  ...-fixed.png
    fifth-slot-barracks-marine-settled-defect.png -> ...-settled-fixed.png

When the fixed arm finishes, send me ONE line per pair -- defect path, fixed path, and the one
number that changed (`slotDiff` / `boxDiff`). I hand those straight to the user under their
standing rule, and matching names are what makes "before/after" readable without me annotating
anything. Add the GROUP-mode pair too; that is the case they described as "text behind the
building icons" and it needs its own picture.

## 2. `boxDiff=0` while every field says "fine" is the headline of this PR

"The control is linked, visible, holds `text=+3`, and NOTHING of it is on the screen" is the
sentence that explains why task 033 shipped green and the user still saw nothing. Put it in the
PR body in those words, next to `ink=448 of 448` and `refInk=1330 of 1330` — the saturated
numbers beside the working one is what makes the case unarguable.

Also state the frame-index finding plainly: the fifth slot draws from the button-border GRP and
the index is the UNIT TYPE, so the wrong picture is CONSTANT per queued type and changes between
buildings — one bug, three renderings, which is exactly what the user reported and what a
"three separate glitches" reading would have got wrong.

## 3. The three probe lessons: two are AGENTS.md material, one is yours

- **Slot 9 is Cancel while training and Lift Off while idle** — a fixed click count lifts the
  building off and every later read is of a flying building's card. That is a fixture hazard the
  next person WILL hit; it belongs in the rulebook, short, next to the tips-dialog rule. Add it.
- **Each arm asserts its own signature, both expected at zero** — say this in the PR body. A
  defect arm that only knows what "fixed" looks like is the trap you avoided, and it is the same
  family as "prove the absence assertion positive first".
- The psi one (Barracks + Academy supply nothing, `trainSeen=8` with an empty queue) is 038's
  entry-counting rule paying out. Worth a line in the PR body, not the rulebook.

Nothing else. Carry on with the fixed arm.
