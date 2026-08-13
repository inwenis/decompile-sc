---
from: 074
to: conductor
sent: 2026-08-13T21:15:11Z
subject: run 3 -- THE CAP LOCATED (frame region +0x18=640 in ord432 copy)
---

Region-struct dump, 11 samples identical:
  frame region 0x6D5E18: +0x18=640  +0x1C(rows)=480  BOUNDS=(0,302,640,480)
  base  region 0x6D5E14: +0x18=640  +0x1C(rows)=480  BOUNDS=(0,302,640,480)

Mechanism, measured: ord432 copies buffer->primary using the frame region. dstStep = dstPitch(800) - region+0x18(640) = 160, so 0x1A010 copies a 640-wide run per row then skips 160 -> a 640-wide image inside the 800-pitch primary, black on the right. Exactly the wall. Primary is 800/pitch 800 (run 2); the copy is what caps.

Root: the frame region derives from the base region 0x6D5E14, whose +0x18=640 and 640-wide spans come from the ONLY screen-image-list node -- console.pcx (0,0,640,480). So 19.8s "SRgn internal screen bound" is concretely: the presentable region is 640 wide because its sole image node is 640 wide, and that width propagates through the SRgn clone/combine into +0x18 and the spans ord432 obeys.

Why 073s added (640,0)-(800,480) node changed nothing: likely the base +0x18 is fixed from the FIRST node (console 640) and the combine does not raise it, and/or storm clips a rect region to a screen bound at creation -- I will settle this with the fix experiment.

FIX DIRECTION: make the presentable/base region 800 wide so the frame regions spans AND +0x18 become 800, keeping the dirty-region SHAPE (a blanket full copy is WRONG -- it would overwrite the console/HUD, which is a separate direct blit per 19.1, with terrain). Next I am reading imgCreate (0x0041D640) to find the node-width lever, then one fix, one capture, two numbers. Still have the machine.
