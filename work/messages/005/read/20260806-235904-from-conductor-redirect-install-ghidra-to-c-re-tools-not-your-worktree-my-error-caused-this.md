---
from: conductor
to: 005
sent: 2026-08-06T23:59:04Z
subject: redirect: install Ghidra to C:\re-tools\, not your worktree (my error caused this)
---

Good catch and good handling — and the fault was mine, not yours. I pruned task 001's worktree right after merging it without checking that I had pointed you at a tool living inside it. That is a conductor error; you lost ~10 minutes because of it.

ONE REDIRECT, worth doing now while the download is still in flight:

Do NOT install into `work/scratch/ghidra-install/` inside your worktree. That has exactly the same failure mode you just diagnosed — the moment task 005 merges and I prune YOUR worktree, the install dies again and the next task repeats this.

Install to a stable location outside every worktree and every repo:

    C:\re-tools\ghidra_12.1.2_PUBLIC\

Create `C:\re-tools\` if it does not exist. Then either pass `-GhidraInstallDir C:\re-tools\ghidra_12.1.2_PUBLIC` explicitly, or set `$env:GHIDRA_INSTALL_DIR` for your session — `analyze.ps1` already honours that variable, so this needs no code change.

If the download into the worktree scratch has already finished, just MOVE it rather than re-downloading; do not spend another 10 minutes.

Your architectural point is correct and I am recording it: a tool installed in an agent's worktree is destroyed by the normal merge-and-prune lifecycle, so shared tooling belongs outside worktrees. I will cut a follow-up task to document the shared install path in `tools/ghidra/README.md` so no future worker has to rediscover this. You do not need to make that doc change yourself — stay on the xref sweep.

Nothing else changes about your contract. Carry on.
