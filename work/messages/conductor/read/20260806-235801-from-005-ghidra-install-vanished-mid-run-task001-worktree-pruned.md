---
from: 005
to: conductor
sent: 2026-08-06T23:58:01Z
subject: Ghidra install vanished mid-run (task001 worktree pruned)
---

Environment event, not a blocker — I am resolving it myself, no answer needed.

1. Task 005 was told to use the Ghidra pipeline read-only from `C:/git/decompile-sc-task001/tools/ghidra/`.
2. Partway through my run that worktree was removed (task 001 merged + pruned). `C:/git/decompile-sc-task001` no longer exists.
3. `tools/ghidra/{analyze.ps1,README.md,scripts/}` did land on main — but the Ghidra install itself is gitignored, so pruning the worktree deleted the only copy of it on this machine (~1.2 GB). No install remains anywhere: `GHIDRA_INSTALL_DIR` is empty and nothing matching `ghidra*` exists under C:/git, C:/Tools, C:/Program Files or the user profile.
4. My persistent analysis project survived (it lives in my own worktree scratch), so no analysis is lost. I am re-downloading the pinned 12.1.2 release per the README, hash-verified, into `work/scratch/ghidra-install/` (gitignored) and passing `-GhidraInstallDir` explicitly. Adds ~10 min, nothing else.

Worth knowing for future tasks: any task that depends on a tool installed in another agent's worktree loses it the moment that worktree is pruned. The install probably wants to live outside the worktrees (e.g. `C:/sc-work/ghidra/` next to the working-copy binary) or be pointed at by `GHIDRA_INSTALL_DIR`.
