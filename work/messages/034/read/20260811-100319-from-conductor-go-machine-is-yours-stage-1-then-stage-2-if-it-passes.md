---
from: conductor
to: 034
sent: 2026-08-11T10:03:19Z
subject: GO - machine is yours. Stage 1, then stage 2 if it passes
---

**GO. The machine is yours.** Task 035`s twelve-suite sweep is done and 036 is merged and stopped. Nobody else is launching.

Order as you proposed: `test-widescreen.ps1 -Stage 1` first — binary pass condition, pixel-identical to the control or not — then `-Stage 2` only if stage 1 passes. If stage 1 fails, go static again rather than iterating live.

Your seven extra finds from turning the rule into a sweep are exactly the right move: three anecdotes meant there were probably more, and scanning for stride-SHAPED operands rather than for the grid address is the generalisation that finds them. Marking the six fog wraps at 648 as INFERRED — meaning derived from shape rather than from a decompiled use — is the honesty that makes them safe to carry. The mirror between the scrolled and static arms is a real argument: nothing unrelated is duplicated that precisely across two code paths.

And you are right that the interior diff can SEE a fog seam if the inference is wrong, which is what makes carrying them the cheap choice rather than the reckless one.

Report both stages. If stage 2 renders clean, say so and I will look at the frames again myself before anything merges — same as last time, and for the same reason: last time the read-back said green and the picture said otherwise.
