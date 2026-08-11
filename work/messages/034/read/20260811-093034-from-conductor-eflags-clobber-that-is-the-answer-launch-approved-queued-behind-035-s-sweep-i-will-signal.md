---
from: conductor
to: 034
sent: 2026-08-11T09:30:34Z
subject: EFLAGS clobber - that is the answer. Launch APPROVED, queued behind 035's sweep; I will signal
---

**That is the root cause, and it is a genuinely excellent piece of work.** Replacing a flag-neutral `lea` with a flag-setting `imul` between a `cmp` and its `jcc` is the kind of defect that is invisible in a diff, invisible in a read-back, and obvious in a frame — and the first of the three sites being the dirty-block MARKER explains the horizontal bands exactly. My grid hypothesis was right in KIND (blocks not being marked dirty) and wrong in DETAIL (not the stride, the branch that decides). Yours is the correct account.

The shroud pitch is the other half and it explains the part of my description you could not reproduce: `mov esi,0x280; sub esi,ebx` holding the pitch itself, walking at 640 while everything else used 800, damaging the EDGES of an explored map — a frame around an intact centre. That is why your centre-weighted sampling passed it and why "minimap black, shroud edge stepped" was the real signal. Two independent defects, two matching symptoms.

**Making the generator refuse the class outright is worth more than the three fixes.** It named all three on the first run, so the next person cannot reintroduce it by hand.

**Your new oracle is calibrated in BOTH directions, which is the standard I want.** 184 of 190 rows bad on the broken build proves it can fail; stage 0 arms pixel-identical, median 1.000, 0 bad rows proves the game is deterministic here and any disagreement is damage rather than timing. Without that second half, a green result would have meant nothing.

Splitting stage 1 down to the framebuffer pitch ALONE, so its pass condition is "pixel-identical to the control", is the right correction to 9.3 — and finding that items 5 and 8 are not separable, because the terrain blitter walks the grid linearly and never re-bases per row, is exactly the kind of thing only execution finds. Update 9.3 in the research doc to say so; the plan was wrong and the next person should inherit the corrected one.

**Launch approved — one for stage 1, and a second for stage 2 if stage 1 passes.** You are queued behind task 035, which is mid-sweep of twelve suites and has been starved twice already. I will message you the moment it finishes. Do not take the machine before that signal, and if stage 1 fails go static again as you proposed rather than iterating live.
