---
from: 027
to: conductor
sent: 2026-08-09T21:24:59Z
subject: DONE: all nine suites 0 failures, local CI green on the head. PR #28 ready to merge
---

All three of your asks are in, and the sweep is complete.

**All nine in-game suites, on the head `343371e`:**

| suite | result | picks a game type? |
| --- | --- | --- |
| test-fanout-orders | 0 failures | no |
| test-selection-circles | 0 failures | no |
| test-burrow-fanout | 0 failures | no |
| test-hud-row | 0 failures | no |
| test-control-groups | 0 failures | no |
| test-combat-death | 0 failures | no |
| test-stim-fanout | 0 failures | yes |
| test-sunken-acquire | 0 failures | yes |
| test-ability-in-combat | 0 failures (second attempt -- see below) | yes |

**One honest caveat.** `test-ability-in-combat` failed once, on its OWN variance guard: "the two control windows agree well enough to be a yardstick (spread 8, must be < 6) -- the fight is decaying too fast for a two-second window to mean anything, re-run on a steadier fixture rather than believing this". Not an input-path failure: in that same run the Game Type set on attempt 1, the ability fired 0 -> 36 units, and every substantive assertion passed. Re-run: spread 2 and spread 0, 0 failures. It is in the PR body as "0 failures (second attempt)" rather than as a clean nine, because it took two runs and you should know which.

**Offline gate**: `run-ci-local.ps1` PASS on `343371e` -- 83 .ps1 parsed, 34 Pester tests, game-content guard over 646 files, python byte-compile, **hooktest 0 failures**. `ruff` reports NOT RUN (not installed here), not a pass. GitHub Actions is red for billing ("the job was not started because recent account payments have failed"), unrelated to this branch.

**Your three asks:**
1. AGENTS.md now leads with BOTH halves -- moves/clicks/drags need no foreground; a dropdown does -- and names `Send-ScDropdownPick` as the only place in the repo allowed to raise. It also documents how to CHECK a run did not steal focus (`watch-foreground.ps1`) and what a correct run looks like for each kind of suite.
2. The hand-back can no longer fail a suite: it checks the window still exists, and warns instead of throwing.
3. `test-combat-death` ran in full: 0 failures in 03:53.

**Focus, measured:** six suites -> ZERO foreground changes across their runs. The three that pick a game type -> exactly one borrow-and-return each, four seconds (`22:03:39 StarCraft` ... `22:03:43 chrome`). Before this branch the game took the foreground on the first click of every run and held it for the whole run with the user`s mouse clipped to its window.

**Branch note:** I did NOT force-push. The branch was behind main, and since force-push is on my "ask first" list I merged `origin/main` in instead (`343371e`) and re-ran the gate on the result. `merge-task.ps1` squash-merges anyway, so the merge commit costs nothing.

PR #28 is ready: https://github.com/inwenis/decompile-sc/pull/28
