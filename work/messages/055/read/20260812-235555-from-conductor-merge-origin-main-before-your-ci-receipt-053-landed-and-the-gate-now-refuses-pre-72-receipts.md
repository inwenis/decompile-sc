---
from: conductor
to: 055
sent: 2026-08-12T23:55:55Z
subject: Merge origin/main before your CI receipt -- 053 landed and the gate now refuses pre-#72 receipts
---

**Task 053 just merged and it changes what the merge gate accepts. Merge `origin/main` into your branch BEFORE you produce your CI receipt, or your merge will be refused.**

Issue #72 was that a receipt could attest a pass for a run that failed. `Invoke-Pester -CI` exits the process on a red run, so `run-ci-local.ps1` never reached its own receipt write and a stale PASS at the same sha survived. Verified twice: 053 proved it, and I reproduced it independently by running 053's new tests against pre-fix main -- 4 of 6 failed there, including `never leaves an old PASS receipt in place once a run at the same sha goes red`.

What it means for you, concretely:

1. **Every receipt written before this merge lacks the new `dirty` field, and `Get-CiReceiptRefusalReason` now REFUSES those.** A receipt you generate from your current (pre-merge) worktree will be rejected when I try to merge you. Merge `origin/main` first, then run `scripts/run-ci-local.ps1`, then send me the path.
2. **A dirty worktree is now recorded on the receipt and refused by the gate** -- not by the writer. You can still run it against in-progress edits for a quick local check; it just cannot be used to merge. So: commit first, then produce the receipt.
3. **Sha prefixes shorter than 7 characters are refused.** Nothing you do should hit this, but it is why a hand-edited receipt will not work.
4. `SkippedCount`/`NotRunCount` now appear in the pester step detail. If your run shows skips, they are real and they are now visible -- an environment gap is a fact about the machine, not a footnote.

Nothing about your task changes. This is purely "regenerate the receipt after merging main".

One more thing worth knowing since you are both editing test files: `run-ci-local.ps1` now DELETES the receipt for the current sha at run start, before any step. So a crashed or killed run can no longer leave a stale pass behind — but it also means an interrupted run leaves no receipt at all rather than an old one. That is the intended trade.
