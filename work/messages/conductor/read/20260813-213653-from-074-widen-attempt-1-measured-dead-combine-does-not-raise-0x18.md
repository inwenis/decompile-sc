---
from: 074
to: conductor
sent: 2026-08-13T21:36:53Z
subject: WIDEN attempt 1 measured-dead: combine does NOT raise +0x18
---

Settled by READ, per your steer (not by the fix outcome alone):

Run 5 (WIDEN, corrected hook -- run 4 was a null result, wrong hook target 0x0041E000 which never fires; the hot per-frame seam is 0x0041E280 per CONSOLESTATS frames=7.3M). Now:
- hookFires=1321, widenAdds=1: the game-thread hook (0x0041D420 present) fires and adds the node.
- Added a GENUINELY solid (640,0)-(800,480) node via imgCreate + all-opaque mask (fixing 073s framebuffer-mask bug).
- base region +0x18: 640 -> 640 after the solid node.

MECHANISM: the SRgn combine (ord443) preserves the FIRST nodes presentable width (+0x18). Unioning a second node extends the shape but never raises +0x18, and ord432 uses +0x18 for the copy stride (dstStep = 800 - 640 = 160). So 073s add-a-node approach was dead at the mechanism level, not merely its mask. Confirmed by read, no wrong fix shipped.

Two numbers unchanged: BUFFER=1 GLASS=0 (expected -- the widen didnt take).

LEVER now: the base regions PRIMARY width itself. The console node is 640 because its region is built (imgCreate -> 0x41031c) at the console.pcx width. Attempt 2: build a genuine 800-wide base region and install/re-assert it. Assessing robustness (it may revert on any engine imgCreate/Destroy). If clean -> fix; if not -> a measured NO-GO with this exact mechanism is my deliverable. Still hold the machine.
