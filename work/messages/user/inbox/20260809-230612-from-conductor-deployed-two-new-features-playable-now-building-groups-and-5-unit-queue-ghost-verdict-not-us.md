---
from: conductor
to: user
sent: 2026-08-09T23:06:12Z
subject: DEPLOYED: two new features playable now - building groups and 5+ unit queue. Ghost verdict: not us
---

# Deployed -- go play

Your desktop shortcut is rebuilt. Two new features are live, plus the answer to your Ghost question.

## What is new when you launch

1. **Box-select same-type buildings as a group.** Drag a box over your buildings, get them all -- 12 shown in the HUD, the rest tracked as overflow, selection circles on every one. Rally-point a whole group of Barracks in one click. Mixed box picks one type, same as units do.
2. **Queue more than 5 units.** Default max 16 instead of 5. They build in order. Resources are correct: the game charges you once per unit, exactly as normal.

Both are on by default. Selection circles, HUD row paging and >12 unit control are unchanged.

## Your cloaked Ghost -- answered, and it is NOT us

Clean A/B on real cloaking Ghosts, plugin versus stock:

| | with our mod | stock |
| --- | --- | --- |
| Ghosts the cloak reached | 36 | 12 |
| Ghosts that were attacking and stopped | 0 | 0 |
| Ghosts attacking, before -> after | 33 -> 34 | unchanged |

Nothing we do takes a cloaked Ghost off its attack order. The only two units that changed orders were walking INTO the fight, one of them joining it. The count attacking went UP.

That "no" is backed rather than assumed: the cloak provably fired inside the measured window at full scale (all 36 cloaked, all 36 charged energy), and the SAME measurement has caught a mass stop-attacking when one really happened. It can see the thing it did not find.

The greyed-out Cloak button we found earlier was OUR bug, in our test-map generator -- not in your game. Your Ghost had cloak researched and working, so that bug does not explain what you saw. Your report stays unreproduced. The plugin has no AI, targeting or acquisition code that could plausibly cause it; most likely it was ordinary StarCraft behaviour (cloaked units still lose targets and go idle when a target dies), but I am not dressing a guess up as a finding.

## Two things worth knowing about the night

1. **A worker nearly reported a false bug against our own mod.** A run came back showing 33 of 36 cloaked Ghosts stopping -- your exact symptom, apparently our fault. It was a target dying mid-measurement, which looks identical. Worse, it was MORE likely in the modded arm precisely because the feature works (36 units shooting kill things 3x faster than 12). Caught, fixed, and the same guard applied backwards to the Stim tests, which had the same exposure and nobody had noticed.
2. **The 5+ queue was built wrong first, and a real game proved it.** The original design handled the 6th queue command -- but the game never SENDS a 6th; it greys its own button out. Every offline test passed and the queue never grew. The design was inverted to keep the button lit. That is now a written rule: a feature that starts with a player input is not proven until the wire has been watched in a real game.

## Still open

- 026 (the Ghost work) has one test re-run left, then it merges. Nothing in it changes gameplay.
- Not started: queuing upgrades, wider screen.
- GitHub Actions is still billing-blocked; local checks cover it.

## One caveat on the new queue

Cancelling a queued unit is proven correct at the code level in both directions, but no test has actually clicked cancel in-game yet (issue #26). If you cancel a queued unit and the refund looks wrong, tell me -- that is the one path not exercised by a real run.
