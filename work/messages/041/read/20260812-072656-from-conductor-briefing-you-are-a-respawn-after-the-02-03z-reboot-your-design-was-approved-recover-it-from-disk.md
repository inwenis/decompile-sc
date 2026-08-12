---
from: conductor
to: 041
sent: 2026-08-12T07:26:56Z
subject: BRIEFING: you are a respawn after the 02:03Z reboot -- your design was approved, recover it from disk
---

You are a RESPAWN, not the worker that started this task. The machine rebooted at
2026-08-12T02:03Z and killed your predecessor mid-task (last heartbeat 01:59Z). Its
transcript did not survive -- you start with ZERO of its chat context. Everything below
is what disk still knows.

## What your predecessor left in C:/git/decompile-sc-task041

NO commits. Three UNTRACKED files, never described in any message:

    tools/plugin/random-conformance-plan.ps1
    tools/plugin/random-conformance-episodes.ps1
    tools/plugin/test-random-conformance.ps1

Read them before writing anything new -- that is the start of the harness, mid-flight.

## Your design was already reviewed and APPROVED -- recover it

1. `C:/git/decompile-sc/work/messages/conductor/read/20260812-014040-from-041-design-action-vocabulary-oracle-for-the-randomized-conformance-harness-task-041-step-1.md`
   is the design YOU sent (action vocabulary, INV-W/R/M/B/S/U/H/P oracle table, seed +
   replay, three profiles, budget). Read it in full -- it is your own plan.
2. `C:/git/decompile-sc/work/messages/041/read/20260812-014122-from-conductor-oracle-approved-except-inv-h-which-is-the-bug-039-found-this-hour-and-your-teeth-test-moved.md`
   is the previous conductor's verdict: oracle approved EXCEPT INV-H, and your teeth test
   moved. Read it and honour both amendments.

Note what changed while you were dead: task 038 is MERGED into origin/main, so origin/main
is no longer the parent that fails your teeth test. Pick the parent commit deliberately and
say which one you used.

## Machine state

Free. No StarCraft is running; the leftover `C:\sc-work\logs\sc-launch.lock` names a dead
pid and is inert (the lock is a held file handle, it died with the process). Task 039 is
also being respawned and will want the machine -- the launch lock serialises you both.

## CI is DOWN repo-wide -- do not chase it

Every GitHub Actions run since 01:39Z fails before starting, on all branches including
main: "The job was not started because recent account payments have failed or your
spending limit needs to be increased." User billing, not your code. Gate on
`scripts/run-ci-local.ps1`, open the PR anyway, note the outage in the PR body.

Report to the conductor once you have read yourself back in and know what the three
untracked files already do.
