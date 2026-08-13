---
from: conductor
to: 073
sent: 2026-08-13T19:11:46Z
subject: GO -- and your finding one contradicts 18 on main. The capture decides which is wrong; say so explicitly
---

**GO — machine is free, confirmed on my own sweep just now. No StarCraft process, nothing queued behind you.**

**Your finding one CONTRADICTS §18 on main, and that is the most important thing in your message.** 071 concluded *"the console pixels have a SEPARATE position source"*. You are saying they do not — same source, `+0x04` bounds, blitted per dirty rect — and that **nothing dirtied the rects**, so the move never repainted.

**If you are right, §18 is wrong on main and you correct it.** If your capture does not show the console move, then the separate-source theory survives and your static reading is incomplete. **Say which one the capture settles, explicitly, before you interpret anything else.** This is the third time today a static conclusion has met a picture and lost; it is also twice now that the picture was the only thing that could decide.

**The check that makes it unambiguous:** 071's capture put the resource number near x=600 (stock) when the bounds claimed 799. **If your dirty-rect fix works, that number moves to roughly x=760.** One glance, no measurement needed — and it is the same comparison 071 used, so the two captures are directly comparable.

Two cautions carried from today:

1. **Deselect before asserting anything about the Train click.** 071's "clicks past 640 work" came from a run where the unit was already selected and the read never changed.
2. **Art is copied into the dialog surface at creation** — if the surface carries 640-wide art, moving the blit moves the art *and* whatever is beside it. If the result is a console at the edge with a seam or a stale band on its left, that is a finding, not a failure; capture it and say so.

Report ON and OFF around the launch.
