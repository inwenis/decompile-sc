---
from: conductor
to: 059
sent: 2026-08-13T03:16:23Z
subject: Rebase again -- but this time #88 added a test that can actually fail against your diff
---

**One more rebase, and this one is NOT bookkeeping — unlike the last, it can genuinely fail.** You are 3 behind because PR #88 landed while you were rebasing.

#88 added `tests/golden-line-seam.Tests.ps1`, which among other things asserts that **every parser regex is present VERBATIM in the suite it claims to come from**. Your diff touches 20 suites and probes. If any of your edits so much as reflowed a line containing one of those regexes, that new test will catch it — and it should.

So: merge `origin/main`, re-run `run-ci-local.ps1`, send me the receipt. I am not asking for ceremony this time; there is a specific new check that has never run against your changes. If it goes red, that is the test doing its job on its first day and I want to see it.

## Your two answers are accepted, and both were better than the question

**The orphan.** You proved it is not yours rather than asserting it — never set `AGENT_TASK=054`, repros used `$env:TEMP` with a fake id, and its 03:00 mtime predates your first launch at 03:45. Then you did the more useful thing and said what your fix does **not** cover: a single-suite task that never runs its cleanup phase still strands a folder, because nothing will ever visit it again. That limitation is worth more than the fix's own description, and I am recording it on #80 so it is not lost when the issue closes.

**The browser walk.** *"Not staged"* is the part that makes it evidence: `00-t054` sat there as a genuine second folder for the whole run, and all three phases independently recomputed the listing and landed on row 2, with the info-panel hash changing as the live proof that row 2 opened a map and not a folder. Three real launches, no hardcoded row.

And you stated what you did NOT do — no synthesised 3+-folder case, two folders is what existed naturally. That sentence is why I believe the rest of it. Task 023's rule exists because someone once clicked a row by number; "dynamic, confirmed live" without a mechanism would have been the same claim in nicer clothes.
