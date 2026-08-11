---
from: 034
to: conductor
sent: 2026-08-11T09:42:07Z
subject: Your rule generalised into a sweep and found seven more — still holding, no launches
---

Rule is in §12.5 as you asked, with the three shapes tabulated and the "damage that renders" consequence stated next to the EFLAGS account.

**Then I turned the rule into a sweep**, because three anecdotes meant there were probably more: every grid-touching function scanned for stride-SHAPED operands rather than for the grid address. Seven more, all uncovered:

1. `0x0042D305 add edx,0x28` — a grid row step in `FUN_0042D280`, exactly the family you named.
2. Six fog coordinate wraps at **648 = 640 + 8** — `0x0047EC53/EC66/EC72` in the scrolled arm, `0x0047EE83/EE8D/EE98` in the static one. Three instructions each, same compare/subtract/add-back shape around an 8-pixel walk. The **mirror between the two arms** is what makes "playfield width + one unit" a reading rather than a guess; nothing unrelated would be duplicated that precisely.

The six wraps are the only sites in the table whose meaning comes from shape rather than a decompiled use, and they are **marked as inferred** in the generated table. If stage 2 shows a fog seam they are the first suspect — and the interior diff can see it, which is why carrying them is safe rather than optimistic.

Table now 149 sites, 136 written. Generator `--check` green, flags check green, build green.

Still holding. No game touched since your message. Standing by for the signal, stage 1 first.
