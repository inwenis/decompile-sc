---
from: conductor
to: user
sent: 2026-08-11T08:25:35Z
subject: THE WIDER SCREEN RENDERS - 800x400 playfield in a live game. One thing left to confirm
---

# It works — with one question left

Task 034 has the playfield running at **800x400 instead of 640x400** in a live game, with the HUD untouched. Read out of the running engine, both arms side by side:

| | normal | widescreen |
| --- | --- | --- |
| framebuffer | 640x480 | **800x480** |
| playfield layer | 640x400 | **800x400** |
| HUD dialog positions | ... | **byte-identical** |

The game loads a map, plays, and closes cleanly. 17/17 checks pass. 126 instruction rewrites applied, none refused.

**It chose 800x480 rather than 800x600, and the reasoning is better than the brief I gave it:** keeping the height at 480 leaves the console exactly where it is and leaves every height-related constant untouched, so the empty space is a single 160x80 block beside the console instead of an L-shape around it. And 5:3 is closer to your monitor than 4:3. Other sizes are a re-run, not a rewrite.

# The one thing not yet known

The engine composes 800 pixels wide. What the windowing helper then PUTS ON YOUR SCREEN cannot be read from memory — and the window it creates is the same size in both arms. So either it is scaling the full 800 into that window (works, window just small) or it is showing 640 of the 800 columns (invisible).

I have asked for a frame from each arm written to a local diagnostic path — not committed, since game frames reproduce artwork and that is a hard rule here — and I will open them myself and tell you. One look settles it.

# Honest note on cost

I gave 034 permission to stop if the job exceeded roughly a dozen patch sites beyond the known list. It hit **139 sites** — an order of magnitude past that — and told me so in the same message as the success rather than burying it. I accepted it because it did not grind: it finished in one run, and the count IS the measurement I wanted.

Why last night`s estimate was low is worth knowing: about a quarter of the sites are invisible to the search technique that produced it. The compiler had built `x * 640` as a shift-and-add pair, and a texture width as three shifts summed — arithmetic that never contains the number 640 anywhere. Anything estimated by searching for constants in this binary is now known to undercount.

Regression run and PR next. Nothing merges until I have looked at those frames.
