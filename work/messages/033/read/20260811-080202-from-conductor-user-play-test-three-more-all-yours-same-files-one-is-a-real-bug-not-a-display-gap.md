---
from: conductor
to: 033
sent: 2026-08-11T08:02:02Z
subject: USER PLAY-TEST: three more, all yours (same files). One is a real bug, not a display gap
---

The user played the deployed build and reported six defects. Three are yours because they live in the status pane / `sc_hudrow.cpp`, which you already own for this PR. I am giving you all three so one worker owns that file. The other three are going to a separate task (building selection input).

**PRIORITY ORDER — do 1 first, it is a correctness bug and the other two are display.**

1. **The HUD row goes STALE when units die.** User: "when i have more than 12 units selected and some die - the group display in tug doesn`t get updated (i might have 30 units selected but the group shows 6 cuz 6 of the ones from tug died)". So the row keeps showing a page whose units are dead instead of re-flowing the live ones. `sc_hudrow.cpp` already has divergence detection that snaps back to page 1 (around lines 269, 295, 321-330) — either it is not firing on death, or it fires and the page is rebuilt from a stale list. This is the worst of the six: the player is looking at a display that is actively lying about what they have selected, mid-fight, which is exactly when they need it. Note the liveness machinery already exists — `-Liveness 1`, `research/fanout-liveness.md`, and the HP!=0 + player-unit-list checks that replaced the 0xA5 myth. Reuse it; do not invent a new death test.

2. **The 5th production slot is always empty.** User: "when i queue more then 5 units the 5`th slot is emtpy". That is `SC_PRODQ_ENGINE_HOLD = 4` showing through — task 025 keeps the engine ring at four so the client keeps sending, and the strip therefore never draws a fifth icon. The FEATURE is correct; the display is not, and it looks broken to the player. Fix it on the DISPLAY side by drawing the fifth (and the `+N`) from the plugin`s own queue — do NOT raise ENGINE_HOLD to 5, that is the very thing that made the client stop sending and it would silently break the whole feature. Read `research/production-queue.md` on why 4 before you touch anything.

3. **Queued upgrades are invisible and the card is confusing.** User: "queueing upgrades is confusing cuz they don`t dissapear from the shop window and there is no queue insidcating the queu". Two halves: (a) there is no indication of what is queued — your `+N` work should extend to the upgrade queue (`sc_upgrades.cpp` holds the list, task 029), and (b) the buttons staying lit is task 029`s unblock working as designed, so the player cannot tell what they have already queued. At minimum show the queue. If you can also mark an already-queued upgrade, say what that costs; do not redesign the card.

So your PR now covers: `+N` on the production strip, `page i/j` on the unit row, the empty 5th slot, the upgrade-queue indicator, and the stale-row-on-death fix. If that is too much for one PR, SPLIT IT: land the stale-row fix first on its own, because it is the only correctness bug in the set. Tell me if you want to do that.

Everything else from your task file stands: cheapest thing that works, engine`s own text routine, nothing drawn when off, assert from memory not from frames.
