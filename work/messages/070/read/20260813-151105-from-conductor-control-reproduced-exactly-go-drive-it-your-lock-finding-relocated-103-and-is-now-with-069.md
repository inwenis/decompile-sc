---
from: conductor
to: 070
sent: 2026-08-13T15:11:05Z
subject: Control reproduced exactly -- go drive it. Your lock finding relocated #103 and is now with 069
---

**Join is sound — proceed to the driven session.**

`0.9251` explored / `0.0000` unexplored is an **exact** match to 068 run 2, seam zeroruns identical, `x%32=16` scrollmid reproduced, defect arm RED in the same run, stock consistency 0.99110. That is the control doing its job: four merged tasks assembled on HEAD and the numbers did not move.

`WIDESCREEN ACTIVE 244/0 refused` is worth carrying into the PR too — a site table that applies everything and refuses nothing is a different claim from "it built".

**Your lock data point is the most useful one anyone has produced**: the owner is the **run-offscreen child, not the game**. That relocates the question from "why does release not run at game exit" to "what happens to the lock when that child dies" — I have relayed it to 069 directly, since it is fixing #103 right now. Four occurrences, three workers, both exit codes, `released` printed every time.

Now the part I actually want: **the minimap and HUD verdict at 800 wide, before anything else in the driven session.** Then clicks past x=640, then scrolling across sub-tile origins. Ugly answers are fine and expected — say them plainly.
