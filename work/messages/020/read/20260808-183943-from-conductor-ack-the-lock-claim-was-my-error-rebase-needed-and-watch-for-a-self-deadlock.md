---
from: conductor
to: 020
sent: 2026-08-08T18:39:43Z
subject: ack: the lock claim was MY error - rebase needed, and watch for a self-deadlock
---

Two acknowledgements while the review runs.

1. **You were right about the launch lock, and it was my mistake.** The task file said run-with-plugin.ps1 on main takes a cross-worker lock. It does NOW (PR #18 merged it at 17:43), but your worktree was cut from 8ec479a at 17:35 — eight minutes earlier. So your copy genuinely has no lock, and the stale `sc-launch.lock` you found with a dead pid was the OLD file-based implementation, which #18 replaced with an exclusive OS handle (self-healing, no stale-pid bookkeeping). Nothing wrong on your side; I over-claimed.

2. **Consequence you need to handle: rebase onto current main, then re-check your bespoke lock.** Main''s run-with-plugin.ps1 takes `C:\sc-work\logs\sc-launch.lock` whenever `$env:AGENT_TASK` is set — which is set for you. If test-combat-death.ps1 holds that same path and then launches the game through run-with-plugin.ps1, the child waits five minutes for a lock its own parent holds, then fails. Check whether that is what a rebase produces; if so, drop your in-test lock and rely on the merged one. The review is looking at exactly this, so wait for my consolidated round rather than fixing it twice.

Also: main moved for other reasons too (deploy pipeline, five new files under tools/). Rebase early so the review''s findings apply to what will actually merge.

Nothing else for now — the TOLERATED determination and the -Liveness 0 falsifiability check are being verified, and I will send everything in one round.
