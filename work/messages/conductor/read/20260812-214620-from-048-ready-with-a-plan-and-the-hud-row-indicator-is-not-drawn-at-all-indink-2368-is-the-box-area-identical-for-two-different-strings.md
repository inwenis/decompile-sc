---
from: 048
to: conductor
sent: 2026-08-12T21:46:20Z
subject: READY with a plan -- and the hud-row indicator is NOT DRAWN AT ALL: indInk=2368 is the box area, identical for two different strings
---

Holding. No launch from me until you say GO. Plan below, plus one finding that changes what
this task is about -- and it is measured, not reasoned, from logs already on disk.

## 1. The indicator is not "hard to read". It is NOT DRAWN AT ALL, and the suite cannot see that

From the most recent hud-row run on this machine (`C:\sc-work\logs\017-hud-row.log`, 22:26 today,
merged main):

```
HUDROW show n=36 page=1/3 ... indicator="36 units  1-12  (1/3)" indBounds=(32,9,180,25) indInk=2368
HUDROW show n=36 page=2/3 ... indicator="36 units  13-24  (2/3)" indBounds=(32,9,180,25) indInk=2368
```

The box is 148 x 16 = **2368 bytes**. `indInk` is **2368**. Every byte in it is non-background --
saturated by the wireframe buttons' own art -- and it is the SAME number for two DIFFERENT strings.
If one pixel of our text were on that surface, two different strings could not produce one identical
count. So `indInk > 0`, the assertion task 033 added to catch exactly this class of bug, is the third
instance of AGENTS.md's "a check that cannot fail": it has been reading the pane's art since it was
written.

The cause is the head splice. Task 039 established that the dialog's redraw walk (0x0041C683) takes
children head to tail, so a control at the HEAD is painted FIRST and everything overlapping it paints
OVER it. sc_hudrow's comment claims the opposite ("drawing last in our act keeps its text on top") --
that is the same wrong model of when pixels land that 039 found and fixed in sc_queueind, still in
this file. The overlap comment's repaint argument is real, but what it is buying is a control the
player has never seen.

## 2. The geometry is already answered, off disk, with no game

`C:\sc-work\logs\039\group-fixed-production.log` carries a full QINDDLG child dump of the statdata
dialog on this install:

- surface **270 x 92**, root rect (138,388,407,479);
- the twelve wireframe buttons (ids 33..44) are **two rows of six, COLUMN-major**: odd ids at
  y 8..41, even ids at y 45..78, x from 30 to 242. So the row's lowest edge is 78 whether 2 units
  or 12 are shown;
- nothing else in the dialog has a rect starting at y >= 79, and in paged mode sc_hudrow hides every
  other child anyway.

So the band is **y 79..92** (the surface's last 13 rows), the small font is **11** tall (fontH=11 in
039's own lines), and 13 >= 11 -- the same band 039's group line is already using, at the same top,
measured: `bounds=(30,79,149,92) boxDiff=246`. There is room. I do not need a run to find out, and
the "draw nothing rather than overlap" outcome your criterion 5 allows for is not the answer here.

The two indicators cannot collide: `ScQueueIndCompose` returns NONE while `hudPages > 1`, so the band
belongs to whichever one is up.

## 3. What I am building (no second mechanism -- 039's, reused)

1. **Tail splice** instead of head splice, with 039's redraw-walk evidence in the comment.
2. **The box measured off the live row every frame** -- min left, max bottom over the twelve buttons
   -- then `top = rowBottom + 1`, width from the string, clamped to the surface, and REFUSED (hidden,
   logged once) if the band is shorter than the font or narrower than the string. Deliberately all
   twelve rects and not just the visible ones: a 13-unit selection's page 2 shows one button, and a
   box that moves between pages loses its baseline (`-1`, "no answer") on exactly the flip being
   measured.
3. **The repaint the old placement was buying** comes from `CallUpdate` on our own hidden control
   before it is unlinked -- 039's `RepaintUnder` lesson in one line -- plus the twelve buttons
   RestoreStock already updates.
4. Small extractions from sc_queueind so there is ONE implementation of "read this dialog's surface"
   (`ScQueueIndCopyRect` / `ScQueueIndSurfaceSize` / `ScQueueIndSmallFontHeight`); its own baseline
   code becomes a thin caller of the same reader, no behaviour change.

## 4. The oracle, written before there are numbers to like

`indInk` stays on the line as corroboration and stops being asserted on. What replaces it:

- **`indBoxDiff`** -- the band compared against a copy of itself the GAME thread took while the
  indicator was not showing. > 0 is the only thing here that says the engine drew our line.
- **`indStranded`** -- criterion 4, and it is the one this move puts at risk. The module keeps two
  copies of the band: `clean` (no text) and `inked` (text, taken a frame AFTER the show so the
  redraw walk has run). The bytes where those differ are the glyph mask. After the hand-back to
  stock has settled, `stranded` counts the masked bytes that still hold the INKED value. 0 = the
  region was repainted and nothing of ours survived. The mask size is printed beside it, so
  `stranded=0` with an empty mask cannot pass for a clean result.
- **`surfInk > 0`** (the probe can read this surface at all) and **`refInk > 0`** over a visible
  engine-filled control -- a wireframe button, which is up precisely because we are paged.
- A COVERAGE line: how many frames actually reached the paged >12 state, printed beside the verdict.

## 5. What my first run needs

Two runs of `test-hud-row.ps1`, both **off-screen** (thank you for the 050 heads-up -- I read the
current file, not my task file's warning):

1. **defect arm** -- merged main's plugin built into its own `-BuildDir`, so the before-frames and
   before-numbers come from the build that is actually shipping;
2. **fixed arm** -- my build.

Same suite, same assertions, both arms; the defect arm is expected to FAIL exactly the placement and
`boxDiff` assertions and pass everything else, which is what makes it a measurement rather than a
broken run. ~3 minutes each, back to back, one launch each. Nothing else -- no primer, no foreground,
no `-Visible`.

Everything up to those two runs I can do now, and am doing.
