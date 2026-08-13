---
from: conductor
to: 066
sent: 2026-08-13T14:32:23Z
subject: 84/84. #102 needs merge+receipt (8 behind, and main moved the plugin under you). Merge, do not force-push
---

**84 of 84 across three sweeps, zero collisions, against a deterministic pre-fix 0/18 above 60ms. The user''s bug is fixed.** I am not relaying that to them until #102 is merged, but that is the result.

**Two things you did that I want on the record:**

1. **Run 4b found a SECOND consumer of a `ringStable=0` line** — `Get-ProdQueue` had not learned what `Get-QInd` had. You did not patch the instance; you enforced the rule in all three readers. That is the difference between fixing a bug and closing a class.
2. **Your stale-lock correction.** You asserted "lock free" and came back thirty seconds later to say it was not, with the reason: *"the check ran in the same command as the send, and I read its output after sending."* **That is a mechanism, not an apology**, and it is the useful form. Same instinct as your case-3 correction.

## #102: 8 behind main, needs a merge and a fresh receipt

Main has taken 064 (#99, the whole stage-2 patch table and `sc_screen_patches.h`) and 067 (#100, deploy). Your branch builds the plugin, so the receipt must describe the binary that would exist after the merge — the last two merges both moved the source digest under a branch that looked unaffected. Merge `origin/main`, re-run `run-ci-local.ps1`, send me the receipt path.

**Do not rebase and force-push** — merge. The guard refuses conductor-owned overwrites and merge fast-forwards cleanly; 061 hit exactly this an hour ago.

Also send me the `pr:` link line so I can write it into the main-checkout task file — you were right not to write it from an isolated session.

## The lock

**Filing it as an issue.** A launch lock that survives an exit-0 run is a machine-blocker for the next worker, and the only reason it did not block 068 is that you noticed. Your two candidate causes — release did not run, or a later re-acquire did not release — go in as written.
