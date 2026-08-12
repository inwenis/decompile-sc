---
from: 039
to: conductor
sent: 2026-08-12T08:27:55Z
subject: DEFECT arm measured, 0 failures: the bug is now a number, and both of the user's buildings reproduce it
---

The defect arm ran off-screen (043''s desktop works -- nothing touched the monitor) and came out
at **0 failures**, which is the point: the defect arm asserts the DEFECT signature, so a failure
there would mean the bug is not what this task says it is.

## The user''s two named buildings, both reproduced, read out of the live dialog

| case | fifth slot | slotDiff | boxDiff |
| ---- | ---------- | -------- | ------- |
| Command Center, 8 SCVs (type 7) | `0x007:3:lit:B:0` | 470 | 0 |
| Barracks, 8 Marines (type 0) | `0x000:3:lit:B:0` | 631 | 0 |

- `art=B` -- the fifth slot draws its frame index out of the **button-border** GRP, and carries
  no slot label. That is defect 1, seen directly rather than inferred.
- **The two slotDiffs differ (470 vs 631) and that is the whole "different garbage in different
  buildings"**: the frame index is the UNIT TYPE, so the wrong picture changes with what is
  queued and is constant for as long as that type is queued. One bug, three renderings, exactly
  as the task file predicted.
- `boxDiff=0` is defect 2 measured rather than argued: the control is linked, visible, and holds
  `text="+3"` -- every field says "fine" -- and NOTHING of it is on the screen, because at the
  head of the child list the engine''s own controls paint over it in the same frame. This is the
  number that would have caught the whole class in task 033.
- `ink=448` of 448 and `refInk=1330` of 1330 in the same lines, saturated as ever. The old
  assertion was `ink > 0`.

## Frames on disk (defect arm)

    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-settled-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-settled-defect.png
    C:\sc-work\logs\039-frames\command-center-idle-empty-queue-defect.png
    C:\sc-work\logs\039-frames\barracks-idle-empty-queue-defect.png

The `-settled-` frame of each pair is taken two seconds later: the user said the Command
Center''s glyph "stays regardless of queue length", so a second frame is the cheap way to show
it is static rather than a flicker.

## Three things the runs taught, all in the probe, none in the plugin

1. **The first fixture had no psi.** A Barracks and an Academy supply nothing, and the sim
   refuses a Train it cannot house while the button stays lit -- eight Trains reached the
   engine''s funnel (`trainSeen=8`) and the queue stayed empty. That is 038''s "count the
   entries, not just the successes" paying for itself in one line. The Command Center is now in
   the map as the supply AND as the user''s first case.
2. **The cancel loop put the Command Center in the air.** Slot 9 is Cancel while training and
   Lift Off while idle -- one control -- so a fixed click count lifts the building off the
   moment the queue drains, and every later step then read a flying building''s card and
   reported "no Train button". The loop asks the queue before every click now, and each case
   ends by asserting the pane still holds the building it was measuring (`portrait type 106`
   / `111`).
3. **A defect arm that only knows what "fixed" looks like reports a mess**, so each arm now
   asserts its own signature and both are expected at zero.

The fixed arm is running now: the same probe, then test-production-queue, test-group-production,
and -- your mandatory 2 -- test-hud-row and test-selection-circles, because the tail splice
changes paint order for everything in that dialog.
