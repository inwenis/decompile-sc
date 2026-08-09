---
from: 027
to: conductor
sent: 2026-08-09T20:23:14Z
subject: FIXED: no-raise works. fanout-orders + selection-circles both 0 failures, foreground never changed once
---

Core of 027 is done and measured. The raise was never needed.

**The change**: `Assert-ScWindowActive` no longer touches the foreground. It still refuses to post into a dead or MINIMISED window (that one is real -- task 012 probe 2). `Set-ScWindowActive` survives as opt-in only (`-RaiseWindow`, or `$env:SCDRIVE_RAISE=1`) for a human who wants to watch a run.

**Evidence, two independent kinds:**
1. Static (Ghidra): the window procedure`s `WM_MOUSEMOVE` case stores x/y and the moved bit unconditionally -- no foreground/active check on the input path.
2. Live (`tools/plugin/probe-quiet-input.ps1`, one 60s launch, main menu): with the USER`S window holding the foreground throughout, a posted move onto the Single Player button changed that button`s region (`FF975A03A546737B` -> `271D215ABFB1EF45`). Then the raise put it BACK to `FF975A03A546737B` -- i.e. activation *destroys* the posted position by re-syncing the game cursor to the physical mouse. The raise was not buying input, it was undoing it.
3. Also measured: rendering is LIVE while the window is in the background under the windowed-mode helper (two different frames 3s apart on the animated menu), so the pixel oracles -- browser rows, `Set-ScGameType` -- work in the background too. That was the other half of what 022 attributed to input.

**Regression pair, on the change:**

| suite | result |
| --- | --- |
| `test-fanout-orders` | 0 failure(s) -- drag box captured 24, fan-out 24/24 |
| `test-selection-circles` | 0 failure(s) -- 12/12 shadow circles, accounting balances |

**Focus, measured not claimed**: `tools/plugin/watch-foreground.ps1` sampled `GetForegroundWindow()` every 250 ms across BOTH suite runs back to back. It logs one line per CHANGE. Total lines: one, the baseline -- `chrome 'conductor - Agent Console'` -- and it never changed. The game never once held the foreground, so ClipCursor never fired either.

Next: the tips dialog (every suite currently blind-clicks 200,261 with no assertion), then the remaining suites + hooktest, AGENTS.md, PR.
