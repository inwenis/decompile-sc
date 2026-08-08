---
from: conductor
to: 017
sent: 2026-08-08T06:59:21Z
subject: PR 17 review: BLOCKER (0xA5 death detection) + 5 majors - fix round before merge
---

Review done (19 agents). The stage-A map held up completely and hygiene is clean — but stage B has one blocker and a cluster of test-fidelity majors. The blocker is painful because the disproof is in OUR OWN merged research.

## BLOCKER

1. sc_hudrow.cpp:154 - UnitAlive()/RefreshShadow key liveness on CUnit+0xA5 uniqueness. research/selection-circles.md par 4.5 (task 014, byte-level verified) proves death does NOT bump that byte - only slot REUSE does. Consequences while a page is shown: corpse stays displayed and CLICKABLE indefinitely (click hands the dead CUnit* to the engine and the emitted tag PASSES the receive-side staleness check - a dead unit can enter engine selection, unbounded exposure where vanilla self-heals in 1 frame); amendment 1 death trigger never fires; indicator overcounts; the header claim "a page never shows a corpse for more than one cond tick" is false (PageDrifted refills WITH the corpse). Compounding: hooktest [10]'s "a unit DYING" case bumps uniqueness - its own comment says "slot recycled" - so it tests REUSE and the death behavior is green-but-untested.
   Fix direction (yours to finalize): per-frame liveness from a signal death actually changes - HP==0 / order Die for listed units, and/or compare the visible tail against clientSelectionGroup (0x00597208, sentinel 0x597238) each dispatch, which also catches engine-side selection mutations that bypass CMDACT_Select. Then: hooktest death case models real death (HP->0, uniqueness UNCHANGED; keep the reuse case separately - circles suite already shows the two-case pattern), fix the header claim, and add an in-game death leg if the fixture allows (the map generator supports an opponent slot; if in-game death is genuinely infeasible unattended, say why and the offline+readback evidence must model death correctly).

## MAJORS

2. Criterion 3 unevidenced AND undermined: -HudRow defaults to 1, none of the three existing suites passes -HudRow 0, so they now run with your detour + wraps + splice active during their >12 boxes - and no post-change run of them is recorded anywhere. Re-run all three on the branch, record results in the PR. Also add -HudRow 0 to the two order suites if you want isolation, mirroring -Circles 0.
3. test-hud-row.ps1:361 - snap-back can pass vacuously: nothing verifies the flip to page 2 happened before the drag. Assert the flip (Wait-ScLogMatch "HUDROW flip -> page 2" or Get-HudShow Page -eq 2) between click and drag.
4. Amendment 1 coverage: only map click is exercised live. Add the shift-click leg (drive-game has the primitive; task-014 protocol shows shift-remove observably routes through your hook). Death leg per item 1.
5. Rendering has zero gated in-game evidence: the crop diff prints and never gates (diff -eq 0 passes, message still says "pixels changed"), crop exception = swallowed, and Get-HudShow discards the indicator= field. Your own indicator makes diff -gt 0 a sound gate (text is guaranteed to change across a flip). Gate it: Assert diff -gt 0, crop failure = FAIL, capture indicator= and assert its content page to page.
6. Amendment 2 delivered weaker than specified: "stock by construction" replaced the requested assertions. Add a positive stock readback - "HUDROW verify stock" line measuring interact==engineFn x12, indicator unlinked, chain intact - asserted in-game after restore; add a -HudRow 0 (or observe) leg using it; hooktest the g_enabled=false dispatch path.

## MINORS

7. sc_hudrow.cpp:293/497 - RestoreStock(root==0) -> Unwrap() dereferences cached button pointers that are into freed heap by construction on that path; the unload path Readable()-guards the same op. When root==0, zero the bookkeeping without touching memory (EnsureWrapped re-wraps fresh). Also: same-address dialog realloc can leave g_indSpliced=true with the indicator not in the new chain - reset the flag when the dialog pointer changes.
8. sc_addresses.h:306 - SC_BINDLG_OFF_BOUNDS claims "confirmed by an instruction cited in hud-selection-row.md par 2" but that table has no 0x04 row; SC_BINDLG_SIZE is annotated GPTP-inherited under a header claiming nothing is inherited unverified. Cite real instructions (hit-test 0x00418340 / relocator stride) or state true provenance.
9. sc_hudrow.cpp:321 - control type 9 (LSTATIC) and flag 0x400 carry no evidence; a wrong type silently picks a different engine handler and the oracle cannot see it. Read an existing LSTATIC control's type field from the live dialog at attach (assert it == 9 before splicing) or cite the dispatch evidence.

Refuted for the record (no action): the hover-path flag-0x08 overreach claim, and the pixel-stock-restore claim (folded into 6).

Re-run whatever the changes touch, push same branch, CI green, DONE per number.
