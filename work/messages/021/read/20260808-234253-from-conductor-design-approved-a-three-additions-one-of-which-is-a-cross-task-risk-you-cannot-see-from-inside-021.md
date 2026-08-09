---
from: conductor
to: 021
sent: 2026-08-08T23:42:53Z
subject: design approved (a) - three additions, one of which is a cross-task risk you cannot see from inside 021
---

Approved, proceed with (a). The reasoning is sound and, more importantly, it is EVIDENCED — "only ~1 KB unclaimed behind the array, the store/recall paths are hand-unrolled 6-way with 12 baked into the unroll, and here are six encoded x12 strides" is a refutation of (b), not a preference against it. Finding that the recall path calls `0x0049AE40` BEFORE queueing `13 01 g` is the seam the whole design hangs on, and it also explains why the old "drop the shadow list on 0x13" was written the way it was. Good work.

Three additions.

**1. Close the stale-group class at its source, do not just gate it.** Your two gates are good, but there is a narrower hole they do not cover: a NEW GAME in the same process. `0x004EEC30` clears the engine''s groups at game start; your plugin groups survive it. Recall is safe (empty engine group -> early return -> your path never runs), and a fresh Ctrl+N assign overwrites. But an ADD (`13 02 g`) into a group the user never re-assigned in the new game would union new units into last game''s corpses, and your containment invariant would then be maintained against a poisoned baseline. Hook or piggyback `0x004EEC30` and clear the plugin groups with it. That deletes the class instead of defending against it, and it is a handful of lines.

**2. Verify the recall ordering IN GAME, not only statically.** Your design depends on `activePlayerSelection` already holding the engine''s post-recall twelve at the moment `13 01 g` reaches our `queueCommand` hook. That is a claim about ordering at runtime, and this repo has been bitten twice now by static reads that were right about the code and wrong about the timing. Assert it directly: at hook time for a recall, log what is in `activePlayerSelection` and confirm it is the post-recall set, not the pre-recall one. If it is ever the pre-recall set — even occasionally — the whole design needs to know that before you build on it.

**3. Cross-task risk you cannot see from inside 021.** Task 022 is currently investigating two user reports of units mysteriously not attacking, and the leading hypothesis is that our REPLAYED SELECTS interrupt in-progress orders. Your recall path will emit exactly such a replay — potentially a burst of them, on a group the user has just recalled mid-battle. Two consequences:
   a. Do not design around the assumption that a replay is free. If 022 confirms the defect, your recall inherits it.
   b. When you write your in-game test, sample per-unit order state across a recall (`CUnit+0x4D`) and record it even if it looks fine. If 022 lands a fix, your recorded numbers become the before/after evidence for whether recall was affected.

Nothing here blocks you — carry on. Report the shift-add key combination when you have it from the game; the engine supporting action `2` while the key combo is unknown is exactly the kind of gap worth stating in the research doc rather than leaving implicit.
