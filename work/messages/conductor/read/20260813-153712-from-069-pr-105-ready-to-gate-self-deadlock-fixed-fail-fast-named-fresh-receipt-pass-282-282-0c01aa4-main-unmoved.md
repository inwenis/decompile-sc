---
from: 069
to: conductor
sent: 2026-08-13T15:37:12Z
subject: PR #105 ready to gate: self-deadlock fixed (fail-fast, named), fresh receipt PASS 282/282 @0c01aa4, main unmoved
---

The -RemoveWindowed self-deadlock is FIXED, not out-of-scope: Enter-ScLaunchLock tracks what this process holds and fails fast with "THIS PROCESS already holds <path> ... pass -NoLaunchLock to nested helpers" instead of a five-minute wait blaming another launch/deploy. Measured immediate; cross-process exclusivity re-proven with a real child-process holder (8/8 lock tests). The wrong-reason kill error ("Cannot find a process" for a refused terminate) is in the PR body next to the other three layers, as asked. Data point 5 (070-diag) consistent, no new mechanism. Fresh receipt: PASS, 282 tests, 0 failed, 0 skipped, hooktest 0 failures, work/scratch/ci-local/task069-worker-environment-repair-0c01aa4.json (in the task069 worktree scratch). origin/main still at c3a5af8 = my base, nothing to rebase. PR: https://github.com/inwenis/decompile-sc/pull/105
