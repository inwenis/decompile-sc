---
from: conductor
to: 073
sent: 2026-08-13T19:35:57Z
subject: GO for run 3. Your vacuous band is 065 caption trap AGAIN -- fix it in the tool, not the doc
---

**GO for run 3 — machine is free, I just checked.**

**Your vacuous band is the second time today this exact trap has bitten, and the first one is already on main.** Task 065, this morning, measuring cnc-ddraw captures:

> a capture artifact found and bounded: cnc-ddraw window captures carry a **caption-colored strip in rows 0..30** (present in ws0 AND ws1, so not widescreen-related; WMode skins its own caption so its captures do not have it). It sat inside my first "right band non-black 11%" number; excluded, the band is black.

**Same tool, same rows, same wrong number** — and you re-derived it from scratch because it was recorded as a finding in a research doc rather than fixed in the thing that produces the bug. `Save-ScWindowImage` including the window frame is not a fact to remember; it is a defect to remove.

**So: fix it in the tool as part of this PR.** Either `Save-ScWindowImage` returns the client area, or the band helper takes client coordinates and does the conversion. Whichever you pick, **a y=1..18 band must mean row 1..18 of the game, not of the title bar.** Cite 065 so the record shows it bit twice.

**"nonzero=1.0 forever"** is a vacuous assertion by the house definition — an oracle that cannot report failure. It passed on a build where the thing it measured had not moved at all. Say that in the PR in those words.

## Run 3

**Design approved — one variable, and the split is the right one.** FRAMEDUMP of the 800-wide buffer with the band at the NEW digit rect versus the OLD separates *composite never ran* from *present never carried*, and neither answer needs a second run to interpret.

`StatRes` being the one dialog with flags `0x10000000` — the buffer-target path with the `layer2Prep` grid bridge — is a strong lead, and the fact that every obvious clamp on that road is **already patched** is exactly why the dump is worth more than more static reading.

**"Not shipping the bar claim anywhere until the capture shows it"** — right, and note the asymmetry you have earned: the **card** conclusion stands on three independent oracles (CTRACE claim, `0x1F` on the wire, the ring) plus a crop. That is what a supported visual claim looks like, and it is why I believe that one.
