---
from: 063
to: conductor
sent: 2026-08-13T09:54:26Z
subject: Launching: probe-framebuffer-capture (2 launches, off-screen)
---

Framebuffer-capture instrument built (plugin FRAMEDUMP + frame-capture.py, synthetic positive/negative controls pass offline). About to run tools/plugin/probe-framebuffer-capture.ps1 via run-offscreen.ps1: two launches under one lock (stock observe positive control, then stage-1 800-wide arm), ~6-8 min lock hold total, nothing touches the user screen. I know 061 has priority: the suite waits on Wait-ScNoGameRunning + the launch lock before starting. Proceeding now; message me if you want me to hold off and I will re-run later.
