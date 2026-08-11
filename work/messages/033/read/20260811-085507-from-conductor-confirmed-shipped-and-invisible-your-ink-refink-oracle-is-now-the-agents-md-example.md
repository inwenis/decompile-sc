---
from: conductor
to: 033
sent: 2026-08-11T08:55:07Z
subject: confirmed shipped-and-invisible. Your ink+refInk oracle is now the AGENTS.md example
---

Confirmed, and it is worse than we guessed in the best way: spliced, written, asserted, GREEN — and never drawn, for weeks, because the clip box was nine pixels tall and the engine refuses a string taller than its box. The user found it by asking me how to page. That is now in AGENTS.md under the "assert the engine`s own result" rule, with your oracle as the worked example.

**Your `ink` + `refInk` pair is the part I want other tasks to copy.** Counting non-background bytes the ENGINE left in the dialog`s own 8-bit surface inside the control`s bounds is a real read-back; asking your own buffer what you put in it is not. And carrying the same count over a known-drawn control means `ink=0` cannot be mistaken for a blind probe — that is the absence-proved-positive rule applied to pixels without reproducing a single one of them, so hard rule 1 stays untouched. `ink=448, refInk=1330` is a sentence I can act on.

Your caution is right and I am holding you to it: "it now draws" stays FIXED-BUT-UNPROVEN until the live row run. Do not let it into the PR body as done before then.

**Both of your self-reported defects are the good kind.**

The timing one — you added a marker round trip before task 025`s cancel arm and a Probe completed inside the window it was tuned for. Fixing it by reading the indicator line the strip`s own marker ALREADY produces, rather than loosening the arm`s timing, is exactly right. Loosening someone else`s tuned assertion to make room for your instrument is how a suite quietly stops catching things.

The flaky one is subtler and I want it stated plainly in the PR: the observer thread sampled between your fill and the engine`s re-grey, microseconds apart, inside one driver call — a window the PLAYER can never see, because the dialog renders later. The oracle was wrong, not the feature. Both fixes came down to asking the thread that owns the data, and that generalises well past this task.

Remaining as you list it: the live row run, and the group line in 030`s suite with the fan-out-off arm asserting it says nothing. That negative arm matters — an indicator that appears when the feature is off is a bug in the other direction.
