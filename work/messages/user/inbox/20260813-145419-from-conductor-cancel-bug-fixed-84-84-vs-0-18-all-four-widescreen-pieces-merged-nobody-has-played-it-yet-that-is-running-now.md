---
from: conductor
to: user
sent: 2026-08-13T14:54:19Z
subject: Cancel bug FIXED (84/84 vs 0/18). All four widescreen pieces merged. Nobody has played it yet -- that is running now
---

**Every piece of the widescreen goal is now merged. Nobody has played it yet — that is the last task and it is running.**

## What landed while you were at work

| what | PR |
|---|---|
| Your cancel bug, **fixed** | [#102](https://github.com/inwenis/decompile-sc/pull/102) |
| The game draws map 800 columns wide | [#99](https://github.com/inwenis/decompile-sc/pull/99) |
| Fog covers all 800 — no seam, nothing revealed | [#104](https://github.com/inwenis/decompile-sc/pull/104) |
| 800 columns reach the screen in a window | [#98](https://github.com/inwenis/decompile-sc/pull/98) |
| The test map survives a redeploy | [#100](https://github.com/inwenis/decompile-sc/pull/100) |

## 1. The cancel bug is fixed, measured

**84 of 84 clicks cancelled, at every hold duration, zero collisions.** Before the fix: **0 of 18** above a 60ms hold.

That gap is why it failed reliably for you and only sometimes for us — you press the button longer than the test harness did. The fix stops our own drawing from destroying your click, rather than trying to survive it.

## 2. The map is genuinely wider now

Terrain, units and minerals drawn out to column 799, and fog correctly hiding what you have not explored. Two pictures if you want them:

- `C:\sc-work\logs\063-frames\s2-ingame-render.png`
- `C:\sc-work\logs\063-frames\s2-scrolled2-render.png`

## 3. What is NOT done, and it is the part that matters to you

**Nobody has actually played it.** Every test so far has been a frozen frame. Unknown until someone drives a real game:

1. **Where the minimap and HUD sit at 800 wide** — they were never part of this work and may still be anchored to 640. Most likely thing to be wrong, and the first thing you would notice.
2. Whether clicking at x=700 selects the unit at x=700.
3. Scrolling across a full map.

Task 070 is running now and does all of that off-screen, then hands you **one action** to try it yourself. **The first real play is yours to trigger** — I am not putting anything on your screen or touching your install while you are out.

## 4. Two things waiting on you when you are back

1. **Deploy to your play copy?** Everything above is on main but NOT on `C:\sc-deploy\starcraft-modded`. Your next deploy picks it all up — including the test map, which now survives. Your call when.
2. `C:\sc-deploy\task067-scratch` (~1 GB) is a test deploy root I can delete whenever.
