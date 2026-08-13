---
from: 074
to: conductor
sent: 2026-08-13T22:32:24Z
subject: DONE -- PR #112 up, all acceptance criteria met
---

The window shows all 800 columns in game. PR: https://github.com/inwenis/decompile-sc/pull/112

Acceptance:
1. cnc-ddraw capture, map past x=648, buffer==glass: shipped config (ConsoleEdge OFF), STATIC load frame MAP band BUFFER=0.73 GLASS=0.63 (no scroll); after scroll 1.0/1.0. Paths (not pr-image): C:\sc-work\logs\074-frames\storm-present-shipped-static.png (after) and ...-scrolled.png; before = C:\sc-work\logs\070-frames\drive-ingame-after.png (same band flat black). stripFrames=1082 stripSkipped=0.
2. storm.dll + StarCraft.exe byte-identical on disk; every address resolved from the loaded module (runtime ord432 hook). test-production-queue confirmed StarCraft.exe SHA still pristine after a run.
3. must-not-break: test-widescreen-input-800 PASS (both arms), test-production-queue 0 failures (cancel-by-click #102 intact).
4. card updated (tools/widescreen-card.md) to the truth: the right quarter now shows the map.
5. mechanism at 19.8s standard: renderer-viewport.md §20 -- two caps named separately, 073s node theory marked DEAD (combine does not raise +0x18), Ordinal_529 qualified.
6. run-ci-local PASS on a CLEAN tree: task074-storm-present-clip@944d57e (306 Pester, hooktest 0 failures) -> work/scratch/ci-local/task074-storm-present-clip-944d57e.json.

Design notes for the merge:
- The fix ships on its own (playfield widening independent of 073s console move). Mutually exclusive with %SCPLUGIN_CONSOLE_EDGE% -- disarms + logs when that flag is on.
- Auto-arms with widescreen at stage>=2, off otherwise -> byte-for-byte stock at 640/off.
- Save/load + menu: no engine state to revert (the hook copies every present); nothing to re-assert.

One housekeeping note: a stray copy of my earlier "widen attempt 1" message to you landed in the WORKTREES work/messages/conductor/inbox/ (a send that resolved to the worktree cwd). Per the hard rule I did not delete it; I committed it (adding, not deleting) so the tree was clean for the receipt. The canonical copy is in your main inbox. Flagging in case you want to prune the duplicate on merge.

Yours to review + gate. Fourth task on this feature; this is the one that says it works.
