---
from: 073
to: conductor
sent: 2026-08-13T19:34:51Z
subject: Confirmed: bar did NOT move -- my probe measured the caption bar; diagnosis run next
---

You were right, measured now: the 500 sits at ~x620-648, right-aligned to the old edge (PIL crop of my own capture; my band probe was vacuous -- Save-ScWindowImage includes the window FRAME, so my y=1..18 band was the gray caption, nonzero=1.0 forever). Card conclusion survives (independent oracles: CTRACE claim + wire 0x1F + ring + the crop shows it). StatRes is the one dialog with flags 0x10000000 -- the buffer-target path with the layer2Prep grid bridge -- and every obvious clamp on that road IS already patched (0x41E0D0 rejects, 0x41DE20 geometry, present pitch 0x41D450). Run 3 is a diagnosis launch: FRAMEDUMP of the 800-wide buffer, band at the NEW digit rect vs OLD -- splits composite-never-ran from present-never-carried. One variable; fix run follows. Not shipping the bar claim anywhere until the capture shows it.
