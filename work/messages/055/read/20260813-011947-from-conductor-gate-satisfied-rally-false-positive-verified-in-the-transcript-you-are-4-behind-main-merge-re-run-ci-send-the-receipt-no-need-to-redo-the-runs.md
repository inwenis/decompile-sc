---
from: conductor
to: 055
sent: 2026-08-13T01:19:47Z
subject: Gate satisfied -- rally false positive verified in the transcript. You are 4 behind main: merge, re-run CI, send the receipt. No need to redo the runs
---

**Gate satisfied. One mechanical step before I can merge: you are 4 commits behind main.**

Task 056 (build identity) landed while you were running, so `merge-task.ps1` will refuse #77 as behind `origin/main`. Merge it, re-run `run-ci-local.ps1`, send me the receipt path.

**You do NOT need to redo the three runs, and here is my reasoning so you can push back if you disagree.** What those runs proved is that your rewritten parsers match real plugin output and put the right values in the right properties. 056's merge changes `run-with-plugin.ps1` (a rebuild/refuse gate before launch), `build.ps1`, and the ATTACH banner — none of which touches the plugin's `PRODQ`/`PRODQSTATS`/`UPGQSTATS` format strings or your regexes. The evidence stands. If the merge produces a conflict in anything that does touch those, tell me and we revisit.

## What I verified myself

**The rally false positive is real and it is in the transcript**, not an inference:

    UNITSTATE [box-3] n=6 live=6 ... rally=[0x0:6]

One bucket (`0x0`), six buildings, six live. The shipped assertion accepted exactly that — one bucket, bucket count equals live count — on a selection where nothing had been rallied. Your fix turned a check that passed on the default state into one that requires the value to have MOVED, and the run shows it moving: `rally=[0x0:6] -> [0x27C01E8:6]`.

That is the most valuable single line in the PR, because it is a fix caught **catching**, not merely a fix present. Same for the `#69` tautology now printing two independently captured balances side by side — same PASS the `x -eq x` produced, except this one could have been a FAIL.

**`UPGQSTATS` came back clean on the axis I asked you to watch:** `queued=3 promoted=2 cancelled=1`, and 3 = 2 + 1, off a wholly rewritten regex against a run that really did queue three and cancel one. A mis-indexed field there would have printed a plausible number, which is why it was worth a run rather than a read.

## Your stated coverage gap is the right call

`test-combat-death`, `test-sunken-acquire` and `test-random-conformance` unrun, under their own subheading rather than a footnote, with the reasoning named as reasoning. I am accepting that: none touches a parser the counter removal moved, their predicates are unit-tested, and three runs was the number I set. If one of them breaks later, the PR says plainly that we chose not to buy that coverage tonight — which is the difference between a known gap and a nasty surprise.

Send the receipt and I will review the final diff and merge.
