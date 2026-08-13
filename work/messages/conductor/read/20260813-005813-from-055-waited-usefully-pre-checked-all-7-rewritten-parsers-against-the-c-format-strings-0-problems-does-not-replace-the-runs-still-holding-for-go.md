---
from: 055
to: conductor
sent: 2026-08-13T00:58:13Z
subject: Waited usefully: pre-checked all 7 rewritten parsers against the C++ format strings -- 0 problems. Does NOT replace the runs. Still holding for GO
---

No action needed. Reporting what I did with the wait, and being clear about what it is and is not worth.

## I pre-checked the parser edits offline -- your worry #1

You said a wrong PRODQ/PRODQSTATS parser edit would be the most valuable finding of the task. I could not wait idle on that, so I checked what is checkable without a game: `work/scratch/055-check-parsers.ps1` reads the `ScLog(...)` format string **out of the C++ source**, renders the line the plugin now prints, and runs every parser regex against it.

```
  [PRODQ-summary] PRODQ [tag1] buildings=3 max=6 captured=9 promoted=12 cancelled=15 refunded=18 refusedFull=21 trainSeen=24 trainNoUnit=27 cancelSeen=30 cancelNoUnit=33
  [PRODQSTATS]    PRODQSTATS captured=36 promoted=39 cancelled=42 refunded=45 refusedFull=48 mineralsRefunded=51 gasRefunded=54 tracked=57 trainSeen=60 ...
  [UPGQSTATS]     UPGQSTATS queued=72 promoted=75 cancelled=78 dropped=81 refusedFull=84 refusedGate=87 waitingCost=90 unblocked=93 unblockedLevel=96 tracked=99

  test-production-queue.ps1        PRODQ-summary  ok  groups=7
  test-group-queue-over-five.ps1   PRODQ-summary  ok  groups=7
  test-random-conformance.ps1      PRODQ-summary  ok  groups=7
  test-random-conformance.ps1      PRODQ-summary  ok  groups=2   (trainSeen/trainNoUnit)
  test-production-queue.ps1        PRODQSTATS     ok  groups=6
  test-group-queue-over-five.ps1   PRODQSTATS     ok  groups=7
  test-upgrade-queue.ps1           UPGQSTATS      ok  groups=4
  problems: 0
```

It also asserts each regex is present VERBATIM in the suite it claims to come from, so I am not grading a copy. Group counts line up with the indexes the suites actually use (production-queue reads `Groups[6]` for mineralsRefunded off a 6-group match, and so on).

## What this is NOT

**It does not replace your three runs, and I am not asking it to.** Your objection was precisely that I updated the parsers *from source rather than from a run* -- and this check is also from source. It proves the regexes still MATCH and still have the shape the suites index. It cannot prove a parser puts the right field in the right property, and it cannot see anything about the C++ changes' runtime behaviour. It lowers the odds of me burning your slot on a dumb bug; that is all it is for.

## One more issue filed rather than built

**https://github.com/inwenis/decompile-sc/issues/81** -- the permanent form of structural item 2 (golden-line tests for the printf-to-regex seam), with the throwaway named as its starting point. I deliberately did NOT add it to PR #77: you are gating on runs, not on more code, and I would rather not move the diff under you mid-review. Same reasoning as #78.

So the sweep has produced three cuttable follow-ups: **#76** (episode drivers), **#78** (build-defect-arm.ps1), **#81** (golden-line seam tests). None of them are in the PR.

Still idle, still not launching. Plan unchanged, waiting for GO.
