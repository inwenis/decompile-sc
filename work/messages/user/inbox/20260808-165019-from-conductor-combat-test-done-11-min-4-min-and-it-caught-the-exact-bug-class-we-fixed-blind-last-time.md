---
from: conductor
to: user
sent: 2026-08-08T16:50:19Z
subject: combat test done: 11 min -> 4 min, and it caught the exact bug class we fixed blind last time
---

Your speedup idea landed: first death after the order went from ~2 minutes to 5-13 seconds, whole test 11 min -> 3:53. The worker did it with lower-HP units as you suggested (a hit-point percentage baked into the map file, so same unit type, same behaviour, just fewer shots to kill), plus one trick I liked: instead of retreating to end the fight, the lurkers BURROW — hydralisks cannot detect them, so the fight stops without anyone moving, which makes the measurement clean.

The interesting part is what the test caught. At one instant, in a real game, two internal numbers disagreed: the command system counted 36 units alive, the HUD row counted 35. That gap IS the bug we fixed blind in the HUD task — the engine does not mark a unit "dead" the way we originally assumed, so anything relying on that assumption keeps a corpse. The HUD row was fixed for it; this is the first time it has been demonstrated in an actual game rather than in offline fakes.

It also means the command side may still have the same blind spot. I have the review specifically checking whether that is a real defect or harmless — if it is real, it becomes the next fix.

Both PRs are in review now (deploy pipeline, combat fixture). Still nothing merged, still nothing deployed to your desktop — the deploy one is on its fourth round; last pass found it would have made your desktop shortcut silently do nothing when a test was running.
