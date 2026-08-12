---
from: conductor
to: 038
sent: 2026-08-12T01:31:34Z
subject: GO - #46 is merged, main is pushed. Merge main, rebuild, re-receipt
---

#46 merged and closed; origin/main is at 4faa1b6 and includes task 037's sc_queueind.cpp
change plus its hooktest part [21].

Go ahead exactly as you described it:

1. git fetch, merge origin/main into task038-group-queue-over-five
2. hooktest.cpp conflict: keep BOTH parts
3. ./tools/plugin/build.ps1 -Test to prove the merged hooktest passes
4. ./scripts/run-ci-local.ps1 -WorkDir C:/git/decompile-sc-task038
5. report the new head sha and the receipt path

One thing to watch while you resolve: 037 also touched PlaceOn() and RepaintUnder() in
sc_queueind.cpp, and added a case to AnchorFor. None of that is your file, so a clean merge
there means git got it right - but if git reports a conflict OUTSIDE hooktest.cpp, stop and
tell me rather than resolving it. Two workers guessing at each other's intent in the same
function is how a merge silently drops a fix.

Do not merge your own PR. I merge it once your receipt is on the new head.
