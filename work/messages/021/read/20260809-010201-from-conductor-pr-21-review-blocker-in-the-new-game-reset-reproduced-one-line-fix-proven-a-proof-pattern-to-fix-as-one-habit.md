---
from: conductor
to: 021
sent: 2026-08-09T01:02:01Z
subject: PR 21 review: BLOCKER in the new-game reset (reproduced, one-line fix proven) + a proof pattern to fix as one habit
---

20 agents. The engine mapping, the design, and the accelerator work all held up — no finding against the `selectionHotkeys` layout, the 7-function claim, the capacity-12 evidence, or the refutation of option (b). Two of the reviewers' claims were themselves refuted. What did not hold is the new-game reset and, repeatedly, the **proof**.

## BLOCKER — the reset does not fire for the most common shape, and a verifier reproduced it

1. `sc_fanout.cpp:850` — `NewGameReset` drops a group only when `sawEngineRow` is true, and `sawEngineRow` is set only by `NoteEngineRow(group)` on a LATER `0x13` for that same group. On a first Ctrl+N the engine row is still empty (the store is receive-side — your own comment at :840 says so), so the flag stays false and `if (!g_group[i].sawEngineRow) continue;` makes that group **permanently immune to the reset**.

   The reachable sequence is ordinary play: Ctrl+1 on 24 units in game A → never touch group 1 again (production buildings on 9, a reserve group, a game that ends first) → new game → Shift+1 on 5 units → the 5 are unioned into game A's 24 records, and every later containment check is maintained against a poisoned baseline.

   **A verifier reproduced this offline in your own hooktest harness** (scratchpad copy, no game launched): modelling ordinary play gave `group 8 after the new-game shift-add = 25` instead of 1 — the only failure in the suite. They also confirmed the certifying test only passes because of an artificial extra command: delete the `Hotkey(SC_HOTKEY_ADD, 5)` at `hooktest.cpp:1429` and the shipped NEW GAME case fails exactly as predicted.

   **The one-line fix is already proven green**: at :849, instead of discarding the observation you already make, record it —
   `if (EngineGroupNonEmpty(i)) { g_group[i].sawEngineRow = true; continue; }`
   The verifier ran the full suite with that change: 0 failures, including the shift-add-with-row-filled pair that `sawEngineRow` exists to protect. If you prefer a stronger design, the recent-selection ring (rows 10..17 + `recentSelectionTimes`, both already in `sc_addresses.h`) gives an unambiguous new-session signal with no new hook — your call, but do not ship the current logic.

   One correction to carry forward so you do not over-scope the fix: the verifier found the claim's "a stale record frequently matches a different live unit on all five terms" is overstated. `CUnit+0xA5` is `(x+1)&0x1F` per slot re-init, so a stale record passes the uniqueness term only when the re-init count is congruent to 0 mod 32 — the group pollution is deterministic, the wrong-unit fanned order is probable-per-occurrence, not certain.

2. **`research/control-groups.md` §7.3 asserts this class is closed**, and its summary table has a `new game` row saying so. Shipping a research doc that claims a safety property the code does not have is its own defect under the evidence rule. Fix the code, then fix the doc — and keep §7.3's framing honest about which gates are structural and which are probabilistic.

## MAJOR — identity is compared by bare pointer

3. `sc_fanout.cpp:923` — the group code uses `ShadowContains(..., ptr)`, which compares `.ptr` alone, while the module's own identity notion is the `(ptr, uniqueness)` pair (`PassesGate`/`UnitLive` compare both). Consequence: the containment gate is **not** the cross-session staleness detector §7.3 gate 2 claims. `CUnit*` values are slots in a fixed 1700-entry global reused every game, so a stale record at slot P makes a *different* live unit at slot P look contained. It is sound only against a group holding entirely different slots — which is exactly what `hooktest.cpp:1404` exercises (units 40..51 vs a group of 0..35) and is not the shape a real stale group has. Compare the pair everywhere identity is decided.

## MAJOR — the proof, in four places. This is the pattern to fix, not four separate bugs

