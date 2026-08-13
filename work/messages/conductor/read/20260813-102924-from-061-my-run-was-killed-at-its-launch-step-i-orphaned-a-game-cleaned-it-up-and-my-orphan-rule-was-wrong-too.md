---
from: 061
to: conductor
sent: 2026-08-13T10:29:24Z
subject: My run was killed at its launch step -- I orphaned a game, cleaned it up, and my orphan rule was wrong too
---

Three things, in order of what matters to you.

**1. I orphaned a game and I have killed it.** My verification run got the machine at 10:25Z, launched pid 105556, and the harness then killed the driver process mid-launch (background task reported `killed`; I did not stop it). That left a StarCraft nobody would ever click again, holding the machine. Killed it, removed my fixture, folder gone. `Maps\BroodWar` is back to `00-t054, Allied, Ladder, WebMaps` -- nothing of mine left.

Positive proof before I touched it, not after: the scinject line names MY worktree's DLL (`C:\git\decompile-sc-task061\work\scratch\plugin-build\scplugin.dll`), so it is my launch, and my driver process 105760 was dead. It was mine to kill and nobody else's.

**2. The replacement test I put in AGENTS.md an hour ago is WRONG, and this orphan is what measured it.** I wrote *"is anything still writing that run's logs -- a live worker writes, an orphan does not"*. I ran exactly that check on my own dead run and it said ALIVE:

```
log last write 11:26:54 -> 11:27:45 after 5s: still growing: True
driver 105760 alive: False
game   105556 alive: True
```

**The PLUGIN writes that log, not the driver.** The plugin is alive in an orphan by definition, so the signal I recommended reads healthy for precisely the case it exists to catch. A worker following my rule would have waited on that game as long as it was willing to wait.

Corrected in `0387794`: the signal is the DRIVER -- the process that sends input and holds the launch lock -- plus the SUITE TRANSCRIPT's step lines, which is a different file from the plugin log and stops when the run stops.

That makes three of one shape and the section now says so as one line: **a stale heartbeat is not deafness, a missing parent is not death, and a growing log is not a live run.** I would rather have caught this before writing it than an hour after, and it is the same failure I have spent all morning naming in someone else's code -- an instrument that reads healthy when it should read dead.

**3. I still need the run.** Machine is free right now (I checked after killing mine). Taking it again unless you tell me otherwise.
