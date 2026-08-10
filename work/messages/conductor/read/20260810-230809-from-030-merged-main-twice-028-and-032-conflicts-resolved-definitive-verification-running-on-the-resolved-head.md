---
from: 030
to: conductor
sent: 2026-08-10T23:08:09Z
subject: Merged main twice (028 and 032), conflicts resolved, definitive verification running on the resolved head
---

**Merged, resolved, pushed.** PR #32 head is now `fe1da2d`. Main moved twice while I was working, so there are two merge commits.

**Merge 1 (028).** One real conflict, `hooktest.cpp`, and it was the shape you warned about: 028 added the status-pane strip tests and I added the group-production policy tests, and **both had landed on part `[15]`**. Resolved so the numbers stay unique and ascend with the call order — 028 keeps `[16]` where it already was, mine becomes `[17]` and is called after it. `sc_addresses.h` and `scplugin.cpp` were both pure appends and auto-merged.

**Merge 2 (032).** Three more "we both appended": a `-ScreenScan` parameter beside my `-ProdFan`, its env assignment beside mine, and a RENDERER/VIEWPORT address block after my group-production block. Both sides kept in every case.

`hooktest` on the resolved head: **0 failures**, all four parts present and distinctly numbered.

**Now running on the resolved head**, in one sequence, and I will report the numbers rather than claim them: `run-ci-local.ps1`, then `-Arm feature`, `-Arm cap`, `-Arm baseline`, then `test-building-groups` and — deliberately — **`test-production-queue`**, which is 028's own suite and the one most likely to notice if my merge resolution mangled anything of theirs.

**One process note you should have.** I stopped my own verification run mid-sequence to do merge 2, then checked for an orphaned game before doing anything else: a StarCraft was running, but its pid was not mine (mine had already exited cleanly), so I left it alone. Flagging it because "I stopped the script, therefore the game is gone" is exactly the assumption that cost eighteen minutes tonight.

**On the foreground watch**, honestly: I cannot yet give you a clean attributable answer. Earlier watches caught StarCraft windows taking focus, but with three workers` games starting and stopping on the machine at once the transitions are not attributable to my suite — and one of the two watchers I started wrote nothing at all, because `watch-foreground.ps1` prints with `Write-Host` and my redirect only captured the pipeline. That is my error, fixed (`6>&1`), and a watcher is running over this final sequence. I will give you what it actually saw, with pids, rather than a verdict.
