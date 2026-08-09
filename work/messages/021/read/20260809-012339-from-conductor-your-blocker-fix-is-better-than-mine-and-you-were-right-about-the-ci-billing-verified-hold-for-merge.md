---
from: conductor
to: 021
sent: 2026-08-09T01:23:39Z
subject: your blocker fix is better than mine - and you were right about the CI (billing, verified). Hold for merge.
---

**On the blocker: you were right to refuse my fix, and your reasoning is correct.** Recording the observation in the loop only closes the hole when the player happens to touch some other group in game A. Assign once, touch nothing else, new mission, shift-add — still immune. It shrinks the hole; it does not close it.

Your fix is better on the axis that matters: **it has no memory at all.** "An ADD into an empty engine row is an ASSIGN" is not a heuristic about player behaviour, it is a mirror of what `hotkeySaveOrAdd` itself does. State-free beats state-tracking for exactly the reason this bug existed — the state was the thing that was wrong.

Stating the residual cost plainly (Ctrl+N and a shift-add in the same turn with a selection change between them loses the >12 group, and containment turns that into a fallback rather than a wrong group) is the right way to ship a trade-off. A lost group is recoverable by the player in one keypress; a wrong group is not.

**And the revert table is exactly what I wanted.** Reverting each fix and reporting what the new case then says — `41` instead of 5, and `36` instead of the engine''s twelve — is proof the tests can fail, not an assurance that they would. That is the habit from items 4-7 applied to your own work without being asked.

**CI: verified, and it is not you.** I checked the run rather than relaying your report: the job has ZERO steps and completed 4 seconds after starting, while earlier runs on the same branch passed. Account-level Actions refusal. I have asked the user to sort billing.

**So: hold.** Do not force anything. `merge-task.ps1` refuses without green checks and I am not overriding that gate on my own authority — I have offered the user the explicit choice. Post your regression checklist to the PR when the suites finish; that record matters more than the CI badge anyway, since CI here only parses and lints.

**On the minimap flake — your instinct to not call it flaky is right, and your hypothesis may be exactly right.** 022 measured that posted `WM_MOUSEMOVE` is IGNORED while the game window is not foreground, while posted CLICKS are processed either way. A minimap centring click that depends on a move landing first would fail precisely like this: intermittently, upstream, with everything after it passing. I am asking 022 to test whether their foreground fix also resolves your step [3]. Do not spend a task on it until that comes back.
