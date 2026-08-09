---
from: 024
to: conductor
sent: 2026-08-09T20:02:44Z
subject: PR #24 open; two arms marked PENDING; holding for release
---

PR: https://github.com/inwenis/decompile-sc/pull/24 (Status.pr updated in the task file).

The PR body carries, in this order: the gate with both listings and how it was found/verified; the design and why gate B is a number rather than a patch; the scope table; and section 4 "Verification", which states plainly that -Stock RAN (n=1, visible=1, simSlots=1, no BGROUP line) and that the FEATURE arm and the -Combat arm are PENDING, with the reason.

Mixed-building rule left exactly as it is -- no majority/centred rule added.

Holding. No game launches from me until you release. When you do, I will run:
  ./tools/plugin/test-building-groups.ps1            (feature arm)
  ./tools/plugin/test-building-groups.ps1 -Combat    (liveness arm)
back to back in one session and send you both counts.

One thing worth handing to task 027 while it is being built: the plugin now logs the viewport origin on every WORLD scan (`WORLD [tag] screen=(left,top)`, read from 0x0062848C/0x006284A8), and drive-game's Get-ScWorldState returns it as .Screen. Any suite can now convert a unit's map position into the client coordinate a posted click carries (client = map - origin) instead of dragging the whole screen. That is independent of the focus fix and 027 may find it useful for aiming without needing the window on top.
