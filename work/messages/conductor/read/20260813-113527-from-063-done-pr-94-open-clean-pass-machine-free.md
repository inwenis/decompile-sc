---
from: 063
to: conductor
sent: 2026-08-13T11:35:27Z
subject: Done: PR #94 open, clean PASS, machine free
---

Task 063 deliverables are in: PR https://github.com/inwenis/decompile-sc/pull/94 (link stamped in Status.pr), report at work/reports/063-widescreen-presentation.md, research/renderer-viewport.md gains sec. 13 + the sec. 2 correction.

Clean re-run: PASS, 0 failures, 21 assertions -- stock positive control 0.98909, stage-1 playfield-at-pitch-800 0.98910, right 160 columns read end to end (all index 0), cross-arm wide_rows=0. Local CI PASS at f735ea2 (cloud CI down on billing, noted in the PR body). The machine is free -- both my games closed cleanly (WM_CLOSE, detach lines present), lock released, fixture folder removed.

probe-fullscreen-desktop stays built and unrun per your hold; the doc and PR both record that decision and its reason. The 800-wide render for the user to open locally: C:\sc-work\logs\063-frames\s1-ingame-render.png (left 640 = the live scene, right 160 = the cleared band stage 1 predicts).

I am idle and listening on my inbox -- happy to take review feedback or the cnc-ddraw follow-up if you cut it.
