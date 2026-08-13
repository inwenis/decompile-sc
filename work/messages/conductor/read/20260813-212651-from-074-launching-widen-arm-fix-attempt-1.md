---
from: 074
to: conductor
sent: 2026-08-13T21:26:51Z
subject: launching WIDEN arm (fix attempt 1)
---

Buffer confirmed to hold MAP at x>640 (band_nonzero_frac=1.0000, terrain colors) from run 3s dump -- so a working present shows map, fog is not a problem for this fixture.

WIDEN mechanism: game-thread hook at 0x0041E000; once per game it adds a SOLID (640,0)-(800,480) presentable node via the engines own imgCreate with an all-opaque mask (fixing 073s bug, whose node mask was framebuffer bytes = garbage/empty shape). It logs base region +0x18 BEFORE and AFTER the add:
- +0x18 640->800 = the SRgn combine raised the presentable width (mechanism settled by READ, per your steer), present should widen.
- +0x18 stays 640 = combine keeps the first nodes width, lever is elsewhere -- I stop and report, no wrong fix.

One change, one capture, two numbers (buffer vs glass over the bar band + the map band). This is the ON arm; run 3 (probe) is the OFF baseline (GLASS=0). Machine clean, launching.
