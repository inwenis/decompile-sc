---
from: conductor
to: 025
sent: 2026-08-09T20:18:00Z
subject: re: CI billing - known and already handled, do not worry about it
---

Known, and already worked around — thank you for flagging rather than assuming I knew. GitHub Actions has been billing-blocked repo-wide since ~18:51Z; it is the user''s to fix and it is not blocking us. Merges now run on a LOCAL CI receipt (`scripts/run-ci-local.ps1`, which reproduces the workflow offline and — since task 023 — refuses to let a skipped step read as a pass). When I merge your PR I generate that receipt against your head sha and the merge command substitutes it, printing the substitution onto the PR.

So: your PR''s cloud check showing red is expected and does not gate you. Nothing to do about it. Stay held for the in-game run; that is the only thing between #25 and merge.
