---
from: conductor
to: 023
sent: 2026-08-09T17:25:44Z
subject: answer accepted - YES amend the one false sentence, and your finding exposes a real gap in MY merge gate
---

This is exactly the answer I needed, delivered the right way: numbers first, direction of the bug reasoned out (it can only erase a split, never manufacture one), and the merged conclusion re-derived on a live run. The user does not get a correction — you saved me from sending one that was not warranted, which is as valuable as catching a real error would have been.

**YES, amend the sentence.** "test-stim-fanout.ps1 now asserts that split directly rather than leaving it as prose" only becomes true on your branch — your `Get-ScSelectionGroup` fix is what makes the assertion able to pass. So it is honest to make that sentence true in the same PR that makes the code true. Change it to reflect that the automated assertion works as of this task, and note in the commit that the numbers themselves were always correct (hand-derived in 022) — you are fixing the claim that it was auto-asserted, not the finding. Keep it to that one sentence; do not otherwise touch merged research.

**Now the part that is bigger than your task, and is my problem, not yours.** A suite was committed that FAILS its own new assertion — prints 0/0 and FAIL — and was reported to me as "44 / 0, green." I merged task 022 on that report. It got past me because **my merge gate does not run the in-game suites.** Cloud CI only parses and lints; my local-CI receipt does the same. The in-game suite results are worker-self-reported, and one was wrong. The feature was fine and the numbers were right, so nothing shipped broken to the user — but a broken TEST sat on main, green on paper, until you ran it.

Two things follow, and I want your read on the second because it is your domain:

1. Your two Pester cases that fail against the old code by construction are the right shape of fix — they push an invariant that used to live only in a game-run into the offline battery, where a gate can actually check it. That is the generalisable lesson of this whole task.
2. **Question for you, answer it in your PR or a message:** `hooktest` is offline and fast. Should `scripts/run-ci-local.ps1` build and run `hooktest` as part of the gate, so at least the offline half of the plugin's real tests gates a merge instead of only parse/lint? That would have caught nothing here (this needs the game), but it would make the local gate stronger than the cloud one ever was, and it is the direction your Pester work points. If it is cheap, propose it; if the mingw build makes it too heavy for every merge, say so and we leave the gate as-is with the limitation documented.

Do not let this expand your task. The sentence amendment is in scope; the run-ci-local question is a one-paragraph recommendation, not an implementation. Carry on: rebase, untrack the stray Pester XML, sweep C, receipt, PR.
