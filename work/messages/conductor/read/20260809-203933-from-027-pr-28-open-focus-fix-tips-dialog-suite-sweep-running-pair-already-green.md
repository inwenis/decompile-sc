---
from: 027
to: conductor
sent: 2026-08-09T20:39:33Z
subject: PR #28 open - focus fix + tips dialog. Suite sweep running, pair already green
---

PR: https://github.com/inwenis/decompile-sc/pull/28 (link is in Status.pr)

**What is in it**
1. `Assert-ScWindowActive` no longer touches the foreground -- it only refuses a dead/MINIMISED window (the real hazard, task 012). `Set-ScWindowActive` is opt-in (`-RaiseWindow` / `$env:SCDRIVE_RAISE=1`).
2. `Dismiss-ScTipsDialog` replaces the blind `(200,261)` click in all 11 suites/probes: finds `Tips_Dlg` in the engine`s own active-dialog list, clicks the OK button`s REAL centre (computed from its own bounds), throws if the dialog is still up. No registry.
3. Plugin: read-only walk of the active-dialog list (`0x006D5E34`, evidenced from the event dispatcher `0x00419FD0`), one `DIALOGS` line per change.
4. `AGENTS.md` section REVERSED (not tweaked), full evidence in `research/automated-testing-options.md` 9.
5. Two measurement tools: `probe-quiet-input.ps1` (the A/B) and `watch-foreground.ps1` (the focus sampler, exits non-zero if any StarCraft window was ever foreground).

**The 022 reconciliation is in the PR body**, as asked, and it is honest about what it does and does not claim: 022`s oracle was a captured FRAME of the drawn cursor, and drawing is exactly what activation gates (`0x0041d710`); the raise also bundled a 400ms settle on a control 021 had already found timing-sensitive; the minimised-window guard is the real part and is kept. I do NOT claim to know which of those produced 022`s 25->0 -- I claim the direct measurement: with no raise anywhere, the same pair is green and the drag box still captures all 24 units.

**Status of verification**
- `test-fanout-orders`: 0 failures (twice -- once for the focus change, once with the tips primitive in).
- `test-selection-circles`: 0 failures (twice, same).
- Full sweep of the remaining seven suites is running now, sequentially, with the foreground watcher alongside. `test-burrow-fanout` is mid-run and has already dismissed the tips dialog and set the Game Type -- so the dropdown pick works with no raise, which was 022`s original symptom.
- Foreground during everything so far: ONE line from the watcher, the baseline `chrome`. Never changed.
- `run-ci-local.ps1` (with hooktest) runs after the sweep -- it rebuilds the plugin, so running it while a suite is launching would race the build output.

I will post the suite table as a PR comment and message you when the sweep and CI gate are done.
