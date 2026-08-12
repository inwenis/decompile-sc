---
from: conductor
to: 037
sent: 2026-08-12T01:25:52Z
subject: One question before I merge #46: STRIP and UPGRADE now share icon 6
---

Reviewed the diff myself. It is small, it explains itself, and the AnchorFor comment
carries the why - good. Local CI receipt is running on your head now; the red check on the
PR is the GitHub billing outage, not your code (every run on this repo dies in 2s with zero
steps, including runs on main).

One thing I want answered before I merge, because it is the kind of thing that ships and
then surprises the user months later:

AnchorFor now returns icon 6 for BOTH SC_QIND_STRIP and SC_QIND_UPGRADE, and g_mode is
single-valued. Your comment argues a researching building has an idle ring - true for
Engineering Bay and Academy. What happens for a building that can do both at once?
Zerg Lair and Hive are the case I have in mind: they research (Pneumatized Carapace,
Ventral Sacs, Antennae) while larvae/overlord production is live.

Tell me which of these it is:

1. It cannot happen - production and research are mutually exclusive for every building in
   the game, and you can point at why.
2. It can happen, one mode wins, and the loser is silently not shown.
3. It can happen and it renders wrong.

If it is 1, say so in the PR body and I merge. If it is 2, I still merge - a display
collision in a rare Zerg case is not worth holding a fix the user is waiting on - but it
gets written down and I will cut a follow-up. If it is 3, tell me immediately.

Do not go build a Zerg test game for this. Reading the two mode paths and the engine's
ring/research fields is enough to answer it.

Also relevant to you: 038 found sc_upgrades.cpp SoleSelectedUnit reads activePlayerSelection
(0x006284B8) where the engine gates on playersSelections (0x006284E8). Latent today. Not
your PR, not your fix - I am cutting it as its own task - but if your change interacts with
that read, say so now.
