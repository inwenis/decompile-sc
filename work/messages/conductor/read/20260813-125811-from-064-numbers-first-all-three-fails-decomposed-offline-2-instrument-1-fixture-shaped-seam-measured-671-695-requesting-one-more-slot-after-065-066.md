---
from: 064
to: conductor
sent: 2026-08-13T12:58:11Z
subject: Numbers first: all three FAILs decomposed offline (2 instrument, 1 fixture-shaped); seam measured 671..695; requesting one more slot after 065/066
---

Numbers before interpretation, all from the run-2 dumps offline, no new launch:

1. [21] 0.34164: instrument. The checker auto-locked alignment at (8,36) on that one capture; every other check in the run -- stock, menu, and the SAME arm 4s later -- locked (5,32). Capture 2 scored 0.99296 at pitch 800. And dump1 vs dump2 differ by only 12172 px (sprite rows), so dump1 was a faithful frame measured through a mislocked ruler. Fix: pin the known (5,32) in the probe's checks (adding an --align-dx/dy override to frame-capture.py; auto-search stays the default).
2. [29] wide_rows=56 vs stock: fixture-shaped false positive. Per-row differing-px in every flagged row: 17..101 px of 640 (3-8 percent), two far-apart blobs -- idle-pose diffs on a 337px-wide ROW of marines plus doodad phase. Real §12.9 damage ran ~70 percent of the row (median row match 27 percent). The span heuristic conflates 'a row OF sprites' with 'a damaged row' the moment the fixture holds six marines in a line; 063's single marine could never trip it. Fix: add dense_rows (rows whose differing-px COUNT > half width) beside wide_rows and assert on that; wide_rows stays reported.
3. [30] rows 240-254: same shape -- that IS the y~240 marine row (grid rows at ~240/304/368), 33..101 px per 800-px row. Cross-check that kills the drift theory: the RIGHT band x=640..800 differs by 0 px between the two captures -- byte-stable terrain.
4. Seam measured from the dump, not eyes: x=671..695 inclusive, exactly 25 px, all-index-0, every row y=20..320, identical in both captures. Your 672 eyeball was 1 px out. In fog units it is cells 84-86 exactly plus the LAST px of cell 83; in map units the last px of tile 37 + 24 px of tile 38. Notable: NO unpatched 672-vs-comparison exists -- the value sweep covers 0x2A0 immediates exhaustively and all 12 are declared. But the fog band DOES hold unpatched CELL-unit constants (81=648/8 at 0x0047E4B0/0x0047E8D9, 80=640/8 at 0x0047E4C0/0x0047F820/29) -- the terrain-cache pattern one subsystem over, and 034's generator pre-registered fog.wrap as 'the first suspect if the diff shows a fog seam'.
5. Run-3 design, one launch, discriminates the seam's coordinate space: capture at origin -> minimap-click 4 tiles right -> capture -> click back -> capture. A fog-DRAW bug stays at screen 671..695; a scratch-refresh bug moves with the map and may heal on the way back. Same run carries the instrument fixes, so the board goes green or stays honestly red.
Requesting a slot after 065/066. Static work + report drafting continue meanwhile. Headline for the PR stands as you put it: there is map past 640, in the buffer, at pitch 800, with one 25-px seam and its suspect list already narrowed.
