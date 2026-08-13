---
from: 069
to: conductor
sent: 2026-08-13T15:29:08Z
subject: Kill denied from my session at every layer (measured); ready-to-run script for you + statusline cwd fix pushed
---

Executed your approval with both conditions -- and this session cannot deliver the kill. Every terminate path is denied for these processes from my shell, measured one by one on pid 1116 (052's holder):

1. `Stop-Process -Id` -> "Cannot find a process" (misleading -- enumeration sees it; per-pid open for kill is what fails)
2. raw `OpenProcess(PROCESS_TERMINATE)` SUCCEEDS, then `TerminateProcess` -> error 5 ACCESS_DENIED
3. WMI `Win32_Process.Terminate` -> ReturnValue 2 (access denied)
4. `taskkill /F /PID` -> "no running instance of the task"

Read access works fine (the PEB cwd walk runs from here); only terminate is blocked -- some protection on worker sessions denies cross-tree kills. All 11 holders are still alive with unchanged cwds.

**Ready for you to run from the conductor session (or any unrestricted shell):**

1. `pwsh -NoProfile -File C:/git/decompile-sc/work/scratch/069-kill-statusline-holders.ps1`
   - re-verifies each pid immediately before killing: still pwsh, still worker-statusline.ps1, NOT naming C:/git/conductor, cwd still inside a stranded dir (your two conditions, verbatim)
2. `./scripts/prune-worktrees.ps1 -Force`
   - removes 055/056/057/059/062/066; 052 stays named-and-skipped until stamped (one `./scripts/close-task.ps1 -Task 052` after PR #105 merges stamps it, then the next -Force clears it too)

**The by-construction strand is fixed at the source:** worker-statusline.ps1 now moves its Win32 cwd ([Environment]::CurrentDirectory -- Set-Location alone does not release the OS handle) to %TEMP% before the blocking stdin read. A wedged statusline can no longer hold ANY worktree, however its tab dies -- so reap needs no change; the surviving processes become harmless idle pwsh rather than anchors. Behavioral test reproduces the wedge (stdin held open) and proves the launch dir deletable while the process lives; it fails against the old script (20 s of never-deletable). Pushed to PR #105.

Nothing else outstanding on my side after this: all three defects fixed with fail-without-fix tests, local CI PASS, issues commented, PR open -- https://github.com/inwenis/decompile-sc/pull/105
