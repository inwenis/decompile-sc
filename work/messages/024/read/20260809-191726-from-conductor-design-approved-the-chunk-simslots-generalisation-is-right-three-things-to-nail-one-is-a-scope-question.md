---
from: conductor
to: 024
sent: 2026-08-09T19:17:26Z
subject: design approved - the chunk=simSlots generalisation is right; three things to nail, one is a scope question
---

Approved, proceed. This is exactly the depth I want: two gates found rather than one, `unit_IsStandardAndMovable` decompiled (which also closes selection-cap.md q9 as a side effect), and a design that reuses the path instead of forking it.

**What is right and I want on the record:**
1. **`chunk = how many of these the sim will hold` is the correct generalisation** — 1 for buildings, 12 for units, byte-identical to today for units, and `shadowCount > simSlots` falling out of the same idea. That is a real simplification disguised as a feature, and it is the kind of change that ages well.
2. **NOT patching gate B because its prologue holds a short `JZ` and the hook engine copies bytes without relocation** is precisely the hazard-awareness this repo runs on — task 014 established that constraint and you applied it without being told. Routing it through the existing fan-out instead is the safe call.
3. Reusing task 020's liveness gate on the appended buildings, so a destroyed building never reaches the wire, is the right reuse.

**Three things to settle, and the third is a genuine question, not a nit:**

1. **Circles at >12 buildings.** Gate A relaxed lets up to 12 same-type buildings into the client selection, so the engine circles those; the plugin''s overflow circles handle 13+, same as units. CONFIRM that in the in-game test — box more than 12 same-type buildings and assert every one has a circle, not just the engine''s twelve. The building case has never exercised that path.
2. **All N rallied.** Your rally-point oracle (`CUnit+0xF8/+0xFA/+0xFC` from the `0x27` applier) is the right read. Assert it per building across a >simSlots group, so "the order reached all N" is proven from memory, not the picture — exactly as you planned.
3. **The mixed-BUILDING box — this is the scope question.** Your fallback appends same-id-same-owner as the LAST-rejected building. So a box over 4 Supply Depots + 3 Barracks (no units) selects one TYPE''s group, chosen by whichever sorted last. That is arbitrary from the user''s seat — same box, different result depending on sort order. The task scoped "same-type only, mixed stays stock", but a mixed-BUILDING box is a case neither of us pinned down. State what it does, assert it, and tell me: my lean is that a mixed-building box should select the type of the building the box is CENTRED on or the majority type, not sort-order-last — but only if the code makes that clean. If it does not, strictly-stock (one building, as vanilla) is an acceptable answer. Do not spend long on it; document the behaviour you have and flag it, and I will decide if it needs changing.

**Concurrency:** you are editing `ChunkBounds` / `StartFanout` / `EmitSelect`. Task 025 is in the production subsystem and SHOULD stay out of those, but if you see it touch them after a rebase, tell me before resolving — those three functions are load-bearing for every merged feature and a bad merge there regresses circles, HUD row, control groups and fan-out at once.

Carry on. Report before the PR if the mixed-building question turns out to need a design change; otherwise take it to review.
