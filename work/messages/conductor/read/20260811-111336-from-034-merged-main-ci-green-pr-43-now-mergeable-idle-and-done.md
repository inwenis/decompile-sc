---
from: 034
to: conductor
sent: 2026-08-11T11:13:36Z
subject: Merged main, CI green, PR #43 now MERGEABLE - idle and done
---

**Done.** `origin/main` merged in main-first, conflicts resolved by reading the result, CI re-run, pushed. PR #43 reads **MERGEABLE**.

## The two conflicts, both the same shape

Task 033 added a translation unit exactly where this branch added one.

| file | HEAD | origin/main | resolution |
| - | - | - | - |
| `tools/plugin/build.ps1` | `sc_screen.cpp` in `$pluginSrc`/`$testSrc` | `sc_queueind.cpp` in both | both, in both lists |
| `tools/plugin/src/scplugin.cpp` | `#include "sc_screen.h"` | `#include "sc_queueind.h"` | both, alphabetical |

**Read as a result rather than as text, which is what you asked for.** "Keep both halves" happens to be correct here, so the check was whether the RESULT is coherent, not whether the merge parsed:

- both files exist in `src/` — `sc_queueind.cpp` 36861 bytes, `sc_screen.cpp` 16628, verified on disk rather than inferred from the conflict markers;
- **both modules are actually wired into `scplugin.cpp`**, which is the part a marker cannot tell you: `ScQueueIndInit` / `ScQueueIndEnabled` / `ScQueueIndLogState` and `ScScreenInstall` / `ScScreenLogStats` / `ScScreenRemove` are all present, in the auto-merged hunks I did not resolve by hand;
- both env vars survive in `run-with-plugin.ps1` (`SCPLUGIN_QUEUEIND`, `SCPLUGIN_WIDESCREEN`, `SCPLUGIN_WS_STAGE`);
- no conflict markers anywhere in `tools/`;
- it compiles and links all of it, and `hooktest` passes with 0 failures — which is the real test that the merge produced a valid program rather than valid text.

## CI after the merge

`scripts/run-ci-local.ps1`: **PASS** at `49cee7d`.

- 97 .ps1 parsed, 2 JSON validated
- **77 Pester tests passed** (up from 61 — the merge brought in 035/036's suites), 0 failed
- game-content guard over **907** tracked files
- hooktest-parts: 20 parts, uniquely named
- hooktest: 0 failures
- ruff: SKIP, not installed on this machine — unchanged from before, not something I touched

`renderer_patch_sites.py --check` still verifies **166 sites** against the unmodified exe after the merge (4 / 41 / 121 across stages 0 / 1 / 2), so nothing in main moved the ground under the patch table.

## One expected non-green

`gh pr view 43` reports `mergeable: MERGEABLE`, `mergeStateStatus: UNSTABLE`. UNSTABLE is the GitHub-side checks, which do not run — Actions is billing-blocked on this repo, per the task file. Local CI is the gate and it is green. Flagging it so you do not read UNSTABLE as a real failure when you go to merge.

No re-runs of the in-game suites, as you said: the feature is off by default and none of 033/035/036 touch the renderer.

**Idle. Nothing of mine is running, no game, no lock held, worktree clean.**
