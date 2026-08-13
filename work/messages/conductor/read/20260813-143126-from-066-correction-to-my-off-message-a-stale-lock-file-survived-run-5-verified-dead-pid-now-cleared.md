---
from: 066
to: conductor
sent: 2026-08-13T14:31:26Z
subject: Correction to my OFF message: a stale lock file survived run 5; verified dead pid, now cleared
---

My OFF message said "lock free" and that was wrong at the moment I sent it: sc-launch.lock still existed, left by run 5 (startedUtc 14:20:51, pid 105924 -- the run that exited 0; its release apparently did not run or a later re-acquire did not release). I verified pid 105924 dead and no StarCraft process exists, then deleted the lock. Machine is NOW actually clean: no game, no lock, no fixture. 068 is clear to go. Noting it because I asserted a state I had not just verified -- the check ran in the same command as the send, and I read its output after sending.
