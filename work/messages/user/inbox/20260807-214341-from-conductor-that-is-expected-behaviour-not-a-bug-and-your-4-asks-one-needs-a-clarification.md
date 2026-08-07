---
from: conductor
to: user
sent: 2026-08-07T21:43:41Z
subject: that is expected behaviour, not a bug - and your 4 asks, one needs a clarification
---

**That is the expected behaviour, not a bug — and it is good news.** More units moved, and the extra ones carried no selection circles. That is exactly the signature this design predicts: fan-out changes what is *commanded*, not what is *displayed as selected*. It is also the same signature the two closed-source 1.16.1 tools we found were described as having.

So run B did work. I have added your fuller wording to the merged PR so the record is not rosier than reality.

## Your four asks, and how I read them

1. **Selection circles on the extra units** — the visual half. This is candidate #3 from our research: widen the CLIENT-side selection state and the HUD, leaving the simulation cap alone. Cutting it next.
2. **"make command work for all selected"** — I want to check what you mean before I scope it. Either (a) more ORDER TYPES work, not just move/right-click — attack, patrol, hold, stop, ability casts; or (b) something you saw where not every unit obeyed. If it is (b), that is a bug and I want it now, not later. Tell me which.
3. **More units in the bottom row** — same family as 1, and the harder part of it: the portrait row is a fixed 12-slot dialog, so this is layout work as well as data. Naturally a stage after the circles.
4. **StarCraft Remastered** — flagging a real risk before we plan anything. Remastered is Battle.net-connected and has anti-cheat. Everything we have done so far is safe because 1.16.1 is offline with nothing watching. Injecting into Remastered is a different risk profile, and the plausible cost is **your Blizzard account**, not a crashed game. I am not refusing — it is your machine and your copy — but I want that stated before it is queued rather than discovered afterwards. There is also almost no public reverse-engineering for it, so the address map we built does not transfer.

## Order I would suggest

  next   selection circles on the extra units       (visual half, stage 1)
  then   whichever answer you give for item 2
  then   the bottom portrait row                    (visual half, stage 2)
  later  Remastered, with the risk discussed first

Starting item 1 now unless you redirect. Answer item 2 whenever — if it is a bug, say so and it jumps the queue.
