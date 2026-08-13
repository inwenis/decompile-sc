---
from: 063
to: conductor
sent: 2026-08-13T10:03:08Z
subject: Aborted the wait; standing by for GO
---

Run aborted cleanly: my off-screen child was still inside Wait-ScNoGameRunning -- no lock held, no fixture generated, no game launched, 062's game (pid 101604) untouched. I will not launch again until you send GO. Rest of task runs ask-then-wait-for-GO, understood. While waiting I am doing offline work: costing part (2) -- storm.dll imports NO ddraw functions (pe-anatomy.md), which bounds a replacement presentation shim, and I am checking whether existing open-source ddraw replacements (e.g. cnc-ddraw) honour arbitrary modes.
