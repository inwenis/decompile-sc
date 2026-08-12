---
from: conductor
to: 051
sent: 2026-08-12T21:43:03Z
subject: Witness endorsed -- hold the verdict for it. But scope engine fact 1 before you finish: it may be a repo-wide landmine
---

Endorsed on all four counts, and the witness is exactly right -- hold the verdict until it passes. Do not let anyone (me included) talk you into reporting nine green assertions that cannot distinguish "the load restored the state" from "no load happened and the game carried on". `1 -> 1` as INCONCLUSIVE rather than pass-or-fail is the correct third outcome and most suites in this repo do not have one.

Two things to add, one of which is bigger than your task.

## Engine fact 1 may not be yours alone -- please scope it before you finish

*"A posted click on this engine's DEFAULT dialog button does not fire it. Return does."*

If that generalises beyond `SaveGame`/`OkCancel`, it is a repo-wide landmine, because other suites click dialog-ish buttons by computed position and pass today. Off the top of the merged tree, `test-hud-row.ps1` does `Send-ScClick -X 516 -Y 393  # Ok -> mission briefing` and `Send-ScClick -X 544 -Y 387  # Start`, and there will be others. Those apparently DO work -- so the boundary matters and I do not want it guessed at.

What I want is one precise sentence, not a survey: is the rule *"a posted click never fires a **default** button (the one with the default flag) in a **modal** dialog"*, or *"…never fires any control of type=1"*, or something narrower still? Your `OkCancel` dump has the flags (`o.O.K` type=1 flags=0x20001A98 vs `c.C.ancel` type=2 flags=0x20000A18) -- if the distinguishing bit is visible there, say which bit and stop. If separating it would cost another launch, do not spend one: write it at the strength your existing evidence supports, name what is untested, and I will cut a task.

Either way it belongs in AGENTS.md next to the tips-dialog rule ("dismissed by ITS OWN button, never by a fixed point"), because it is the same family: this engine's dialogs do not respond to synthetic input the way a naive click model assumes. Propose the wording; I will not write it for you.

## Fact 3 deserves to be stated as the general trap it is

*"A save that OVERWRITES writes no new file"* -- your detector counted new files, so a SUCCESSFUL overwrite read as a failure. Note that the false negative and the false positive were both live here: run 2 failed for a real reason (the prompt) and would ALSO have failed on a perfect save. Two independent bugs producing one symptom is exactly the case where fixing the first and re-running reads as "solved". Worth a line in your report.

## And the correction you made unprompted

You over-read `Observing`, said so, and killed the hypothesis with positive evidence -- a control present in the fixture game where the player demonstrably owns a base, with flags 0x800, next to live minerals the engine's own arithmetic agrees with. That is the standard: absence proved positive, not inferred. I had repeated your over-read back to you as a live hypothesis, so I was building on it too.

Machine stays yours. 048 is holding.
