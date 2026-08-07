---
from: 011
to: conductor
sent: 2026-08-07T21:40:44Z
subject: PR #11 finalised - stage D result recorded, ready to merge
---

PR #11 is finalised: https://github.com/inwenis/decompile-sc/pull/11

Your four items, all done:

1. User result quoted verbatim in the PR body, in its own fenced block, under a
   "Stage D - the user's test" section that opens the description:
       run a - 12 moved
       run b - all moved
2. Map recorded as (1)Enslavers02b, a stock Blizzard Brood War campaign map,
   24 units in the drag box - with an explicit note that this is NOT the
   36-Marine test-many-units.scx fixture the task originally specified, why
   that one was dropped, and that task 013 has since fixed it.
3. A dedicated "What the test does not cover" section, before any of the
   success evidence: one map, one order-type pair (0x14/0x15), 24 units,
   single-player offline, one human run of each mode. Whole-selection orders
   (archon merge, unload-all, building morph) called out as unhandled AND
   untested - noting the box did contain an Archon and Observers, so the
   opportunity existed and was not taken.
4. No features added. Two docs-only commits.

Verified fresh, not carried over from earlier:

- SHA-256 of both StarCraft.exe re-hashed after the user's runs:
  AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46
  identical for C:\sc-install\Starcraft (pristine) and C:\sc-work\1161-base
  (working copy). Nothing patched on disk.
- No StarCraft process running.
- CI green on the head commit ca67856 (parse/lint/import + GitGuardian).
- Offline suite re-run on this branch: 50 checks, 0 failures.

Two honest corrections I made rather than left to be found:

- The description said "51/51 checks pass". The suite emits 50 ok lines. I
  counted it three times, corrected the PR body and the test plan, and said in
  the body that the earlier number was wrong. Commit ca67856.
- The test plan predicted 22 selectable units on that map from a static read;
  the live drag box took 24. Recorded in tools/plugin/fanout-test-plan.md as
  "the static count is a lower bound on what a box actually catches". The
  result never depended on the number - the plugin measures it - but the doc
  said 22 and would have read as a discrepancy against the 24 in the logs.
  Commit 4e96f16.

Commits pushed: 4e96f16, ca67856. Both docs-only; no code changed since the
user's test, so the binary they exercised is the binary the PR describes.

Not merging - yours to merge.
