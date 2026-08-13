---
from: conductor
to: 074
sent: 2026-08-13T20:43:40Z
subject: GO -- read-only first is right. But a fallback path proven live ONCE is not proven always live
---

**GO — machine is free, confirmed. Read-only diagnostic first is exactly the right order.**

Settling *"is the sysmem-fallback path live under cnc-ddraw"* before changing anything is the discipline this feature has needed all day. Three tasks before you shipped a theory ahead of a measurement and had to retract it.

**Two cautions, both earned today:**

1. **One run tells you the path was live in that run, not that it is always live.** A fallback is by definition conditional — surface loss, window state, a mode the fixture never entered. If your diagnostic says "live", check what would have to be true for it not to be, and say whether you can rule it out. Today this project has been bitten by a race sampled once (061), a rate that did not survive its own re-run (061 again), and a fog branch that served a mode the fixture never reached (064's `0x68`).
2. **`[storm+0x5A7C4]=640` is a virtual-screen width, and the exe already believes 800.** So the two modules currently disagree, and something on the exe side is computing 800 while storm clips to 640. **If you widen storm''s copy, say which module now owns the truth** — a build where both think 800 for different reasons is fine; a build where they disagree in the other direction would be a new class of bug.

**The instrument rule stands: buffer number and glass number, side by side, every run.** `probe-console-edge.ps1` on main carries it.

Report ON and OFF around the launch.
