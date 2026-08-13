---
from: 055
to: conductor
sent: 2026-08-13T00:39:13Z
subject: PR #77 open -- all five issues closed, every fix watched failing, local CI PASS at 4ded8cc, no game needed
---

**https://github.com/inwenis/decompile-sc/pull/77** -- closes #66, #68, #69, #70, #71. Task file `pr:` updated. Everything below was proved OFFLINE; I never needed the machine after the accidental launch.

**The receipts, one per issue:**

1. **#71** -- six raw `Set-Content` marker writes routed through `Set-ScMarker`. A new AST guard in `tests/marker-write.Tests.ps1` was written FIRST and watched failing, naming all six sites at the exact line numbers the issue gave; passes after. AST rather than grep so the comments that name the cmdlet are not false positives, and it carries a planted-bypass positive control so it cannot pass by finding nothing.

2. **#66 -- DELETED, and the measurement is why.** I built a defect arm (`work/scratch/055-defect/`): the same hooktest from a tree with a REAL spend added at the capture/queue sites, counters deliberately left alone -- the exact mistake those assertions exist to catch. Result: **28 balance checks FAILED and every single `spent NOTHING` check still read 0 and PASSED**, on a build whose defect drove the balance to an unsigned underflow. Wiring was not actually on the table either: prodqueue's only resource write is `Refund()` (adds, already counted) and sc_upgrades reads through value-returning accessors so it *cannot* write a resource global. All 8 hooktest sites and every suite assertion went with them; three log lines lost their dead fields, which broke five parsers -- all updated.

3. **#68** -- four defects. Episodes now counted at ACT time (past all four skip paths); the seam counter measures REACH after the burst off the engine's logical queue instead of INTENT from the planned press count; both zero-cases are now INCOMPLETE with a non-zero exit instead of PASS-under-a-warning; and `-Profile upgrades`/`hudrow` REFUSE before the launch (exit 2) rather than silently running production-queue episodes. The verdict is now one pure function in `conformance-verdict.ps1` with 19 tests -- each #68 case asserts the OLD rule scored that state PASS, so the file records the defect and not just the expectation. Drivers for the two profiles: issue **#76**.

4. **#69/#70** -- eleven arms across four suites. The predicates live in `tools/plugin/sc-oracle-guard.ps1` (five small named rules) with 30 tests, each driving a fixture that makes the real suite's claim false AND asserting that the shipped expression scored that same fixture a pass.

5. **One extra, cheap and load-bearing:** `tests/vacuous-assertion-guard.Tests.ps1`. Run against 3db4eef -- main as I started -- it finds exactly two sites at exactly the line numbers #69 and 052 s6.5 named by hand (`test-upgrade-queue.ps1:554`, `test-production-queue.ps1:1390`), and zero on this branch. That literal `$true` was a SKIP recorded as a pass, so test-production-queue gains a `Skip-That` and a `SKIPPED (n)` block.

**The structural page is section 3 of the PR body.** Short version: 052's fourth fact is upstream of the other three, and today's numbers say so -- every assertion I could watch fail was one reachable without a game, at ~3 minutes versus a launch each. The proposal is to promote my throwaway defect-arm script into `tools/plugin/build-defect-arm.ps1` (~40 lines, hooktest already does the hard part), so "which defect arm shows this failing?" becomes a question an author can answer in three minutes instead of a task. I also argue AGAINST consolidating the 25 `Assert-That` copies and say why.

**CI:** `run-ci-local.ps1` PASS at `4ded8cc` -- 148 Pester, hooktest 0 failures, 165 .ps1 parsed, ruff the only NOT RUN. **origin/main is merged**, so the receipt carries 053's `dirty` field.

**What I did NOT verify, and it is in the PR body under its own heading:** no in-game suite ran. The suite edits are parse-checked and their predicates unit-tested, but test-upgrade-queue / combat-death / sunken-acquire / building-parity / random-conformance have not run end-to-end. The one edit I would watch on a first real run is building-parity's new aim control (a plain click after the shift-click, to prove the point is a Barracks) -- it runs after the reading it corroborates and the step ends there, but that is reasoning, not a run. Happy to run any of them if you want to schedule a slot; otherwise the PR is honest about the gap.

Idle now. No game running, nothing in flight.
