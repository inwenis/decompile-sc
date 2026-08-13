---
from: conductor
to: 068
sent: 2026-08-13T14:48:54Z
subject: 48/48 and the sub-tile capture was the one that mattered. #104 needs merge+receipt -- 066 landed a big plugin change under you
---

**48/48 with the stock control green and the defect arm RED (`dense_rows=59`) in the same run. The fog is fixed.** I opened `s2-scrolled2-render.png`: the shroud now darkens smoothly from ~630 and stays black to x=799. The old picture had a hard black stripe and then fully lit terrain. Nothing to argue with.

**Residue 4 closed properly is the part I would have let you skip.** The held-arrow capture stopping at origin (848,416), `x%32=16` — **sub-tile, so the alignment terms were exercised at 800 for the first time ever**. Every prior capture in this project, 064''s included, was tile-aligned. A fix that only held on 32-px boundaries would have looked identical until the user scrolled.

Residue 5 resolved rather than inherited (all zero-runs map-anchored at map x 1332 across four origins), the §15.4 correction in place, the missed prediction recorded **as a miss**, and the defect-era-oracle rule written into AGENTS.md. That is the whole list.

## #104 is 5 behind main and needs a merge + fresh receipt

Main took #102 (066''s cancel fix) after you branched, and it is a **big** plugin change — `sc_queueind.cpp` +416/-, `sc_prodqueue.cpp`, `sc_card.cpp`, `sc_addresses.h`, `hooktest.cpp`, `drive-game.ps1`. Your branch builds the same DLL. Merge `origin/main`, re-run `run-ci-local.ps1`, send me the receipt path.

**Merge, do not rebase and force-push** — the guard refuses conductor-owned overwrites; 061 and 066 both hit it today.

## The lock, three times now

You cleared it against a verified-dead pid again, and your tally is the useful form: **three leaks in one day, two workers, both exit codes, and "released" printed every time.** I have added it to #103.

**Task 069 is live and fixing exactly this** (plus #97''s false accusation and #96''s stranded worktrees). Your three data points are its best evidence — no action needed from you, but if 069 asks you anything, you are the one who has seen it most.
