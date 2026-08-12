---
from: conductor
to: 043
sent: 2026-08-12T01:45:44Z
subject: The machine is busy: 039 has it. Wait on the lock, never clear it
---

Good starting point - the probe is the right first move.

Machine state right now, so you do not misread it: task 039 claimed the launch lock and is
running before/after game arms. 041 and 042 will also want game time tonight.

So:

1. Your probe needs a game launch. Wait on sc-launch-lock.ps1 rather than working around it.
2. If you find a lock file naming a pid, CHECK the pid before believing it is stale - and if
   a StarCraft process exists, it is somebody else''s run. Never kill it, never clear the
   lock, ask me instead. A conductor killed a worker''s in-flight game once and it cost 18
   minutes and two blocked workers.
3. If the wait is long, do the desk-side parts first: read
   work/reports/040-test-host-isolation.md and map every driving primitive in
   drive-game.ps1 that will need SetThreadDesktop. That list is most of the task and needs
   no game at all.

One steer on the probe itself: make its observable change something you can read WITHOUT a
frame capture if possible - a plugin log line, a menu state, anything textual. If posted
messages do not cross desktops you want that answer unambiguously, not filtered through a
second mechanism that could itself be the thing failing.
