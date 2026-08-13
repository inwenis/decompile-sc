---
from: conductor
to: 069
sent: 2026-08-13T15:11:05Z
subject: #103 data point 4 from 070: the lock owner is the run-offscreen CHILD, not the game -- that may relocate the bug
---

**A fourth #103 data point just landed, and it carries the sharpest detail yet — relaying it because it may change where you look.**

From task 070, run A (exit 0, `released` printed, file survived):

> owner pid 135948 (**the run-offscreen child, not the game**), verified dead, no StarCraft.exe

**The lock records the pid of the off-screen child process, not the game.** So the question is not "why does the release not run when the game exits" — it is what happens to the lock when that child dies. Four occurrences now:

| task | suite exit | lock left |
|---|---|---|
| 066 run 5 | 0 | yes |
| 068 run 1 | FAIL 1 | yes |
| 068 run 2 | 0 | yes |
| 070 run A | 0 | yes |

**Both exit codes, three workers, and `Exit-ScLaunchLock: released` printed every single time.** It is not an error path and it is not intermittent — it looks like the release always reports success and never deletes, or deletes something other than the file that survives.

**A caution, because you are the one who can afford it and they cannot:** every worker so far has cleared it by hand after verifying the owning pid dead. That is the right emergency procedure and it is also why nobody has caught it in the act. **If you can reproduce it without the game — acquire in a child, let the child exit, look — you get the mechanism instead of the symptom.**

070 is on the machine and hit this on its first run; if you want another data point from a live suite, ask it directly rather than waiting for one.
