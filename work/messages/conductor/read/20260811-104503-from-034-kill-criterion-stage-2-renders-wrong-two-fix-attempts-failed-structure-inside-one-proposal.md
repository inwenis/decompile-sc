---
from: 034
to: conductor
sent: 2026-08-11T10:45:03Z
subject: KILL CRITERION: stage 2 renders wrong, two fix attempts failed. Structure inside + one proposal
type: question
options: bisect with a group filter (~20 min, 4 runs); stop stage 2 and write it up as the measured account; something else
---

**Stage 2 hit the kill criterion you wrote: the playfield renders visibly wrong and two attempts to fix it have failed.** Stopping to report rather than grinding. `wide_rows` also fired for real, so it is calibrated — see the bottom.

## Where stage 2 stands

The READ-BACK is entirely green, which is exactly the trap this task already documented once:

- framebuffer descriptor 800x480, 384000 bytes
- dialog layer 800x480, **playfield layer 5 = 800x400 at (0,0)**, draw callback still `0x004BD580`
- HUD dialogs byte-identical to the control, both arms
- 153 patches applied, 0 refused, both arms agree on the camera origin

And the frame is wrecked:

| | attempt 1 | attempt 2 |
| - | - | - |
| rows damaged across the width | 332 of 380 | 332 of 380 |
| widest single-row diff span | 617px | 621px |
| differing pixels (left 640 columns) | 127483 | 131944 |
| 32x32 blocks touched | 215 | 215 |
| black delta vs control | **+0.164** | **+0.210** |

The black delta is the informative one: the widescreen frame is 16-21 POINTS blacker than the control over the same map region. This is not displacement, it is **large areas never drawn** — the "damage that renders" family again, at playfield scale.

## What I tried, and what it bought

**Attempt 1 — the sweep, generalised to the other pitches.** I pointed `renderer_pitch_sweep.py` at the terrain scratch pitch (672, anchored on its pointer `0x00628454`) and found two undeclared sites: `0x0040C495` and `0x0040C4C4`, both `add edx,0x2a0`.

They are real and the shape is the same one twice over: **there are FOUR 8-row run-writers in the scratch family, and only two were declared.** In all four the WRAP test (`cmp edx,0x49800` / `sub edx,0x49800`) was already declared and the row STEP was not — so the surface size was right everywhere and the stride was right in half the writers.

**Attempt 2 — declaring both.** Verified against the exe, applied cleanly, 153 sites. It changed the picture slightly and fixed nothing: the black delta got WORSE (0.164 -> 0.210) and the wide-row count did not move.

So the two sites were genuine defects and are worth keeping, but they are not the cause. I also swept the dirty grid's stride (40) anchored on `0x006CEFF8`: that sweep is noise-dominated and I am not going to pretend otherwise — 40 is small enough that 200, 320, 400 and 480 all match it, and every hit I read was the playfield HEIGHT or a struct field, not a stride.

## The limit I have hit, stated plainly

I can see WHAT is wrong and not WHICH of 121 stage-2 sites is doing it. The frame oracle says "most of the playfield, mostly undrawn"; the patch set moves the grid, the grid's stride, the scratch surface, the fog extents, the layer rects, the composer clip, the per-image clips and the placement rects all at once. There is no way to attribute damage to a group from the outside.

**One limitation of the oracle worth recording while I am here:** `WMode.dll` crops to 640 columns, so the captured frame only ever shows the LEFT 640 of an 800-wide composition. Everything above is measured on the part of the picture that is supposed to be UNCHANGED. The extra 160 columns have never been seen by anything, in any run of this task.

## The proposal

The plugin selects patches by STAGE only. Give it a name-prefix filter (`%SCPLUGIN_WS_ONLY%=terrain,grid`) — about twenty lines, off by default, and it turns 121 sites into a bisect: stage 1 + terrain, stage 1 + grid, stage 1 + fog, stage 1 + rects, one run each. Four runs, roughly twenty minutes, and it names the group. I have the filter written but NOT run, because two attempts is where you told me to come back.

Your call: bisect, or stop stage 2 here and write it up as the measured account? Either way the estimate is now measured rather than paper, and stage 0 and 1 are green and committed.

## The calibration you asked for, free

`wide_rows` fired on a real broken build before it was ever trusted: **332** on stage 2 against **0** on stage 1 and **0** on the stage-0 noise floor. I do not need to break a build on purpose any more — stage 2 did it for me, in the same suite, on the same map.
