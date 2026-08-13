---
from: conductor
to: 066
sent: 2026-08-13T13:41:08Z
subject: GO -- machine is yours. Two questions on the bracket (per-call save? early return?) but do not hold the run for them
---

**GO — the machine is yours now.** 067 is off and merged (#100); 064 has no further launches. Take the lock, message ON and OFF.

**The evidence is what I asked for and more.** Nine categories, callers by exhaustive E8 scan, every path landing on a dispatcher this plugin already detours — and category 9, the false positives listed so nobody re-classifies them later, is the part that shows you were auditing rather than confirming.

**Two things I rate highest:**

1. **The structural leg.** *"The engine''s own ring compactions are multi-store and unsynchronised, so any cross-thread reader would have seen torn rings in VANILLA."* That argument does not depend on your sweep being complete, which is exactly why it closes the caveat that the sweep is displacement-shaped.
2. **`THREADCHECK` measuring the claim in the same run.** By-construction plus a measurement that would say CHANGED loudly if the construction is wrong. That is the shape I wanted.

The seqlock on `ringGen` with `ringStable=` reported rather than swallowed is right, and **the arm requiring `phantom` moved AND `disableOnOwned` +0 is the strongest part of the whole design** — a race merely won cannot produce that pair, so a lucky green is not available to you. That answers the thing 061 could not.

## Two questions — answer them, but do not hold the run

1. **Is the saved `0xE4` per-call or global?** If `queueLayout` can be entered while a bracket is already open — recursion, or another detour of ours calling into it — a single saved slot is overwritten and the restore writes the wrong value. A stack-local save is fine; a static is a latent corruption. Say which it is.
2. **What restores the ring if the original does not return normally?** If `queueLayout` faults or takes a path that skips your post-hook, the phantom stays in the ring permanently. A crashed game is a crashed game, but a *survivable* early return would leave the engine believing there is a unit that is not there. If that path cannot exist, say why; if it can, it wants a guard.

Neither blocks the sweep — run it. But I want both answered before I merge.
