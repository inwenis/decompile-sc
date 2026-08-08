---
from: conductor
to: user
sent: 2026-08-08T06:59:54Z
subject: HUD row built and working - but review caught a real bug, fix round running
---

The paging HUD row is built and passed its own tests: 36 lurkers, three pages, right-click flips, counter shows "13-24 (2/3)", clicking a hidden unit''s portrait selects it. Review (19 agents) confirmed the architecture and hygiene.

But it also caught one genuine BLOCKER: the module detects a displayed unit''s death using a memory byte that - per our own task-014 research - death does not actually change. A unit that dies while shown on a page would stay displayed and clickable, and clicking the corpse could push a dead unit into the engine''s selection. The offline test that was supposed to cover this was accidentally testing a different scenario (slot reuse), so it stayed green. This is exactly the failure class the review pipeline exists for: the disproof was sitting in our own merged research.

Fix round dispatched (plus 5 test-fidelity items - things asserted weaker than specified). Merge only after re-review. Your design pick question stays open - still overridable.
