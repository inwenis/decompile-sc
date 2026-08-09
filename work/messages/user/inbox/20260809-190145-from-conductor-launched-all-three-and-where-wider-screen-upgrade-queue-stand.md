---
from: conductor
to: user
sent: 2026-08-09T19:01:45Z
subject: launched all three; and where wider-screen + upgrade-queue stand
---

On it — three workers running now, and the answer on the other two.

**Launched (running concurrently — safe now that the harness serialises game access):**
1. **Building selection** (task 024) — box-select same-type buildings as a group, through the machinery we already built. First it finds WHY the engine selects only one building today, then reuses the selection/circle/liveness path.
2. **Queue >5 units** (task 025) — a different subsystem: the per-building production queue. It maps where the 5-slot cap lives before touching anything, and the hard constraint is resource safety (nothing paid for twice, cancels refund right).
3. **The cloaked ghost** (task 026, your "figure this out") — the command-card-from-memory approach. Instead of clicking at the Cloak button, read the card''s button array out of the process to name the slot AND whether it''s disabled. If the game greys Cloak out under some condition, that alone may answer your report — a Ghost that can''t cloak by an engine rule isn''t our bug. If it CAN be driven, it re-runs the order-stability test on a real cloaking Ghost.

I could run these three at once because of exactly what got hardened tonight: the launch lock serialises who drives the game, and per-task map folders stop them colliding. A week ago this would have been the bug factory you watched all evening.

**Where the other two stand — both QUEUED, not started:**
- **Wider screen:** an INVESTIGATION, scoped to your choice (a wider viewport with the stock HUD, not a stretched window). Nothing done yet — it comes after the three above. It''s the highest-uncertainty thing on the list; 640×480 is baked into the HUD, our own circle code, and the tests, so the spike has to map the renderer before anyone can say what''s achievable or at what cost. I will not put a number on it before that.
- **Queue upgrades:** QUEUED as a DESIGN-first task, because vanilla has no pending-upgrade concept at all — it''s inventing a mechanism, not raising a cap (where a pending upgrade is stored, what the UI shows, what cancel does). Nothing done yet; after the queue-5 work, since they''re the same subsystem and 025 will have mapped the production/build path first.

So: three in flight, two queued behind them, in that order. Redirect any time.
