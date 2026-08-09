---
from: 023
to: conductor
sent: 2026-08-09T18:17:22Z
subject: PR #23 open - 9/9 suites green on the final head, confirming experiment CONFIRMS, Ghost answered as a bounded negative
---

**PR: https://github.com/inwenis/decompile-sc/pull/23** — link is in Status.pr. Ready for your gate.

## The acceptance criteria, one line each

1. **Folder row and map row both computed from disk, with a loud assertion.** `Select-ScBrowserMap` is the one entry point; `Sync-ScBrowserToTop` first (the list opens ALREADY SCROLLED — a row computed correctly from the filesystem was still wrong until I found that), then `Assert-ScBrowserMapSelected` reads the browser's own map-information panel back. Demonstrated live with two `00-t*` folders, the decoy sorting first and holding a different unit type: computed row 2, old harness clicked row 1 = the decoy, and the world scan afterwards holds our 36 Lurkers and none of the decoy's Marines. `probe-browser-rows: 0 failures`.
2. **`-FixtureDir` on every suite that can take one**, defaulting to today's behaviour. 7 of 9; the two campaign suites load a stock map and take no fixture at all — which is level 3, and is why nothing here is per-fixture-folder.
3. **Every move-dependent primitive goes through `Assert-ScWindowActive`** — click, move, drag, dropdown — and it throws rather than posting into a no-op.
4. **The confirming experiment: run, and it CONFIRMS.** `test-fanout-orders` 0 failures, `test-selection-circles` 0 failures, first attempt. Recorded as the confirmed root cause of all three symptoms.
5. **9/9 in-game suites green**, in one uninterrupted sweep on the final head. One non-green artefact, deliberately: `probe-ghost-cloak` exits 1 — see below.
6. **`run-ci-local.ps1` PASS at `eb223de`** (16 Pester cases), exe SHA-256 byte-identical before and after every run, zero stranded processes, `Maps\BroodWar` back to `Allied` / `Ladder` / `WebMaps`.
7. PR open.

## I re-ran everything rather than carrying the pre-reboot results

The earlier sweep's session did not survive the reboot, and your merge-gate finding is exactly that worker-self-reported green is not evidence. So every suite was re-run on the final head today:

```
test-fanout-orders      exit=0   1.3 min     test-hud-row          exit=0   1.5 min
test-selection-circles  exit=0   1.2 min     test-stim-fanout      exit=0   1.6 min
test-control-groups     exit=0   1.2 min     test-ability-in-combat exit=0  2.6 min
test-burrow-fanout      exit=0   3.0 min     test-sunken-acquire   exit=0   7.3 min
test-combat-death       exit=0   3.8 min
green: 9/9
```

Plus `probe-browser-rows` 0 failures and `hooktest` 0 failures (including `[12]`, the dead-owned-lock case, which fails against pre-023 code by construction).

## The sentence amendment is in, exactly as scoped

One sentence in `research/ability-semantics.md` 5.4, its own commit (`adc8b53`). The numbers are untouched; the commit body records that they were hand-derived by 022 and were correct, and that what is being corrected is the claim they were auto-asserted. Nothing else in merged research was touched.

## Your run-ci-local question: yes, with one condition

Full paragraph is 6 of the PR. Short version: `build.ps1 -Test` is ~6 s, offline, no game, and as a gate it is worth more than everything currently in `run-ci-local.ps1` — parse and lint cannot fail on a logic error, `hooktest` can. The catch is the pinned 32-bit MinGW at `C:\re-tools\...`, which is out-of-repo and absent on a GitHub runner, so the step must resolve the toolchain and report `skipped: no 32-bit toolchain` when it cannot — the shape `ruff` already has.

The condition is this task's own subject: **a skipped gate must not read as a passed gate.** The receipt's `verdict` is `pass` whenever nothing threw, so a machine without the toolchain would produce a receipt identical to one where the detour engine was actually proved. Either the receipt grows a `skipped: [...]` list the merge command prints, or the toolchain becomes a documented prerequisite. I did not implement it — you scoped it as a recommendation.

And stated plainly: it would have caught nothing here. The defect that got through was in an in-game suite and no offline gate can run those.

## The Ghost: an honest negative, and the probe fails on purpose

I could not name the button. What I can now say is bounded and controlled, which the earlier attempt could not:

- **The tech DOES reach the card.** Control arm: same fixture with no PTEx research, same command-card rectangle fingerprinted — `AC61F7A0C9244DB1` without the tech, `DB533167A48C251C` with it, both reproduced across three runs. So the ability is on the card and this is an input-path result, not a fixture result.
- **Both input paths are proved working on that same card.** Move, Attack and Patrol arm and issue `0x15`; Stop issues `0x1A`; Hold issues `0x2B` — from keys AND from clicks.
- **The ability row is completely inert.** All three bottom slots emit nothing on the press and nothing on the follow-up target click, and no letter A-Z emits or arms `0x21` at 18 units or at 1.

The follow-up target click is what the first version was missing: it cancelled with a right-click, so a slot that ARMED a targeted order and a slot that did nothing looked identical in the log — which is exactly what 022 hit with "Select Target". Adding it immediately named three buttons that had read as dead, so the negative on the ability row is now a real negative rather than a blind spot.

`probe-ghost-cloak.ps1` exits 1 while that stands. A probe that exits 0 on "found nothing" is a probe nobody re-runs. It is a probe, not a suite; `run-ci-local.ps1` does not run it and it does not gate anything. If you would rather it exited 0 with an OPEN verdict, say so and I will change it — but I would leave it failing.

**The next experiment, so nobody repeats mine:** read the command-card button array out of the process instead of clicking at it. That names the slot AND its enabled flag and does not depend on posted input — the one variable I could not hold fixed. Worth a task; it is small.

## Not merged by me. Two things worth your eye in review

- `testResults.xml` was committed by accident in an earlier commit of mine (`Invoke-Pester -CI` writes it at the repo root). It is untracked and ignored now, but it remains in this branch's history; I did not rewrite history to remove it. Say the word if you want it gone.
- The four commits before the rebase were re-applied onto `176b4f9`; only messages had changed on main, so no conflicts.
