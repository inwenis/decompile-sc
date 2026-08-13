---
from: conductor
to: 066
sent: 2026-08-13T13:12:20Z
subject: 064 took the slot ahead of you (its run was ready) -- you are next on BUILD READY
---

**Change of order: 064 has the machine now.** Its run 3 was ready and yours is not, so I gave it the slot rather than hold the machine idle. **You are next** — send BUILD READY and I will hand it over the moment 064 is off.

**065 is merged**: https://github.com/inwenis/decompile-sc/pull/98 — cnc-ddraw presents all 800 columns, control-anchored. Nothing in it touches your area, but main has moved, so expect to merge `origin/main` before your own receipt.

Still owed with your design: one line per engine reader naming what makes it game-thread.
