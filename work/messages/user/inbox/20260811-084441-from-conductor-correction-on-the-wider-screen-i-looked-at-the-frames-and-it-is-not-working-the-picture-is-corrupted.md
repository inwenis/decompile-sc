---
from: conductor
to: user
sent: 2026-08-11T08:44:41Z
subject: correction on the wider screen: I looked at the frames and it is NOT working - the picture is corrupted
---

# Correcting what I told you an hour ago

I said the wider screen "renders" and that the only open question was whether the windowing helper carried it to your monitor. **I opened the two frames and that is wrong. The picture is broken.**

Side by side, same map, same moment:

- The **control** frame (feature off) is clean.
- The **widescreen** frame is shredded — the playfield is cut through by irregular horizontal black bands, terrain is displaced sideways in strips, the fog boundary is ragged instead of smooth, and the minimap area is black where the control shows terrain.

So it is not "the engine composes 800 columns and the helper crops to 640". The engine is composing a BROKEN 800-wide frame, and you are being shown the left 640 columns of something already wrong.

# Why the worker got it wrong, which matters more than the bug

It never looked. It measured three regions structurally — the HUD strip, the top edge, and the rightmost lit column — and all three came back essentially identical to the control, so it concluded "clean crop" and told me what I would see rather than checking.

Every one of those numbers is TRUE. The conclusion is false. The corruption is in the middle of the playfield, which is precisely the one area none of the three probes sampled. "98.9% of HUD pixels identical" is perfectly consistent with a wrecked playfield, because the HUD is not the playfield.

That is this project`s recurring failure in a new costume: a check that cannot fail. It is the seventh time, and it is the reason I insisted on seeing frames before merging anything.

# Where it actually stands

- The engine CAN be made to compose a wider frame — 126 patch sites applied, and the size really does change. That part is real.
- It does not yet compose a CORRECT wider frame.
- I have a specific suspect: a grid the engine uses to track which 16x16 blocks of the screen changed. It is sized for 640 wide, and last night`s survey flagged that it physically cannot be made bigger in place, because another live value sits immediately behind it in memory. If it is still 40 columns wide while the screen is 50 blocks wide, you would get exactly these bands.
- I have told the worker: no PR claiming this works, add a check that looks INSIDE the playfield and prove that check can fail, then chase the grid.

# Two things I am NOT doing without you

1. **The only presentation route that could actually put 800 columns on your monitor is true fullscreen**, which would switch your 4K desktop to 800x600. That **rearranges your desktop icons and does not put them back**. The worker stopped rather than do that unattended, which was the right call. If you want that tested, say so and I will run it — or hand you the command to run yourself.
2. Nothing merges on this until a frame looks right.

Sorry for the premature "it renders". It composes; it does not render correctly.
