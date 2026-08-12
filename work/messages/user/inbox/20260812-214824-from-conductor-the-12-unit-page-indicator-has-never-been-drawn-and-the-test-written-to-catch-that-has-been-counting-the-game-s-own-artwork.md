---
from: conductor
to: user
sent: 2026-08-12T21:48:24Z
subject: The >12-unit page indicator has never been drawn, and the test written to catch that has been counting the game's own artwork
---

Worth telling you before it is fixed, because it is a feature you have never seen work and were never told was broken.

**When you select more than 12 units, the HUD row is supposed to show a line like `36 units 13-24 (2/3)` so you know there are more pages. That line has never been drawn. Not once.**

Not "hard to read", not "behind the icons" — never on the screen at all. And the test that was written specifically to catch this class of bug has been passing the whole time.

## How it hid

Task 033 built the indicator, noticed it might not draw, and added an oracle: count the non-background bytes the engine left in the control's own box, and require that count to be above zero. Sound reasoning. Here is what it actually reads, from a run on the current build two hours ago:

    indicator="36 units  1-12  (1/3)"   indBounds=(32,9,180,25)  indInk=2368
    indicator="36 units  13-24  (2/3)"  indBounds=(32,9,180,25)  indInk=2368

The box is 148 x 16 = 2368. The ink count is 2368. Every single byte in it is non-background — and the number is identical for two different strings. If one pixel of our text were in there, two different strings could not produce the same count.

The box sits on top of the unit wireframes, whose artwork already fills it completely. So the assertion was counting the game's own pictures and reporting them as our text. It could never have failed.

## Why it happens at all

Same root cause as the bug you reported. The indicator is spliced at the HEAD of the dialog's child list, and the engine paints children head first — so it is painted, and then the wireframe buttons paint straight over it. The source comment claims the opposite. Task 039 found that exact misconception and fixed it for the group line you complained about; this file still has it.

The remedy is the one 039 already proved: put the line in the empty band below the icon row, and measure it as a **difference** against a copy of the same region without the text, not as a raw count. Worker 048 has the geometry worked out off existing logs without needing a single game run — the band is 13 pixels tall, the font is 11, and it is the same band the group line already uses successfully.

## The lesson is bigger than the bug

I have asked 048 to write this into the rulebook, because it is a new rule rather than another example of an old one:

> An ink count detects your text only over a region the engine leaves as background. Over a region the engine also paints, it saturates and goes blind — and it fails as a healthy-looking positive number, not as a zero.

The existing rule guards against `ink = 0` being mistaken for a working probe. It says nothing about saturation, which is the failure that actually happened, twice now, in this repo.

## Nothing for you to do

048 is holding — 051 has the machine for its save/load chain and I am not interleaving them. When 051 is done, 048 gets an uninterrupted block for two runs: one on the shipping build to photograph the defect, one on its fix. Both off-screen. You will not see either.
