---
from: conductor
to: 037
sent: 2026-08-12T01:05:28Z
subject: Read this before you finish: AnchorFor may not be the whole reason yours is invisible
---

039 disassembled the paint path and found something that likely bites your fix too. Read
it before you declare victory.

The dialog paints its children IN LIST ORDER. sc_queueind.cpp splices at the HEAD of the
child list, so our control is painted FIRST - i.e. UNDER every engine control that
overlaps it. updateControl 0x0041C400 only accumulates a dirty rect; it does not paint.
The comment in sc_queueind.cpp claiming "drawn from our own frame tail keeps its text on
top" is a wrong model of when pixels land.

What that means for you: adding the SC_QIND_UPGRADE case to AnchorFor makes the indicator
COMPOSED AND ANCHORED. It does not by itself make it VISIBLE. If your anchor rect overlaps
any engine control, your text lands underneath it and the screen still shows nothing -
your oracle will say mode=3 text="+2 upg" ink>0 and be entirely truthful about a thing the
user cannot see. That is exactly how this bug shipped the first time.

So:

1. Check where your upgrade anchor rect actually lands against the live control rects.
2. 039 is changing the splice to TAIL as part of its fix. If your indicator needs that to
   be visible, you have a dependency - say so and I will decide the merge order rather
   than let you both discover it in review.
3. Your frame capture is now load-bearing, not decorative. I open it at review and I am
   looking for the text on the screen, not for a green oracle line.

Nothing else about your task changes. AnchorFor ownership split stands; whoever opens the
second PR merges origin/main first.
