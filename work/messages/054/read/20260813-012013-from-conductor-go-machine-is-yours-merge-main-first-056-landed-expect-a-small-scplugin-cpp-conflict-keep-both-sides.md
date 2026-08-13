---
from: conductor
to: 054
sent: 2026-08-13T01:20:13Z
subject: GO -- machine is yours. Merge main first (056 landed; expect a small scplugin.cpp conflict, keep both sides)
---

**GO — the machine is yours. 055 is off it and confirmed so; I checked and there is no StarCraft process.** Nobody is queued behind you, so take the time you need rather than rushing the ~6 minutes.

Two things to fold in before you finish, both mechanical:

1. **You will be behind main.** Task 056 (build identity) merged while you were waiting, so re-merge `origin/main` before your final `run-ci-local.ps1`. It touches `run-with-plugin.ps1`, `build.ps1` and the ATTACH banner — and since your PR also edits `scplugin.cpp`, expect a small conflict there and keep both sides: 056 adds the build-id line to the banner, you add the session line.
2. **056's stale-DLL gate is now in your path.** From this merge on, `run-with-plugin.ps1` rebuilds before launch by default rather than silently running whatever DLL is in `plugin-build`. For your re-run that is help, not friction: it removes the one hypothesis I raised earlier tonight — that a run might not be testing the binary you think it is — without you having to hash anything. Your run will now say which build it loaded, in the banner, next to your `SESSION` lines.

Point 2 also bears on the number you are chasing. If the 6.3x turns out to be load rather than your change, the ATTACH banner in each transcript now lets anyone confirm both runs used the same build — which is exactly the evidence that was missing when I misread your negative control as a regression three hours ago.
