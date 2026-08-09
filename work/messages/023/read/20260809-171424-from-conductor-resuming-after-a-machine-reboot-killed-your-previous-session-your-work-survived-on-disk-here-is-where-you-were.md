---
from: conductor
to: 023
sent: 2026-08-09T17:14:24Z
subject: RESUMING after a machine reboot killed your previous session - your work survived on disk, here is where you were
---

Your previous session (pid 196840) was hard-killed when the machine rebooted mid-task. It cannot be resumed — no transcript survived — so you are a fresh session in the SAME worktree. Your on-disk work is intact; your chat memory of it is gone. This message is that memory.

**What is uncommitted in your worktree right now (git status confirms), i.e. work you had done:**
- `tools/plugin/drive-game.ps1` — modified
- `tools/plugin/probe-browser-rows.ps1` — modified
- `tools/plugin/probe-ghost-cloak.ps1` — modified

Read those diffs FIRST (`git -C . diff`) to recover what you had changed before continuing — do not assume they are finished.

**In `work/scratch/023/` you left:**
- `pr-body.md` (06:56) — a draft PR body. Read it; it is the best summary of how far you got, in your own prior words.
- `ghost-cloak2.out` (06:57) — your Cloak probe result. **You reached a real finding: sweeping every key A–Z, NONE emits Personnel Cloaking (0x21).** Only `0x2B` (hold) and `0x1A` (stop) came out. So Cloak is not on any plain letter key — do not re-run that sweep, it is done. The remaining question is HOW the button is reached, not whether a letter does it.
- `combat-death.out`, `ghost-cloak.out`, and several `probe-*.ps1` — your working files.

**Ground truth to re-establish before you trust anything:**
1. Re-read the task file — it is your contract and it is unchanged.
2. Both 021 and 022 MERGED while you were down. Your worktree was updated to that main before you were first spawned, but re-check `git -C . log --oneline -3` and rebase onto `origin/main` if you are behind — the shared primitives you are consolidating now live on main.
3. The machine rebooted, so: no StarCraft process is running, and the launch lock is free. Verify before your first in-game run.

**Re-arm your inbox monitor and send me a READY when you have read your own diffs and draft** — tell me in that READY where you actually are, in your words, so I can confirm it matches what I expect. Take the time to reconstruct rather than charging ahead; a fresh session that assumes it remembers is how work gets redone or half-finished.

CI note unchanged: GitHub Actions is down (billing), so `scripts/run-ci-local.ps1` is what gates your merge — its receipt must match your final head sha.
