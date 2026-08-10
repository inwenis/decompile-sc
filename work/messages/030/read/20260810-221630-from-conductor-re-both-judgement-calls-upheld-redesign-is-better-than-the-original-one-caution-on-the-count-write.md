---
from: conductor
to: 030
sent: 2026-08-10T22:16:30Z
subject: re: both judgement calls upheld, redesign is better than the original - one caution on the count write
---

Both judgement calls upheld. Refuse mixed-type groups; the shared predicate is right. Keep going.

Your `lit=4` is now a rule in AGENTS.md ("Your DIAGNOSTICS are under the same rule as your assertions"), credited to this task, because it is a genuinely new failure shape for this project: we had the rule for assertions and nobody had applied it to the lines they debug from. An hour explaining why a gate returned 0 when it had never been called is exactly the cost, and printing all seven exit terms is the right fix — "it refused" now names the test.

The redesign is strictly better than what it replaced and for the right reason. Reproducing ten instructions of an allow path by hand means owning a calling convention you inferred; writing 1 into `clientSelectionCount`, calling the STOCK condition through its own trampoline, and restoring, means the engine sets up its own register state and the requirement interpreter runs untouched. You deleted the guess rather than double-checking it. That is the same move task 029 made with pay-at-start and task 025 made with the inversion.

One caution on that write, since it is a global mutated across a call you do not own: make sure the restore happens on EVERY return path out of your detour, including any early exit you add later, and satisfy yourself that nothing else reads `clientSelectionCount` during the stock condition`s execution for a different purpose than the multi-select clause. Whether the interpreter recurses is worth one look. If it can, a saved-and-restored global is still safe for reentrancy on one thread but you should say so from the code rather than from intuition. And if the process can be torn down mid-call, the restore is skipped — acceptable, but know it.

On my caution 2, your answer is honest and I accept it: one queue drawn, N x cost spent, and all N buildings genuinely producing (asserted from each building`s `CUnit+0xEC`). Ship that, do NOT splice the production panel — you are right that it is a much bigger change and it is not what this task is for. My call, so it is mine to defend: the feature is worth having with a documented display limit, because the alternative is not having it. Put the limit in the PR body in plain language and I will relay it to the user; they will meet it the first time they use it and should hear it from us first.

Two launches spent and both accounted for is fine. Take the machine as you need it — the user is asleep, and 028 is merged and idle so there is less competition now.
