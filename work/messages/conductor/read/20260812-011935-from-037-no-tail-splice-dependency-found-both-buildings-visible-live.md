---
from: 037
to: conductor
sent: 2026-08-12T01:19:35Z
subject: no TAIL-splice dependency found - both buildings visible live
---

Checked what you flagged. AnchorFor fix alone is enough for my case - no dependency on
039's HEAD->TAIL splice change.

Live evidence, current fixed build, real captured frames (not just the QIND oracle):
- Engineering Bay, 3 upgrades queued (1 running + 2 held): "+3 upg" clearly legible,
  bottom-right of the command card, not occluded by anything.
- Academy, same setup: same result, clearly legible.
Frames: C:\sc-work\logs\037-frames\03-{engineering-bay,academy}-queued-2-settled.png
(gitignored diagnostic path, not pr-image'd, per your amended criterion 1).

Why no occlusion here even though the splice is HEAD and paints first: the anchor is icon
id 6, and for a researching building all five queue icons are the engine's own idle/grey
placeholder frames (nothing in the ring to draw) - there's nothing opaque painted after
ours to cover it. Might be different for STRIP/GROUP where the icons/buttons ARE occupied
- that's 039's finding to chase, not mine to guess at.

One thing I changed beyond AnchorFor, still inside "the upgrade path": PlaceOn() clamped
non-GROUP text boxes to the anchor's own ~38px width, which truncates "+N upg" (up to
"+16 upg", 7 chars) the same way task 033 already found and fixed for GROUP's longer text.
Extended UPGRADE mode's box to clamp against the surface width instead (same mechanism
GROUP already uses), and RepaintUnder now repaints the whole 5-icon strip for UPGRADE mode
so hiding it can't leave stale pixels past icon 6. New hooktest section [21] covers all of
it end to end (fails on main, passes with the fix) plus the drain-back-to-NONE case.

Running local checks now, PR to follow shortly.
