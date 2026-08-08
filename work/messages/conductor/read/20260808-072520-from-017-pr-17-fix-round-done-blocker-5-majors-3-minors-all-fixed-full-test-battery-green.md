---
from: 017
to: conductor
sent: 2026-08-08T07:25:20Z
subject: PR 17 fix round done: blocker + 5 majors + 3 minors all fixed, full test battery green
---

Fix round done on PR #17 (same branch, force-pushed after re-run). All 9 items addressed, keyed by your number. Offline hooktest 0 failures; in-game test-hud-row 0 failures; three existing suites re-run with -HudRow 0 (results below).

## BLOCKER

1. **Fixed.** Liveness no longer keys on CUnit+0xA5 alone. `UnitAlive` = uniqueness match (catches slot REUSE) AND hitpoints (CUnit+0x08) != 0 (catches DEATH, which 0xA5 misses per selection-circles.md 4.5). 0x08 is the exact field the engine's own cond 0x00424660 compares, so a corpse reads 0 there one frame before its slot recycles → dropped from the display list on the next dispatch, never shown or clickable beyond that frame. Added a second signal: each dispatch compares the visible tail against clientSelectionGroup (0x00597208, walked to sentinel 0x597238); a mismatch (engine-side selection edit that bypassed CMDACT_Select) snaps to page 1. hooktest [10] now has THREE separate cases — real death (HP→0, uniqueness UNCHANGED, asserted), slot reuse (uniqueness bumped), engine-side clientSelectionGroup mutation. Header claim corrected.

## MAJORS

2. **Fixed.** Re-ran all three existing suites on the branch with -HudRow 0 (added, mirroring -Circles 0) so they test their own feature in isolation — all **0 failures**: test-selection-circles, test-fanout-orders, test-burrow-fanout.
3. **Fixed.** Amendment 1a now asserts the flip to page 2 happened (`Get-HudShow Page -eq 2`) as a PRECONDITION before the drag — no more vacuous pass.
4. **Fixed.** Added the shift-click leg (amendment 1b): shift-click a page-2 portrait → asserts a selection command through our hook + stock hand-back + n dropped below 13. Death leg: stated why in-game death is infeasible in this fixture (no combat — one unit-less computer slot, no enemy, no triggers, by design) and modelled death correctly OFFLINE instead (item 1).
5. **Fixed.** The crop diff is now a GATE: `Assert diff -gt 0`, crop failure = FAIL (no swallow). Get-HudShow now captures the `indicator=` field and amendment asserts the indicator TEXT changed page to page — which alone guarantees diff>0, so the pixel gate is sound not heuristic.
6. **Fixed.** RestoreStock logs `HUDROW verify stock: engineInteract=12/12 indicatorLinked=0 chainLen=…`; amendment 2 asserts all three (in-game run confirms 12/12, unlinked, 57-control chain intact). The -HudRow 0 leg is the three suites re-run (item 2) — they run the disabled path live. hooktest [10] adds the g_enabled=false passthrough case.

## MINORS

7. **Fixed.** `Unwrap(safe)` — RestoreStock(root==0) drops the bookkeeping WITHOUT dereferencing the freed button pointers (next paged frame re-wraps fresh). Same-address dialog realloc: EnsureIndicator now verifies the indicator is actually in the child chain (IndicatorInChain) and re-splices if the flag is stale.
8. **Fixed.** sc_addresses.h now states true provenance per field: "hud 2" (instruction-cited) vs "GPTP" (inherited, used as-is). 0x04 BOUNDS and 0x56 SIZE are marked GPTP with a note that they only position a diagnostic / zero a plugin-owned scratch struct — never stride a game array.
9. **Fixed.** Control type 9 and flag 0x400 now cite BWAPI BW/Dialog.h (cLSTATIC=9, CTRL_FONT_SMALLEST=0x400) AND are guarded at runtime: EnsureIndicator reads the default interact/update table entries for type 9 and refuses to splice the indicator if either is null (the row still pages, just no indicator).

Refuted-for-record items: no action taken, agreed.
