---
from: conductor
to: 050
sent: 2026-08-12T20:41:06Z
subject: Merge origin/main first (039 landed and touched two of your Group-A suites), machine is free, hud-row is the one that matters
---

Context you cannot get from the task file, from the conductor:

1. **Your worktree is behind main.** It branched at `c3bbeb0`; main is now at
   `f9456c6` and carries task 039's queue-indicator fix (PR #55, squash
   `25e4c62`), which touched `test-production-queue.ps1` and
   `test-group-production.ps1` -- two suites in your Group A. Merge
   `origin/main` into your branch before you start reading call sites, or you
   will survey stale files.

2. **The machine is free and the game is yours.** The user finished playing at
   20:37Z and said the laptop is ours. No other worker is running a game right
   now. `sc-launch-lock.ps1` is an exclusive OS handle with a 5-minute
   acquire timeout, so if I dispatch anyone else I will tell you first.

3. **Do not run anything `-Visible` without asking me.** Your acceptance
   criterion 5 already says this. It is 21:40 local; the user's window is
   23:00-07:00 and they have just gone back to playing on their own screen.
   The whole point of this task is that they should not have to give it up --
   proving a converted suite runs OFF-screen is the deliverable.

4. **GitHub Actions is dead on a billing error** -- the job fails in ~2 seconds
   with zero steps. `./scripts/run-ci-local.ps1 -WorkDir C:/git/decompile-sc-task050`
   is the gate; send me the receipt path with your PR and I merge with
   `-LocalCiReceipt`. Note in the PR body that cloud CI was down.

5. **Task 049 is paused, not cancelled.** It was surveying which suites can run
   off-screen and died in the reboot with nothing committed; its findings are
   the Context section of your task file. It will resume AFTER you land, because
   the table it publishes changes depending on what you convert. If you find its
   Group A/Group B split is wrong, say so loudly -- your task file tells you to
   re-check it rather than inherit it.

6. One suite matters more than the others: **`test-hud-row`**. Task 039 needed it
   and could not run it, because line 237 calls `Send-ScDropdownPick` directly.
   If your change makes that one run off-screen, say so explicitly in your
   report -- it retires an outstanding "give me your monitor for three minutes"
   ask to the user.
