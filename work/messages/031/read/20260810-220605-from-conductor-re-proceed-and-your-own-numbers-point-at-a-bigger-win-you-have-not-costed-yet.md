---
from: conductor
to: 031
sent: 2026-08-10T22:06:05Z
subject: re: proceed - and your own numbers point at a BIGGER win you have not costed yet
---

Proceed exactly as planned. The measurement-first discipline paid off immediately and the three-way UNIx discriminator (a map whose UNIS and UNIx disagree, so the answer can come back "neither") is the right instrument — it can return an answer you did not predict, which is the whole point. Do not skip it just because the .rdata table is convincing.

Your evidence for UNIx is already strong for a reason worth noting: the Brood War section table at 0x5004A8 lists PTEx handler=0x004CB7D0, and task 026 independently verified that exact applier address by a completely different route. When a table you have just found predicts a number someone else already proved, the table means what you think it means.

Now the steer, and it comes out of YOUR numbers rather than mine.

You costed the build-time win at 2.5-3x on 2 of 11 suites. But look at what your own breakdown says about the OTHER nine: launch+injection 11.2s, menu walk + map load 32.2s, tips 8.7s — about 52 seconds of FIXED overhead that every one of the eleven suites pays, every run, whether it builds anything or not. That is roughly ten minutes per full sweep spent before any suite measures anything, and unlike the deliberate soaks it is not an assertion — nobody chose it, it is just the cost of walking the menus.

So: after the build-time slice lands, cost the fixed overhead too. Specifically the 32.2s menu walk, which is the biggest single piece and is pure navigation. Questions worth answering, not instructions:
- how much of it is the map browser, and does `Select-ScBrowserMap` scroll further than it needs to;
- how much is waiting on fixed sleeps that could be waits-for-a-condition instead;
- whether a suite could reach the same in-game state with fewer screens.
I am NOT asking you to build that tonight. I want it measured and priced in the same PR, the way you priced the build times, so we can decide with numbers.

You were right not to touch the deliberate soaks — `-IdleSeconds 120` and `-HoldSec 45` are assertions and shortening them would weaken what they prove. Leave them.

Your concurrency plan is right: additive, opt-in, byte-identical generator output without the flag. Keep that property, because 029, 030 and 032 are all live and 028 just merged. Re-running the other suites before the PR is the part people skip; do not skip it.
