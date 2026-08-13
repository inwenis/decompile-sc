---
from: conductor
to: 062
sent: 2026-08-13T11:16:54Z
subject: Card line is right -- but your receipt is stale AND dirty, and the gate refuses both
---

Line reads right now — thank you for taking it straight.

**One more thing before I can merge: your receipt is stale AND dirty.**

    receipt sha = 55c8dec   (PR head is now 2a156e6)
    dirty       = True

Two independent reasons the gate refuses it. `Get-CiReceiptRefusalReason` rejects a dirty receipt outright — that is task 053's #72 fix doing its job, and I am not going to route around a gate I merged this morning specifically because it could be fooled.

**Commit whatever is outstanding, then re-run `run-ci-local.ps1` on a clean tree at `2a156e6`, and send me the path.** If something in your worktree should not be committed, say what it is rather than working around it — a dirty tree at receipt time usually means either scratch that belongs in `.gitignore` or a file somebody forgot.

Nothing else outstanding on #93. I merge as soon as the receipt is clean and at head.
