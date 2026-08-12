---
from: conductor
to: 043
sent: 2026-08-12T07:27:11Z
subject: BRIEFING: you are a respawn after the 02:03Z reboot -- the cross-desktop probe may already be on disk
---

You are a RESPAWN, not the worker that started this task. The machine rebooted at
2026-08-12T02:03Z and killed your predecessor mid-task (last heartbeat 01:59Z). Its
transcript did not survive -- you start with ZERO of its chat context. Everything below
is what disk still knows.

## What your predecessor left in C:/git/decompile-sc-task043

NO commits. One modified file and three new ones, none of them described in any message:

    M  tools/plugin/run-with-plugin.ps1
    ?? tools/plugin/probe-cross-desktop-input.ps1
    ?? tools/plugin/run-offscreen.ps1
    ?? tools/plugin/sc-desktop.ps1

Its only message was READY at 01:45Z: "Starting with the decisive probe: cross-desktop
posted-message driving." So the probe was written and possibly RUN, and no result ever
came back. Read those four diffs first, and check `C:\sc-work\logs\` for anything the
probe left behind (`043` paths) before re-running it -- the answer may already be on disk.

That probe IS the task's first gate: if posted input does not cross desktops, task 043 is
a documented NO and that is a good outcome. Settle it before wiring anything further.

## Machine state

Free. IMPORTANT, since your predecessor was told to wait on it: the leftover
`C:\sc-work\logs\sc-launch.lock` names ITS OWN dead pid 30984 from 01:59Z. The lock is a
held file handle, so it died with the process -- the JSON left on disk is inert and
`Enter-ScLaunchLock` will acquire straight over it. Do not hand-delete it; just acquire
normally. No StarCraft is running. Tasks 039 and 041 are also respawning and will want the
machine; the lock serialises all three.

## CI is DOWN repo-wide -- do not chase it

Every GitHub Actions run since 01:39Z fails before starting, on all branches including
main: "The job was not started because recent account payments have failed or your
spending limit needs to be increased." User billing, not your code. Gate on
`scripts/run-ci-local.ps1`, open the PR anyway, note the outage in the PR body.

Report the probe's verdict to the conductor as soon as you have it -- yes or no, either is
the deliverable.
