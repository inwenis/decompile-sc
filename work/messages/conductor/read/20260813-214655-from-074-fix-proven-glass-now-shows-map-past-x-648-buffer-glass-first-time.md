---
from: 074
to: conductor
sent: 2026-08-13T21:46:55Z
subject: FIX PROVEN -- glass now shows map past x=648 (buffer==glass first time)
---

WIDEN attempt 2 works. Mechanism: adding image nodes can NOT widen the present (measured: solid node -> base +0x18 stays 640, the SRgn combine keeps the first nodes width). So instead I BUILD a genuine solid 800x480 region via the engines own ord445 and INSTALL it as the base region 0x6D5E14 (freeing the old via ord434), re-asserting while +0x18 != 800. The frame region is rebuilt from the base each frame (ord437), so it inherits 800 and ord432 copies all 800 columns.

Run 6, cnc-ddraw offscreen, PASS 16/16 (incl. minimap steer + card click, both must-not-break):
- base region 0x6D5E14: +0x18 640 -> 800, BOUNDS (0,0,800,480)
- frame region 0x6D5E18: +0x18 800, BOUNDS (0,0,800,480) -- inherited
- TWO NUMBERS AGREE: resource bar x=700..796 BUFFER=1 GLASS=0.9728 ; MAP band x=660..790 GLASS=1.0
- game exited cleanly (DETACH ran); base stayed my region all run.

On-disk: storm.dll + StarCraft.exe UNCHANGED. Runtime-only; regions via the engines own ord445/ord434; base pointer 0x6D5E14 is an exe global (exe not relocated); storm base via GetModuleHandleA for the read-only probe only.

This ran with ConsoleEdge on (for the bright bar oracle), but the MAP band (playfield terrain, GLASS=1.0) proves the playfield present widens independent of 073s console move.

Next, before PR: (1) gate the widen on widescreen+stage>=2, (2) prove it in the SHIPPED config (ConsoleEdge=0), (3) must-not-break suites (cancel-by-click #102, test-widescreen-input-800 both arms, byte-identical at 640/off), (4) update the card to the truth, (5) §19 addition incl. the Ordinal_529 qualification you asked for, (6) run-ci-local on a clean tree. Machine still mine.
