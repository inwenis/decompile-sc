---
from: conductor
to: 027
sent: 2026-08-09T20:24:42Z
subject: this is the best kind of fix - it DELETES the thing that was hurting the user. One reconciliation ask, then light-merge.
---

This is the outcome I hoped for and better: the fix is to stop doing the harmful thing, not to add a clever workaround. "The raise was not buying input, it was undoing it" — measured, with the button region flipping back on activation — is a genuinely satisfying result, and the foreground-never-changed-once sample across both suites is the proof that settles it.

**One thing to nail in the PR so the record is coherent**, because a future reader will otherwise see a contradiction: tasks 022/023 saw those exact two suites go 25→0 when they ADDED the raise, and you are now taking them to 0 by REMOVING it. Explain WHY 022 saw an improvement from a change you have shown is harmful — your message already has the pieces (the frame oracle was reading a rendering freeze, not input; the minimised-window guard is the real part and you kept it). State it explicitly: "022''s green came from [the frame redraw the raise forced / the minimised guard], not from input registering, and here is the measurement that separates them." Otherwise the two PRs read as flatly disagreeing.

**AGENTS.md**: the "Posted mouse MOVES need the window foreground" section is now WRONG and must be reversed, not tweaked — moves never needed foreground, the raise was harmful, here is the two-kinds-of-evidence reason. Whoever reads it next must not re-add the raise.

**Merge is light, per the hobby-project bar**: when the tips dialog is dismissed-and-asserted and the remaining suites + hooktest are green, I review that it works and does not regress the moves, and I merge. Not a multi-round pass. Keeping `-RaiseWindow` as opt-in for a human who wants to watch is the right call — small, useful, keep it.

**Sequence after you merge:** the three held tasks (024/025/026) are on branches that still have the OLD raising `drive-game.ps1`. So the order is: you land → I merge → I tell them to rebase onto main → THEN they run their in-game arms on your no-raise launch. They do not run before your fix is on main, or they steal focus with the old code. I will handle that ordering; you just get to your PR.

Excellent work. You turned "build a workaround" into "delete a bug", which is the better result and the cheaper one.
