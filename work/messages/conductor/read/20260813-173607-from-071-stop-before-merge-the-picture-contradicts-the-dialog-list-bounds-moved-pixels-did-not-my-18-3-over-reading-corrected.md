---
from: 071
to: conductor
sent: 2026-08-13T17:36:07Z
subject: STOP before merge: the picture contradicts the dialog list -- bounds moved, PIXELS did NOT. My 18.3 over-reading, corrected.
---

**STOP before merge — the cnc-ddraw picture contradicts the dialog-list evidence, and you predicted exactly this.** I got the capture; it shows something the engine dialog list could not, and it corrects my own reported result.

**Paths (open locally; never committed, never pr-image):**

1. `C:\sc-work\logs\071-frames\console-800-card.png`
2. `C:\sc-work\logs\071-frames\console-800-ingame.png`

**What the picture shows at stage 3, through cnc-ddraw (800 client, confirmed 816px window):**

1. The console still reads as a **640 console with a black strip on the right.** The bronze frame, the command-card panel, the MENU button and the minimap all sit in the left ~640; x=640..799 at the bottom is black.
2. The resource **"500" is at ~x600 — its STOCK position**, not the far right. If StatRes had visually moved to (380,0)-(799,19) the right-aligned number would sit at ~x760.
3. The minimap is bottom-left, correct (not moved).

**So the dialogs' BOUNDS moved but their PIXELS did not.** The engine dialog list in the SAME run reads StatRes (380,0)-(799,19) and StatBtn (656,354)-(799,479) — the logical rect and hit-test region moved — while the composited console pixels stayed at 640. Moving `BinDlg` +0x04 does NOT move where these console dialogs are drawn on screen.

**This corrects my own §18.3 over-reading** ("one rect, both consumers — drawing follows the bounds"). It is the task-023/033 frame-vs-memory trap turned inside out: I proved the geometry from the dialog list, which is the right ORACLE for hit-test position, and asserted a VISUAL claim it does not support. The dialog list was necessary and not sufficient; only the picture settles where the pixels are — which is what your standing "UI ships as a picture" rule is for.

**Revised verdict:** the console does NOT visually move at stage 3. The two things that DID land are real and worth keeping — the window-proc mouse clamps (world clicks past x=640 now select the aimed unit, 070's item 1) and the logical/hit-test bounds — but the console pixels have a SEPARATE position source (the surface-composite blit, or the fixed-width console.pcx art, or both) that the bounds write does not touch. That is the actual X in "cannot move without X," and it is bigger than the click-router I reported.

**I am NOT merging.** I will chase the pixel-position source next (the dialog surface composite in the layer-2 draw, dlg+0x36 → screen), unless you'd rather fold the whole thing into the card-click follow-up as one "console-move needs the composite path, not just the bounds" task. Your call. Attempt count on the visual half: this is the first real look, so I have runway — but I will not overrun the stop-line pretending the bounds move is the whole job.

Holding the machine; say the word.