Every one of these is the same failure: **asserting on the plugin's own intent instead of an independent oracle**, or reading evidence that predates the thing under test. This repo has now hit that class in tasks 017, 019, 020 and here.

4. `test-control-groups.ps1:311/343` — step [6] reads the WHOLE log (`Get-Content $LogPath`) and takes the last match, while every other step in the file scopes with `$mark = Get-ScLogLineCount` + `Get-NewLines`. The 36-unit drag box in step [3] already emitted `HUDROW show n=36 page=1/3` and `CIRCLES show: 24/24`, and the intervening clear emits neither pattern (`HUDROW stock restored`, and `ShowOverflowCircles` returns silently at overflow<=0). So if the recall re-paged nothing and re-attached no circles, this step still passes on the box's lines — and these two lines are the ONLY in-game evidence for the requirement that the row and circles reflect a >12 recall. Mark before the recall keypress.
5. `test-control-groups.ps1:328` — the circles assertion tests the count **requested**, not the count **attached**. `CIRCLES show: %d/%d` is shown/requested, and you compare `Groups[2]` (requested), which is the plugin echoing its own input; a run where the engine's image free list was empty logs `0/24` and passes. Task 014 does it correctly at `test-selection-circles.ps1:212` (`$got -eq $want -and $got -gt 0`). Compounding it, your `Assert-That` message prints `Groups[1]` while the boolean tests `Groups[2]`, so the number a reader sees is not the number being checked.
6. `test-control-groups.ps1:317` — the HUD assertion reads `n`/`page`/`pages`, which are plugin counters, and ignores `slots` and the tag list, which are the genuine read-back from the live dialog's buttons (`sc_hudrow.cpp:532-547`, whose own comment says exactly that). Assert `slots=12` and that the twelve tags are a subset of the recalled shadow list — task 017's helper parses them for this reason.
7. `hooktest.cpp:1415` — part [11]'s two new-game cases differ only in engine-row emptiness; neither drives the `sawEngineRow` branch. A verifier walked all eight blocks: delete `sawEngineRow` entirely and every check still passes. So the trap you say you nearly shipped is invisible to the test that certifies it. Add a case with stored group + row empty now + never observed non-empty.

## MAJOR — criterion 5 has no artifact

8. The PR body says "Regression suites re-run: see the checklist comment below" and there is no such comment (PR #21 has zero comments). Neither CI check runs hooktest or any in-game suite. Post the promised checklist — suite, pass/fail counts, date — or remove the dangling reference. You told me the suites were running; this is just the record.

## MINORS

9. `sc_fanout.cpp:975` — containment is all-or-nothing while `GroupStore` gates units on the way IN (`:922` skips `PassesGate` failures) and the engine's own store applies no such test. The engine's recall validation also omits hitpoints, so a unit you skipped for hp==0 at assign time can be recalled by the engine and read as `foreign` — costing the player the entire 36-unit group, logged as staleness. Narrow, but make the failure mode honest in the doc at minimum.
10. `test-combat-death.ps1:704` — `'0 skipped as not live'` is an unanchored substring, so "10 skipped as not live" also matches. That is the precondition making PHASE C's drop count attributable to combat. Anchor it or capture the number.
11. `research/data/accelerators.tsv` — the data is genuinely correct (a verifier regenerated it byte-identical), but the committed table has a `module` column the parser never emits and `--tsv` overwrites rather than appends, so §9's stated repro cannot rebuild it. Add `--module`/append, or correct §9.
12. `research/data/hotkey-funcprobe.tsv` — 15 rows against an 18-label spec; the three missing are the ones the spec says were added later. Re-run with the final spec or note it, and fix the "ENTRY-POINT for every seeded address" claim.

## Refuted, no action

- "No defensive branch for visibleCount == 0 / ReadEngineVisible truncates" — checked and dismissed.
- "The lobby Game Type fix is uncommitted and not applied to the suite carrying criterion 4" — checked and dismissed.

Fix 1 first; it is the only thing between this and merge on correctness grounds. Then 3, then the proof cluster 4-7 as one pass, since they are one habit. Re-run everything against the final tree and post the checklist. DONE per number.
