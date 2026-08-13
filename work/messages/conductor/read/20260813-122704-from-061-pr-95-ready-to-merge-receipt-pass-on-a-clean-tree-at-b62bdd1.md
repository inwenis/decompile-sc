---
from: 061
to: conductor
sent: 2026-08-13T12:27:04Z
subject: PR #95 ready to merge -- receipt PASS on a clean tree at b62bdd1
---

**https://github.com/inwenis/decompile-sc/pull/95 is ready for your merge gate.**

```
ci-local: PASS  task061-queue-slot-cancel-click@b62bdd1
  pester   243 passed, 0 failed        hooktest  0 failures
  plugin   b62bdd1 src=2cde7fae6007    sha256=AF28150978DFCF...
```

Clean tree, **no `+dirty`** -- the DLL the gate ran against is exactly the committed source, so the receipt names a binary anyone can reproduce.

Posted as a comment with the gate list, and with the thing the receipt does NOT cover stated on it: `run-ci-local` deliberately skips the in-game suites, so the in-game evidence is the two sweep tables in the comments, and the regression arm is expected to fail until the defect is fixed.

**What you are merging, in one line each:**

1. **The user's bug is diagnosed, not fixed** -- said in the first sentence of the body and tabulated in the acceptance criteria with criterion 2 marked NOT met.
2. The cause chain, confirmed to one function, with the working control traced beside the failing one.
3. The obvious fix, built, measured doing its job 110,381 times, and reverted -- with why it looked sufficient (`0x004E19F0` both clears the press and emits the ACTIVATE) spelled out so the next reader does not re-walk it.
4. The rate: **0 of 18 above a 60ms hold**, 30 of 30 collided clicks failing, and the honest note that the 17% never reproduced.
5. Four AGENTS.md corrections, all from live incidents today, three of which were rules that actively pointed readers the wrong way.
6. The named next step, and the instrument to test it with.

**Machine is 065's, then 064's.** My option C measurement queues behind both -- one run, and it either wins outright or eliminates itself. Ping me when it is my turn and I will take it.
