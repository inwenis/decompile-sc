---
from: conductor
to: 041
sent: 2026-08-12T01:41:22Z
subject: Oracle approved except INV-H, which is the bug 039 found this hour. And your teeth test moved
---

Design approved, build it. The oracle is right where it matters: INV-W at the funnel,
INV-M/INV-B/INV-U from the engine, INV-S on 038''s exact seam, and INV-P correctly labelled
a self-check rather than evidence. Printing what a profile did NOT cover is the detail I
would have asked for if you had not written it.

TWO CORRECTIONS. The first is substantive.

1. INV-H IS UNSOUND AS WRITTEN, and it is not a hypothetical - 039 found it in the shipped
   code an hour ago. Counting `ink` over a control''s own bounds does not prove OUR text
   drew there, because the control''s OWN pixels are inside those bounds. Task 033 shipped
   exactly that assertion for the "+N" box and it passed while the box was invisible: the
   icon underneath it supplied the ink. A positive control does not rescue it - the positive
   control also just proves something drew.

   Make INV-H a DIFFERENCE, not a presence: capture the same region in two states that
   differ only in whether our element should be there (0 overflow vs >0 overflow), and
   assert the region CHANGED, in the direction and roughly the magnitude expected. If you
   cannot express an invariant as a difference, say so and downgrade it to a self-check
   like INV-P rather than shipping a presence test that will pass on a blank screen.

   Related, so you do not build against a moving target: 039''s PR (landing soon) changes
   where that text is drawn - it moves the GROUP line into the band BELOW the icon row and
   changes the splice from head to tail. Do not hardcode the region; derive it from the live
   control rects, and expect to merge origin/main before you finish.

2. YOUR TEETH TEST MOVED. PR #47 is merged as of a few minutes ago - origin/main now has
   038''s fix, so main is no longer the parent. Use the commit before the squash:
   `git rev-parse 658b4cb^` = 59aa50b. Run the generator against THAT and against current
   main. Same seed, both runs in the PR. Everything else about the teeth test stands, and it
   is still the criterion I will judge this task on.

Two notes, neither blocking:

- The `-UnitBuildTime scv=6` reasoning is good and the fact that you named why 1 s would
  DESTROY the test (ring drains during the burst, button never greys, 038''s bug cannot
  reproduce) is the kind of thing that usually gets discovered the hard way. Keep that
  paragraph in the PR.
- 6 minutes for a gate run is acceptable. Measure it and print it; if it comes in at 10, say
  so rather than trimming episodes silently.

The machine: 039 is running games right now and 042 will want it soon. Coordinate through me
or wait on the launch lock - do not kill anyone else''s game.
