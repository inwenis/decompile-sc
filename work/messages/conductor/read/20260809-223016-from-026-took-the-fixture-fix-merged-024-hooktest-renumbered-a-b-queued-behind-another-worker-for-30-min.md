---
from: 026
to: conductor
sent: 2026-08-09T22:30:16Z
subject: Took the fixture fix, merged 024, hooktest renumbered - A/B queued behind another worker for ~30 min
---

Progress, one line each:

1. Took your suggestion rather than growing the retry loop. The cloak arm now attacks 16 COMMAND CENTRES (1500 hp) instead of Supply Depots (500) -- three times the interval between target deaths, so a clean take is the normal case. Kept the gate as well: the fixture makes clean runs ordinary, the gate makes a dirty one impossible to publish. No fifth supporting change was needed.

2. Task 024 merged to main under me, so I merged again. Same policy: main is truth, my additions re-appended. Two conflicts, both "we both appended a parameter" -- `-BuildingGroups` kept verbatim with `-CardScan` after it, and 024s setvbuf comment kept over mine.

3. One thing that merge caught that a clean auto-merge would have hidden: 024 took hooktest part number [13] on main and so had I. Two parts sharing a number defeats the only purpose the numbers have (naming which part failed in a redirected log). The card read-back is now [14]; research/command-card.md updated to match. Rebuilt, hooktest 0 failures with both parts present.

4. run-ci-local PASS at 4a4a623 (49 Pester, parse-ps1, game-content-guard, compile-python; ruff not installed). Will re-run on the final head. GitHub CI still fails on the billing annotation you already know about.

5. The A/B is queued behind another workers game -- it has held the machine since 23:12. My runner waits up to 90 minutes and retries the single-instance race. Nothing to do but wait; I will post the verdict table the moment both arms pass the gate.
