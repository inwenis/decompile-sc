# Task 049 — Sweep every suite off-screen and publish the verdict table

**Closed without its own PR: its scope was absorbed by task 050, and its one remaining
item was satisfied by a run from task 056.** Written by the conductor at close, because
049's worker never got the chance to write it.

## What happened to the worker

Spawned 2026-08-12T09:27:14Z. Killed 12 minutes later, at 09:39:49Z, when Windows
restarted the machine — the second unrequested restart of that day (task 044 traced the
first, at 02:03Z, to Windows Update KB5121003). The worktree survived with zero commits;
nothing had been written yet.

## What it produced before dying, and where it went

Its survey of which suites call the raw dropdown pick — the Group A / Group B split — went
to the conductor as messages and became the Context section of **task 050**, which landed
as PR #61. So its analysis shipped; only its authorship did not.

**And 050 overturned its central claim.** 049 had reported that Group A suites "mostly run
off-screen fine" because the game-type combo is "almost always already correct". Task 050
found the real mechanism: `Custom Type` is ONE machine-wide value in
`HKCU:\SOFTWARE\Blizzard Entertainment\Starcraft`, shared with the user's own play. Whether
any suite skips the dropdown depends on what last used the real game — test or human. The
A/B split described the fleet's run order on one day, not a property of nine suites. The
corrected account is in `tools/plugin/README.md` and in AGENTS.md's section on the game's
own UI as a live-user-state writer.

That correction is the most valuable thing to come out of 049, and it arrived by 050
re-checking an inherited premise instead of building on it — which its task file explicitly
told it to do.

## The one item that outlived the absorption

Task 039's `test-selection-circles` regression run was killed by the same reboot, mid-run,
at step 3 of the map browser. It was never re-run, and 039 merged (PR #55) without it. That
made it an unfinished regression check on a change already deployed to the user, and it was
queued in 049's inbox as the reason to resume the task.

**It is now satisfied.** Task 056 ran the suite unmodified, off-screen, at 2026-08-13T00:55Z
on a branch carrying every merge of that night (039, 048, 050, 051, 053):

```
test-selection-circles: 0 failure(s)
CIRCLES stats: shown=24 hidden=12 held=12 skipped=0 noImage=0 lost=0
ok  the working copy starts out byte-identical to pristine 1.16.1
ok  and still byte-identical to pristine 1.16.1
run-with-plugin: ATTACH banner confirms the running plugin is af6d7e0 SRC=a634fe20f088
```

Verified by the conductor from the transcript rather than accepted from a report.

## Why this closes rather than resumes

Nothing is left. The table 049 existed to publish is published and is more accurate than
049's own version would have been; the regression check it was holding is green. Resuming a
worker to re-derive both would spend a slot to produce a worse artefact.

The task id is retired and not reused (AGENTS.md § Conventions: ids are never reused, gaps
never refilled).
