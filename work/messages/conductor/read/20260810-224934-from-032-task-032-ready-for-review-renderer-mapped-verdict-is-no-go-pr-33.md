---
from: 032
to: conductor
sent: 2026-08-10T22:49:34Z
subject: Task 032 ready for review: renderer mapped, verdict is NO-GO (PR #33)
---

PR: https://github.com/inwenis/decompile-sc/pull/33

VERDICT: NO-GO on 1.16.1 for "wider viewport, stock HUD". Reachable in principle, but it is a renderer rewrite at the plugin`s price point. I took NO slice, deliberately - see below.

THE MAP (research/renderer-viewport.md, all derived from this binary; the renderer is the one subsystem BWAPI/GPTP/OpenBW skip, so nothing was inherited):
- ONE 8-bit framebuffer. Descriptor {u16 w; u16 h; u8* data} at 0x006CEFF0, 640x480, SMemAlloc(0x4B000). Present is ONE blit (0x0041D420) whose SOURCE PITCH 0x280 is a hardcoded immediate.
- THE SEAM: GraphicLayer[8] at 0x006CEF50, 20 bytes each, composed 7 -> 0. Layer 5 IS the playfield, 640x400 at (0,0), draw 0x004BD580. Layer 2 is the dialog layer at 640x480. The HUD is drawn OVER the playfield, not beside it.
- Found by the binary`s own __FILE__ strings ("Starcraft\SWAR\lang\gds\vidinimo.cpp" and 109 others). Calibration: the technique independently re-derives statcmd.cpp -> 0x00459B90 and statdata.cpp -> 0x00458570, which tasks 026 and 017 had found by other means.

WHY NO-GO, in order of weight:
1. There is no viewport to widen. The playfield size is stored NOWHERE - it is 640/400 open-coded in ~30 places (per-image clip 0x004D57B0, rect clip 0x0045CC90, click rect 0x0046FB40, fog x4, terrain, placement).
2. Two fixed-size buffers cannot grow in place. The dirty-block grid (u8[30][40], 16x16 blocks, 0x006CEFF8) is boxed in - 0x006CEFF8 + 0x4B0 == 0x006CF4A8, a live global - and 62 instructions in 13 functions reach it. The terrain scratch surface is 672x448 with its pitch and wrap size inlined in the blitter.
3. "Stock HUD" is the EXPENSIVE half: console.pcx is fixed-width and the HUD dialogs carry absolute coordinates. Wider screen + stock HUD = a 160px strip of nothing, or new art, which hard rule 1 forbids this repo from shipping.
4. Growing the playfield into the console strip gains nothing - the console is opaque and drawn over it.
5. WMode is NOT the lever it looked like. It intercepts SetDisplayMode(640,480,8) and scales the finished image to the desktop. That upscale IS what the user rejected. (It is also not a blocker - the obstacle is entirely engine-side.)

NO FIRST SLICE, on purpose. §9.3 has a staged plan if it is built anyway, but every stage before "playfield geometry" produces a 640x400 image in the corner of a bigger black rectangle - strictly worse than what the user has now. Shipping that would be worse than shipping nothing.

MEASURED, NOT JUST READ. Added a read-only SCREEN read-back to the plugin (%SCPLUGIN_SCREENSCAN%, OFF by default, no hook, works in -Mode observe) and probe-screen-layout.ps1, which drives one game and reads TWICE - main menu and in game, because a single in-game reading cannot tell "layer 5 is the playfield" from "layer 5 always looks like that". 13/13 assertions passed first run. Highlights: layer 5 absent at the menu and 640x400 in game; scrollMax=(3456,2696) on a 128x96 map against predicted (3456,2696) from (mapTiles-20/-12)*32; layer 0 is a 20x21 rect that moved to where the driver last clicked (the cursor); layer 1 reads rect=(640,400) in game, confirming 0x00481480 parks it offscreen to hide it.

NO SCREENSHOT: game frames reproduce artwork, hard rule 1 wins (AGENTS.md "Screenshots vs hard rule 1"). The read-back is the oracle.

WHAT I DID NOT DETERMINE (§10, in full in the doc): the minimap`s viewport RECTANGLE is not located - the one candidate the sweep offered (0x004A6030) decompiled to a SOUND TIMER, recorded as the false positive it was; WMode at a non-640x480 mode is unmeasured; the terrain scratch surface`s producer is unread; the Storm ordinal->name mapping in §3 is inferred from argument shapes, not derived from storm.dll.

MY OWN MISTAKE THIS RUN: the probe`s cleanup called Remove-ScOwnFixtureDir -Run when it takes -Dir, so the first run left an empty 00-t032 folder behind - which pushes every browser row down for the other four workers. Fixed in the script and the folder removed by hand.

VERIFICATION: run-ci-local.ps1 PASS (49 Pester, 85 .ps1 parsed, content guard over 733 files, hooktest 0 failures). StarCraft.exe byte-identical to pristine (AD6B58B2...288C6A46). No stranded process (the one live game is another worker`s, pid 46144; mine was 45672 and close-game confirmed it exited). Nothing in the PR patches, hooks or writes game memory.

I am IDLE now - no run in flight, safe to stop.
