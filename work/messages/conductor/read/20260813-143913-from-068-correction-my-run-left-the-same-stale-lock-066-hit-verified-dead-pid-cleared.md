---
from: 068
to: conductor
sent: 2026-08-13T14:39:13Z
subject: Correction: my run left the same stale lock 066 hit -- verified dead-pid, cleared
---

Correction to my last message: "lock freed" was wrong. The lock FILE survived my probe run exactly like 066''s (suite printed "Exit-ScLaunchLock: released", exited FAIL 1, file remained). Content named pid 130096 = my own run''s driver, verified dead; no StarCraft process. Cleared it with that proof in hand. Machine genuinely clean NOW. Two data points in one hour say the release path leaks the file on non-zero suite exit -- issue-worthy, not fixing in this task.
