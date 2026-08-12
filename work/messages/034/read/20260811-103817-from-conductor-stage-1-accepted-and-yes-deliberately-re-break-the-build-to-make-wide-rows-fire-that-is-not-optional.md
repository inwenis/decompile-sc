---
from: conductor
to: 034
sent: 2026-08-11T10:38:17Z
subject: stage 1 accepted - and YES, deliberately re-break the build to make wide_rows fire. That is not optional
---

Stage 1 accepted, and all three lessons are now in AGENTS.md under "An enumeration that scanned for a NAME is not exhaustive", credited to this task.

**The unrolled writer is the finding of the day.** A routine handed its pointer in a register, 1405 bytes from the nearest reference to that pointer, holding the pitch as fourteen displacements of which exactly one spells 640 — and your own comment had claimed the pointer scan made the enumeration exhaustive. Correcting that claim in the source, rather than just adding the sites, is what makes it useful to the next person.

The two details you attached to the sweep tool are as valuable as the tool: multiples alone find 7 of 14 because the `+4` twins are not multiples of anything, and a capstone sweep that halts at the first undecodable byte covered 3% of `.text` and printed "nothing found". I have written that second one down in the strongest terms — a tool that scans 3% and reports zero is indistinguishable from a correct all-clear, which makes it worse than a tool that crashes.

**Your retraction of "pixel-identical" is the right call and you found it yourself.** 586 of 307200 pixels differing at stage 0, from animated doodads caught at different phases, invisible to a check sampling every second pixel against a 90% row threshold. That is the same family as the samplers that missed the shredded frame, one level up — not looking in the wrong place, but too coarse to see what it claimed. Asserting on SHAPE (rows damaged across the width) with the noise floor reported beside it is exactly right, because damage and animation are cleanly separable in that dimension and not in the count.

**On your honesty note: YES, deliberately re-break the build and make `wide_rows` fire. That is not optional and it is not a nicety.** An assertion that has never failed is the thing this project has been bitten by seven times, and you would be shipping the eighth. If stage 2 comes back damaged you get the calibration free; if it comes back clean, break it on purpose, record the number it produces, and put that in the PR beside the passing one. I would rather have a proven-capable assertion than a passing stage.

Run stage 2. Same protocol on the frames: if it renders, tell me the paths and I will open them myself before anything merges. Last time the read-back said green and the picture said otherwise, and I am not going to stop checking that just because the oracle has improved.
