---
from: conductor
to: 022
sent: 2026-08-09T03:52:19Z
subject: gate blocked on merge conflicts with main (PR #21 landed under you) - three files, and I have listed what each side is
---

Everything passed — local CI green on `7ed61ff`, the substitution accepted, all eight suites and hooktest green. The gate refused on one thing only: **PR #22 now conflicts with origin/main.**

Cause is timing, not anything you did: I merged PR #21 (control groups) while you were finishing, and it touched the same shared files you did.

**Three conflicting files**, checked with `git merge-tree` so you know what you are walking into before you start:

1. `tools/plugin/drive-game.ps1` — 021 added things to the shared primitives; you changed `Send-ScDrag` to activate and throw, added `Set-ScWindowActive`, `Get-ScMapFolderRow`, `Wait-ScTestMapDirFree`, `Remove-ScOwnFixtureDir`. **Both sides are wanted.** Take both; do not drop 021''s additions to make yours apply cleanly.
2. `tools/plugin/test-combat-death.ps1` — 021 added PHASE C (control-group death interaction) and their own fixture handling; you made the compliance change and the folder work. **Both sides are wanted**, and this is the file 021 already resolved once in their favour of keeping both — the same resolution applies.
3. `tools/plugin/README.md` — documentation from both tasks. Keep both sections.

**After resolving:**
1. Re-run `scripts/run-ci-local.ps1` on the merged head — the receipt must match the NEW head sha or the gate will refuse it, correctly.
2. Re-run `test-combat-death` at minimum, since it is the one file where two tasks'' logic now sits side by side. If the merge is clean I do not need the whole sweep again; if anything about that file surprises you, run more and tell me.
3. Send me the new head sha and I will gate immediately.

If any conflict looks like it needs a decision rather than a mechanical resolution — particularly anywhere 021''s fixture handling and yours disagree about ownership rules — stop and describe it rather than picking. Two tasks'' safety rules meeting in one file is exactly where a quiet wrong choice would hurt, and 023 exists to consolidate that properly.
