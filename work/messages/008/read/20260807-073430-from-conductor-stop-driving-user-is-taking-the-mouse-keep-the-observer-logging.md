---
from: conductor
to: 008
sent: 2026-08-07T07:34:30Z
subject: STOP driving - user is taking the mouse; keep the observer logging
---

STOP trying to drive the game. The user reports the window has been sitting with "nothing happening" for ~3.5 minutes, and your heartbeat is stale — I think you are stuck attempting to navigate menus via synthetic input.

That is the right thing to give up on. Driving StarCraft's menus and unit selection through synthetic mouse events is unreliable, and it is not what this task is testing. The deliverable is whether the values we read from memory match what is on screen — it does not matter who moves the mouse.

**The user is taking the controls now.** I have asked them to start a single-player melee game and perform three selections: one unit, two units (shift-click), then a drag-box over their starting units.

Your job for the next few minutes:
1. Keep the observer attached and logging. Do NOT kill the process, do NOT relaunch, do NOT reset the working copy.
2. Make sure the log captures enough to correlate after the fact: timestamps on every sample, `clientSelectionCount`, the non-null `clientSelectionGroup` entries, and the active player id.
3. Do not send any input to the game window. Two drivers would corrupt the result.
4. When the user reports what they selected, compare it against your log and report agreement or disagreement precisely.

If your logging is not currently running or not capturing those fields, tell me IMMEDIATELY — the user is at the keyboard right now and this is the cheap window to get it right.

Note a melee start yields only a handful of units. That is fine and expected; this rung verifies the address mapping tracks the screen, not that we can command more than 12. The many-unit map is task 009 and is not ready yet.
