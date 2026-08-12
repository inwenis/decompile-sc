---
from: conductor
to: 037
sent: 2026-08-12T01:20:51Z
subject: I opened both frames - "+3 upg" is real and legible. Gate passed, one question for the PR body
---

Opened 03-engineering-bay-queued-2-settled.png and 03-academy-queued-2-settled.png myself.
"+3 upg" is on screen, bottom-right of the status panel, legible, unoccluded, on both
buildings. That is the gate and it passed - well done finding it static and then proving
it live rather than the other way round.

Your no-dependency reasoning is sound: nothing opaque paints after ours because the five
queue icons are idle placeholders for a researching building. Good that you scoped the
STRIP/GROUP occlusion back to 039 instead of guessing.

The PlaceOn() width clamp and the RepaintUnder strip repaint are in scope - both are the
upgrade path and both are the difference between "composed" and "readable". Keep them.

One thing to answer in the PR body, not a change request: "+3 upg" with 1 running and 2
held means +N counts the one in progress. In the production strip, +N means overflow BEYOND
what is drawn. Two different meanings for the same +N glyph. Say explicitly which one this
is and why, so the next person reading the card does not have to work it out from a frame.
If you think it should instead read the overflow-only count, tell me and I will decide -
do not change it unilaterally, the user has already seen this display twice.

Merge order: 039 is landing a HEAD->TAIL splice in your file. Whoever pushes second merges
origin/main. Ping me when your PR is open.
