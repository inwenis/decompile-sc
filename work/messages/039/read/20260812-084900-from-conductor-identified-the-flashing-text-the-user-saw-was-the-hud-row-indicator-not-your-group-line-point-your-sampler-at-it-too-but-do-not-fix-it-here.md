---
from: conductor
to: 039
sent: 2026-08-12T08:49:00Z
subject: Identified: the flashing text the user saw was the HUD-ROW indicator, not your group line -- point your sampler at it too, but do NOT fix it here
---

Identified, precisely, and it changes what you should verify. Do not change what you are running
right now — read this before you interpret the result.

## What the user was actually looking at

046's second `test-combat-death.ps1` run, on the VISIBLE desktop (that suite takes a game-type
dropdown, which cannot work off-screen). From the plugin's own ATTACH/DETACH lines:

- on their monitor **08:30:50.092Z -> 08:33:49.041Z**, about three minutes;
- selection 26-36 units throughout, always over 12;
- the text on screen was the HUD-ROW paging indicator, logged verbatim:
  `36 units  1-12 (1/3)` ... `30 units  1-12 (1/3)`, and **"30 units" was the reading for ~83
  seconds** immediately before the end (1143 log lines, the most common in the run);
- the game had CLOSED 8 seconds before their 08:33:57Z message.

So their "30 units have been selected" is exact, and it is `sc_hudrow`'s indicator — task 017 /
033 — **not your `sc_queueind` group line.**

## Why this matters to you, and what I want from it

You are fixing the group line's placement and z-order. The text the user watched flashing is a
DIFFERENT module's text in the SAME dialog, and their sentence ties them together: *"it's the
same place where I saw the number of units queued"*. They are describing one region misbehaving,
not one module.

So, while you have the machine and the six-sample instrument built:

1. Run your sampler against the HUD-ROW indicator too, not only the group line. Same question:
   does `sc_hudrow`'s control put bytes on the screen on EVERY sample, or does it alternate the
   way the user described? Your `boxDiff` machinery already answers it; the control is different,
   the method is not.
2. If `sc_hudrow` splices at the HEAD the way `sc_queueind` did, say so with the number. **Do not
   fix it in this PR** — tell me and I will cut it as its own task, because a second module's
   paint order is not what 039 was scoped for and I would rather ship your three defects proven
   than four half-proven.
3. If it turns out `sc_hudrow` is fine and only the group line alternates, that is equally worth
   knowing, and it means the user watched the queue indicator after all.

Your mandatory-2 already has you running `test-hud-row` after the tail splice, so this is mostly
a matter of pointing the sampler at that control while you are there.

## One correction to something I told you

I said their report "confirms your defect 2 from the outside". That was too quick — it confirms
that SOMETHING in that region loses the z-order fight intermittently, and on this evidence the
most likely candidate is the HUD row, not your group line. Your `boxDiff=0` measurement stands on
its own; it just is not the same observation as theirs until you have measured the row.
