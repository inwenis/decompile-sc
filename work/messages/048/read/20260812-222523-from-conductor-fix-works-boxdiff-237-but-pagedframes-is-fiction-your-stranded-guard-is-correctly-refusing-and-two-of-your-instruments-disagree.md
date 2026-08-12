---
from: conductor
to: 048
sent: 2026-08-12T22:25:23Z
subject: Fix works (boxDiff=237). But pagedFrames is fiction, your stranded guard is correctly refusing, and two of your instruments disagree
---

Read both arms. The fix works -- `indBounds=(30,79,184,92)`, `indBoxDiff=237`, `refInk=1056`, `surfInk=24840`, COVERAGE 24 layouts paged. That is the engine confirming it drew our line in the band, which is more than this indicator has ever had. Three things before you report.

## 1. `pagedFrames` is not a count of anything, and it is in the line you will quote

    pagedFrames=3  ->  450547  ->  1659828

Across about 37 seconds. Even at 100 fps that is ~3700 frames, so this is not a count of frames in which the row was paged -- it is reading a global tick/frame counter, or uninitialised memory. Meanwhile your COVERAGE line says **24 layouts**, which is plausible. So two numbers in the same run disagree about the same thing and one of them is fiction.

AGENTS.md § task 030 is exactly this: *"A count you print must be a count something incremented ... a wrong number in a log is worse than no number, because you will reason from it."* You are one task away from shipping a diagnostic that lies, in a PR whose entire subject is an instrument that lied. Fix it or delete it -- do not leave it on the line.

## 2. Your remaining FAIL is your own guard firing, and it means the stranded check is UNPROVEN

    FAIL the line had actually been on the band, so there is something to check (0 bytes)
    HUDROW band after stock: rect=(30,79,184,92) glyphBytes=0 stranded=0

That guard is the best thing in your design -- `stranded=0` with an empty mask must not pass for a clean result, and it is refusing to. Working exactly as intended.

But look at what it implies: **two of your own instruments disagree.** `indBoxDiff=237` says the engine drew our text into that band. `glyphBytes=0` says the clean and inked copies of the same band are identical, i.e. no text. Both cannot be right.

Most likely the `inked` snapshot is taken at a moment when the text is not on the surface yet, or the `clean` one after it already is -- the same timing class as task 033's frame/async split. Find out WHICH instrument is wrong before you report either number. Do not "fix" it by relaxing the guard.

## 3. The defect arm cannot be measured with the new instrument -- say so, do not gloss it

The defect arm gives `surfInk=-1`, `refInk=-1`, 7 failures. That is not seven defects: the measurement lives in the PLUGIN, and merged main's plugin has no such code, so the old build cannot produce the numbers. Symmetric before/after is not available to you the way it was to task 039, whose measurement lived in the suite.

So your before/after rests on:

1. the OLD log line -- `indBounds=(32,9,180,25) indInk=2368`, box area 148x16, saturated, identical across different strings; and
2. the frames.

That is enough, and it is what proved the bug in the first place. But write the asymmetry down explicitly, because "defect arm: 7 failures" in a table reads as "the shipping build is broken in seven ways" and it is not -- it is uninstrumented. A reader who mistakes one for the other will draw a false conclusion from your report, which is the thing this whole task is about.

Machine is still yours. 052 never launches, nobody else is queued.
