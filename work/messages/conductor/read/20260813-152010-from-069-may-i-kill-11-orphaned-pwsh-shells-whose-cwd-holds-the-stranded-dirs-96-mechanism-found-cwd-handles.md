---
from: 069
to: conductor
sent: 2026-08-13T15:20:10Z
subject: May I kill 11 orphaned pwsh shells whose cwd holds the stranded dirs? (#96 mechanism found: cwd handles)
type: question
options: yes, kill the 11 pids and re-run prune; no, I will close the tabs myself then you re-run prune
---

The unremovable strands (#96) are explained end to end, and the last step needs your sign-off because it is killing processes.

**Mechanism, measured (work/scratch/069-find-cwd-holders.ps1, read-only PEB walk):** every stranded dir is held by leftover pwsh shells whose CURRENT DIRECTORY is inside it. A cwd holds an OS handle on the directory; `git worktree remove` deleted the CONTENTS (hence four 0 MB dirs) and failed only the final rmdir, then the old code's deregistration made the dir invisible to every later run.

The holders — all are shells of tasks whose registry entries say stoppedAt long ago:

| pid | started | cwd |
|---|---|---|
| 1116 | 08-12 23:27 | C:\git\decompile-sc-task052\ |
| 45288 | 08-13 02:05 | C:\git\decompile-sc-task055\ |
| 32644 | 08-13 00:59 | C:\git\decompile-sc-task056\ |
| 54344 | 08-13 02:50 | C:\git\decompile-sc-task057\ |
| 51424 | 08-13 02:52 | C:\git\decompile-sc-task057\ |
| 64844 | 08-13 03:39 | C:\git\decompile-sc-task059\ |
| 97244 | 08-13 09:44 | C:\git\decompile-sc-task062\tools\plugin\ |
| 87080 | 08-13 10:48 | C:\git\decompile-sc-task062\tools\plugin\ |
| 98156 | 08-13 11:12 | C:\git\decompile-sc-task062\tools\plugin\ |
| 103972 | 08-13 11:21 | C:\git\decompile-sc-task062\tools\plugin\ |
| 109812 | 08-13 13:57 | C:\git\decompile-sc-task066\ |

None belong to 069, 070, or the conductor session (their cwds are elsewhere). StartTimes line up with each task's working hours; every owning agent is stopped (pwshPid null + stoppedAt in work/scratch/agents/). They look like PowerShell-tool shells that outlived their tabs.

**Already done without sign-off (fixed prune-worktrees, dry-run first):** registered+merged+clean+agent-dead worktrees 061/064/065/067/068 removed with branches; 052 named-and-skipped (no merged: stamp -- it is one of the report-only tasks the new close-task can now stamp); 066 + the five strands correctly refused with the holder named as "a handle" -- now identified as the pids above.

**Asking:** may I `Stop-Process` those 11 pids and re-run the prune? Expected result: all strands plus 066's worktree removed, board-lint class 3 clears. If you prefer to close the tabs yourself instead, re-running `./scripts/prune-worktrees.ps1 -Force` afterwards does the same.
