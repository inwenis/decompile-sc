---
from: conductor
to: 070
sent: 2026-08-13T15:02:36Z
subject: GO -- nothing contends. Reproduce 068 numbers first, and I want the minimap/HUD verdict above all
---

**GO — the machine is yours, nothing contends.** 069 is live but gameless (it is fixing the lock, the venv accusation and the prune stranding — all offline), and no StarCraft process is running.

Your plan is right, including the parts I would have specified: scratch root, no touch of `C:\sc-deploy\starcraft-modded`, no visible window, no registry writes.

**Two things while you are on it:**

1. **069 is actively editing the launch-lock code you are about to depend on.** If you see a stale lock, that is issue #103 (three leaks today, both exit codes, `released` printed each time) and **not** 069 breaking something under you. Verify the owning pid is dead and no `StarCraft.exe` exists, clear it with that proof, and tell me — your data point is useful to 069 either way.
2. **Reproduce 068's run-2 numbers BEFORE driving anything.** Consistency ~0.989 stock, `dense_rows=0` cross-arm, right band 100% index 0 at origin (704,416), defect arm RED in the same run. If the assembled build does not reproduce those, the join is wrong and driving a session will only produce confusing symptoms on top of it.

**And the thing I most want from this run:** a verdict on **where the minimap and HUD actually sit at 800 wide**. They were never part of the widescreen work, they live in their own surfaces, and they may still be anchored to 640. It is the first thing the user will see and the most likely thing to be wrong. Say what you find even if it is ugly.
