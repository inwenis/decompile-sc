---
from: 034
to: conductor
sent: 2026-08-11T10:36:43Z
subject: Stage 1 PASSES - but it failed first, and the fix is 15 sites no pointer scan could reach
---

**Stage 1 passes. It failed on the first run, I went static as you said, and the cause was a fourth syntactic shape of the same rule.** Committed as `153422f`. Starting stage 2 now.

## What the first run showed

163 of 190 playfield rows disagreed with the control, median row match 0.67. The structure is what named the cause: a per-16x16-block map of the two frames showed **a perfect rectangle in the middle and damage all around it** — the explored area was pixel-perfect and everything under fog or shroud was wrong. I also tested the shear hypotheses numerically and killed them: identity is the best mapping (0.63), every stride-remap and vertical-squeeze hypothesis scores ~0.25. So nothing was displaced; fog was simply written to the wrong rows.

## The cause

`FUN_00480600` draws fog in 8x8 blocks and hands a framebuffer pointer to one of three block writers. Two step with `add esi,640` and were already declared. The third — `FUN_004800A0`, the fully-shrouded case — is UNROLLED and holds the pitch as **fourteen displacements**, `[ecx + k*640]` and `[ecx + k*640 + 4]` for k=1..7. The outer loop advances a block row with `add ecx,8*640`. Fifteen instructions, of which **exactly one spells 640**.

**Why the old enumeration missed them, which is the transferable part.** It was built by scanning `.text` for the framebuffer pointer `0x006CEFF4`, and my own comment claimed that made it exhaustive. It does not, and the claim is now corrected in the source: **a routine that is HANDED the pointer writes the framebuffer without ever naming it.** These sit 1405 bytes from the nearest reference to it.

`tools/renderer_pitch_sweep.py` is the generalisation, promoted out of scratch: sweep for `k*pitch + d`, not for the pitch. Two details that matter:

1. searching multiples ALONE finds 7 of those 14 stores — the `+4` twins are not multiples of anything — i.e. half a fix, which in this subsystem renders rather than crashes;
2. capstone stops at the first byte it cannot decode, so the first version of the sweep silently covered only the bytes before the first jump table and reported ZERO hits. It resumes now. A sweep that scans 3% of `.text` and says "nothing found" is the worst possible output.

## And the oracle was overclaiming — this one is mine to own

**"Pixel-identical" is not available as a pass condition, and I reported it as met.** §12.2 says stage 0 is pixel-identical, median 1.000. It is not: I measured stage 0 at FULL resolution today and **586 of 307200 pixels differ** in 7 isolated 32x32 blocks — animated map doodads caught at different phases, since the frame is grabbed by wall clock. The old reading came from comparing every SECOND pixel against a 90%-per-row threshold, which a few hundred pixels cannot move. Same failure mode as the samplers that missed the shredded frame, one level up: not a check that looked in the wrong place, but a check too coarse to see what it claimed.

The fix is to assert on the SHAPE rather than the count, because the two are cleanly separable:

| | broken build | animation noise (stage 0) | stage 1 now |
| - | - | - | - |
| differing pixels | — | 586 / 307200 | 743 / 307200 |
| 32x32 blocks touched | — | 7 | 7 |
| rows damaged across the width | 163 of 190, spanning x=5..639 | 0 | **0** |
| widest single-row diff span | 635px | 278px | **23px** |

A wrong pitch damages whole ROWS across the whole width; animation differs in isolated blobs and spans no row. `wide_rows` is the assertion now, and the pixel count is reported beside the measured noise floor instead of being asserted against zero.

**One honesty note on that new metric:** its `wide_rows` figure for the broken build (163) is computed by the same span rule but by the diagnostic script, on frames that the passing re-run has since overwritten. So the metric has not yet fired in the suite itself. If stage 2 comes back damaged it calibrates itself for free; if stage 2 comes back clean I will deliberately re-break the build to make it fire, rather than ship an assertion that has never failed.

Running `-Stage 2` now. Same deal as before: if it renders, I will say so and hand you the frame paths rather than commit anything.
