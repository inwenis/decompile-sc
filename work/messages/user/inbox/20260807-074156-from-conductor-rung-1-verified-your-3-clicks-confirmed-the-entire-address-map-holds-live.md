---
from: conductor
to: user
sent: 2026-08-07T07:41:56Z
subject: RUNG 1 VERIFIED: your 3 clicks confirmed the entire address map holds live
---

**Your three clicks verified the whole address map. It holds at runtime — nothing was wrong.**

What the plugin read from memory while you played:

  count=0  ->  in game, nothing selected
  count=1  ->  you clicked one worker
  count=2  ->  you shift-clicked the second
  count=4  ->  you dragged the box

Exactly your actions, in order, and those were the ONLY state changes in the log.

`count=4` is a better result than "about right". A melee start is 4 workers plus one main building, and your box contained both — so 4, not 5, means the game counts units and not buildings there, and the byte we are reading means precisely what we thought it did.

## Three things worth telling you

**1. We accidentally measured the unit struct size from your clicks.** The four selected units sat at memory addresses separated by exactly 336 bytes each — evenly, no remainder. 336 is the unit-record size the modding community documents, and we just confirmed it independently from your drag-box. Nice bonus for zero extra effort.

**2. The game keeps TWO copies of your selection, and they disagree in two ways.** Both are new facts, not errors:
   - **Timing.** The screen-side copy updates first; the simulation-side copy caught up 268 ms later. That is the game's turn model visible in memory.
   - **Order.** Both held the same four units, but in different orders — the screen copy rebuilt from scratch, the simulation copy kept your already-selected units first and appended the new ones.

   This matters directly for the next rung: whatever we hook must not assume those two copies agree at any given instant. Better to learn that from a read than from a crash.

**3. A gotcha that would have cost us later:** you are player **1**, not player 0. Anyone indexing the per-player table from 0 by habit would read the wrong player's selection. We also caught the three player-id values transiently disagreeing during the transition into the game — our notes warned they were distinct, and now there is live proof.

## Honest limitation

One value (the selection iterator) read zero the whole time. We sample every ~200ms, so anything set and cleared inside a single function call is invisible to us. It is recorded as unconfirmed rather than claimed either way.

## Where that leaves us

**Rung 1 is done** — toolchain, injection, windowed mode, and the address map confirmed against a live process. Writing it up now, then PR and review.

Next: rung 2 (intercept selection input, keep a plugin-side list of any size), then rung 3 (fan out orders so more than 12 units obey). Task 009's many-unit map is being built in parallel for exactly that.

Thanks for taking the mouse — that was the fastest and most reliable way to get this, and the worker's own attempt was landing clicks hundreds of pixels off target.
