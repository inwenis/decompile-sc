---
from: 031
to: conductor
sent: 2026-08-11T00:15:03Z
subject: need the remote branch overwritten (or approve my alternative): I rewrote history to drop a stale number
type: question
options: overwrite the remote branch for me; let me merge the old remote tip in instead; other
---

Everything else is done. Blocked only on getting the branch to the remote.

WHAT I DID AND WHY. My first commit's subject claimed **1.77x**, which was measured on the PRE-028 SCV version of this suite. Task 028 turned it into Probes and two Nexuses, so after rebasing that number was simply wrong -- and it was in a commit SUBJECT, where a reviewer reads it first. I rewrote the branch into two commits carrying the re-measured numbers (215.1s -> 160.1s, 1.34x) and verified the rewrite changed no content at all: diffing the pre-rewrite tip against the new tip is empty, and the tree is clean.

The remote still holds the pre-rebase commits, so my ordinary push is non-fast-forward, and the guard hook correctly refused the overwriting kind. That is your call, not mine, so I am asking rather than looking for a way round it.

Two options, and I prefer the first:

1. YOU OVERWRITE THE REMOTE BRANCH (my preference). Nothing of value is lost: those commits were never reviewed, no PR exists yet, and the content is byte-identical to what I would push. Branch `task031-faster-test-fixtures`, local tip `26f9712`, remote tip is the old `3c5fc33`.
2. I MERGE THE OLD REMOTE TIP BACK IN and push normally. Costs an extra merge commit and puts the stale "1.77x" commit back in the branch history. Harmless after a squash-merge, uglier for anyone reading the commits.

READY BEHIND IT, all verified:

* ci-local PASS at 26f9712 -- pester 61/61, hooktest 0 failures (with its own log-path fix in), ruff NOT RUN as expected.
* Regression: 10 of 11 in-game suites at 0 failures. `test-ability-in-combat` fails 2, reproducibly, inside its own retake loop -- it stims again on every retake and the stim effect outlives one, so from take 2 onwards the did-it-fire delta is 0. Reproduced twice, once needing four takes and once two, so ONE retake is enough. I ruled this branch out rather than asserting it: the generated fixture's CHK bytes are identical to the origin/main generator's for that suite's exact arguments, that suite and drive-game.ps1 are untouched here, and the only plugin-source code changes are an unused #define and a log path inside hooktest.cpp's main() -- a standalone binary, not part of scplugin.dll.
* Both first-sweep failures were my own harness and both pass on the re-run: `sunken-acquire` 0 failures once my yield sentinel was gone, `production-queue` 0 failures with one log directory per suite instead of eight sharing one marker file.
* THE FIND I DID NOT EXPECT, and it is in code that merged tonight. `Get-TraineeCount` in test-production-queue counted Probes in the player's unit list, and a unit still being TRAINED is already in that list. That count feeds `$completed`, which both cancel arms subtract from the expected queue length -- so a build that had merely STARTED inside the window made the arm expect one item fewer than the engine had. On the vanilla fixture a Probe finishes every ~14 real seconds and the cancel window is ~5s, so it was mis-counting roughly one run in three: rare enough to read as a flake, which is the worst kind of rare. Shortening the build time made it fire nearly every run, which is how it surfaced. Fixed by testing the completed bit; the arm now logs `9 -> 7 (and 1 finished building in the window)` and passes.
* Your rebase warning earned its keep. `scv=8` would have compiled, run, overridden a unit this suite no longer trains, and reported a speed-up that never happened. It is `probe=12` now, and every number in the PR was re-measured on the merged suite rather than carried over.

Say the word and I will open the PR immediately -- the body is written, and I will put the link in Status.pr.
