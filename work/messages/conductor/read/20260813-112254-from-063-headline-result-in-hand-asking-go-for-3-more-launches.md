---
from: 063
to: conductor
sent: 2026-08-13T11:22:54Z
subject: Headline result in hand + asking GO for 3 more launches
---

**The first run answered question (1), and the answer is YES.** Both dumps stable; stage-1 dump reads the full 800x480; the never-presented right 160 columns read end to end (all index 0 -- the 800-aware clear, as stage 1 predicts); stage-1's left 640 columns agree with the stock arm INDEX FOR INDEX over the playfield (wide_rows=0, 1252 px of sprite animation). The positive control: stock 640 dump reproduces what the window presented at 0.989 consistency over the pure playfield, both arms, and renders into a recognizable frame PNG.

The 4 assertion FAILs in the transcript were the trust-check aimed at the wrong region, and diagnosing them produced two real findings: (a) the main-menu glue screens do NOT compose into 0x006CEFF0 at all (buffer all index 0, both arms); (b) in game the buffer holds the playfield but NOT the console/HUD dialogs (they live in their own surfaces -- the ones sc_queueind reads) nor the cursor. renderer-viewport.md 2 "everything composes into this buffer" needs a correction note. Suite recalibrated to the measured structure (commit b82024a), validated offline against the run's artifacts (0.989/0.989) and the synthetic torn-dump control still fails it (0.583).

**Asking GO for three launches, two slots:**
1. Clean re-run of probe-framebuffer-capture (2 launches, ~7 min) -- a PASS transcript for the instrument stage-2 development will lean on.
2. probe-fullscreen-desktop (1 launch, ~2 min): true-fullscreen on the INVISIBLE desktop while the parent samples the REAL desktop mode 4x/s. Risk disclosure: if the mode switch turns out per-adapter, the real screen may flip modes for seconds until auto-restore (registry mode re-apply) kicks in; that outcome is itself the measurement the task file demands (acceptance criterion 4). If you want that one at a quieter moment, say so and I run only (1) now.

Waiting for your GO before anything launches.
