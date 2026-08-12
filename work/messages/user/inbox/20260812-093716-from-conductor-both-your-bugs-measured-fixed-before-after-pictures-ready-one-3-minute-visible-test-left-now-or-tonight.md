---
from: conductor
to: user
sent: 2026-08-12T09:37:16Z
subject: Both your bugs measured fixed, before/after pictures ready -- one 3-minute visible test left: now or tonight?
type: question
options: Run it now, I want the fix today; Wait for tonight per my rule; Merge without that check and run it tonight anyway
---

Both of the bugs you reported are now measured fixed, with before and after pictures. Open these
pairs — the names line up, `-defect` is before and `-fixed` is after.

## 1. Command Center, 8 SCVs — your *"it becomes the number 2 and stays"*

    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-command-center-scv-fixed.png

The fifth slot was drawing its picture out of the BUTTON-BORDER artwork, using the unit type as
the frame number — so it is a function of what you queued, not of how many, which is exactly why
it never changed as the queue grew. Ink measured on the slot: **470 → 57**, and the fixed one
carries the slot number as a label.

## 2. Barracks, 8 Marines — your *"for one barrack it blacked out"*

    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-defect.png
    C:\sc-work\logs\039-frames\fifth-slot-barracks-marine-fixed.png

Same bug, different unit type, therefore different garbage: **631 → 57**. Two different wrong
pictures, one identical right picture — that pair of numbers is the proof it was one bug and not
three.

## 3. The same two, two seconds later — your *"stays regardless of queue length"*

    ...-command-center-scv-settled-defect.png / -settled-fixed.png
    ...-barracks-marine-settled-defect.png   / -settled-fixed.png

Also settles something separate: the "+3" overflow text was on the screen in NEITHER defect frame
(0 bytes drawn) and is in both fixed ones.

## 4. Four Command Centers selected — your *"text behind the buildings icons"*

    C:\sc-work\logs\039-frames\group-defect\feature-05-group-read.png
    C:\sc-work\logs\039-frames\group-fixed\feature-05-group-read.png

**And here you were more accurate than I was.** I told you at 08:38Z that this line was being
painted underneath everything. It was not: it was drawn ON TOP OF the icons at box top 9 — inside
the icon row, over the wireframes, fighting them for the same pixels. Which is precisely what you
described: text that appears in front and behind. The fix moves it to top 79, just below the row''s
lowest button edge at 78. So the line is now outside every button rather than winning a fight it
should not have been in.

## One decision for you — a three-minute game window today, or tonight?

One regression check is left: making sure this change did not break the 12-icon row itself. That
suite is one of six that MUST take the foreground (it opens a dropdown, which cannot work on an
invisible desktop), so it means a StarCraft window on your screen for about three minutes.

By your own rule that waits for 23:00. But it is the last thing between this fix and merging, so
waiting means the fix lands tonight rather than now. Your call — the options are on this message.

Everything else 039 has left runs invisibly and is happening as I write.
