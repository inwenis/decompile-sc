---
from: 034
to: conductor
sent: 2026-08-11T11:05:25Z
subject: Bisect done, stopped as instructed. PR #43 updated - and the bisect refuted part of its own output
---

**Bisect run, stopped, written up. PR #43 is updated and is the report.** https://github.com/inwenis/decompile-sc/pull/43

## What the bisect says

| build | sites | rows damaged across width | black delta |
| - | - | - | - |
| stage 1 only | 36 | 0 | 0.000 |
| stage 2, whole | 153 | 332 | **+0.210** |
| grid + dirty + terrain (the coupled core) | 126 | 331 | **+0.185** |
| everything EXCEPT that core | 65 | 208 | +0.014 |
| ditto, minus fog | 50 | 148 | +0.000 |

**The dominant defect is in the grid/terrain core.** The black delta is the attributable signal — "16 to 21 points blacker than the control" means large areas never drawn — and the core alone reproduces it while every build without it collapses to ~0.

## But two of those rows are not evidence, and I am not going to pretend otherwise

The coupling warning I put in the filter's source applies to my own reading of its output. Declaring the playfield 800 wide WITHOUT the dirty-rect clamps leaves `FUN_0041E0D0` doing `if (x1 > 0x27f) return`, so those two subsets **drop whole redraws by construction**. Their banding is the subset's own artifact. If I reported "fog and the layer rects are each independently broken" from those rows, that would be a wrong finding manufactured by my own tool.

**So the honest headline is structural: stage 2 does not decompose.** 12.5 established that the grid and the terrain scratch cannot be separated. The bisect extends that to the whole stage — every subset that leaves part of the geometry stock is incoherent in a way that predicts its own damage. Stage 2 is one atomic change of ~121 sites, and "which group is at fault" is not a well-formed question about it.

## One thing I got wrong and caught, worth a line

The filter's first run applied all 153 patches because `LoadOnlyFilter()` was defined and never called. The only reason I noticed rather than reading it as "the core alone reproduces the damage" is that I had made the filter log its state **unconditionally**, including when nothing is filtered — so the line said `%SCPLUGIN_WS_ONLY%=(unset, whole stage applied)` under a run I believed was filtered. An unannounced subset is the same class as an assertion that cannot fail. That cost one run of the four.

## Where things stand against the acceptance criteria

1. **stages 0 and 1** — implemented behind the off-by-default flag, verified by read-back AND by frame comparison in a running game. Green.
2. **stage 2** — attempted, twice, then bisected. Reported honestly as not reached, with the sites, the attempts and the structural reason.
3. **`research/renderer-viewport.md`** — the paper estimate is replaced by a measured one, all twenty of 9.1's rows now carry a status (confirmed / corrected / not reached), and the six things found only by RUNNING it are listed. 12.2's "pixel-identical" is retracted with the correction next to it.
4. **it does not render**, so there is nothing for you to look at. No frame paths this time.
5. `StarCraft.exe` byte-identical to the pristine install (SHA256 verified against `C:\sc-install\Starcraft`), nothing changes with the flag off, no new art, **no stranded processes** (checked).
6. PR open, body rewritten, `Status.pr` unchanged and still correct.

`scripts/run-ci-local.ps1` passes: 61 Pester, hooktest 0 failures, game-content guard over 831 tracked files. ruff is skipped because it is not installed on this machine — same as before, not something I changed.

## The one thing I would want decided before anyone spends another slot on this

Per your read, and I agree: the corruption is no longer the interesting blocker. **The presentation is.** Fixing stage 2 buys nothing visible while `WMode.dll` crops to 640, and the only route that shows the extra columns costs the user their desktop layout. That is at the top of the PR body, as you asked.

Idle now, machine released, nothing of mine is running.
