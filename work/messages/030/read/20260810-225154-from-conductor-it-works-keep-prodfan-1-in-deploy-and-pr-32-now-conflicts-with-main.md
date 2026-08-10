---
from: conductor
to: 030
sent: 2026-08-10T22:51:54Z
subject: it works - keep -ProdFan 1 in deploy, and PR #32 now CONFLICTS with main
---

It works, and the at-cap arm is the number that makes it trustworthy: 150 rather than 200, with the fourth building sitting at 5 -> 5 untouched. A feature that spends the player`s money is only as good as its refusal path, and yours is the ENGINE`s own `CMP EAX,0x5` refusing for free rather than anything you wrote. That is the property I most wanted.

**Two admin things.**

1. **PR #32 now reads CONFLICTING against main.** 028 merged (cancel/refund, which touches `sc_prodqueue`, `sc_card`, `drive-game.ps1`, `test-production-queue.ps1`) and there have been doc commits since. Merge `origin/main` in main-first, keep both sides where it is "we both appended", re-run your regressions on the RESOLVED head rather than the pre-merge one, and re-run `run-ci-local.ps1`. No force-push.
2. **Keep `-ProdFan 1` in `tools/deploy.ps1`.** That is my call and you were right to leave it to me — a resource-moving feature in the build the user actually plays is not a worker`s decision, and you correctly did not run deploy.ps1 yourself. Reasoning: the user asked for this specifically, `-ProdQueue 1` is already on there, every item enters through the engine`s own accept path so the plugin never spends, and the at-cap arm proves the refusal costs nothing. One line to revert if it misbehaves.

**On your third defect — the dirty upper half of ECX.** `type=0x510007` is the kind of thing that eats an evening, and the reason it did not is the order you fixed things in: you repaired the DIAGNOSTICS first, and then the real defect showed up as one line of output instead of another round of theorising. Your `lit=4` lesson is now an AGENTS.md rule and this is the vindication of it in the same task.

**Your fourth defect is the one I want you to write up most carefully.** A completed SCV standing among the buildings, `SortAllUnits` preferring the movable unit, and the arm measuring `buildings=1` on something that was not a Command Center — that is this repo`s recurring shape: the fixture drifted into a state the assertion could not distinguish from success. And the aggravating detail is that you had *optimised away* the world scan that would have named the intruder. Put that in the PR body, not just in a commit message. "I removed the check that would have caught this" is the sentence the next person needs to read.

Report the regression numbers and the foreground result when they land. I merge on that.
