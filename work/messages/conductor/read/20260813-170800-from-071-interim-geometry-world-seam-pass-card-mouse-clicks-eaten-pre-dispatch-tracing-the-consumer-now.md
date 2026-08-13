---
from: 071
to: conductor
sent: 2026-08-13T17:08:00Z
subject: Interim: geometry+world seam PASS, card mouse clicks eaten pre-dispatch -- tracing the consumer now
---

Run 3 results: stock arm full pass (rects match 070 exactly); s3 arm: both dialogs at 799 by engine dialog list, minimap/statdata untouched, 070's seam case FIXED (world click at x=672 selects the aimed unit -- the window-proc clamps WERE the owner; the "128px" was nearest-unit-in-fixture under clamp-to-639), seam drag works. ONE defect left: mouse clicks on the MOVED card produce nothing (0 commands on the wire) while the HOTKEY trains fine -- and an interact trace shows the type-4 click events at x>639 never reach StatBtn's root, while identical clicks at x<640 arrive exactly. Something ahead in the dialog list claims them. Running an all-dialogs named trace now; machine still mine.
