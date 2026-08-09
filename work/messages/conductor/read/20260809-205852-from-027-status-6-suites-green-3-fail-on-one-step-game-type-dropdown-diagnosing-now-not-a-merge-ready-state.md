---
from: 027
to: conductor
sent: 2026-08-09T20:58:52Z
subject: status: 6 suites green, 3 fail on ONE step (Game Type dropdown) - diagnosing now, NOT a merge-ready state
---

Honest status: **not green, do not merge yet.**

| suite | result |
| --- | --- |
| test-fanout-orders | 0 failures |
| test-selection-circles | 0 failures |
| test-burrow-fanout | 0 failures |
| test-hud-row | 0 failures |
| test-control-groups | 0 failures |
| test-stim-fanout | **1 failure** -- `Set-ScGameType`: the pick did not take |
| test-sunken-acquire | **1 failure** -- same step |
| test-ability-in-combat | **1 failure** -- same step |
| test-combat-death | not run -- I stopped the sweep rather than spend 15 min on a predictable repeat |

`run-ci-local.ps1` has NOT been run on the head yet (it rebuilds the plugin, so it must not overlap a launch).

**One failure mode, three suites, and it is exactly 022`s original symptom** -- the Game Type dropdown pick not taking. That is the one thing that could plausibly be my no-raise change, so I am not hand-waving it.

What I have measured since:
- A dedicated probe (`probe-quiet-dropdown.ps1`) ran the SAME `Set-ScGameType` on the Create Game screen in three arms: background/no-raise, background+AttachThreadInput, and foreground. **All three took, first attempt.** So the pick is NOT inherently broken without the raise.
- The difference between the probe and the three failing suites is the MAP: the probe used a stock campaign map, the suites use their generated fixture. So the next question is whether the panel fingerprint (which is `Set-ScGameType`s oracle) actually changes between Melee and Use Map Settings on those generated maps -- i.e. whether this is a broken PICK or a broken CHECK.
- Currently running: `test-stim-fanout` with `$env:SCDRIVE_RAISE=1`, i.e. the OLD raising behaviour, as the control. If it fails that way too, my change is not the cause.

Caveat you should know: that control run raises the window, so it WILL come forward a few times for ~2 minutes, and the user looked active a moment ago. It is one short run and it is the measurement that settles whether the regression is mine.

I was also the cause of one stranded artefact: stopping the sweep mid-`test-combat-death` left its fixture in my own folder. I deleted it (my folder, my run`s file) and killed the stranded game process.
