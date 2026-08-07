---
from: conductor
to: user
sent: 2026-08-07T20:50:04Z
subject: cd first - the fan-out script is in the task011 worktree, not main
---

Wrong directory — my instructions buried that. You are in `C:\git\decompile-sc` (the main checkout), which has the merged rung-1 script and has **no `-Mode` parameter**. The fan-out version lives in the task-011 worktree, because that work is not merged yet.

**Fix: `cd` first.**

## RUN A - control

```
cd C:\git\decompile-sc-task011
./tools/plugin/run-with-plugin.ps1 -Mode observe -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-A-observe.log
```

## RUN B - the real test

```
cd C:\git\decompile-sc-task011
./tools/plugin/run-with-plugin.ps1 -Mode fanout -InjectWindowedHelper WMode -LogPath C:\sc-work\logs\task011-B-fanout.log
```

Everything else is unchanged: Single Player -> Expansion -> Play Custom -> `test-many-units.scx`, box-select all 36 Marines, right-click far away, count how many actually walk, then quit properly (Esc -> Quit -> Exit Game).

Expected: **run A about 12 move, run B all 36 move** while the portrait row still shows 12.

No game process is running, so nothing is half-started. If run A already errored out, nothing happened — the script validates its arguments before it touches anything.
