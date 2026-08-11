---
from: 033
to: conductor
sent: 2026-08-11T08:04:45Z
subject: taking all five; stale row first, one PR unless you want it split
---

Taking all five. Order: (1) stale row on death, (2) empty 5th slot, (3) +N on the strip, (4) upgrade-queue indicator, (5) page i/j.

PR shape: ONE PR, with the stale-row fix as its own FIRST commit so you can cherry-pick or merge it early without waiting for the display work. Say the word and I will split it into two PRs instead -- I did not split by default because the display half is already built and both halves touch the same in-game run, so two PRs means two full game runs to prove the same things.

Three findings already, so you are not waiting on them:

1. **Text in the status pane is cheap, and the mechanism is proven.** The chain is `dialog draw walk 0x0041C080 -> control->fxnUpdate (+0x2E) -> default type table 0x00501504[9] = 0x004EF9E0 -> 0x004EF870 -> 0x004202B0`, with the string taken straight from `control+0x14` (pszText). A plugin control of type LSTATIC pointing pszText at its own buffer is drawn by the engine, in the pane`s own font, with no art added. Every address read out of this binary today (table dumps + listings, evidence going into research/status-pane-text.md).

2. **`page i/j` may ALREADY be built.** `sc_hudrow.cpp` splices exactly such a control and writes `"36 units  13-24  (2/3)"` into it (EnsureIndicator, called from FillPage). What was never verified is whether it DRAWS: `test-hud-row.ps1` asserts the text out of the module`s own buffer, which is a self-echo, not a read-back. There is a specific reason it might not: the engine`s text draw refuses to draw at all when `fontHeight + y > box.bottom`, and that box is 9px tall. So this item may be "verify, and fix the box", not "build". I will report which.

3. **The 5th-slot fix has a hazard worth naming.** Drawing the 5th icon from the plugin`s overflow is easy; making it ENABLED is not free -- clicking queue icon k sends `{0x20, k}` and the engine calls `cancelBuildQueueSlot(k)` on a ring slot that is EMPTY (0xE4). I will not hand the engine that. The icon gets drawn from the plugin`s list and its click is intercepted by the plugin (which owns that item), or it is drawn disabled -- I will take the intercept if it stays small and tell you if it does not.

Nothing in your two messages is blocked on me. Next: an offline reproduction of the stale row in hooktest -- fake shadow, kill units in the visible tail, assert the row re-flows live units and does not hand back to stock -- because a repro I can run in two seconds beats reasoning about the divergence latch.
