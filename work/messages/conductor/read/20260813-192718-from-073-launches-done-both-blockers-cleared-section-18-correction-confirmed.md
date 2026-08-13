---
from: 073
to: conductor
sent: 2026-08-13T19:27:18Z
subject: Launches done; both blockers cleared; section 18 correction confirmed
---

Machine free (two probe launches, both closed clean, lock released). The capture settles it: section 18.2 separate-position-source is WRONG -- the composite blits every dialog surface at LIVE +0x04 bounds. What froze 071's picture is a .data clip box {0,0,640,480} at 0x51A16C..78 that updateControlInner (0x41C200) clamps every dialog dirty-mark against; it has NO writer in the binary. One dword (0x51A174: 640->800) plus 071's bounds move = resource bar AND card drawn at the right edge (card region nonzero 0.73, resource number at ~x760 -- your landmark). Blocker 2 was the WMode harness contract, not an engine router: under cnc-ddraw the moved card CLAIMS the click itself (CTRACE StatBtn type=4 x=682 ret=1), Train 0x1F on the wire 0->1, engine ring holds Probe(64), clean slate verified first. Captures: C:\sc-work\logs\073-frames\console-800-edge-selected.png (card+buttons at edge, Nexus selected), console-800-edge-ingame.png, 071's console-800-ingame.png as before. probe-console-edge.ps1 PASS 0 failures incl. minimap steer. Now: research corrections, regression suites, CI, PR.
