---
from: 039
to: conductor
sent: 2026-08-12T01:04:14Z
subject: Root cause: statUser->grp left at the EMPTY-slot GRP, plus head-of-list z-order
---

Root cause found, from the binary, before writing any fix. It is NOT AnchorFor and NOT a
per-card buffer, so no overlap with 037 except the file itself.

DEFECT 1 - the 5th slot's garbage (one cause, three renderings)

queueLayout 0x004268D0 writes FOUR fields per slot, not three. Disassembled here
(work/scratch/039/disasm.py over C:\sc-install\Starcraft\StarCraft.exe):

  occupied  00426A33  mov edx,[0x68C1E0]      ; statUser->grp  = cmdicons.grp
            00426A39  mov [eax],edx
            00426A3B  mov [eax+4],cx          ; icon = unit type
            00426A3F  mov [eax+6],3           ; mode
            00426A45  mov [eax+8],cx          ; type
            00426A55  mov [ebx+0x14],eax      ; ctrl->pszText = slot-number buffer

  empty     00426A5A  mov ecx,[0x68C1C0]      ; statUser->grp  = <race>cmdbtns.grp
            00426A63  mov [eax],ecx
            00426A65  mov [eax+4],di          ; icon = k+6
            00426A69  mov [eax+6],6
            00426A74  mov [ebx+0x14],0        ; pszText = NULL

0x0068C1E0 = unit\cmdbtns\cmdicons.grp; 0x0068C1C0 = unit\cmdbtns\%ccmdbtns.grp (the
button-border art), both resolved from their load sites at 0x00459C0C/0x00459C2A.

sc_queueind.cpp FillOverflowIcons writes icon/mode/type and NOT grp. The engine had just
laid that slot out EMPTY, so grp still points at the button-border GRP - and the draw
0x00456C30 reads BOTH the grp pointer and the frame index out of that record
(00456C80 mov cx,[eax+4] / mov eax,[eax] / frame-count clamp to frame 0). So the 5th slot
blits frame #unitType out of the wrong GRP. The frame index IS the queued unit type, which
is why one building shows a stuck glyph, one black, one flashing, and why each is CONSTANT
regardless of queue length - three renderings, one bug, exactly as the task file guessed.
pszText is also left NULL, so the slot loses the little slot-number the other four draw.

DEFECT 2 - the group text behind the icon row: Z-ORDER, not placement

The control is spliced at the HEAD of the child list. updateControl 0x0041C400 only
accumulates a dirty rect (it ends in 0x0041C200, a 16px-grid region merge); the actual
paint is the dialog's child walk, in list order. Head = painted FIRST = under every engine
control that overlaps it. The wireframe row is ids 33..44 at (30,8)-(242,78) and the GROUP
box lands at (40,9)-(159,25), i.e. straight under the top row of buttons. sc_queueind.cpp's
comment claims the opposite ("drawn from our own frame tail keeps its text on top") - that
is the wrong model of when pixels land.

Same defect touches STRIP mode: the "+N" box sits inside icon id 6, which is also later in
the list, so 033's ink>0 for it proves nothing - the icon's own pixels are inside the box.

Planned fix (tell me if you want it split): splice at the TAIL; write grp (and pszText)
in FillOverflowIcons from the engine's own globals; move the GROUP line into the band
BELOW the row (y 79..91 of a 92-tall pane surface, computed from the live button rects,
never hardcoded) so it is legible instead of merely on top.

TOUCHING AnchorFor: my GROUP case changes what it returns. 037 is adding an UPGRADE case
to the same function - textual conflict, not a logical one. Whoever is second rebases.
