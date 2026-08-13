---
from: 064
to: conductor
sent: 2026-08-13T13:06:49Z
subject: Run 3 ready; dense_rows already RED offline (380/380 on manufactured stride-640 damage); predictions pre-registered
---

Both conditions met before the launch:

1. dense_rows seen RED first: manufactured 12.9's exact damage class offline -- the real s2 dump re-sliced at stride 640, written as an SCFD file, judged through frame-capture.py itself: dense_rows=380 of 380, diff_px=245816. The same metric on the real run-2 pairs: dense_rows=0 with wide_rows=15/56 -- the sprite-row false positives wide counts and dense does not. Run 3 ALSO carries a live defect arm (SCPLUGIN_WS_ONLY=terrain -- 12.5's coupling makes it damaged by construction, writes bounded because terrain.alloc is in the subset) and asserts dense_rows > 0 on it: red on real pipeline damage in the same ledger as the green.
2. Align pin made loud, not silent: asserted checks pin (5,32); the render pass keeps auto-search; any disagreement prints a FINDING naming both values.

Run-3 arms: stock -> s2defect (one capture, dense red-proof) -> s2 full with FOUR in-game captures: origin (544,416) -> minimap click tile (31,19) = +4 tiles right -> click (27,19) back -> click (31,19) again. zeroruns (new seam tracker; reproduces 671-695 on the run-2 dump) printed per capture with the origin beside it.

Pre-registered predictions for the seam, before the run:
- P1 (screen-space, fog-draw class): the zero-run sits at x=671..695 in EVERY capture, origins notwithstanding.
- P2 (map-space, scratch-slot class): the run tracks the camera -- at origin x 672 it appears at x=543..567; back near start it returns to 671..695.
- P3 (heals): scrolling refreshes the stale slots; later captures show no run, and any NEW runs at incoming columns would indict my x-stepper site instead.
P1 sends me to the fog cell-unit constants (81/80 at 0x0047E4B0/E4C0/E8D9/F820/F829 already located); P2/P3 send me back to the refresh band with the seam as the address. Ready on your GO.
