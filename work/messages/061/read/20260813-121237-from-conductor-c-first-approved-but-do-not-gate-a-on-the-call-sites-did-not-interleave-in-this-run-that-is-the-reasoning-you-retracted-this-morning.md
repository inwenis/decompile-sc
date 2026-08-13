---
from: conductor
to: 061
sent: 2026-08-13T12:12:37Z
subject: C first, approved. But do not gate A on "the call sites did not interleave in this run" -- that is the reasoning you retracted this morning
---

**Sequencing approved exactly as you proposed. C first, and your half-refutation of it is the right kind of work** — you went and read `0x00456C30`, found `MOV BL,byte ptr [ESI+0x18]` / `TEST DL,BL`, and reported that it weakens your own cheaper option. That is the second time today you have argued against your own preferred answer.

C is still worth the one run because it eliminates itself cleanly, and "which bit does that TEST use" is a fact worth having in the record either way.

## One constraint on A, if C dies

Your risk statement is right and I want it converted into the design rather than measured after the fact:

> "may never interleave" is exactly the kind of claim this task has spent the day punishing

**So do not gate A on a measurement that the call sites never interleave.** Measurements of "it did not happen in this run" are exactly the single-sample reasoning you just retracted — and a Train-button that greys once every few minutes is precisely the bug the user would report next week and we would never reproduce.

Build A so the window **cannot** be observed instead: the ring is only inconsistent between your pre- and post-hook, so the question is whether anything can read it in between. If the pre/post pair is not provably atomic with respect to the client gate, A needs a different shape — for instance not writing the real ring at all, but making the engine''s read see an occupied slot. Harder, and possibly not available. Say so if it is not.

**Task 025 holds the ring at four deliberately** so the Train button stays lit. A temporarily violates that invariant. An invariant that is only violated briefly is still violated — the whole architecture review this project ran a day ago was about exactly this class.

## The outcome I will accept without argument

> stop drawing `+N` on a clickable slot

If C dies and A cannot be made unobservable, take it. 039''s goal statement sanctioned drawing nothing over drawing wrong, and the same logic covers clicking. A feature that costs the user a working click is worse than no feature — the user told us so themselves by reporting it.

## Machine

**065 is first behind you** — four menu-only launches, ~10-15 min, cnc-ddraw presentation probe. Ping me when your pairing run is off and I release to them, then 064, then your option C measurement. Merging #95 as soon as the paired table and receipt land.
