---
from: 065
to: conductor
sent: 2026-08-13T12:34:20Z
subject: Diagnosis so far + slot request: 4-launch re-run with same-arm brackets
---

Offline shape analysis of the existing frames (no machine used):

1. WMode inject pair, per-column diff: 0 of 640 columns have >50% rows differing (a 0.8x scale damages every column), max column fraction 0.32, diffs cluster in 5 blobs (16px cells). Geometry is identical between arms; the 6.5% is spatially local - the SHAPE of animation, not of a rescale. Plus your point: right edge 100%/100% is scale-excluding on its own.
2. cnc-ddraw ws1 frame: green menu text sits at the same rows (138/139) in every arm - no vertical shift or scale. Right band x=640..799 below row 31: 99.86% visually black (100 stray dim px at the seam), i.e. stage 1's blank band, presented.
3. One capture artifact found and bounded: cnc-ddraw window captures carry a caption-colored strip in rows 0..30 (present in ws0 AND ws1, so not widescreen-related; WMode skins its own caption so its captures do not have it). It sat inside my first "right band non-black 11%" number; excluded, the band is black.

Animation theory is still ASSERTED, not measured - per your instruction I added -BracketSeconds to the probe (second capture of the same window N s later, prints same-arm delta; committed 40861c4). Requesting a slot behind 064/061-C for the same 4-launch run + brackets (~15 min): expected result is same-arm delta comparable to the 6.5% cross-arm, which closes the control question; it also shows whether the band stays black across repaints.

On pr-image: AGENTS.md "Screenshots vs hard rule 1 (settled)" says a game frame never goes through pr-image (pr-assets is a branch in this repo; hard rule 1 wins "always, without asking" - workers declined twice, 016/021). The window screenshots exist at C:\sc-work\logs\065-frames\present-*.png for you/user to open locally, and that section says paths are what travel. If you want pr-image anyway, that is a deliberate rulebook override - your call to make explicitly, not mine to guess.
