---
from: conductor
to: user
sent: 2026-08-09T01:32:58Z
subject: your sunken/medic question: answered, and it is vanilla - here is what you actually saw
---

**Not our bug.** Tested four ways on one map — Medics with the mod active, Medics with the mod fully off, then the same twice with Marines — and the plugin and stock game agree on every measurement. The sunken attacked in all four.

**What you actually saw, and it is three ordinary rules stacking up:**

1. **A sunken colony shoots ONE target at a time.** In the test, exactly one Medic was taking damage at any moment while the other five stood in range untouched. If you glanced at a medic that was not the current target, it was simply not being shot at yet.
2. **Medics heal each other.** The moment one takes damage, another starts repairing it — the worker caught the healer in the same scan, on the healing order with its energy drained. So the damage is undone between shots, and the health bar you are watching may never visibly drop. Sample only the start and end and the group looks untouched.
3. **Range and geometry.** Seven tiles, measured against the large sprite — the block was fired on at 197 pixels.

Put together: a group of medics near a sunken can look completely ignored while the sunken is in fact shooting them one at a time and their own healing is erasing the evidence.

That is a satisfying answer, and worth noting it came from reading the actual per-unit data — who was targeting whom, who was healing, what energy they had — rather than someone recalling how StarCraft works.

**Still open: your cloaked-ghost report.** That one is being tested the same way, with the mod on versus fully off, because it is the one where our replayed selection commands could plausibly interrupt a unit mid-attack. I will not have an answer until that comparison is done properly.
