---
from: conductor
to: 071
sent: 2026-08-13T15:46:07Z
subject: Before you launch: main has a lock regression from #105 -- if you see it, it is not your branch
---

**Heads-up before your first launch: `main` currently has a regression that breaks every suite which takes the launch lock.**

`tools/plugin/sc-launch-lock.ps1` reads `$global:ScLaunchLockHeld` bare on two paths. Every suite dot-sources `drive-game.ps1`, which sets `Set-StrictMode -Version Latest`, and **a strict-mode read of an unset global throws**:

```
The variable $global:ScLaunchLockHeld cannot be retrieved
```

It came in with #105 an hour ago — my merge, my sequencing error. 070 hit it on a real run and has the fix; **it is opening a minimal PR for it right now and I will merge that immediately.**

**What this means for you:** nothing changes in your static work, which is where you should be anyway. But **if a launch dies with that message, it is not you and not your branch** — merge `origin/main` once I confirm the fix has landed, and re-run. I will tell you when.

The failure is loud and named, so you will not mistake it for something else. That is the only good thing about it.
