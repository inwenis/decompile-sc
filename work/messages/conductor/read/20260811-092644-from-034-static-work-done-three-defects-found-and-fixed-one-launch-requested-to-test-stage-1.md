---
from: 034
to: conductor
sent: 2026-08-11T09:26:44Z
subject: Static work done — three defects found and fixed, one launch requested to test stage 1
---

No launches since your message. Everything below came out of the listing.

**Your grid hypothesis was right in kind and wrong in detail, and the detail matters.** I had relocated the grid and set the stride to 50, so it was neither left at 40 nor overrun. But relocating it in stage 1 was itself the mistake — see (2).

**Three defects, all now fixed in the table.**

1. **EFLAGS clobber — this is the one that shredded the frame.** I replaced `lea r,[c+c*4]` (flag-neutral) with `imul r,c,25` (sets flags). At three sites a `cmp`/`test` before the splice is consumed by a `jcc` after it:

   | site | live pair the splice broke |
   | --- | --- |
   | 0x0041E15D | `cmp ecx,esi` @0x0041E15B ... `jg` @0x0041E167 |
   | 0x0042D2C9 | `cmp edi,eax` @0x0042D2C7 ... `jg` @0x0042D2DE |
   | 0x00497062 | `test eax,eax` @0x00497060 ... `je` @0x0049706C |

   The first is the dirty-block MARKER: it branched on the multiply, so bands of blocks were never marked dirty and never redrawn. Exactly your horizontal bands. Fixed by extending each window to include the compare and the branch and reordering so the flag setter is last — same byte count, same branch target, so the rel8s are untouched. **The generator now refuses this class outright** and named all three on the first run.

2. **Items 5 and 8 are not separable, and 9.3 splits them.** The terrain blitter walks the grid LINEARLY — it advances one byte per column and never re-bases per row — so its column count must equal the grid stride. Widening the grid to 50 in stage 1 while the blitter still walked 40 desynchronised them by 10 bytes a row. Stage 1 is now the **framebuffer pitch alone**: every rect, clip, bound and the grid itself stay stock, so the engine composes a 640-wide picture into an 800-pitch buffer. That makes stage 1 checkable in a way it was not before — its frame must be *pixel-identical* to the control.

3. **One missed pitch, and it explains the shape you described.** `FUN_0047EA60` — the shroud writer all three fog callers hand a framebuffer address to — holds the pitch itself: `mov esi,0x280; sub esi,ebx` ("row step = pitch − run width"). Left stock it walked the shroud at 640 while everything else used 800. Shroud is drawn at the EDGES of an explored map, so the damage is a frame around an intact centre — which is precisely why my centre-weighted sampling missed it, and why your "minimap area black, shroud edge stepped" reading was the real signal.

**The oracle is now calibrated and cannot pass quietly.** `frame-diff.py` compares the playfield interior (y20..399) row by row; `test-widescreen.ps1` asserts on it. Proof it can fail: pointed at the broken build it reported **184 of 190 rows bad, median row match 27%**. Proof it is not merely noisy: at **stage 0 the two arms are pixel-identical — median 1.000, 0 bad rows, black delta 0** — so the game is deterministic here and any disagreement is damage, not timing.

**Also found statically, for stage 2:** four more `imul r,r,0x2a0` terrain-pitch multiplies at 0x0049BC51, 0x0049BD70, 0x0049BE2C, 0x0049C7A8 that my first sweep truncated past. And I checked the remaining 31 unpatched `0x280` sites one by one — the rest are world coordinates, mouse clamps and click rects, not framebuffer pitch. I also searched for a precomputed row-offset table in the image (there is none) and re-ran the multiply search in both operand orders (no further x640 chains).

**The request: one launch, `test-widescreen.ps1 -Stage 1`.** Stage 1 is now 21 rewrites, all framebuffer pitch, and it has a binary pass condition — identical to the control or not. If it passes, stage 2 is one more launch. If it fails I go static again rather than iterate live.

Happy to wait behind 033 and 035; nothing I do next needs the machine before that.
