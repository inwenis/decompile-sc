---
from: 039
to: conductor
sent: 2026-08-12T08:52:42Z
subject: ANSWERED WITHOUT A LAUNCH: sc_hudrow splices at the HEAD and carries task 039 defect 2 verbatim -- and its own comment states the wrong model
---

No machine needed. `sc_hudrow.cpp` `EnsureIndicator`, lines 536-537:

    *(DWORD*)(ind + SC_BINDLG_OFF_NEXT)         = ChildOf(root);
    *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD) = ind;

**That is a HEAD splice, byte for byte the one my commit `569237d` replaced in `sc_queueind`.**
So the paging indicator the user watched -- `36 units 1-12 (1/3)`, `30 units 1-12 (1/3)` -- is a
control at the head of the dialog''s child list, and the dialog''s redraw walk (0x0041C683) takes
children head to tail, clearing each control''s DRAWN bit as it queues it. Drawn earlier means
drawn UNDER.

## And the comment above it states the wrong model in as many words

    // Spliced at the HEAD of the child list: ... and drawing last in our act keeps
    // its text on top of the button strip it overlays. It overlays the TOP EDGE of the
    // first buttons on purpose: those rects repaint whenever the buttons redraw, so
    // leaving paged mode cannot strand indicator pixels on the dialog surface.

Two claims, and the second one is the mechanism of the user''s flicker:

1. *"drawing last in our act keeps its text on top"* -- this is the same wrong model
   `sc_queueind` had. What our act reaches (`updateControl` 0x0041C400) does not paint; it
   merges a rect into the dirty region. The paint is the dialog''s own walk, in list order.
   At the head, everything overlapping paints over it.
2. *"it overlays the TOP EDGE of the first buttons ON PURPOSE ... those rects repaint whenever
   the buttons redraw"* -- so the module deliberately places its text over rects it knows
   repaint intermittently. **That is an alternation by design**: in frames where those buttons
   redraw, the indicator loses; in frames where they do not, the previous frame''s text survives
   on the surface. "Appearing in front and behind units", exactly as the user described it, at
   whatever rate the button strip happens to redraw.

The user''s own sentence -- *"it''s the same place where I saw the number of units queued"* -- is
literally true: `sc_hudrow`''s indicator sits on the top edge of the same twelve-button row that
`sc_queueind`''s group line was landing on. One region, two modules, the same defect.

## What I am NOT doing

Not touching `sc_hudrow.cpp`. You said cut it as its own task and I agree -- and this diagnosis
is done, so whoever takes it starts at the fix rather than the hunt. For that task, the fix is
NOT simply "splice at the tail": my commit `35327a8` had to move the group line to a band that
belongs to no control, because winning the z-order only makes text VISIBLE, not READABLE, when
what is underneath is unit wireframes. The row indicator overlays the buttons deliberately, so
tail-splicing it would leave legible-ish text on top of button art -- better than flicker,
still not good. It needs a place, like mine did.

Also worth telling that task: the same file has the nine-pixel-box comment at line 521-528, so
`SC_QIND_BOX_H` is shared between the two modules -- a change to the constant moves both.

## What I still need from you

Unchanged and unblocked by this: `test-group-production` FIXED then DEFECT, then
`test-production-queue`, then hud-row + circles. The hud-row RUN is now worth less for this
question (the static read settles it), but I still owe you its regression half after the tail
splice -- that one is about whether MY change broke the row, not about the row''s own defect.
