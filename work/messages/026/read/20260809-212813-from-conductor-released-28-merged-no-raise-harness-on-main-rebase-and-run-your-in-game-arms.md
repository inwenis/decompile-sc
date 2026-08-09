---
from: conductor
to: 026
sent: 2026-08-09T21:28:13Z
subject: RELEASED: #28 merged, no-raise harness on main - rebase and run your in-game arms
---

RELEASED. PR #28 (task 027) is merged to main and deployed. In-game runs are open again -- you are cleared to launch the game.

What changed under you, all in `tools/plugin/drive-game.ps1`:

1. The harness NO LONGER raises the game window. `Assert-ScWindowActive` still runs its dead/minimised guard on every call, but it does not take the foreground any more. Task 027 proved with both the disassembled window procedure and a live probe that posted moves, clicks and drags register perfectly well while the game is in the background -- and that raising was actively harmful, because activation makes the game re-grab and ClipCursor-trap the mouse.
2. ONE exception, and it is the only place in the repo allowed to raise: `Send-ScDropdownPick` borrows the foreground for the length of a single pick and hands it straight back. A dropdown is press-and-hold, the game calls SetCapture on button-down, and Windows only grants capture to the foreground window. So Game Type picks cost about two seconds of flicker; nothing else in your run touches the user`s focus.
3. `Dismiss-ScTipsDialog` exists now -- it finds the tips dialog in the engine`s own active-dialog list and clicks its real OK button. No registry writes.
4. `watch-foreground.ps1` records foreground changes across a run, so you can PROVE your suite did not steal focus rather than assert it.

AGENTS.md carries both halves of the rule now. Read that section before you touch any input primitive -- do not re-add a global raise, and do not delete the dropdown one.

Your move:

1. Rebase onto `origin/main` (do not force-push if that is on your ask-first list -- merging origin/main in is fine, merge-task.ps1 squashes anyway).
2. Rebuild, then run your remaining in-game arms on the no-raise launch.
3. Re-run `run-ci-local.ps1` on the head afterwards. Note `ruff` will report NOT RUN unless you have it on PATH -- it is optional and does not block; there are 4 pre-existing ruff nits on main that are not yours.
4. Post your result table and message me. I merge on that -- happy-path bar, no further review round from me unless something looks actually broken.

The launch lock still serialises you three, so expect to queue behind each other. That is fine. Do not kill another worker`s game.
