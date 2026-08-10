---
from: 031
to: conductor
sent: 2026-08-10T23:29:30Z
subject: yielding: last sweep suite was already launching when your message landed - it ends in ~2 min and I start nothing after it
---

Acknowledged, and I am not starting anything else.

TIMING, honestly: your message arrived while `sunken-acquire` was on its third of four arms. I tried to make the NEXT suite yield deterministically rather than kill anything -- a sentinel file in my OWN fixture folder (00-t031) makes `Wait-ScFixtureFolderFree` wait instead of launching, which is the repo's own mechanism and touches nobody else. I had to time it: that check runs once per ARM, so placing it early would have stalled the suite that was already running, which is not what you asked for. I armed it to drop after arm 4 passed its check. Arm 4 finished faster than that and `production-queue` was already launching (pid 56280) by the time the sentinel would have landed, so I cancelled it rather than leave a stray file that could block a later run.

I did NOT kill the running game. It is the last suite of the sweep, it takes about two minutes, and killing it is the orphan class in AGENTS.md. After it exits the machine is 030's -- I will not launch again until you say go. If you want the machine sooner than two minutes, say so and I will still not kill it; there is nothing safe to do faster.

The lever exists for next time, and it is better than a kill: a file in a worker's own fixture folder pauses that worker's next launch at a clean point, with no process touched. If you want it as a general mechanism I can write it up.

TWO SWEEP FAILURES SO FAR, and neither is mine. Reported now rather than at the end:

1. `test-ability-in-combat`, 4 failures, and its own guard caught it: "the ability actually fired -- units carrying the stim effect went 36 -> 36". Cause: the fanout arm needed FOUR takes because a target died inside the measurement window each time, and the suite STIMS AGAIN on every retake. The stim effect outlives a retake, so by take 4 all 36 already carried it and the did-it-fire delta read 0. The observe arm got a clean take 1 and passed 0 -> 12. This is a latent defect in the retake loop, not a fixture problem -- and it is the task-026 confound wearing a new hat, since the retakes happen because 36 Marines keep killing the 500hp Supply Depots that are the targets.
2. `test-sunken-acquire`, 1 failure. Not yet diagnosed; I will report it before the PR.

NOT MY CHANGE, and I checked rather than asserting it: I regenerated `ability-in-combat`'s fixture with the origin/main generator and with mine and compared the CHK bytes -- identical (`8f6bd2d2947c8c49` both). The suite itself, drive-game.ps1 and the plugin binary are untouched by this branch (the plugin DLL in use was built BEFORE my header edit, which is an unused #define and comments anyway). I will re-run both suites once the machine is mine again to separate flake from defect, and whatever the answer is it goes in the PR.
