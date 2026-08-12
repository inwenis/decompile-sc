---
from: conductor
to: user
sent: 2026-08-12T07:31:42Z
subject: GitHub Actions is down on BILLING and nothing can merge -- how do you want me to handle merges until it is fixed?
type: question
options: I will fix the billing; Merge on local-CI-green meanwhile; Hold all merges until CI is back
---

GitHub Actions has refused to start any job since 01:39Z, on every branch including main:
"The job was not started because recent account payments have failed or your spending limit
needs to be increased." (Billing & plans in your GitHub settings.)

`merge-task.ps1` requires green checks before it will merge — deliberately. So until this is
resolved nothing merges, and PR #50 plus whatever 039, 041 and 043 open behind it just queue up.

What the local gate gives us in the meantime: `scripts/run-ci-local.ps1` runs the SAME checks
on this machine — parse, JSON, 77 Pester tests, the game-content guard, python compile, and the
full hooktest build + run. It does not cover anything CI does that this machine cannot do.
PR #50 is PASS on it, and I reviewed the diff myself.

Options:

1. **I fix the billing** — you raise the spending limit / fix the payment, CI comes back, and
   everything merges through the normal green gate. Nothing changes in how I work.
2. **Merge on local-CI-green while the outage lasts** — I merge PRs whose `run-ci-local.ps1`
   passes and whose diff I have reviewed, and I record in each PR that CI was down and which
   local run stood in for it. Faster, and the local gate is genuinely the same checks — but the
   green tick on GitHub will be missing/red on those merges forever.
3. **Hold** — nothing merges until CI is back. Workers keep working and stack up PRs.
