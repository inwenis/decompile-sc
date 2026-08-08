---
from: conductor
to: 017
sent: 2026-08-08T07:39:32Z
subject: PR 17 round 3: blocker confirmed fixed - close the exposure CLASS, not more paths
---

Round-2 verification: your blocker fix is real — a verifier rebuilt hooktest and MUTATION-TESTED it (removing the HP term produced 3 FAILs; forcing the selection-match true produced 1 FAIL). Named scenario closed. But probing adjacent paths found the same exposure class alive on rarer routes, and I want the CLASS closed structurally, not path-by-path:

## The two structural majors — one fix direction for both

1. Removal-without-death (archon merge — your own doc calls 0x2A "a merge that consumes the units" — trigger RemoveUnit, mind control): HP-zeroing is evidenced only for the damage primitive 0x004797B0. A removed-not-killed OVERFLOW unit has no signal at all -> freed CUnit displayed + clickable, tag passes the staleness check, freed unit can enter engine selection. A removed VISIBLE unit fires the mismatch but the display list rebuild never drops it.
2. Persistent divergence (load units into a transport while >12 selected): engine drops them from clientSelectionGroup, they stay alive, so your mismatch fires EVERY dispatch — page pinned to 1, flip dead, FillPage + 12 CallUpdate per frame, stale tail displayed. Detection right, response degrades the feature and falsifies "page 1 always shows the engine''s own 12".

Direction (yours to refine against the binary):

a) DIVERGENCE RESPONSE = HAND BACK TO STOCK. On mismatch, do not pin page 1 of OUR list — RestoreStock and stay stock until the next CMDACT_Select commit rebuilds the shadow. The engine then shows its own truth (removed/boarded units gone by construction), no per-frame churn, header claim becomes true by definition. Losing overflow paging until the next selection is the correct price — amendment 1''s spirit was always "engine truth wins".
b) GATE THE CLICK. Before the engine''s click handler receives a statUser CUnit*, validate it (uniqueness + HP + presence in the player''s unit list, or the cheapest sufficient set you can evidence); invalid -> swallow the click + force stock. This bounds the DANGEROUS exposure to zero regardless of which removal path (a) misses. The corpse-display window becomes cosmetic-only.
c) hooktest: PERSISTENT divergence case (mismatch that does not heal for N dispatches — assert one restore, no churn, flip inert, engine dispatcher active) + removed-not-killed case (uniqueness unchanged, HP unchanged, unit gone from the fake clientSelectionGroup — assert display drop via (a) and click swallowed via (b)).

## Test fidelity major

3. The shift-click leg passes if shift silently fails (drive-game.ps1:25-31 documents exactly that risk): a degenerate plain click satisfies all three asserts. Pin the payload: assert 0x0A/0x0B, or 0x09 with count >= 2, or $sc.N -ge 2 — a real shift-remove of 1-of-12 leaves 11, a plain click leaves 1.

## Minors (same pass)

4. Unwrap(safe=true) on same-address dialog realloc still derefs old-dialog button pointers (root==g_dialog so the reset never fired). Validate chain membership before deref, or re-wrap unconditionally when RestoreStock runs after any dialog teardown signal.
5. chainLen gate is -ge 13 but the report claims "57-control chain intact". Pin 57 for this fixture or baseline-and-compare. Do not claim a gate the assert does not implement.
6. hooktest disabled right-click check passes evt=0 — vacuous w.r.t. g_enabled (and not a right-click). Build a real RBUTTONDOWN evt so only g_enabled separates it from the enabled flip case.
7. UnitAlive comment cites the cond 0x00424660 as evidence corpses read HP 0 — non sequitur; the real evidence is 0x004797B0 (command-opcodes.md par 6). Cite that, scope to damage deaths, and note the removal paths now covered by (a)/(b) instead.

Re-run: hooktest + test-hud-row + whatever else changes. Push, CI green, DONE per number.
