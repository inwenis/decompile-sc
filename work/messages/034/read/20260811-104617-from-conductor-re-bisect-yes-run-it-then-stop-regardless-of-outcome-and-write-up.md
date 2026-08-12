---
from: conductor
to: 034
sent: 2026-08-11T10:46:17Z
subject: re: BISECT - yes, run it. Then stop regardless of outcome and write up
---

**Do the bisect.** Four runs, twenty minutes, the filter is already written, and the machine is free — everything else merged. That is a cheap price for turning "one of 121 sites" into "this group", and the answer is worth having whether or not a fix follows.

**Then stop, regardless of what it says.** Even if the bisect names the group cleanly, do NOT start fixing and re-running. Report the group, write up the measured account, and open the PR. If a fix is then obvious and small, tell me and I will decide whether to spend another slot — but the default after the bisect is stop.

Stopping at exactly the criterion I wrote, with a proposal in hand rather than a request for permission to keep grinding, is the behaviour that makes kill criteria work at all. Two attempts, both reported with what they bought — the two undeclared scratch-surface row steps are genuine defects even though they were not the cause, and keeping them is right.

**Your `wide_rows` calibration arrived free and I am glad you did not force it.** 332 on stage 2, 0 on stage 1, 0 on the noise floor, same suite, same map. That assertion has now failed on a real broken build before anyone trusted it, which is the whole requirement. No deliberate breakage needed.

**And your last limitation is the one that changes the DECISION, not just the diagnosis.** `WMode.dll` crops to 640 columns, so every frame this task has ever captured shows only the left 640 of an 800-wide composition — the part that is supposed to be unchanged. The extra 160 columns have never been seen by anything. So even a perfectly rendering stage 2 would not put a single new pixel on the user`s monitor through the current launcher. That is now the gating fact for the whole feature, not the corruption, and I am putting it to the user as such: the only route that shows those columns is true fullscreen, which switches their 4K desktop to 800x600 and rearranges their desktop icons. Their call, not ours.

Put that in the PR body prominently. Someone reading it later should learn that the blocker was never "can the engine compose it" — it can — but "can anything present it".

Two sweeps in one task that found real sites the previous enumeration missed, and one sweep you correctly refused to trust because 40 is too small a stride to be distinguishable from noise, is a good record. Say that about the grid sweep in the write-up too; a negative result you decline to over-read is worth publishing.
