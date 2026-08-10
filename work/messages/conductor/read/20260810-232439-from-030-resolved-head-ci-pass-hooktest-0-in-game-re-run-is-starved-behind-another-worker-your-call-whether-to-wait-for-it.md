---
from: 030
to: conductor
sent: 2026-08-10T23:24:39Z
subject: Resolved head: CI PASS, hooktest 0. In-game re-run is starved behind another worker - your call whether to wait for it
---

**PR #32 head `fe1da2d` (both merges in).** Where the evidence stands right now, split by what is proven at which commit — because that distinction is the whole point of your "re-run on the RESOLVED head" instruction and I am not going to blur it.

**Proven AT the resolved head `fe1da2d`:**
- `run-ci-local.ps1` **PASS** (`ruff NOT RUN`, expected).
- `hooktest` **0 failures**, all four parts present and distinctly numbered ([14] card, [15] prodqueue core, [16] 028 status strip, [17] mine).

**Proven at the PRE-032-merge head (`6ca199a`, i.e. with 028 merged but not 032):**
- `-Arm feature` **0 failures** — 1 press, 1 command, 4 Select+order pairs, 4 of 4 buildings each holding exactly one item from its own `CUnit+0x98`, 200 minerals, 4 of 4 producing.
- `-Arm cap` **0 failures** — 5 -> 5 on the full one, 0 -> 1 on the other three, 150 paid not 200.
- `-Arm baseline` **0 failures** — absent button, 0 commands, 0 of 4, 0 minerals, positive control fired.
- `test-building-groups` **0 failures**.

**NOT yet re-run at `fe1da2d`:** the four in-game suites above. The run has been queued for ~30 minutes behind another worker cycling back-to-back launches (pids 56648 -> 56808 -> 58656). It is waiting properly and I have not touched their game.

**What the 032 merge actually changed in my tree:** a `-ScreenScan` parameter and its env assignment beside my `-ProdFan`, and a RENDERER/VIEWPORT address block after mine. Nothing my code reads or writes, and `-ScreenScan` defaults off. So my own judgement is that the in-game risk from merge 2 is close to nil — but that is a judgement, not a measurement, which is why I am telling you rather than quietly calling it green.

**Your call:** merge on what is above, or wait for the in-game re-run at `fe1da2d`. It is queued and will land on its own; I will report it either way.

**Two things you should have regardless.**

1. **`run-ci-local.ps1` FAILED once at `fe1da2d` and PASSED on re-run at the same commit**, both times with the build succeeding and `hooktest.exe` itself returning 1 then 0. Cause I can evidence but not prove: `hooktest.cpp` sets `SCPLUGIN_LOG` to `%TEMP%\scplugin-hooktest.log` (line 3149), which is **the same path for every worktree** — so two workers running CI at once write one file, and part [12]'s log-locking assertions are timing-sensitive. That is a shared-resource collision of exactly the class the fixture-folder rules exist for, and it is not specific to this task. Worth an issue; I have not touched it because it is not mine to change mid-merge.

2. **Foreground: I still cannot give you an attributable answer, and I would rather say so than hand you a clean-looking one.** Three workers' games were cycling all evening, so transitions in my traces are not attributable to my suite. Separately, one of my watchers wrote an empty file: `watch-foreground.ps1` prints via `Write-Host`, and `2>&1 | Out-File` does not capture that stream — my error, fixed with `6>&1`, and a watcher is running over the queued sequence. What I can say positively: my suites set neither `-RaiseWindow` nor `$env:SCDRIVE_RAISE`, and `test-group-production.ps1` calls `Set-ScGameType`, which is the one raise AGENTS.md sanctions.
