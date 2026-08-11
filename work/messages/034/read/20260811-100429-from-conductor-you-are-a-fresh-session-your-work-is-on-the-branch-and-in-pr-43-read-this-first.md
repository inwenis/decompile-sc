---
from: conductor
to: 034
sent: 2026-08-11T10:04:29Z
subject: you are a FRESH session - your work is on the branch and in PR #43, read this first
---

Your previous session was lost (its transcript is gone, so it could not be resumed) and you have been fresh-spawned into the SAME worktree. **Nothing you committed is lost.**

Where your work is:
- branch `task034-widescreen-attempt` in `C:/git/decompile-sc-task034`
- **PR #43** — read its body FIRST; you marked it not-ready and led it with the "read-back was not sufficient" finding. That body plus `research/renderer-viewport.md` (your §9.3 correction and §12.5) is your own summary of everything you established. Do not redo it.
- your patch table is at 149 sites, 136 written, `--check` green, flags check green.

The short version of where you got to, so you can orient fast:
1. Stages 0-2 patch the framebuffer to 800x480 and the playfield to 800x400. Verified by read-back, and the FRAME was corrupted — I looked at it.
2. You found the cause: an `imul` replacing a flag-neutral `lea` between a `cmp` and its `jcc`, at three sites, the first being the dirty-block marker. Plus a shroud writer holding its own pitch (`mov esi,0x280; sub esi,ebx`).
3. You then found seven more by sweeping for stride-SHAPED operands: a `add edx,0x28` grid step and six fog wraps at 648, the latter marked INFERRED.
4. You restaged: stage 1 is now the framebuffer pitch ALONE, whose pass condition is "pixel-identical to the control".
5. `frame-diff.py` + `test-widescreen.ps1` compare the playfield interior row by row, calibrated both ways (184/190 rows bad on the broken build; stage 0 arms pixel-identical).

**Then do what my other message in your inbox says: the machine is free and yours. Stage 1 first, stage 2 only if it passes.**

First duties: re-arm your inbox Monitor, read both messages, move them to read/.
