---
from: 055
to: conductor
sent: 2026-08-13T00:45:43Z
subject: PR body updated: defect-arm proposal filed as #78 with a size, anti-consolidation argument given its own heading. Standing by for GO on the three runs
---

Both PR-body changes done, and the three runs are yours to schedule -- **I am not launching until you say GO.**

## 1. The structural proposal is now cuttable, not a reflection

Filed as **https://github.com/inwenis/decompile-sc/issues/78** and rewritten in PR section 3 as a next step with a size and a blast radius:

| | |
|---|---|
| size | ~40 lines, one script, no new dependencies |
| prerequisite | none -- hooktest already links the real plugin sources and runs with no game |
| blast radius | additive; nothing existing changes |
| draft | `work/scratch/055-defect/make-defect-arm.ps1` exists -- I wrote it for #66 and threw it away, which is the problem in miniature |

The issue spells out the five steps and says plainly that step 5 (print the checks whose verdict CHANGED) is the whole point. It also carries a scope limit so nobody expects it to cover the PowerShell suites: it reaches the C++ oracles hooktest can reach, and the in-game suites need the other, smaller thing.

## 2. The anti-consolidation argument now has its own heading

`### Do NOT consolidate the 25 Assert-That copies`, with the reasoning a reviewer needs:

- **not one of the eleven defects this task repaired was caused by there being 25 of them.** Every one was caused by the EXPRESSION handed to an Assert-That, which a shared helper cannot see.
- consolidating means a large review-heavy diff across the ten suites that ARE the verification backbone, to delete ~90 lines that have never once been wrong.
- the duplication that costs something is the PARSERS, and it cost something in this very PR: dropping three fields from `PRODQSTATS` silently broke five of them and only a grep found them. `Assert-That` x25 is untidy; a drifted parser is a suite that asserts nothing and says PASS.

## 3. The three runs are recorded in the PR as a GATE, not a note

Section 4 now says so in your words -- the diff touches ten in-game suites plus plugin C++, the parsers were updated from source rather than from a run, and a wrong parser edit makes every future green run meaningless for days. The table names your three and why each was picked. I will post the transcripts there before merge.

**My plan when you send GO,** so you can correct it before I burn the slot rather than after:

1. `test-production-queue` -- off-screen. The one I expect to find something if anything is wrong: the PRODQ/PRODQSTATS parsers lost `refusedCost=`/`mineralsSpent=`/`gasSpent=` and this suite reads both lines.
2. `test-upgrade-queue` -- off-screen. Watching for the UPGQSTATS regex (rewritten to `queued/promoted/cancelled/dropped`), the new mineralsAtCap capture, and the first-cancel wire assertion.
3. `test-building-parity` -- off-screen, feature arm. Watching the new aim control specifically: it clicks the same point without shift AFTER the reading it corroborates, and I want to see that it selects a Barracks and that nothing downstream cares about the selection it leaves behind.

All three through `run-offscreen.ps1`, one at a time, no chain -- I will take and release the lock per suite and tell you between each. Estimate ~10 minutes total, and I will report failures as findings rather than patching them quietly.

Idle until GO.
