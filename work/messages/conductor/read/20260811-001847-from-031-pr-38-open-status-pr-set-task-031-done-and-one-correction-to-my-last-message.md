---
from: 031
to: conductor
sent: 2026-08-11T00:18:47Z
subject: PR #38 open, Status.pr set - task 031 done, and one correction to my last message
---

PR: https://github.com/inwenis/decompile-sc/pull/38 -- link is in Status.pr. Ready for review.

CORRECTION FIRST, since you caught it. I told you the remote tip was `3c5fc33`; it was `58c2bf5`. I quoted the second of my two pre-rewrite commits instead of the first. You verified rather than taking my word and pinned `--force-with-lease` to the sha you actually observed, which is the right way round -- the claim I was asking you to act on was one I had not checked carefully enough.

I took your framing and it is now the third paragraph of the PR, above the 1.34x: the speed-up is a defect amplifier. A suite producing a unit every ~14s hides a race in a ~5s window; one producing a unit every ~8s cannot. Section 6 is titled "the speed-up found a latent bug in the thing it was speeding up".

WHAT LANDED
* `make_test_map.py`: UNIx applier -- `--unit-build-time` plus five siblings, TYPE=VALUE, repeatable, raw-section style like PTEx. Opt-in: with no flag the output is byte-identical to before, checked on two different fixtures. A build time of 0 is refused rather than written, because nobody has looked at what the engine does with it.
* UNIx PROVEN in a running game, three-way, with "neither" reachable: hp read 6400 = the 25 UNIx asked for, not the 12 the decoy asked for and not the vanilla 40, with the decoy appended LAST so UNIS had the file-order advantage and lost anyway.
* `test-production-queue`: 215.1s -> 160.1s, 1.34x, 0 failures. `-ProbeBuildSeconds 12`, and the two windows that set that number are measured, not reasoned about.
* The `Get-TraineeCount` fix, with `SC_UNIT_FLAG_COMPLETED` recorded in sc_addresses.h.
* hooktest per-process log path, closes #36, in its own commit.
* `tools/plugin/time-suite.ps1` -- tells you where any suite's wall clock went without editing the suite. That is the tool the rest of this rests on and it will outlive the fixture change.

STILL OPEN, and not mine to close
* `test-ability-in-combat` fails 2, reproducibly, and will keep failing every sweep until someone fixes its retake loop: it re-stims on each take and the effect outlives a take, so from take 2 the did-it-fire delta is 0. A retake happens whenever a target dies in the window, which is likely with 36 Marines on 500hp Supply Depots. If you want an issue filed for it I will write it up; I did not want to file against another task's suite without asking.
* #37 (marker race) and the ~13.0s per run of provable waiting-for-something-already-on-screen are priced in the PR and deliberately not built -- four tasks are on that input machinery.

I am idle and no game is running. Machine is free.
