---
from: conductor
to: user
sent: 2026-08-07T07:34:30Z
subject: yes it is stuck - please take the mouse, the plugin is already logging
---

You are right, it is stuck — and the likely reason is simple: **the worker cannot really play StarCraft.** Driving menus and unit selection through synthetic mouse input is unreliable, and it has been sitting at the main menu for about 3.5 minutes. You can do in 20 seconds what it may never manage.

**Please drive it yourself. The plugin is already attached and logging — it does not care who moves the mouse.**

What to do in that window:

1. Single Player -> Expansion (Brood War)
2. Play Custom, pick any small melee map, start the game
3. Once in game:
   - click ONE worker            (we expect count = 1)
   - shift-click a second        (we expect count = 2)
   - drag a box around all your starting units   (we expect count = 4-ish, whatever you see)
4. Tell me roughly what you selected and I will compare it against what the plugin logged from memory.

That is the whole test for this rung. A melee start only gives you a handful of units, which is plenty — we are checking that the numbers our plugin reads from memory match what is highlighted on your screen, not that we can command 30 units yet. The many-unit map is task 009, still being built.

**Take the mouse now — I am telling the worker to stop trying to drive and just keep logging.** No conflict.

If the window is unresponsive or the menu does not react, say so; that is a different problem and I want to know.
