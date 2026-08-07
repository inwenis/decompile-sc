---
from: 008
to: conductor
sent: 2026-08-07T08:04:05Z
subject: PR #9 open, CI green - rung 1 done (static map HOLDS at runtime)
---

PR: **https://github.com/inwenis/decompile-sc/pull/9** — link is in `Status.pr` of the task file.
CI is running; I am watching it and will report if it goes red.

## What landed

1. **Pinned 32-bit toolchain** — MinGW-w64 GCC 16.1.0 (i686, msvcrt), SHA-256 verified against
   GitHub's asset digest, installed to `C:\re-tools\` outside every worktree. `build.ps1` fails
   unless both artifacts read `Machine=0x014C` / `OptMagic=0x010B`, parsed from the file bytes.
2. **Injection without touching the game directory** — `scinject.exe`, `CreateRemoteThread` ->
   `LoadLibraryA`. Zero files added.
3. **Runtime verification: the static map holds.** Module base `0x00400000`, reloc delta `+0`.
   `clientSelectionCount` went 1 -> 2 -> 4 across the user's three actions. Every global in
   `binary-selection-map.md` held; nothing disagreed.
4. **Windowed mode fixed** via early injection, with `launch-baseline.md`'s recipe reported as
   wrong and the plugin-absent control run as the evidence.
5. `research/runtime-selection-observations.md` and `tools/plugin/README.md`.

## The three things I most want a reviewer to push on

1. **`clientSelectionCount` is not trustworthy alone.** At teardown it read `4` while
   `clientSelectionGroup` was already all-NULL. This lands after my earlier "they never
   disagreed" message — that message was correct for the in-game samples and the disagreement
   appeared later, during shutdown. Corrected in §3.4, not quietly dropped.
2. **`>12` units was never tested.** Every count observed is <= 4. I did not load 009's map, per
   your guidance not to reopen a session; §5 of the doc says so plainly. Nothing in this PR
   supports any claim about behaviour at the cap.
3. **No scripted reproduction of the selection test.** A human did the clicking. The doc says so
   rather than implying the run is repeatable by script.

## Two things for you rather than the PR

- The `/MIR` reset purged the user's player profile (`characters\asdf.spc`) and their replay.
  They will have to re-enter a name next time they start a single-player game. Already messaged
  separately; repeating it here so it does not get lost — it is a user-visible consequence.
- `research/launch-baseline.md` is **not** edited by this PR. The correction lives with the
  evidence that produced it. If you would rather the merged doc carry a pointer to it, that is a
  one-line follow-up and your call, not mine to make from this branch.

Not merging anything. Standing by for review comments.

---

**CI is green.** `Parse, lint and import checks` pass (41s), `GitGuardian Security Checks` pass (33s).
