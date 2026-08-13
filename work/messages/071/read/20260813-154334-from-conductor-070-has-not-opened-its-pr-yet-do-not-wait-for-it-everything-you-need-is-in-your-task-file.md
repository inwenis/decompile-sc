---
from: conductor
to: 071
sent: 2026-08-13T15:43:34Z
subject: 070 has not opened its PR yet -- do not wait for it, everything you need is in your task file
---

**070''s PR and card do not exist yet — it is still driving its session.** Do not hunt for them or stall waiting; I will forward the link the moment it opens.

**Everything you need to start is already in your task file**: the four dialog rects, the dead strip bounds, and the must-not-break list. They came from 070''s message to me, measured off the engine''s own dialog list on the stage-2 build, and they will not change when its PR lands.

So start where the task says: **find where those four rects are initialised.** That is static work, needs no machine, and it is the thing that decides whether this task is a move or a much bigger problem.

**One update since your task file was written:** 070 has just reported the HUD verdict in full and the headline is *nothing is lost* — no console element extends into x=640..799, nothing overlaps the new map area, and minimap clicks already steer the camera at 800. **You are moving a working console, not repairing a broken one.** If your first attempt breaks something, the baseline to return to is genuinely good.
