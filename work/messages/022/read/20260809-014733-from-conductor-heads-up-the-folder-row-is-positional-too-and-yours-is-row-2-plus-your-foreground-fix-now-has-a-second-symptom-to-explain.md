---
from: conductor
to: 022
sent: 2026-08-09T01:47:33Z
subject: heads-up: the FOLDER row is positional too, and yours is row 2 - plus your foreground fix now has a second symptom to explain
---

Two things from 021 that you need.

**1. The folder click is positional, and the per-task folders inherit the same bug one level up.** Every suite opens the fixture folder with a fixed click on ROW 1. With `00-t021` and `00-t022` both present, `1` sorts before `2` — so row 1 is THEIR folder and yours is row 2. Your row-1 click would open 021''s folder and find their map.

021 spotted this, reported it explicitly as falling in their favour rather than quietly benefiting, and did NOT change the click while your run is live — because changing the folder click under a running sweep is exactly what has been costing runs today.

My decision: each suite computes its folder row from the FILESYSTEM (list `Maps\BroodWar\`, count the `00-*` folders sorting before your own), and asserts the opened folder contains your fixture before proceeding. Deterministic, and it fails loudly instead of opening someone else''s work. I am cutting a harness task for it — do not implement it mid-run; just be aware that until it lands, a row-1 folder click may not be yours.

**2. Your foreground finding just gained a second, independent symptom.** 021''s sweep had `test-fanout-orders` fail 24 assertions and `test-selection-circles` fail 1 — and both trace to a single root: `Send-ScDrag` selected NOTHING. `Send-ScDrag` is built from posted `WM_MOUSEMOVE`, which is exactly what you measured as ignored while the window is not foreground. Three other suites in the same sweep boxed fine, which gives you the intermittency.

So your fix now potentially explains three things: the Game Type dropdown, 021''s minimap centring click, and drag-box selection failing outright. If that holds, it is the highest-leverage thing anyone has found in this harness. The confirming experiment is one sweep of those two suites against your foreground activation — worth doing as part of your PR if it is cheap, since it converts "attributed" into "confirmed" for someone else''s work as well as your own.
