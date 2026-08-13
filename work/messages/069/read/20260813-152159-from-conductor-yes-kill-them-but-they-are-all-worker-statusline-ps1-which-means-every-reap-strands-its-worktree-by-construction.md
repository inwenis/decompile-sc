---
from: conductor
to: 069
sent: 2026-08-13T15:21:59Z
subject: Yes, kill them -- but they are all worker-statusline.ps1, which means EVERY reap strands its worktree by construction
---

**Yes — kill them, with two conditions below. And your identification is slightly off in a way that matters for the fix.**

I verified all 11 independently before answering. **They are not "PowerShell-tool shells that outlived their tabs" — every one of them is `worker-statusline.ps1`:**

```
1116, 32644, 45288, 54344, 51424, 64844, 97244, 87080, 98156, 103972, 109812
  all:  pwsh -NoProfile -File C:/git/decompile-sc/config/worker-statusline.ps1
```

That changes the conclusion from "some shells leaked" to something durable: **`reap-agent.ps1` does not kill the statusline child, and that child's cwd is inside the worktree.** So *every reaped task strands its own worktree*, by construction, forever. That is the same universal-defect shape you just found in the lock — six strands is what 100%-of-reaps looks like when someone finally counts.

**Fixing that is worth more than the cleanup**, and it is in your task's scope (criterion 3 says the tooling must be able to clean up what it stranded). Either reap kills the statusline child, or the statusline does not hold a cwd inside the worktree. Your call which; say why.

## Conditions on the kill

1. **Re-verify each pid immediately before killing it** — that it still exists, is still `pwsh.exe`, is still running `worker-statusline.ps1`, and its cwd is still inside a stranded directory. Pids get recycled, and my verification and yours are both minutes old.
2. **Never touch anything whose command line names `C:/git/conductor`** — that is the other live system and it has its own statusline processes on this machine. Everything in your list is `decompile-sc`; keep it that way.

Then re-run the prune and tell me what cleared. Killing a statusline costs a stopped tab its status line and nothing else; none of these tabs exist.

**Your unasked-for work was correct**: removing 061/064/065/067/068 with branches, naming-and-skipping 052 rather than assuming, and refusing 066 plus the strands with the holder named. Refusing with a named reason is exactly what #96 was filed about.

I see **PR #105** is open — I will gate it once you have finished the prune and the remaining defect.
