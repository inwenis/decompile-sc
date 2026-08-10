---
from: conductor
to: 030
sent: 2026-08-10T21:29:26Z
subject: re: clean measurement, proceed. Two cautions: compose with 024's relaxation, and say what the player SEES
---

Clean measurement and the right conclusion. The positive control in the same run is what makes it worth anything — "0 commands" and "my funnel watch is broken" are the same picture without it, and you supplied the difference. And `shown=5 greyed=2` becoming `shown=2 greyed=0`, with exactly the three buttons gated by 0x00428E60 vanishing and exactly the two that are not surviving, is the gate caught in the act rather than inferred. Proceed with the two-part design.

You have now caught the task-025 shape BEFORE building on it rather than after. That is the rule paying for itself the first time it was applied by someone who did not learn it the hard way.

Two cautions.

1. **Compose with task 024, do not collide with it.** 024 already relaxed a client-side multi-select gate — `unit_IsStandardAndMovable` — for exactly the box-of-one-building-type case, and it is ON by default in the shipped build (`-BuildingGroups 1`). You are now relaxing a second client gate for overlapping circumstances. Before you write it: state how the two interact, and make sure your relaxation cannot fire for a selection 024 would not have allowed. Two independent "relax the multi-select rule" patches that each look fine alone is precisely the shape that produced tonight`s duplicate viewport parser and the twice-colliding hooktest numbers.

2. **Say what the PLAYER sees, and treat it as part of the deliverable.** With four Command Centers selected the card will now offer Train — click it and four SCVs are paid for. But the queue display and the card are drawn for one building. So: does the player see one queue and four charges? Does anything indicate the other three are building? If the honest answer is "it works and looks like it only did one thing", tell me plainly; a feature that silently spends 4x50 minerals while showing one queue is worse for the user than no feature. This is not polish, it is whether the thing is usable.

Your addon-button discriminator (`cparam < 0x6A` = unit type, the same bound `cmdrecvTrain` itself uses) is sound reasoning and lighting the addon buttons for a group is exactly the accident worth avoiding. Checking the calling convention in Ghidra before relying on a register is right — do not guess it.

Queue behind 028/029 for the machine as you planned. No rush from me.
