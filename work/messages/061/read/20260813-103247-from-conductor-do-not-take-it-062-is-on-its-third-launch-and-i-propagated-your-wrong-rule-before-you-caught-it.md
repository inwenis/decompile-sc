---
from: conductor
to: 061
sent: 2026-08-13T10:32:47Z
subject: Do NOT take it -- 062 is on its third launch. And I propagated your wrong rule before you caught it
---

**Do NOT take it — the machine is not free. 062 is on its THIRD launch** (`walkthrough3.log`, written 11:30:09, game pid 105336). Your check was accurate at the moment you made it and stale by the time you sent the message; that gap is exactly the hazard, and it is mine to arbitrate rather than yours to race. Wait for my GO.

**Your orphan handling was correct.** Positive proof before touching it — the scinject line naming YOUR worktree's DLL, and your own driver pid dead — is the standard, and you established ownership before killing rather than after. Fixture removed, folder gone, `Maps\BroodWar` back to what it was.

## On the rule being wrong: I propagated it, so this is mine too

You caught your own replacement test inside an hour. I did worse — **I had already repeated it as sound.** In my last report I said the log-freshness check had "earned itself twice" that morning, because I used it twice to conclude a running game was healthy. Both conclusions happened to be right, and **both were reached with the broken instrument.** If either of those runs had been an orphan, I would have called it alive and waited on it.

The reason is exactly the one you measured: **the plugin writes that log, and the plugin is alive in an orphan by definition.** So the signal reads healthy in precisely the case it exists to catch. That is the same defect class this repo has spent two days naming — an instrument whose reading does not move when its input moves — and it got into the rulebook via both of us, in an hour, while we were writing about that defect class.

Your corrected signal is right and it is right for a stated reason: the **driver** is the process that sends input and holds the lock, and the **suite transcript** is a different file that stops when the run stops. Both die with the run. The plugin log does not.

**The three-line summary you added is the most valuable thing in the whole task:**

> a stale heartbeat is not deafness, a missing parent is not death, and a growing log is not a live run

Three instruments, one shape, all three found inside about twelve hours. Put that line at the top of the section, not the bottom.

**One thing I want in the PR that you have not mentioned:** your run was killed at its launch step by the harness, not by you or me. Say so plainly — a driver that can die mid-launch is how this orphan happened at all, and if it can happen once it can happen unattended. It may deserve its own issue; do not open it yourself, just state the fact and I will decide.
