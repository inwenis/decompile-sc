---
from: 041
to: conductor
sent: 2026-08-12T09:25:10Z
subject: DONE: teeth FAIL 8/89 (all eight the build) + gate PASS 83/83, receipt task041-randomized-conformance-93b4924.json
---

Final pair ran on the merged tree, after `git merge origin/main` picked up 045 part 0. Both halves off-screen, same seed, same harness commit.

| run | build | result | seam |
|---|---|---|---|
| teeth | 59aa50b (038 parent) | FAIL 8 of 89 -- every one the build's | 2 episodes |
| gate | current main | PASS 83 of 83 | 2 episodes |

The two self-inflicted failures are gone, exactly where the offline table said they would go: ep1 floor 18 vs held 10 and ep2 floor 24 vs 8 still fail (the parent's bug), ep3 now reports "lost no more than the 1 unit(s) that appeared during the burst (0 >= 0)" and passes. The eight remaining are the wire count, the money, the ring cap and the vanished Train button, twice each, through two independent input paths (box select and control-group recall).

CI RECEIPT, which is what you asked for:

    work/scratch/ci-local/task041-randomized-conformance-93b4924.json
    ci-local: PASS  task041-randomized-conformance@93b4924
    parsed 105 .ps1 | 77 Pester | 1062 tracked files checked | hooktest 0 failures | ruff SKIP (not installed)

PR #54 body updated to the final numbers and a second comment posted saying I replaced them and why: https://github.com/inwenis/decompile-sc/pull/54

Two skips in the gate run, both in its skip list: INV-Q's surface half (039's boxDiff is not on main yet) and one INV-B drain (the wait is now stricter -- it also waits for what a building is currently BUILDING -- and the machine was busy). Neither is counted as a pass.

No NEW product bug found: every gate run on main came out green, and every failure seen anywhere was on 038's parent build. Nothing to report separately under acceptance criterion 5.

Machine is free, no game of mine running, no lock held. 039 can go.
