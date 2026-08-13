---
from: 071
to: conductor
sent: 2026-08-13T16:30:27Z
subject: Static work done, code built and committed -- requesting a machine window for the first live run
---

**The console move is implemented, CI-local green, committed on my branch.** No launch has happened yet -- 070 has priority and I am asking before my first one, per the card.

**What it is (one switch, stage 3):**

1. `sc_screen` stage 3: 8 byte-patch sites widening the window-proc mouse x clamps -- each clamp is a `cmp 640` / `mov 639` PAIR (patching the 639 alone would turn "click at 700" into "click at 799"). Generated + signature-checked like the rest of the table.
2. `sc_console` (new): detour on the dialog layer draw 0x0041CB50; per frame, by GEOMETRY (right edge 639 -> +160, 799 -> done, else -> logged once, untouched). Root bounds are screen coords, children dialog-local (two independent proofs), so draw and hit test follow the same four s16 writes.
3. At 640 / stage<=2 / observe: nothing new runs.

**Static findings worth relaying:**

1. The edge-scroll trigger (0x004D12FF, a >=638 test) behaves IDENTICALLY at 800 after unclamping -- left alone, stated in the generator.
2. Full-coverage cmp sweep (100.0% of .text) found no other consumer of the widened mouse range; the other 0x27F hits are the x87 FPU control word.
3. The dead strip: 15.5.3 already records the user's call (no art, stays black). After the card moves, the strip is mostly card; a 16px sliver at x=640..655 remains black by design. I will state this as the strip decision with a capture.

**The run plan when the machine frees up:** `test-console-800.ps1` off-screen under WMode -- functional proof only (clicks + engine-ring oracle + dialog-list rects are presentation-independent; WMode crops the picture). The VISUAL captures for the user need the cnc-ddraw path, i.e. 070's %SCDRIVE_POST_ACTIVATE% -- I will merge main when its PR lands and do the visual arm then. Regression arms after that: test-production-queue at stock, then at stage 3 if the machine allows.

Ping me when I can take the machine.
