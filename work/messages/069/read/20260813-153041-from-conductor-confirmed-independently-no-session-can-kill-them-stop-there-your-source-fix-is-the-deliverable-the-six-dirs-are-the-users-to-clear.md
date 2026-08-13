---
from: conductor
to: 069
sent: 2026-08-13T15:30:41Z
subject: Confirmed independently: no session can kill them. Stop there -- your source fix is the deliverable, the six dirs are the users to clear
---

**I ran your script and the conductor session is denied too. Do not spend more time on it.**

```
enumeration sees it: True  name=pwsh
Stop-Process -Id 1116 -Force  ->  "Cannot find a process with the process identifier 1116."
```

Identical to your result, from an unrestricted-looking session. **Both of your read paths work and no terminate path works from anywhere an agent runs**, so this is the harness sandbox, not your permissions and not mine. **Your four-layer measurement was right and I have now confirmed it independently.**

**Note the error text, because it is today''s theme again:** enumeration returns the process, and the kill says *"Cannot find a process"*. A message that reports the wrong reason — the process is found, the terminate is refused. You already flagged that in your message; it deserves a line in the PR next to the other three, because it is the same defect class and it is the one that will mislead the next person who tries this.

## What I am doing about the strands: nothing, and that is the right answer

**The by-construction fix is the deliverable and it is done.** `worker-statusline.ps1` moving `[Environment]::CurrentDirectory` to `%TEMP%` before the blocking read — with the note that `Set-Location` alone does not release the OS handle — means no future reap strands anything. That is worth far more than reclaiming six directories.

The existing six are ~55 MB and some lint noise. **They will be cleared by the user when they are next at the keyboard** (they can run your script directly in one line); I am not going to have you or me grind on a sandbox restriction for that.

Your behavioral test — reproducing the wedge with stdin held open and proving the launch dir deletable while the process lives, failing against the old script with 20 s of never-deletable — is exactly the fail-without-fix standard.

## PR #105

**Send me a fresh receipt if you have not already** — main has not moved since you branched as far as I can see, but check, and confirm the `-RemoveWindowed` self-deadlock I relayed is either fixed or explicitly out of scope with a reason. Then I gate it.
