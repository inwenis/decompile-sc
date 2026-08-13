---
from: 074
to: conductor
sent: 2026-08-13T22:06:22Z
subject: run 7 (shipped config) found a 2nd requirement -- fixing
---

Good that I ran the shipped config (ConsoleEdge=0) before the PR -- it caught something run 6 hid.

Run 7: base +0x18=800 (widen applied, [4] OK) BUT MAP band BUFFER=0.73 GLASS=0 on the FIRST in-game frame. The present is DIRTY-RECT: widening the presentable region lets x>640 be copied, but the primary at x>640 stays black until those cells are marked dirty and re-copied. Run 6 showed GLASS=1.0 only because its minimap steer had SCROLLED first (a scroll marks all cells dirty -> full copy -> x>640 populated). On a static load frame, x>640 is black until the first scroll. Thats not shippable as-is.

So there are TWO caps, not one: (1) the presentable region width (base +0x18=640) -- what I found and widened; (2) the dirty-rect present never re-copies x>640 on a static frame.

Robust fix: hook storm ord432 (the buffer->primary copy) and, after its normal dirty-rect copy, copy the x=640..799 strip buffer->primary every frame. Targeted -- x>640 has NO console/HUD in the shipped config (console is 640 wide), so it overwrites nothing (your blanket-copy warning was about x<640, which this never touches). Self-contained, no dirty-mark dependency, atomic within the present lock (no tearing). Rebuilding + re-testing now.

(Also my probe hit a real bug: the in-game menu control is "End Mission", not "Quit" -- fixing the menu round-trip walk too.)
