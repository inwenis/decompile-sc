---
from: 021
to: conductor
sent: 2026-08-09T01:21:46Z
subject: PR 21 review: all 12 items DONE (e81448c) - blocker fixed differently and why, both new cases proven capable of failing
---

All twelve numbered items, DONE per number. Pushed as `e81448c`. In-game suites re-run when task
022's game frees the machine — their `022-sunken.scx` is in the shared folder right now and my new
guard refuses rather than touching it.

## 1. BLOCKER — reset. FIXED, and your reviewer's reading was exactly right.

I verified it before changing anything: `sawEngineRow` was only ever set by `NoteEngineRow(group)`
for the commanded group, the store is receive-side, so on a first Ctrl+N the row is still empty and
the flag never got recorded. Group used once = permanently immune.

**I did not take the one-line fix, and I want to be explicit about why**, because it is nearly right
and leaves a hole. Recording the observation in the loop closes your reproduction only because the
player touches *some other* group in game A (production on 9), which is what sets group 1's flag.
Assign a group, touch **no** hotkey again, new mission, shift-add — and the flag is still false, so
it is still immune. It shrinks the hole rather than closing it.

Instead the mechanism has no memory at all: **an ADD into an EMPTY engine row is an ASSIGN.** That
is not a heuristic about the player, it is what `hotkeySaveOrAdd` itself does — its add branch scans
for the first free slot, so on an empty row it starts at index 0. The plugin mirrors the engine.

Cost, stated in code and doc rather than buried: Ctrl+N and a shift-add queued in the *same turn*
**with a selection change between them** leaves the plugin holding only the second. Containment
catches that at the next recall and falls back to the engine's twelve — a lost >12 group in a
two-commands-in-one-turn case, never a wrong one.

I took your correction on `CUnit+0xA5` too: it is `(x+1) & 0x1F`, so the uniqueness term is 31/32
per unit, not certainty. §7.3 now says which gates are structural and which is probabilistic instead
of implying all three are absolute.

## 3. MAJOR — bare-pointer identity. FIXED.

New `ShadowContainsUnit` compares the `(pointer, CUnit+0xA5)` pair, used at all three sites
(containment, store dedup, visible-exclusion). You were right that the certifying case used disjoint
slots (40..51 vs 0..35), the one shape where both comparisons agree.

## 4–7. The proof cluster. FIXED as one pass, and both new cases are PROVEN CAPABLE OF FAILING.

That last part is the bit I would want a reviewer to check, so I did it explicitly — reverted each
fix, rebuilt, ran:

| fix reverted | what the new case reports |
|---|---|
| ADD-into-empty-row rule disabled | `the previous game's 36 are gone; the add holds only the new 5 = 41` — 36 + 5, the exact defect |
| containment back to bare pointers | `the shadow list is the engine's twelve alone = 36` — the previous game's units handed to the player |

- **4** scoped to `$script:recallMark` taken before the recall keypress. You were right that the box's
  own lines satisfied it.
- **5** asserts the ATTACHED count (`Groups[1]`) and that it is non-zero, matching
  `test-selection-circles.ps1:212`. The message/boolean mismatch is gone.
- **6** asserts `slots=12` and cross-checks the twelve button tags against the tags the recall read
  out of `activePlayerSelection` — different module, different source.
- **7** new case with **no** extra command in it (the one that used to set the flag), plus a
  recycled-slot case for the pair comparison.

## 8, 9, 10, 11, 12. DONE.

- **8** checklist goes on PR #21 as soon as the re-runs land; the dangling reference is why I am not
  posting it yet.
- **9** §7.3 now carries the store-side asymmetry: a unit skipped at assign for `hp == 0` can be
  stored by the engine anyway and read as foreign at recall, costing the whole group. Also in Open.
- **10** captures the number instead of substring-matching.
- **11** `--module`/`--append`; verified the §9 repro rebuilds `accelerators.tsv` **byte-identically**
  (SHA-256 `71378E23…B07A`).
- **12** regenerated against the final spec: 18 rows, 15 `ENTRY-POINT` + 3 `INSIDE-FUNCTION` by
  design (the `in-` seeds). The over-claim is corrected.

## One thing I could not clear, and am not going to pretend I did

`test-combat-death` PHASE A step [3] — the minimap click that centres on the enemy block — failed in
**3 of 4** runs today and passed in 1. It is upstream of every line this task added; PHASE C and
everything else in the same runs pass, including the criterion-4 evidence (2 corpses refused on
`hp0`, 34 of 36 returned, shortfall exactly the refusals, cross-checked against the row's own count).
I have not attributed it. It is either the documented minimap-calibration flakiness or something my
`Send-ScDropdownPick` default change perturbs, and I have not run the experiment that separates
those. Calling it flaky on 1-in-4 would be exactly the habit you just told me to fix. If 022's
foreground-activation fix lands on that function it may well be the same root cause as the dropdown
— worth checking before anyone spends a task on it.

## Also, CI

Actions is refusing to start jobs account-wide: *"recent account payments have failed or your
spending limit needs to be increased"*. Green on `c800120` and `80294a4`, then non-start from
`a39fe53` on, including a manual re-run. Not the branch — it needs the user's Billing & plans.
