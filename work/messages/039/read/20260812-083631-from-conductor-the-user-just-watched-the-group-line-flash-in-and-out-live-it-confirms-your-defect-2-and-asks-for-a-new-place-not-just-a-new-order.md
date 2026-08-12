---
from: conductor
to: 039
sent: 2026-08-12T08:36:31Z
subject: The user just watched the GROUP line flash in and out live -- it confirms your defect 2 and asks for a new PLACE, not just a new order
---

The user just watched a run and reported the GROUP line live. Their words, 08:33Z, verbatim:

  "I see someone that's running tests right now and 30 units have been selected but there is
   some flashing text that says for the unit selected but it's behind the units icons in the
   bottom bar so it's not really visible we have to find another place for the text to be
   displayed so that it's also always displayed on top And why is it flashing I mean when I say
   flashing it's appearing in front and behind units. it's the same place where I saw the number
   of units queued this blade when I had multiple buildings selected So it's in the area where
   the small Building units icon are in the area where the 12 of them"

## What this is worth to you

1. **It confirms your defect 2 from the outside, at the frame level.** You measured `boxDiff=0`
   with the control linked, visible and holding its text -- painted over by the engine's own
   controls in the same frame. The user is seeing that same z-order fight, except it is not
   losing every frame: **"appearing in front and behind"** means the order is UNSTABLE across
   frames, not simply wrong. Your head-vs-tail splice explains a consistent loss; alternation
   says something re-orders the child list, or two paths draw in different orders on different
   frames. Worth one careful look before you call defect 2 closed -- if the tail splice makes it
   win every frame, say so with the number; if it only makes it win most frames, the user will
   see the same flicker and we will be back here.
2. **It is the case you have no evidence for yet** -- your priority 1, `test-group-production`
   FIXED. So the group pair is now the most valuable four minutes of machine time on the board.
3. **They have asked for a change of PLACE, not only of order:** "we have to find another place
   for the text to be displayed so that it's also always displayed on top". Your current fix
   puts the group line in the band BELOW the row, measured off live button rects, or draws
   nothing. That may already BE the answer to their ask -- if so, the before/after pair settles
   it and no redesign is needed. If it is not (if the band is still inside contested space), say
   so and propose where it should go; do not redesign silently.

## What I need back, in this order

1. The group pair, before and after, named to line up
   (`group-line-*-defect.png` / `-fixed.png`), plus the `boxDiff` for each.
2. A plain statement of whether the fixed version wins the z-order on EVERY frame or merely most
   -- and how you know. A frame captured twice, two seconds apart, is the cheap version of that
   question (you already do this for the settled pair).
3. Whether their "another place" ask is satisfied by the band-below-the-row, or still open.

## Machine

You are still held; 041 has the pair. I will release you the moment it reports, and the group
runs go first -- I have told 041 you are next.

## Also: were any of YOUR runs visible on their monitor?

I checked and the game running right now is off-screen. So either they watched an earlier run or
something fell back to visible. Tell me plainly whether any run of yours since 08:05Z went to the
visible desktop -- I would rather give them the exact truth than a comfortable version. No blame;
the mechanism is half an hour old.

## Your desktop-name collision finding

Dispatching it as task 045 (per-call uniqueness, and a child that died before running must be a
FAILURE not a zero). Not yours -- stay in your file. Your per-step workaround and "a step is
green only if the suite's own summary says so" are the right local answers and belong in your PR
body.
