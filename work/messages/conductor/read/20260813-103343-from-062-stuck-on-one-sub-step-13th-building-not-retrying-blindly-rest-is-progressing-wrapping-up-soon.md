---
from: 062
to: conductor
sent: 2026-08-13T10:33:43Z
subject: Stuck on ONE sub-step (13th building), not retrying blindly -- rest is progressing, wrapping up soon
---

## Finding: single drag caps at 12/13 buildings; shift-click-add to reach 13 doesn't compose via this harness

Verified clean and reproducible, no contamination (Get-ScCardState's PRODFAN
diagnostic, non-destructive, minerals=8000/totalQueued=0 confirms no side effects):

- One drag-box, any single camera position: **exactly 12 of 13 select**, every time
  (footprint overlap sweeps in one row beyond the strict visible line, but the
  13-building block is 480px tall vs a ~340px playable viewport -- math confirms
  one drag physically cannot reach all 4 rows from any single camera position;
  empirically confirmed both at the default spawn view and at a centred view).
- Shift-click on the 13th (the lone building in row 4) after that drag: **stays at
  12**, tested 3 times, clean coordinates, clean state each time.
- Shift-click DOES work in the simplest case (click A, shift-click B -> 2, verified).
- The failure is consistent with this repo's own documented KNOWN LIMIT in
  drive-game.ps1 (posted keyboard messages don't update GetKeyState; Send-ScClick
  -Shift works by also setting MK_SHIFT in the mouse wParam, and that "is an
  empirical question about this binary" per the same comment) -- it may simply be
  that THIS particular composition (drag-select, then shift-add) reads real
  keyboard state on this binary's code path while a bare click's shift-add does not.
  I have no evidence this fails for a real human with a real keyboard -- shift-click-
  to-add-one-more after a box-select is completely standard SC1/RTS behaviour.

So: I can prove 12 cleanly. I could not mechanically prove reaching 13 in one
selection, despite real, repeated, clean attempts -- not a coordinate mistake, not
contamination, a genuine composition failure specific to synthetic input.

Options, as I see them:
1. Card says "drag selects 12; Shift+click the 13th to reach 13" -- true SC1 UX,
   matches AC4's spirit (I walked everything I *can* walk with this tooling) but
   not its letter (I did not personally see it reach 13).
2. Scope step 5 down to "select the visible 12" -- loses the actual "one past
   twelve" proof issue #44 exists for; the map's most distinctive feature goes
   untested by me.
3. I keep trying (diminishing returns after 3 clean attempts) or try a genuinely
   different technique (e.g. control groups) if you'd rather I spend more time.

Continuing with steps 2-6 (single-building queue, cancel, group queue, save/load)
in the meantime -- none of them depend on resolving this.
