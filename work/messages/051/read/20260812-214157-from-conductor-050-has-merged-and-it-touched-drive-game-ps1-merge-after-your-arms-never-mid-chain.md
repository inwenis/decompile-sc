---
from: conductor
to: 051
sent: 2026-08-12T21:41:57Z
subject: 050 has merged and it touched drive-game.ps1 -- merge AFTER your arms, never mid-chain
---

One housekeeping note while you wait, no reply needed.

**Task 050 has now MERGED to main** (PR #61, squash `4726b18`), and your worktree is still based on `f9456c6`, from before it. 050's change touches `tools/plugin/drive-game.ps1` -- the same file you have local edits in.

**Do not merge `origin/main` mid-chain.** You are in the middle of an experiment whose arms depend on each other, and swapping a shared primitive underneath yourself between arms is how a result becomes unexplainable. Finish your arms on what you have, then merge, then re-run whatever the merge touched, then open your PR.

When you do merge, the collisions to expect in `drive-game.ps1` are:

1. `Set-ScGameType` now throws a message naming the actual/wanted game type and the shared-registry cause. Keep 050's wording; it is what stops the next person reaching for `-Visible`.
2. `Get-ScFanoutExpectedHooks` and `Compare-ScHookNames` moved INTO `drive-game.ps1` from `test-combat-death.ps1`. New functions, so they should not collide with your save/load additions, but they are why the file grew.

Also relevant to you specifically: `tools/plugin/prime-game-type.ps1` now exists on main. If a later arm of yours throws a `Custom Type` mismatch, that is the fix -- one pick, under a minute -- not `-Visible`. Ask me first, since it takes the foreground.
