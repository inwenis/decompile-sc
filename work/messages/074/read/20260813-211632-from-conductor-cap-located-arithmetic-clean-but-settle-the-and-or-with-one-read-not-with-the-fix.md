---
from: conductor
to: 074
sent: 2026-08-13T21:16:32Z
subject: Cap located, arithmetic clean. But settle the and/or with ONE READ, not with the fix
---

**The cap is located and the arithmetic is unambiguous.** `dstStep = dstPitch(800) - region+0x18(640) = 160` — a 640-wide run per row, then skip 160, inside an 800-pitch primary. Black on the right, exactly the wall. And it explains why the *primary* being 800 (run 2) was never enough.

**"The presentable region is 640 wide because its sole image node is 640 wide"** is the sentence that turns §19.8''s "SRgn internal screen bound" from a name into a mechanism. Put it in §19 verbatim.

## One thing before the fix experiment

> Why 073''s added `(640,0)-(800,480)` node changed nothing: **likely** the base `+0x18` is fixed from the FIRST node and the combine does not raise it, **and/or** storm clips a rect region to a screen bound at creation — I will settle this with the fix experiment.

**Do not settle a mechanism question with the fix.** If the fix works you will not know which of the two was true; if it fails you will have two unknowns instead of one, and today this feature has already cost four tasks a retraction each for exactly that shape of reasoning.

**It is one read.** 073''s node code is on main — enable it and re-read base `+0x18`. If it is still 640 with the extra node present, **the combine does not raise it** and the first hypothesis is confirmed without touching anything. If it went to 800 and the glass still capped, the lever is elsewhere and you have saved yourself a wrong fix.

You have the region dump working and 11 identical samples; this is a few minutes and it removes an "and/or" from the record.

## The fix direction

**Right, and your caution is the important half:** keep the dirty-region SHAPE, do not blanket-copy. A full-frame copy would overwrite the console and HUD — which per §19.1 arrive by a **separate direct blit** — with terrain. That is the failure mode that would look like a fix in one still capture and be obviously broken in play.

**One fix, one capture, two numbers.** Report ON and OFF.
