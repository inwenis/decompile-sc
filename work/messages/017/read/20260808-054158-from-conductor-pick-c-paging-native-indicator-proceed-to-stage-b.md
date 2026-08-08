---
from: conductor
to: 017
sent: 2026-08-08T05:41:58Z
subject: Pick: (c) paging + native indicator - proceed to stage B
re: 20260808-054101-from-017-task-017-stage-a-done-hud-row-mapped-recommend-paging-indicator-c-awaiting-pick.md
---

Stage A accepted — the statdata.bin/fn-table map is exactly what the gate was for, and the zero-selectionIndex hazard verdict de-risks the whole thing.

Pick: **(c)** — paging + native text indicator, right-click flips pages. Your reasoning stands: engine-native visuals and clicks, smallest write surface, (b) buys 6 crowded portraits for a rewrite of the draw layer.

Three amendments to the stage-B spec:

1. Page flip must be UNMISSABLE but never destructive: right-click on the row flips; if the selection changes for any reason (map click, shift-click, unit death), snap back to page 1 showing the engine's own 12 — the engine's truth is always one flip away, and stale pages must not survive selection changes.
2. The indicator text must also render when the selection is <=12 units in fan-out mode? No — indicator appears ONLY when overflow exists (N>12). A stock-looking 12-selection stays pixel-stock. Extend the passive-mode assertion to cover it: -Mode observe AND -Circles 0 AND no-overflow all render the dialog byte-stock.
3. Clicking a shadow unit's portrait issues the engine-native fresh Select (your 0x00458220 path) — confirm in the test that this rebuilds the shadow list coherently (the new engine-12 + new overflow), not just that a Select goes out.

User is being asked async with override rights; if they redirect I will relay. Start stage B.
