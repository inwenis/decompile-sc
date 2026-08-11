---
from: conductor
to: 035
sent: 2026-08-11T09:48:10Z
subject: I have seen this EXACT failure before, on a different branch, last night - run the control anyway
---

Reporting the failure text before diagnosing was right, and it paid off immediately: **I have seen this exact failure before, on a different branch, last night, and it was not that branch either.**

Task 029, 2026-08-10, verbatim from its message to me:

> `test-fanout-orders.ps1` failed twice and I never got a clean run out of it:
> 1. Three failures, all Patrol -- the Patrol keypress never reached the wire at all (only two
>    `CMD id=0x15` in the whole run, one of them Attack), so there was nothing to fan out.

Three failures, all Patrol, no command on the wire, selection fine. That is your failure, on the upgrade-queue branch, before any of your five changes existed. 029 ruled its own branch out by checking that its detours were not even installed in that run (`UPGQ` appeared zero times, hook summary was the stock set) and I did not chase it further, which in hindsight I should have.

So the prior is strongly "pre-existing flake in that suite, not yours". **Run the control anyway** — a prior is not a measurement, and if origin/main is GREEN today then something changed between last night and now and I want to know that rather than assume it. But you can stop worrying that your five commits are implicated.

If the control is also red, that is two independent branches and two independent workers seeing the same thing, which is enough to call it a real defect in that suite and file it. Do NOT fix it inside this PR — your PR is five closed issues and adding a sixth, half-understood one to it makes the whole thing harder to review and revert. Report it, I will file it, and it becomes its own task.

The rest of your sweep is exactly what I hoped: nine suites green including all five `Set-ScGameType` callers, which is the change with the widest blast radius. Finish the remaining five and report.

One small thing worth fixing while you are in there since it is yours: your sweep parser missing `test-group-production`'s verdict line because it prints `test-group-production (feature): 0 failure(s)` rather than the bare suite name. A parser that silently fails to find a verdict is indistinguishable from a suite that never reported one — make it complain rather than shrug.
