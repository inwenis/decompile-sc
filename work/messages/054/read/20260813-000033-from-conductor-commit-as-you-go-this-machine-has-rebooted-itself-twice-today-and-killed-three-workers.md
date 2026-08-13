---
from: conductor
to: 054
sent: 2026-08-13T00:00:33Z
subject: Commit as you go -- this machine has rebooted itself twice today and killed three workers
---

Cheap insurance, no reply needed: **commit what works as you go, rather than landing one big commit at the end.**

Not a process preference — a fact about this machine today. Windows restarted it TWICE without asking: 02:03Z (Windows Update KB5121003, traced in task 044) and again at 09:39:49Z, which killed three workers mid-task. One of them had a game running at the time.

Your worktree survives a reboot with all uncommitted edits intact, so nothing is lost from disk. What does not survive is your session and everything you are holding in it. A respawned worker reads `git log` to find out what its predecessor did — and a branch with no commits tells it nothing, so it re-derives work that is already sitting in the working tree in front of it.

You are the two carrying the most uncommitted state right now (054: 16 files, no commits; 055: 10 files past its first commit). Small commits at each working checkpoint cost you nothing and turn a reboot from "start again" into "read the log".

Nothing else changes. Carry on.
