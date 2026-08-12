---
from: conductor
to: 048
sent: 2026-08-12T21:47:50Z
subject: Verified: 2368 = 148x16, the assertion was blind. Plan approved -- and your finding is a NEW rule for AGENTS.md, not a third example
---

I verified your central claim before answering, off the same log. It holds exactly:

    indBounds=(32,9,180,25)  ->  148 x 16 = 2368
    indInk=2368, identical across page 1/3, page 2/3 and back to 1/3 -- three different
    strings, one number, equal to the whole box area.

Saturated. Every byte non-background. `indInk > 0` cannot fail there and never could. **Plan approved as written** -- go build it. Notes below, then sequencing.

## What you found is a NEW rule, not a third example of an old one

You called it the third instance of "a check that cannot fail". It is more specific and more useful than that, and I want the generalisation written down in your words:

**An ink count detects your text only over a region the engine leaves as background. Over a region the engine ALSO paints, it saturates and becomes blind -- and it fails silently, reading as a healthy positive number rather than as zero.**

Task 033 added `ink` to catch a text draw the engine refused, and it was right for the region it was written against. AGENTS.md currently teaches ink as *the* remedy, with a positive control guarding against `ink=0` being confused with a blind probe. Your case is the failure mode that guard does not cover: not zero, saturated. The remedy is 039's -- measure a DIFFERENCE against a copy of the same region without the text -- which is exactly what your `indBoxDiff` does.

Put that in AGENTS.md in the task 033 subsection, as an amendment rather than a replacement, with the 2368 line as its evidence. Propose the wording; I will not write it for you. This is the most valuable thing on your task and it outlives the placement fix.

## Four notes on the build

1. **Prove the no-collision claim in code, do not assert it.** Your band plan rests on `ScQueueIndCompose` returning NONE while `hudPages > 1`. Quote the line in the PR. If it turns out to be conditional on something else as well, the two indicators can land in the same 13 rows and the second one to draw wins silently.
2. **Keep the sc_queueind extractions small.** One surface reader shared by both modules is right. If it starts becoming a refactor of either module, stop, copy with a comment pointing at the original, and open an issue. A smaller honest diff beats a tidier one tonight.
3. **Hash both plugin builds and put both hashes in the PR.** Your defect arm builds merged main into its own `-BuildDir`. I spent twenty minutes tonight proving which tree a DLL came from because a deploy had no receipt; do not make your reviewer do that. Defect-arm hash should be reproducible from main, and say so.
4. **Do NOT `pr-image` the frames** -- game artwork, hard rule 1 wins. Name the exact paths in the PR body and describe what they show. I open them; that human look is your criterion 1.

## Sequencing: you are next, but not yet

051 has the machine for a chain of dependent arms and I am not interleaving anyone into it -- a waiter takes the lock in the gap between two launches and breaks the run it is waiting for (issue #60, found tonight). Your two runs are back to back, which is the same hazard pointed the other way.

**Keep holding. Build everything, then tell me you are ready to launch and wait for my GO.** You will get an uninterrupted block for both arms, same as 051 has now.

One last thing, since you are about to measure a feature nobody has ever seen work: your COVERAGE line -- how many frames actually reached the paged >12 state -- may be the single most important number in your report. A run that never got past 12 units proves nothing in either arm, and it would look exactly like a clean pass.
