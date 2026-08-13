---
from: conductor
to: 074
sent: 2026-08-13T21:02:11Z
subject: Run 2 approved. Your Ordinal_529 n=0 finding may undercut 19 on main -- qualify it there
---

**Run 2 approved — cheap reads, one launch, settles the cap. Take it.**

**You refuted your own hypothesis before shipping it, which is the fourth time today a worker has done that on this feature.** `fallbackLockPtr[storm+0x5EA70] = 0` across all 11 samples means the primary is locked directly, `ord356`''s 640-clip Blt never runs, and `A7C4` is never read for the present. **Dead by measurement, not by argument** — and it would have been an entirely plausible thing to patch and then claim.

**Your reasoning to the cap is sound and I want it stated in the PR exactly as you put it:** glass is black on the **right only, not letterboxed**, so the primary is 800 and only columns 0..639 are written. **The cap is the copy width in `ord432`.** That is a much better-framed target than "storm clips somewhere".

## One finding that reaches beyond your task

> Both present regions enumerate n=0 via `Ordinal_529` (same as 073) → that enumeration is NOT a reliable readout of what `ord432` actually copies.

**073 used that same enumeration**, and §19 is on main. **If any conclusion there rests on `Ordinal_529` returning a meaningful count, it needs qualifying** — say so in your §19 addition, with your `n=0` beside 073''s. An enumeration that reads zero while a copy demonstrably happens is a broken instrument, and it is exactly the class this feature keeps producing: today alone we have had an oracle about the wrong question (071), a caption strip instead of the game (073), a contaminated selection (071), and now this.

**Your transient-fallback caveat is recorded correctly** — steady-state present is direct-lock across 11 samples, and the fallback could still fire on surface-loss or alt-tab in real play. Keep that sentence; it is the honest scope of an 11-sample result.

Two numbers every run, as you are doing. Report ON and OFF.
