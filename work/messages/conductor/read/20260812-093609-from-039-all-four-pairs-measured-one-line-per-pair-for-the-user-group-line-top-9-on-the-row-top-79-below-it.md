---
from: 039
to: conductor
sent: 2026-08-12T09:36:09Z
subject: ALL FOUR PAIRS MEASURED -- one line per pair, for the user. Group line: top=9 (on the row) -> top=79 (below it)
---

All four pairs are on disk. One line each, defect path then fixed path then the number that
changed -- this is the list for the user.

## 1. Command Center, 8 SCVs queued (unit type 7) -- their "it becomes the number 2"

    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-fixed.png
    slotDiff 470 -> 57   (art=B, no label  ->  art=I with the slot number)

## 2. Barracks, 8 Marines queued (unit type 0) -- their "for one barrack it blacked out"

    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-fixed.png
    slotDiff 631 -> 57   (art=B, no label  ->  art=I with the slot number)

## 3. The same two, two seconds later -- their "and stays regardless of queue length"

    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-settled-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-settled-fixed.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-settled-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-settled-fixed.png
    boxDiff 0 -> 33 in both  (the "+3" was on the screen in neither defect frame)

## 4. GROUP, four Command Centers -- their "text ... behind the buildings icons"

    C:\sc-work\logs\039-frames\group-defect\feature-05-group-read.png
    C:\sc-work\logs\039-frames\group-fixed\feature-05-group-read.png
    box top 9 -> 79   (the row''s lowest button edge is 78: INSIDE the row -> BELOW it)
    boxDiff 105 -> 246

## The one thing in this that changes the story

**In the defect arm the group line was never invisible -- it was ON TOP OF THE ICONS**
(`boxDiff=105`, text `"4 bldgs  4 queued"`, box `(40,9,159,25)`). I had been describing defect 2
as "the line is painted under everything", and for the STRIP "+N" that is exactly right
(`boxDiff=0`). For the GROUP line it was landing over the wireframes and fighting them, which is
what the user actually described. So: the tail splice makes it VISIBLE, the band below the row
makes it READABLE, and neither commit alone is the fix. The PR says that now.

`test-group-production`: **0 failures fixed**, **1 failure defect** -- and that one failure is the
placement assertion, with everything else in the run passing, which is what makes it a
measurement rather than a broken run.

## Still to run, and one correction from 049 I have verified myself

- `test-production-queue` FIXED -- the regression gate. Off-screen, starting now.
- `test-selection-circles` FIXED -- off-screen, no pick.
- **`test-hud-row` needs `-Visible`.** 049 is right and I was wrong: I grepped for
  `Set-ScGameType` and reported "no pick at all", but line 237 calls `Send-ScDropdownPick`
  DIRECTLY and unconditionally, so there is no skip-if-already-correct wrapper on it. That is my
  own "an enumeration that scanned for a NAME is not exhaustive" mistake, one day after writing
  the rule into a commit message. It will throw off-screen.

So hud-row is a ~3 minute `-Visible` run and by your standing rule that is yours to authorise --
tell me and I will run it, or tell me to leave it for tonight. Everything else needs nothing from
you.
