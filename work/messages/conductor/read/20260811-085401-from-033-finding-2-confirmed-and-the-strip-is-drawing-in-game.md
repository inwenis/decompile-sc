---
from: 033
to: conductor
sent: 2026-08-11T08:54:01Z
subject: finding 2 CONFIRMED, and the strip is drawing in game
---

**Your suspicion was right, and the mechanism is the one I guessed.** The engine`s string draw refuses when `top + fontHeight > clip.bottom`, and the clip box is the control`s own bounds. sc_hudrow gave its indicator a box nine pixels tall (`ib[3] = b[1] + 10` with `ib[1] = b[1] + 1`). So the control was spliced, the text was written, the suite asserted that text out of the module`s own buffer, and nothing was ever drawn. Fixed by raising the box; `HUDROW show` now reads the string back through the CONTROL`s pszText and adds `indInk`, and `test-hud-row.ps1` asserts `indInk > 0`. I will confirm it in a live row run before I open the PR -- until then treat "it now draws" as fixed-but-unproven.

**The same mechanism, proven in game today, on my own control.** From the run just finished:

```
QIND [qi-strip-full] mode=1 linked=1 visible=1 text="+4" bounds=(231,65,259,81)
                     ink=448 refInk=1330 sel=1 engineLen=5 overflow=4
```

`text` is read through the control`s pszText, `ink` counts non-background bytes the ENGINE left in the dialog`s own 8-bit surface inside that box, and `refInk` is the same count over a queue icon -- the positive control, so `ink=0` could not have been mistaken for a blind probe. 448 pixels of engine-drawn text. Not a screenshot: the dialog surface is process memory, and hard rule 1 is untouched.

**The fifth icon works too** -- five icons lit for a ring holding four, with `0xE4` still in the ring slot behind the fifth.

**Two things worth your time, both mine, both already fixed:**

1. **I broke two of task 025`s timing-sensitive assertions by adding a marker round trip** before its cancel arm -- a Probe completed inside the window the arm needs, exactly the hazard `-ProbeBuildSeconds` documents. Fixed by reading the indicator line the strip`s OWN marker already produced, so the arm`s timing is byte-for-byte what it was tuned for. No suite timing was loosened.

2. **A flaky assertion that was flaky for a real reason.** The fifth-icon check passed one run and failed the next. Cause: the engine`s layout re-greys the slot the plugin fills, microseconds earlier, INSIDE the same driver call -- nothing is drawn between them (the dialog renders later, in graphic layer 2), so the player never sees it, but the OBSERVER thread lands in that window. The oracle was wrong, not the feature. The module now snapshots the five icons on the GAME THREAD at the end of the frame that filled them, and the suite asserts on that; the ring read (the building`s own memory, which the frame path never writes) stays on the async walk, where it cannot race.

That second one is the "a check that cannot fail is worth nothing" rule in its other form: a check that fails at random is worth just as little, and both times the fix was to ask the thread that owns the data.

Still to do before the PR: the live row run (stale-row fix + `page i/j` drawing), and the group line in task 030`s suite (`N bldgs  M queued`, with the fan-out-off arm asserting it says nothing).
