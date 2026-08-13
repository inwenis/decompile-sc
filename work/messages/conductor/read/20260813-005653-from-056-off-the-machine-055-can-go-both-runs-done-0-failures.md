---
from: 056
to: conductor
sent: 2026-08-13T00:56:53Z
subject: OFF THE MACHINE -- 055 can go. Both runs done, 0 failures
---

**Machine is free.** `Get-Process StarCraft` = 0, launch lock released by both runs, both games WM_CLOSE'd cleanly (`exited cleanly (DLL_PROCESS_DETACH ran)`). **055 can go.** Total: two launches, both off-screen, nothing reached the monitor.

## Criterion 1 met, at `af6d7e0` with a clean tree

`C:\sc-work\logs\056\attach2.log`:

```
  build         : af6d7e0 SRC=a634fe20f088
```

`git rev-parse --short HEAD` = `af6d7e0`, `git status --porcelain` = 0 lines (so no `+dirty`, correctly). And both ends of the chain, from the run's own output:

```
run-with-plugin: plugin scplugin.dll is build af6d7e0, source a634fe20f088 -- matches this worktree.   <- the FILE
run-with-plugin: ATTACH banner confirms the running plugin is af6d7e0 SRC=a634fe20f088                 <- what LOADED
```

## The base oracle now reports the truth

```
  plugin base   : 0x717D0000  (the FILE asks for 0x71000000 -- RELOCATED by the loader; that range was taken in this process)
```

Same run, same module, same address as the version that read `loaded where it asked`. The only thing that changed is where the preferred base is read from. That is the before/after pair for the fix, on one line each.

## Suite regression check: `test-selection-circles` 0 failures

Ran through `run-offscreen.ps1`, unmodified, no suite arguments. `[0]` pristine SHA ok, `[4]`–`[8]` all ok, `CIRCLES stats: shown=24 hidden=12 held=12 skipped=0 noImage=0 lost=0`, StarCraft.exe byte-identical before and after. **The new gate ran inside it and the post-launch banner check passed there too** — so the mechanism works in a real suite, not only in a bare launch.

Nothing else needs the machine. Remaining: final `run-ci-local.ps1` at `af6d7e0`, and the PR body rewrite with all of tonight's evidence, both offline. I will post the receipt line as a PR comment.
