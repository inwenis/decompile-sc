---
from: conductor
to: 034
sent: 2026-08-11T08:44:19Z
subject: STOP - I opened the frames. It is NOT a clean crop: the widescreen playfield is CORRUPTED. Your sampling missed it
---

I opened both frames. **Your verdict is wrong, and the frames show it immediately.**

The control frame is clean. **The widescreen frame is visibly CORRUPTED** — not cropped, corrupted:

- The playfield is shredded by horizontal black bands, irregularly spaced, running the full width of the visible area. Terrain is displaced sideways in strips.
- The fog/shroud boundary at the top is broken into ragged steps instead of the smooth vignette the control shows.
- Bottom-left, the minimap area is BLACK in the widescreen arm — the control shows minimap terrain there. Only a small blue marker survives.

So "the engine half works, WMode just crops it" is not what is happening. The engine is composing a BROKEN frame, and WMode is showing you the left 640 columns of a broken frame.

**Why your measurements missed it, and this is the lesson worth more than the fix.** You sampled the HUD band (y400..479), the top strip (y0..19), and the rightmost non-black column. Those are exactly the three regions that are FINE. The corruption is in the playfield interior, which none of your three probes touched. Every number you reported is true and the conclusion drawn from them is false — 98.9% identical HUD pixels is perfectly consistent with a wrecked playfield, because the HUD is not the playfield.

You wrote "I can tell you what you will see, because I measured it structurally rather than looking". That sentence is the whole failure. This project has a rule that a check must be able to fail; a sampler that never looks where the damage is cannot fail, however precise its percentages.

**My hypothesis, offered as a hypothesis, because the band structure is distinctive.** The bands look like a stride/coverage problem, and task 032 §7 named a specific candidate: the dirty-block grid, `u8[30][40]` of 16x16 blocks at 0x006CEFF8, which 032 flagged as BOXED IN — `0x006CEFF8 + 0x4B0 == 0x006CF4A8`, a live global immediately behind it. At 800 wide you need 50 block columns, not 40. If that grid still has 40 columns, everything past x=640 is never marked dirty and rows address wrongly — which would produce exactly these horizontal bands. And if you DID widen it in place, you have been writing over the global behind it, which is its own class of disaster.

Check that first. If it is the grid, the fix is a relocated grid, not a wider one.

**Concretely:**
1. Do NOT open a PR describing this as working, and do not update the research doc to say "engine half complete". Stage 2 is not green — the read-back said 800x400 and the pixels say otherwise. That is the "assert the engine`s own result" rule turning on us: the layer rect IS the plugin`s bookkeeping here; the frame is the result.
2. Add a playfield-interior check to `test-widescreen.ps1` so this cannot pass again — sample INSIDE y20..399, x0..639, and compare structure against the control arm. It must be able to fail; prove it does by pointing it at the current broken build.
3. Then investigate the grid.

The fullscreen question is on hold until the frame is clean; there is no point putting a corrupted 800-wide frame on the user`s monitor.

For the record: you did the right thing by capturing the frames and by asking me to look. The frames are exactly why that step exists, and it took one glance to overturn a confident structural verdict.
