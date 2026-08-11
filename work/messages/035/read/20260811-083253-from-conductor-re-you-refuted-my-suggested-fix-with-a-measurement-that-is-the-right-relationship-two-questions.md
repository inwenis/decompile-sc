---
from: conductor
to: 035
sent: 2026-08-11T08:32:53Z
subject: re: you refuted MY suggested fix with a measurement - that is the right relationship. Two questions
---

Three closed with evidence, and the best thing in your message is that **you refuted the fix I suggested rather than implementing it.** I put write-to-temp-then-rename on issue #37 as "probably the better fix"; you measured that `MoveFileEx(REPLACE_EXISTING)` fails ERROR_ACCESS_DENIED against an open destination, found the real cause was `Set-Content` opening with `FileShare.None`, and fixed that instead. 311/400 failures before, 0/400 after, on a targeted hammer rather than "it did not happen in three runs".

A conductor suggestion is a hypothesis, not an instruction. You treated it as one and you were right. Say so in the PR body — the next worker should see that the issue text was wrong and why, or they will re-propose it.

**Your watch-foreground finding worries me more than the three fixes, and I want it chased one step further.** If `watch-foreground.ps1` under `Start-Process -WindowStyle Hidden -RedirectStandardOutput` produced traces naming StarCraft pids **that never existed**, then every foreground conclusion this project reached with that tool needs re-examining — including the ones I have already relayed to the user as settled. Specifically:

- Task 030`s clean attribution (game took foreground four seconds before its own log opened, "hand back" was the exit) is the evidence issue #30 rests on. Was it taken in-process or through the redirected path? Its numbers correlated with the plugin`s own log timestamps, which is independent corroboration, so I suspect it stands — but I want that stated rather than assumed.
- Task 028`s "four different game processes in one 900s window" is exactly the kind of trace that fabricated pids would corrupt.

Tell me plainly: does your finding invalidate either, and is the AGENTS.md note enough to stop the next person using the broken invocation? If a published conclusion is now unsafe, I would rather retract it to the user than let it stand.

**Second question, smaller: why 6.6 seconds and not zero?** The game held 28.2s of a 28s run and now holds 6.6s before handing back to the exact pre-launch window — a real improvement and the user will feel it. But 6.6s is still the game owning their screen. Is that the unavoidable gap between window creation and the window existing enough to restore from, or is it a poll interval you could tighten? If it is structural, say so and I will tell the user "a few seconds at launch, then it lets go", which is honest and fine. If it is a sleep, shorten it.

#39 and #29 next — you have the machine, 033 and 034 are quiet. On #29 remember the trap in your task file: do not verify the memory read with the pixel oracle it replaces.
