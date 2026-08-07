---
from: conductor
to: user
sent: 2026-08-07T07:21:50Z
subject: I was wrong about the DirectX cause - and our plugin is already running inside the game
type: question
options: Run one short fullscreen session now (~4 min, desktop drops to 640x480); Fix windowed mode first, then test (adds a side-task, delays rung 1); Wait until I am away from the machine
---

Correction to what I told you 10 minutes ago: **I was wrong about the cause, and the worker proved it.**

It ran the controlled experiment I should have asked for:

  plugin injected, no ddraw.dll   -> game launches, renders, reaches the main menu. WORKS.
  WMode.dll as ddraw, plugin      -> DirectX dialog
  WMode.dll as ddraw, NO plugin   -> SAME DirectX dialog

That third row is decisive: our plugin was never involved. Its injection method adds zero files to the game folder — it never touches the ddraw slot at all. I saw a ddraw.dll in the directory and jumped to a conclusion without checking whether our code even used that route.

**The real cause, and it is a correction to our own research.** The windowed-mode helper has no export table. The game does `LoadLibraryA("ddraw.dll")` then asks it for functions by name, which cannot succeed against a DLL that exports nothing — hence "the specified procedure could not be found". So the windowed-mode recipe in our merged notes does not actually work on this machine. Last night I praised that finding for being backed by a measurement rather than an assertion. The measurement was real; the inference from it was wrong — "the desktop resolution didn't change" is equally consistent with "DirectDraw never started at all". It is being corrected.

## The genuinely good news

Our plugin **already loads and runs inside StarCraft**, reaches the menu, and reports:

  module base 0x00400000, relocation delta ZERO

That means every address we mapped last night is usable exactly as written, with no adjustment. That removes a whole category of risk from the next two rungs.

Toolchain is installed and pinned, 32-bit verified, living outside the worktrees so a cleanup cannot destroy it again.

## One decision, and it is yours because it is your screen

Only one step is left in rung 1: play a few minutes of single-player while the plugin logs the live selection state, to confirm our addresses track what you actually see selected.

Fullscreen works today. Windowed does not, and did not before we started. Fullscreen drops your desktop to 640x480 for the duration.
