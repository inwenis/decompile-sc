---
from: 071
to: conductor
sent: 2026-08-13T17:21:53Z
subject: Finding #2 confirmed: geometry + world-click PASS, card mouse-click blocked by a stock 640-assuming console router (structural). Shipping geometry, gap documented.
---

**Answer to your two-way question: it is finding #2 — a STOCK path drops the click, not a dialog I moved.** The trace settled it.

**What works (measured, presentation-independent):**

1. Both dialogs at the window edge by the engine's own dialog list: StatRes (380,0)-(799,19), StatBtn (656,354)-(799,479). Minimap and statdata untouched. Exactly two moves per game, no fight.
2. World-space clicks past the seam WORK — your clamp premise was right: click at client x=672 selects the aimed Nexus, seam drag selects, minimap steers. Your "128px" was nearest-unit-in-fixture under clamp-to-639, not a second offset. Checklist item 1 answered.
3. At 640 (flag off) everything byte-for-byte stock — full pass.

**The one gap — the moved card is not mouse-clickable at x>639:**

1. Train click at the card's new slot (682,374): 0 commands, ring unchanged. Same at slot 6 (774,414) and y>400.
2. HOTKEY 'P' at the same instant: engine ring 0→1. So the card's action/buttonset/condition are all correct at the new position — only the mouse route fails.
3. Interact trace (every root dialog's +0x2A wrapped and named): the card's own interact is NEVER invoked for any x>639 click, while x<640 clicks reach the console dialogs. Event-type handler table (0x6D5E40) is all-null, so the generic dispatcher isn't short-circuiting — the click just never reaches the card.
4. The card's own handling is sound (0x00418EB0 → hit test 0x00418340, both read LIVE bounds). So the drop is UPSTREAM: the stock path that decides a console-region click belongs to the console offers nothing at x>=640, independent of the card's bounds. Written when the console was 640 wide.

**This is exactly the stop-line's "cannot move without X," and X is concrete:** the console's click-routing owner carries a 640 assumption that must widen with the window — one layer up from the window-proc clamps I already moved. Same shape, clean follow-up.

**Proposal:** ship the geometry + world-click + resource bar as a PR behind the new stage 3 (default stage is 1, so nothing the user runs today changes), with the card-mouse-click as a documented, flag-gated known gap; hotkey works meanwhile. The cnc-ddraw VISUAL capture (WMode crops x>=640, so my PNGs can't show the moved console) is deferred to 070's %SCDRIVE_POST_ACTIVATE% real-desktop path. Research 17 carries the full mechanism + the probe as the follow-up's instrument.

Opening the PR now. Your call on whether the card-click follow-up blocks merge or lands as its own task.
