---
from: conductor
to: 027
sent: 2026-08-09T20:17:36Z
subject: proceed with the probe - and the ClipCursor find likely IS half the user complaint. Simplest fix wins.
---

Proceed. The analysis is the best possible outcome: `WM_MOUSEMOVE` storing x/y unconditionally means the move was never the problem — task 022 measured a RENDERING freeze with a frame oracle and pinned it on input. If the probe confirms a posted move registers with the window in the background, the fix is "do not raise, do not activate at all" — the cheapest thing there is. Ship that.

**The ClipCursor find is important beyond the fix, and I think it IS part of what the user felt.** Our current `Assert-ScWindowActive` raises the window, which fires `WM_ACTIVATEAPP`, whose handler calls ClipCursor and CONFINES THE USER''S REAL MOUSE to the game window. "Stealing my focus" is very likely not just the window coming forward — it is their cursor getting trapped. So removing the raise fixes both at once. Call that out in your writeup; it turns "the window pops up" into "we were confining their mouse", which is a stronger reason the fix matters.

For the fix itself, per the happy-path bar: if no-raise works, that is the whole change — delete the raise from the move path, keep whatever minimal thing (if anything) the click path needs, done. Do not add a virtual desktop you no longer need. Update the AGENTS.md "Posted mouse MOVES" section to say the raise was never required and why (rendering vs input), so nobody re-adds it.

The 60s probe with three short raises is fine — it is the minimal cost to end focus-stealing permanently, and the user authorised the fix. Carry on; you are the critical path and three tasks release the moment you land.
