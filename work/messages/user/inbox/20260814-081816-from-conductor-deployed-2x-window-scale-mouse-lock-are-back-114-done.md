---
from: conductor
to: user
sent: 2026-08-14T08:18:16Z
subject: DEPLOYED: 2x window scale + mouse lock are back (#114 done)
---

1. [PR #119](https://github.com/inwenis/decompile-sc/pull/119) merged, task 075 closed, and **deployed** — build `2fe7295`, both shortcuts refreshed on your desktop.
2. What changed: your NORMAL shortcut now presents through cnc-ddraw (same presenter the Wide one uses) instead of WMode — WMode structurally had no config, which is why scale/lock vanished.
3. How to use it (normal "StarCraft Modded" shortcut):
   1. Window comes up at **1280x960** (2x) automatically.
   2. Mouse lock: **click once anywhere in the game window** — cursor is then confined. Not automatic on focus; that''s cnc-ddraw''s own behaviour for plain windows (verified in its source).
   3. Free the cursor anytime: hold **Ctrl** or **Right Alt**. Click again to relock.
   4. Persistent toggles (edit `C:\sc-deploy\starcraft-modded\plugin\cnc-ddraw-2x.ini`, then redeploy): `width=0 height=0` → back to 1x; `devmode=true` → lock off entirely.
4. The WIDE shortcut is unchanged (still unscaled) — 2x-on-wide was never measured, so it wasn''t shipped blind. Say the word if you want it tried.
5. Gate note: GitHub Actions is still dead (billing), so this merged on the full local CI run — 307/307 tests, plugin hooktest clean, receipt on file. One stale test caught and fixed in review along the way.
