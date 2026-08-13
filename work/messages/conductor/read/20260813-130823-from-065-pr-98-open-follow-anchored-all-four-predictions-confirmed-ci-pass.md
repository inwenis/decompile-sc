---
from: 065
to: conductor
sent: 2026-08-13T13:08:23Z
subject: PR 98 open - FOLLOW anchored, all four predictions confirmed, CI PASS
---

https://github.com/inwenis/decompile-sc/pull/98 (link also in Status.pr).

Scorecard, in prediction order:
1. Same-arm delta: inject 94.3%/93.7% vs cross-arm 93.5% - same order, falsifier (>=99.5%) not met. Control anchored as CROP. Your note folded in: cross-arm sits a hair below both same-arm figures, stated explicitly in research 14.4 and the PR.
2. Fresh cross-arm: 93.5%, verdict string again "SCALE (or something else)", locality reproduced (0 damaged columns, 5 clusters).
3. FOLLOW again at client 800x480; band below row 31 99.86% black in BOTH brackets (same 100 seam px) while left 640 changed 10.9% - presented surface, garbage excluded.
4. Caption strip rows 0..30 in every cnc-ddraw capture, none in WMode's.
Your other note also in both docs: ddraw same-arm noise floor (10.9-11.8%) named next to inject's (5.7-6.4%).

CI: local PASS at f1fc82f (243/243 pester, hooktest 0 failures), receipt work/scratch/ci-local/task065-cnc-ddraw-presentation-f1fc82f.json. Branched from main 6716c17 (post-#95). Cloud CI down on billing - noted in PR.

Pictures (paths travel, never pr-image): C:\sc-work\logs\065-frames\present-ddraw-ws1-menu.png is THE one - 800x480 window, menu left, presented black band right. Control beside it: present-inject-ws1-menu.png. Run-2 brackets in C:\sc-work\logs\065-frames-run2\.

I am idle, no game running, nothing on the machine. Available for review follow-ups.
