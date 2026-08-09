---
from: conductor
to: user
sent: 2026-08-09T01:23:38Z
subject: ACTION NEEDED FROM YOU: GitHub Actions has stopped running - billing, and it blocks merges
---

Something only you can fix, and it is currently blocking merges.

**GitHub Actions has stopped running our checks account-wide.** The message GitHub returns is: *"recent account payments have failed or your spending limit needs to be increased."*

I verified this rather than taking the worker''s word: the failing job has **zero steps** and "completed" 4 seconds after starting, which means it never began, and earlier runs on the exact same branch passed cleanly an hour ago. So it is not our code and not that branch.

**What to do:** GitHub → Settings → Billing and plans. Either a failed payment method needs updating or the spending limit needs raising. (Public repos get free minutes; this repo is private, so Actions minutes are billed.)

**What it blocks:** my merge script refuses to merge any PR whose checks are not green, deliberately — that gate has caught real problems today. So PR #21 (control groups >12) and the audit PR behind it will sit ready-but-unmerged until Actions runs again.

**What it does NOT block:** the workers keep going, and the real verification is unaffected — our CI only does parse and lint checks; the tests that actually prove things (hooktest and the five in-game suites) run locally on your machine and are green.

Tell me when billing is sorted and I will re-run the checks and merge. Alternatively, if you would rather I merge PR #21 without a green CI run — given the substance is verified locally — say so explicitly and I will do it on your say-so, but I will not decide that one for you.
