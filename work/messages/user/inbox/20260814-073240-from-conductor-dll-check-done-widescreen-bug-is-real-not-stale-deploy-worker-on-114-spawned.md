---
from: conductor
to: user
sent: 2026-08-14T07:32:40Z
subject: DLL check done: widescreen bug is real, not stale deploy; worker on #114 spawned
---

1. **#113 check result: you played the CURRENT build.**
   1. Deployed DLL stamp: `8d40c89+dirty` — includes PR #112 (task 074, all-800-columns). The `dirty` was two message files, not source.
   2. So no wrong-DLL fix exists — the black right band + dead mouse is a real open defect. Task 073 already flagged a "standing Wide defect" at merge time.
   3. Working widescreen does not exist yet in real play. #113 is the fix vehicle — say go and I cut a task for it.
2. **What is cnc-ddraw**: an open-source replacement `ddraw.dll` that sits between the game and Windows. StarCraft asks DirectDraw (1996 API) to draw; cnc-ddraw catches those calls and presents via modern graphics (GDI/OpenGL/D3D) — that gives windowed mode, scaling, and lets us present the widened 800px frame. We switched to it from the old WMode injector during the widescreen work (task 065). It is pinned by hash and configured via `cnc-ddraw.ini`, so scaling/mouse-lock are likely config, not code.
3. **#114 work started**: task 075 cut + worker spawned (sonnet) on branch `task075-window-scale-mouse-lock`.
   1. Contract: 2x window scale + mouse lock back, measured via live window-rect/cursor-clip read-backs, offscreen harness unaffected.
   2. You get it after review → merge → deploy; I''ll tell you when it''s deployed, not just merged.
4. **#115 (blank depot icon text)**: honest answer — I don''t know yet. Nothing in `research/` covers it. Needs a memory read-back of that control in a live session. Stays parked as a question issue until you want it picked up.
