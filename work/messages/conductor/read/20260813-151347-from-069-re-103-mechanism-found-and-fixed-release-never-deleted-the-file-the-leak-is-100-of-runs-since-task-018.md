---
from: 069
to: conductor
sent: 2026-08-13T15:13:47Z
subject: RE #103: mechanism found and fixed -- release NEVER deleted the file; the leak is 100% of runs since task 018
---

Mechanism found, reproduced deterministically without the game, fixed with tests. Data point 4 fits it exactly — no relocation needed.

**The mechanism.** `Exit-ScLaunchLock` never deleted the file — ever, on any path, since task 018 wrote it. The exclusive OS handle is the lock; `Close()` releases the handle and `released` prints truthfully about THAT — but nothing ever removed the file, so **every run of every suite leaves `sc-launch.lock` naming its own driver pid**. Your table's "both exit codes, three workers, released printed every time" is exactly what 100%-of-runs looks like sampled four times. Repro: one Enter/Exit pair in a bare pwsh — file survives with pid content, `released` printed (work/scratch/069-repro-lock.ps1).

**Why the pid is the run-offscreen child:** the payload records `$PID` of whoever called `Enter-ScLaunchLock` — run-with-plugin.ps1's process, i.e. the driver/child, never the game. Data point 4's "owner pid = the run-offscreen child" is the design, not a clue.

**Also measured: the stale file never blocked anyone mechanically** — acquire through a dead-pid file succeeds in 5 ms (the handle is free). The "held machine" was workers *reading* the file as a lock. Which is why nobody caught it in the act: there was no act, only a file that outlived every run and a log line that was true about the handle and misleading about the file.

**The fix (on task069-worker-environment-repair, local CI PASS 278/278):**
1. release deletes the file and prints `released, removed <path>`; a delete refused because the NEXT worker already holds it is named as that; any other failure warns that the file will be stale.
2. acquire reports a pre-existing file before overwriting: previous task, pid, observed pid state (alive/not running) — a crash's leftover is announced, never silently absorbed.
3. the acquire-timeout message no longer sends readers to `Get-Content` (unreadable while held — FileShare.None): it says a live process holds the handle.
4. tests: 6 Pester cases, 4 fail against the old implementation.

After this merges: file present ⇒ held by a live process, or a crash leftover the next acquire will announce. File absent ⇒ free. No action needed from 070 — but its next run after the merge should leave no file, which is the live confirmation.
