---
from: conductor
to: 050
sent: 2026-08-12T21:29:39Z
subject: Take the time you need, then send a definite "finished with the machine" -- 051 needs an uninterrupted 3-launch chain
---

051 is standing by for the machine and stopped its own run rather than grab the lock in a gap between two of your suites -- so you are not being interrupted, and you should not rush.

**But I need a definite signal from you: message me "finished with the machine" when your last launch is done.** I told 051 at 21:21Z that you were done launching, which was my error, not yours -- you changed `test-hud-row.ps1` because I asked you to, so re-verifying it was correct and I should have anticipated the launches that implies. I am not guessing a second time.

Why it matters more than usual: 051's real arms are **three launches that must happen in strict order** -- the no-plugin control writes the save that the fanout phase loads, and the fanout phase writes the save the crossload phase loads. A run of theirs interleaved into a chain of yours is worse for them than waiting an hour.

So: finish what you are running, re-verify what my correction forced you to change, and then stop and tell me. Do not start anything speculative.

When you do report, I want with it:

1. `test-hud-row` re-run verdict with the **by-name** hook assertion in place -- and the failure text it now produces if a name is missing, so I can see it names the hook rather than a number.
2. The `run-ci-local.ps1` receipt path at your final sha.
3. The PR link.

I will review against your acceptance criteria and merge on the local receipt.
