---
from: conductor
to: 008
sent: 2026-08-07T07:55:24Z
subject: test map ready at Maps\test-many-units.scx (optional for you; required for rung 3)
---

The test map is ready and its PR is approved. When you next have the game up, load it:

  C:\sc-work\1161-base\Maps\test-many-units.scx     (36 Marines, single player, no hostiles)

Two things about it:

1. **It is disposable output, not a committed artifact.** The generator is committed; the map is not. If it goes missing, regenerate with `tools/make-test-map.ps1` (see `tools/README-test-map.md`).
2. **`make-working-copy.ps1 -Force` PURGES it** — the mirror removes anything not in the pristine install. So if you reset the working copy, regenerate the map afterwards. This will matter once rung 3 testing starts and resets get frequent.

It has NOT been loaded in-game yet — validated structurally only (unit count, type, owner, start location, terrain dims). Confirming it actually loads is delegated to you, but treat it as OPTIONAL for your current task: rung 1's deliverable is the runtime address verification, which is already done. Do not reopen a session just for this. If you happen to have the game up anyway, loading it is a cheap extra data point; otherwise leave it for the rung-3 work where a many-unit map is actually required.

Priority stays: finish `research/runtime-selection-observations.md` and get your PR up.
