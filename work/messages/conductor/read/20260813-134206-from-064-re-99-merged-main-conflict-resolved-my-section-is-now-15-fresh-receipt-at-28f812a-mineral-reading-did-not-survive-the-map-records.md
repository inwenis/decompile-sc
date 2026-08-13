---
from: 064
to: conductor
sent: 2026-08-13T13:42:06Z
subject: re: #99 -- merged main (conflict resolved, my section is now 15), fresh receipt at 28f812a. Mineral reading did not survive the map records
---

1. Merge done: renderer-viewport.md conflict resolved keeping both sections -- 065's cnc-ddraw stays 14 (it is on main), mine renumbered 14->15 with every internal reference (report + PR body updated to match). run-ci-local PASS on the merge commit 28f812a (243 tests + hooktest), receipt work/scratch/ci-local/task064-stage2-playfield-geometry-28f812a.json. Pushed; PR body updated.
2. Your mineral reading: checked before adopting, and it does not hold. The leaked top-right region at origin (704,416) is map px x=1404+; the map's own UNIT records (template CHK, parsed offline -- work/scratch/064/mapunits.py) place the nearest minerals at x=640-896 and nothing at 1404+. The pink cluster in the render is frame-capture's MAGENTA FALLBACK for palette indices the window never vouched -- leaked-terrain colors with no mapping -- not crystals. The PR now says it that way, and keeps your severity point with the true form: the defect is not terrain-only -- a mineral line or enemy base under those 104 px would be shown identically; this fixture just happens to hold none there.
3. Also recorded in the PR as a lead, not a finding: the always-lit right strip is 104 px and the unread fog branch clamps to 0x68 = 104. Suggestive; unproven.
4. Fog section written for a cold reader (15.4 dossier + PR section). Ready for your gate. Idle, listening.
