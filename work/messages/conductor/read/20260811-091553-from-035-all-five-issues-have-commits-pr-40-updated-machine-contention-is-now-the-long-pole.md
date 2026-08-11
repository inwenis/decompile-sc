---
from: 035
to: conductor
sent: 2026-08-11T09:15:53Z
subject: All five issues have commits; PR #40 updated. Machine contention is now the long pole
---

Five commits, one per issue, all pushed to PR #40 (https://github.com/inwenis/decompile-sc/pull/40):

- f436324  #35 hooktest part numbers
- 9dd415a  #37 marker write share mode
- ebd8027 + f6534af  #30 launch foreground (second commit is the retraction + 6.8s -> 4.3s)
- 8979d7a  #29 game type from dialog memory
- a8a39a2  #39 ability re-applied on retake

#39 and #29 are both proved live in one run of test-ability-in-combat:

    test-ability-in-combat: 0 failure(s)          <- the suite that failed 2 every sweep

    [fanout] take 1: targets 12 -> 12 -> 12 -> 10  <- a target died; re-taking
    [fanout] waiting for the stim effect to lapse on 36 unit(s) before the next take
    [fanout] the stim effect has lapsed; taking again from a clean state
    [fanout] take 2: targets 8 -> 7 -> 7 -> 7      <- died again; re-taking
    [fanout] ... lapsed ...
    [fanout] take 3: targets 6 -> 6 -> 6 -> 6      (clean)
    ok [fanout] the ability actually fired -- units carrying the stim effect went 0 -> 36

Take THREE fired 0 -> 36. Under the old code that take read 36 -> 36, delta 0, and failed - so the run exercised the exact failing path rather than getting lucky with a clean first take. The lapse wait is its own positive control: 36 before, 0 after.

#29 in the same run, both arms:
    game type is already 'Use Map Settings' (read from the engine's dialog list; panel shows Human Slots:, Computer Slots:) -- no pick, no raise
and the engine agreed - the run then asserted 36 Marines and 12 enemy buildings on the map, which a melee start would not have created. No pixel oracle anywhere in that chain.

It also turned out to need ZERO new plugin surface: task 027's own DIALOGS scan already carries the combo's text. StarCraft.exe and the plugin are untouched by #29.

The foreground trace for that whole suite is the #30 + #29 payoff together: two launches, two ~4s borrow-and-return pairs, and the game never foreground again during either arm - no dropdown raise at all, because neither arm picked.

WHAT IS LEFT: acceptance criterion 3, every in-game suite green. I changed Set-ScGameType's signature, so all twelve remaining suites need a run. That is now the long pole and it is not my code - 033/034 are launching games continuously and my last three attempts each queued 10+ minutes behind them (pids 169148, 172316, 174172, 175768 in one wait). I am running the sweep in the background, Set-ScGameType callers first. No question for you; just so the wait is not mistaken for a stall.
