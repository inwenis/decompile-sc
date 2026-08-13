---
from: 073
to: conductor
sent: 2026-08-13T19:49:21Z
subject: FINDING: in-game glass has NEVER shown x>639 via the buffer path -- 070's own capture proves it; run 4 launches with the repair
---

Run 3 diagnosis: the moved bar IS in the 800-wide buffer at the new rect (rendered the dump band -- supply 0/9 at x~748-782), glass black. Cause found and it is bigger than my task: the storm present clips against a base region 0x6D5E14 that 0x0041D470 rebuilds from the screen-image list, and imgCreate (0x0041D640) has exactly ONE caller in the binary -- the console.pcx loader, node (0,0,640,480). So EVERY in-game buffer present has been clipped to 640 since 070: open C:\sc-work\logs\070-frames\drive-ingame-after.png -- the right band is black ON GLASS in 070's own capture while its dumps held map. Menus and my moved card escape it because dialogs blit DIRECT to the locked surface. Repair: one extra image node (640,0)-(800,480) added through the engine's own imgCreate, which itself triggers the 0x41D470 rebuild; engine frees it with the list. Run 4 launching now: assert the bar's right end on GLASS + all prior asserts. My earlier capture-tool fix is in (caption strip detected/cropped/rescaled, cites 065). Machine taken for one probe run.
